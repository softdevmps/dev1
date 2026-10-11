#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8) { throw 'Abre Huella en Windows 10/11 x64.' }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Usa Abrir-Huella.cmd para iniciar la interfaz.' }
Import-Module (Join-Path $PSScriptRoot 'Huella.psm1') -Force
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$reader=New-Object Xml.XmlNodeReader([xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Window.xaml') -Raw -Encoding UTF8))
try { $window=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
$controls=@{}
foreach ($name in @('Grid','Details','Status','Value','Refresh','Generate','Apply','Restore','Verify','Export','Admin','HyperV','FirmwarePlan','FirmwareCheck','FirmwareLaunch','AsusPanel','FirmwareHash','UsbLetter','FirmwareCopy')) { $controls[$name]=$window.FindName($name) }
$script:inventory=$null; $script:lastBackup=''; $script:planPath=''; $script:packageCheck=$null; $script:plan=$null; $script:capsule=$null

function Show-HuellaError($ErrorRecord) {
    $controls.Status.Text='Error: '+$ErrorRecord.Exception.Message
    $null=[Windows.MessageBox]::Show($window,$ErrorRecord.Exception.Message,'Huella','OK','Error')
}
function Select-HuellaFile([bool]$Save,[string]$Filter,[string]$Name='') {
    $dialog=if ($Save) { New-Object Microsoft.Win32.SaveFileDialog } else { New-Object Microsoft.Win32.OpenFileDialog }
    $dialog.Filter=$Filter; $dialog.FileName=$Name
    if ($Save) { $dialog.OverwritePrompt=$false }
    if ($dialog.ShowDialog($window)) { return $dialog.FileName }
    return ''
}
function Confirm-Huella([string]$Message) {
    return ([Windows.MessageBox]::Show($window,$Message,'Confirmar cambio','YesNo','Warning') -eq 'Yes')
}
function Update-HuellaInventory {
    $controls.Status.Text='Leyendo los dispositivos de este equipo...'
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
    $script:inventory=Get-HuellaInventory -IncludeHyperV:([bool]$controls.HyperV.IsChecked)
    $controls.Grid.ItemsSource=$script:inventory.Rows
    $errors=@($script:inventory.Rows | Where-Object { $_.Status -like '*error*' }).Count
    $controls.Status.Text="Lectura terminada: $($script:inventory.Rows.Count) datos, $errors consultas con error. Selecciona una fila para ver sus opciones."
}
function Show-HuellaResult($Result) {
    $script:lastBackup=$Result.Path
    $status=$Result.Record.Status; $verification=$Result.Record.Verification
    $controls.Status.Text="Operacion: $status. Verificacion: $verification. Respaldo: $($Result.Path)"
    if ($status -eq 'Failed') { throw "El cambio fallo: $($Result.Record.Error). El respaldo se conservo en $($Result.Path). Puede haber un cambio parcial; verifica antes de restaurar." }
    $message= switch ($verification) {
        'Verified' { 'El valor leido coincide con el solicitado.' }
        'RebootRequired' { 'El nuevo nombre esta configurado. Reinicia Windows y pulsa Verificar respaldo para comprobar el nombre activo.' }
        default { 'El valor aun no coincide. Pulsa Verificar respaldo despues de que el dispositivo termine de reiniciarse.' }
    }
    $null=[Windows.MessageBox]::Show($window,"$message`n`nRespaldo: $($Result.Path)",'Resultado','OK','Information')
}
$controls.Grid.Add_SelectionChanged({
    $row=$controls.Grid.SelectedItem
    $controls.Apply.IsEnabled=$false; $controls.Generate.IsEnabled=$false
    if ($null -ne $row) {
        $controls.Details.Text="$($row.Source)`n$($row.Detail)"
        $available=$row.Action -in @('Cambiar nombre','Cambiar MAC','MAC virtual de laboratorio')
        $controls.Apply.IsEnabled=$available
        $controls.Generate.IsEnabled=$available -and $row.Kind -ne 'ComputerName'
        $controls.Value.Text=if ($available) { $row.Value } else { '' }
    }
})
$controls.Refresh.Add_Click({ try { Update-HuellaInventory } catch { Show-HuellaError $_ } })
$controls.Generate.Add_Click({ try { $controls.Value.Text=New-HuellaMacAddress } catch { Show-HuellaError $_ } })
$controls.Apply.Add_Click({
    try {
        $row=$controls.Grid.SelectedItem
        if ($null -eq $row) { throw 'Selecciona un identificador.' }
        $extra=if ($row.Kind -eq 'ComputerName') { 'Se requiere reiniciar Windows. No se reinicia automaticamente.' } else { 'Cambiar la MAC del adaptador fisico corta su conexion; no lo hagas durante una sesion remota que dependa de esa interfaz.' }
        if ($row.Kind -eq 'VirtualMacAddress') { $extra='Confirmas que esta es una VM apagada y dedicada al laboratorio.' }
        if (-not (Confirm-Huella "Cambiar $($row.Label) a $($controls.Value.Text)?`n`n$extra`nSe guarda el valor anterior antes del cambio.")) { return }
        $result=Invoke-HuellaChange -Kind $row.Kind -Target $row.Target -NewValue $controls.Value.Text -LabVm:([bool]$controls.HyperV.IsChecked) -Confirm:$false
        Show-HuellaResult $result
        Update-HuellaInventory
    } catch { Show-HuellaError $_ }
})
$controls.Restore.Add_Click({
    try {
        $path=Select-HuellaFile $false 'Respaldos Huella (*.json)|*.json' $script:lastBackup
        if ($path -eq '' -or -not (Confirm-Huella 'Restaurar el valor de este respaldo? Puede reiniciar el adaptador o requerir reiniciar Windows. Se guardara tambien la configuracion actual.')) { return }
        Show-HuellaResult (Restore-HuellaChange -Path $path -LabVm:([bool]$controls.HyperV.IsChecked) -Confirm:$false)
        Update-HuellaInventory
    } catch { Show-HuellaError $_ }
})
$controls.Verify.Add_Click({
    try {
        $path=Select-HuellaFile $false 'Respaldos Huella (*.json)|*.json' $script:lastBackup
        if ($path -eq '') { return }
        $result=Test-HuellaChange $path
        $controls.Status.Text="Verificacion: $($result.Verification). Estado registrado: $($result.OperationStatus)."
        $null=[Windows.MessageBox]::Show($window,$controls.Status.Text,'Verificacion','OK','Information')
    } catch { Show-HuellaError $_ }
})
$controls.Export.Add_Click({
    try {
        $path=Select-HuellaFile $true 'Inventario JSON (*.json)|*.json' ('huella-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
        if ($path -eq '') { return }
        Export-HuellaInventory $script:inventory $path
        $controls.Status.Text='Inventario guardado localmente. Contiene identificadores del equipo: '+$path
    } catch { Show-HuellaError $_ }
})
$controls.Admin.Add_Click({
    try {
        if (Test-HuellaAdministrator) { $controls.Status.Text='Esta ventana ya tiene permisos de administrador.'; return }
        # Keep the normal execution policy. No policy override or profile loading.
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $null=Start-Process -FilePath $exe -Verb RunAs -ArgumentList @('-NoProfile','-STA','-File',('"'+$PSCommandPath+'"')) -ErrorAction Stop
        $window.Close()
    } catch { Show-HuellaError $_ }
})
$controls.FirmwarePlan.Add_Click({
    try {
        $path=Select-HuellaFile $true 'Plan de firmware (*.json)|*.json' ('firmware-plan-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
        if ($path -eq '') { return }
        $plan=New-HuellaFirmwarePlan $path
        $script:plan=$plan; $script:planPath=$path; $script:packageCheck=$null; $script:capsule=$null
        $controls.FirmwareLaunch.IsEnabled=$false; $controls.FirmwareCopy.IsEnabled=$false
        $isAsus=$plan.Route.Mode -eq 'AsusUefi'
        $controls.AsusPanel.Visibility=if ($isAsus) { 'Visible' } else { 'Collapsed' }
        $controls.FirmwareCheck.Content=if ($isAsus) { '2. Preparar ZIP BIOS' } else { '2. Revisar paquete oficial' }
        $controls.FirmwareLaunch.Content=if ($isAsus) { 'Abrir manual ASUS EZ Flash' } else { '3. Abrir asistente del fabricante' }
        $message="Equipo: $($plan.Target.Manufacturer) $($plan.Target.Model)`nPlaca: $($plan.Target.BoardProducts -join ', ')`nBIOS actual: $($plan.Target.BiosVersion)`n`nActualizar firmware no garantiza cambiar seriales. Comprueba el procedimiento y la recuperacion para este modelo en el soporte oficial."
        if ($plan.SupportUrl -ne '' -and (Confirm-Huella ($message+"`n`nAbrir $($plan.SupportUrl)?"))) { $null=Start-Process $plan.SupportUrl }
        else { $null=[Windows.MessageBox]::Show($window,$message,'Plan BIOS/UEFI','OK','Information') }
        $controls.Status.Text='Plan guardado: '+$path
    } catch { Show-HuellaError $_ }
})
$controls.FirmwareCheck.Add_Click({
    try {
        if ($script:planPath -eq '') { throw 'Primero crea el plan BIOS/UEFI.' }
        $script:packageCheck=$null; $script:capsule=$null; $controls.FirmwareLaunch.IsEnabled=$false; $controls.FirmwareCopy.IsEnabled=$false
        if ($script:plan.Route.Mode -eq 'AsusUefi') {
            $path=Select-HuellaFile $false 'BIOS ASUS oficial (*.zip)|*.zip'
            if ($path -eq '') { return }
            $script:capsule=New-HuellaAsusCapsule -PlanPath $script:planPath -ArchivePath $path -ReferenceSha256 $controls.FirmwareHash.Text.Trim()
            $controls.FirmwareCopy.IsEnabled=$true; $controls.FirmwareLaunch.IsEnabled=$true
            $controls.Status.Text="ZIP coincide con el hash de referencia. CAP preparado: $($script:capsule.Record.CapsulePath). Falta validacion desde UEFI."
            return
        }
        $path=Select-HuellaFile $false 'Asistente oficial (*.exe)|*.exe'
        if ($path -eq '') { return }
        $script:packageCheck=Test-HuellaFirmwarePackage $script:planPath $path
        $controls.FirmwareLaunch.IsEnabled=$true
        $controls.Status.Text='Firma del fabricante valida. La compatibilidad de la imagen debe comprobarla el fabricante.'
        $null=[Windows.MessageBox]::Show($window,"$($controls.Status.Text)`n`nModelo: $($script:packageCheck.Model)`nEditor: $($script:packageCheck.Publisher)`nSHA256: $($script:packageCheck.Sha256)",'Revision de paquete','OK','Information')
    } catch { Show-HuellaError $_ }
})
$controls.FirmwareLaunch.Add_Click({
    try {
        if ($null -ne $script:capsule) { $null=Start-Process $script:capsule.Record.ManualUrl; return }
        if ($null -eq $script:packageCheck) { throw 'Revisa primero el paquete.' }
        $dialog=New-Object Windows.Window
        $dialog.Title='Preparacion del firmware'; $dialog.Width=540; $dialog.Height=380; $dialog.Owner=$window; $dialog.WindowStartupLocation='CenterOwner'
        $stack=New-Object Windows.Controls.StackPanel; $stack.Margin='20'
        $label=New-Object Windows.Controls.TextBlock; $label.Text="Escribe el modelo exacto revisado: $($script:packageCheck.Model)"; $label.TextWrapping='Wrap'; $stack.Children.Add($label) | Out-Null
        $modelBox=New-Object Windows.Controls.TextBox; $modelBox.Margin='0,10,0,14'; $stack.Children.Add($modelBox) | Out-Null
        $checks=@()
        foreach ($text in @('Revise el procedimiento y la imagen para este modelo.','Prepare la recuperacion de firmware y BitLocker.','Tengo alimentacion estable segun el fabricante.')) {
            $box=New-Object Windows.Controls.CheckBox; $box.Content=$text; $box.Margin='0,6,0,6'; $stack.Children.Add($box) | Out-Null; $checks+=,$box
        }
        $button=New-Object Windows.Controls.Button; $button.Content='Abrir asistente del fabricante'; $button.Margin='0,20,0,0'; $button.Add_Click({ $dialog.DialogResult=$true }); $stack.Children.Add($button) | Out-Null
        $dialog.Content=$stack
        if (-not $dialog.ShowDialog()) { return }
        $result=Start-HuellaFirmwareUtility -PlanPath $script:planPath -PackagePath $script:packageCheck.PackagePath -ExpectedSha256 $script:packageCheck.Sha256 -ReviewedModel $modelBox.Text -VendorProcedureReviewed:([bool]$checks[0].IsChecked) -RecoveryKeyAvailable:([bool]$checks[1].IsChecked) -PowerConfirmed:([bool]$checks[2].IsChecked) -Confirm:$false
        $controls.Status.Text="Asistente: $($result.Record.Status). Huella no ha determinado si se flasheo ni si cambiaron identificadores. Registro: $($result.Path)"
        if ($result.Record.Status -eq 'LaunchFailed') { throw $result.Record.Error }
        $script:packageCheck=$null; $controls.FirmwareLaunch.IsEnabled=$false
    } catch { Show-HuellaError $_ }
})
$controls.FirmwareCopy.Add_Click({
    try {
        if ($null -eq $script:capsule) { throw 'Prepara primero el ZIP BIOS.' }
        $letter=$controls.UsbLetter.Text.Trim()
        if (-not (Confirm-Huella "Copiar la capsula al USB $letter`:? Debe ser FAT32 y ajeno al sistema. No se formatea ni se flashea. Revisa luego la imagen desde ASUS EZ Flash segun el manual.")) { return }
        $copy=Copy-HuellaFirmwareToUsb -PreparedPath $script:capsule.Path -DriveLetter $letter -Confirm:$false
        $controls.Status.Text="CAP copiado y hash comprobado: $($copy.Path). Sigue el manual desde UEFI; los seriales aun no se han cambiado."
    } catch { Show-HuellaError $_ }
})
$window.Add_ContentRendered({ try { Update-HuellaInventory } catch { Show-HuellaError $_ } })
$null=$window.ShowDialog()

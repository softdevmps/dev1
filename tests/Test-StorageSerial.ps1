#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
    [Parameter(Mandatory)][string]$PnpInstanceId,
    [Parameter(Mandatory)][switch]$PhysicalSecondary,
    [ValidatePattern('^[A-Za-z0-9_-]{1,31}$')][string]$Serial='LAB-0001',
    [string]$Checker='', [Parameter(Mandatory)][string]$ResultDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module "$root\huella\Huella.psm1" -Force
if (-not $PhysicalSecondary) { throw 'Selecciona expresamente el disco fisico secundario de pruebas.' }
if ($Checker -eq '') { $Checker="$root\out\x64\Debug\checker\Checker.exe" }
$disk=Get-Disk -Number $DiskNumber -ErrorAction Stop
if ($disk.IsBoot -or $disk.IsSystem -or $disk.IsOffline) { throw 'Rechazado disco de arranque/sistema o no disponible.' }
$devices=@(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Where-Object Index -eq $DiskNumber)
if ($devices.Count -ne 1 -or $devices[0].PNPDeviceID -ne $PnpInstanceId) { throw 'Instancia PnP no coincide con el disco seleccionado.' }
$state=Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker
if ($state.Enabled -or $state.Restricted -or $state.OriginalCapacity -lt $Serial.Length) { throw 'Se requiere un perfil desactivado y un campo de serial independiente con capacidad suficiente.' }
$checkerArgs=@('snapshot')
$snapshot=@(& $Checker @checkerArgs)
if ($LASTEXITCODE -ne 0 -or -not ($snapshot -match '^devices=1 returned=1 ')) { throw 'La prueba de concurrencia exige exactamente una instancia adjunta.' }
if (Test-Path -LiteralPath $ResultDirectory) { throw 'Usa una carpeta de resultados nueva.' }
if (-not $PSCmdlet.ShouldProcess($PnpInstanceId,'Probar sustitucion, concurrencia y restauracion de serial en consultas del disco secundario')) { return }
$null=New-Item -ItemType Directory -Path $ResultDirectory
$baseline=Join-Path $ResultDirectory 'before.bin'
$result=[pscustomobject]@{ SchemaVersion=1; DiskNumber=$DiskNumber; StartedUtc=[DateTime]::UtcNow.ToString('o'); Status='Running'; Baseline='before.bin'; Error=''; RestoreStatus='NotRequired'; ModuleScope='StorageDeviceProperty.SerialNumber' }
$change=$null
function Run-SerialChecker([string[]]$Arguments) {
    & $Checker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Checker $($Arguments[0]) fallo: $LASTEXITCODE" }
}
try {
    Run-SerialChecker @('baseline',[string]$DiskNumber,$baseline)
    Run-SerialChecker @('serial-negative')
    Run-SerialChecker @('serial-test',[string]$DiskNumber,$Serial,'--secondary')
    Run-SerialChecker @('compare',[string]$DiskNumber,$baseline)
    $change=Set-HuellaStorageProfile $DiskNumber $PnpInstanceId $Serial -PhysicalSecondary -Checker $Checker -Confirm:$false
    if ($change.Record.Status -ne 'Applied') { throw "Activacion fallida. Diario: $($change.Path)" }
    $before=Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker
    $verification=Test-HuellaStorageProfile $change.Path -Checker $Checker
    if ($verification.Verification -ne 'CheckerVerified') { throw 'La consulta no acredita el serial solicitado.' }
    Run-SerialChecker @('stress',[string]$DiskNumber,'4','200')
    $after=Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker
    if ($after.Instance -ne $before.Instance -or $after.Generation -ne $before.Generation -or
        $after.Transformed - $before.Transformed -lt 800 -or $after.Skipped -ne $before.Skipped) { throw 'Contadores de transformacion no acreditan todas las consultas concurrentes.' }
    $result.Status='ChecksPassed'
} catch { $result.Status='Failed'; $result.Error=$_.Exception.Message }
finally {
    if ($null -ne $change -and $change.Record.Status -eq 'Applied') {
        try {
            $restored=Restore-HuellaStorageProfile $change.Path -Checker $Checker -Confirm:$false
            if ($restored.Enabled) { throw 'Perfil sigue activo.' }
            Run-SerialChecker @('compare',[string]$DiskNumber,$baseline)
            $result.RestoreStatus='VerifiedAgainstBaseline'
        } catch { $result.RestoreStatus='Failed'; $result.Status='Failed'; $result.Error+=' Restauracion: '+$_.Exception.Message }
    }
    try {
        $finalState=Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker
        if ($finalState.Enabled) {
            $result.RestoreStatus='ProfileStillActive'; $result.Status='Failed'
            $result.Error+=' Perfil todavia activo; consulta el diario y el estado antes de desactivarlo expresamente.'
        }
    } catch { $result.RestoreStatus='Unknown'; $result.Status='Failed'; $result.Error+=' Estado final: '+$_.Exception.Message }
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ResultDirectory 'result.json') -Encoding UTF8
}
if ($result.Status -ne 'ChecksPassed') { throw $result.Error }
Write-Output 'PASS: consulta cubierta, concurrencia y restauracion a baseline. No acredita cambios de firmware ni otras rutas de identidad.'

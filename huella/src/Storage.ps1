function Get-HuellaCheckerPath {
    param([string]$Path)
    if ($Path -eq '') { $Path=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'out\x64\Debug\checker\Checker.exe' }
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -ine '.exe' -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Selecciona Checker.exe compilado desde este proyecto.' }
    return $file.FullName
}

function Get-HuellaSecondaryDisk {
    param([int]$DiskNumber,[string]$PnpInstanceId,[switch]$AllowProtectedRead)
    if ($DiskNumber -lt 1 -or $DiskNumber -gt 1024 -or [string]::IsNullOrWhiteSpace($PnpInstanceId)) { throw 'Selecciona un disco secundario con su ID de instancia PnP.' }
    $disk=Invoke-HuellaSystem SecondaryDisk @{ DiskNumber=$DiskNumber }
    if ($disk.Number -ne $DiskNumber -or $disk.PnpInstanceId -ne $PnpInstanceId) { throw 'El disco seleccionado cambio de instancia desde la lectura.' }
    if (-not $AllowProtectedRead -and ($disk.IsBoot -or $disk.IsSystem -or $disk.IsOffline)) { throw 'El disco debe ser secundario, estar disponible y ser ajeno al arranque/sistema.' }
    return $disk
}

function ConvertFrom-HuellaStorageStatus {
    param([object[]]$Output)
    $matches=@($Output | ForEach-Object {
        $match=[regex]::Match([string]$_,'^serial instance=(\d+) disk=(\d+) enabled=(0|1) capacity=(\d+) generation=(\d+) transformed=(\d+) skipped=(\d+) lastResult=(\d+) restricted=(0|1)$')
        if ($match.Success) { $match }
    })
    if ($matches.Count -ne 1) { throw 'Checker no devolvio un estado de perfil reconocido y unico.' }
    $g=$matches[0].Groups
    [pscustomobject]@{
        Instance=[uint32]$g[1].Value; DiskNumber=[uint32]$g[2].Value; Enabled=$g[3].Value -eq '1'
        OriginalCapacity=[uint32]$g[4].Value; Generation=[uint64]$g[5].Value
        Transformed=[uint64]$g[6].Value; Skipped=[uint64]$g[7].Value; LastResult=[uint32]$g[8].Value
        Restricted=$g[9].Value -eq '1'; Scope='StorageDeviceProperty.SerialNumber'
    }
}

function Get-HuellaStorageProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
        [Parameter(Mandatory)][string]$PnpInstanceId,[string]$Checker='')
    $null=Get-HuellaSecondaryDisk $DiskNumber $PnpInstanceId -AllowProtectedRead
    $path=Get-HuellaCheckerPath $Checker
    $output=@(Invoke-HuellaSystem Checker @{ Path=$path; CommandArguments=@('serial-status',[string]$DiskNumber) })
    $state=ConvertFrom-HuellaStorageStatus $output
    if ($state.DiskNumber -ne $DiskNumber) { throw 'Checker devolvio un disco distinto del seleccionado.' }
    return $state
}

function Set-HuellaStorageProfile {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
        [Parameter(Mandatory)][string]$PnpInstanceId,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]{1,31}$')][string]$Serial,
        [Parameter(Mandatory)][switch]$PhysicalSecondary,[string]$Checker='')
    if (-not $PhysicalSecondary) { throw 'Confirma expresamente el disco fisico secundario seleccionado.' }
    if (-not (Invoke-HuellaSystem Administrator)) { throw 'Abre Huella como administrador.' }
    $null=Get-HuellaSecondaryDisk $DiskNumber $PnpInstanceId
    $before=Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker
    if ($before.Enabled) { throw 'Ya hay un perfil activo. Desactivalo antes de aplicar otro para conservar una restauracion clara.' }
    if ($before.Restricted -or $before.OriginalCapacity -lt $Serial.Length) { throw 'Dispositivo restringido o serial nuevo mas largo que el campo original.' }
    if (-not $PSCmdlet.ShouldProcess($PnpInstanceId,'Activar sustitucion temporal de serial en StorageDeviceProperty con diario y verificacion')) { return }
    $path=Get-HuellaCheckerPath $Checker
    $record=[pscustomobject]@{
        SchemaVersion=1; Type='StorageSerialProfile'; MachineBinding=(Invoke-HuellaSystem MachineBinding)
        DiskNumber=$DiskNumber; PnpInstanceId=$PnpInstanceId; Instance=$before.Instance; Serial=$Serial
        CreatedUtc=[DateTime]::UtcNow.ToString('o'); Status='Prepared'; Error=''; Restore='RemoveProfile'
        Scope='StorageDeviceProperty.SerialNumber'; FirmwareChanged=$false; Verification='NotChecked'; AppliedGeneration=[uint64]0
    }
    $journal=Join-Path (Get-HuellaDataDirectory) ('storage-'+[Guid]::NewGuid().ToString('N')+'.json')
    Write-HuellaJson $record $journal
    try {
        $null=Get-HuellaSecondaryDisk $DiskNumber $PnpInstanceId
        $record.Status='Applying'; Write-HuellaJson $record $journal -Replace
        $output=@(Invoke-HuellaSystem Checker @{ Path=$path; CommandArguments=@('serial-set',[string]$DiskNumber,$Serial,'--secondary','--generation',[string]$before.Generation,'--instance',[string]$before.Instance) })
        $after=ConvertFrom-HuellaStorageStatus $output
        if (-not $after.Enabled -or $after.DiskNumber -ne $DiskNumber -or $after.Instance -ne $before.Instance -or $after.Generation -ne ($before.Generation+1) -or $after.Transformed -le $before.Transformed -or $after.Skipped -ne $before.Skipped) { throw 'El perfil o sus contadores no coinciden con la verificacion esperada.' }
        $record.AppliedGeneration=$after.Generation
        $record.Status='Applied'; $record.Verification='CheckerVerified'
    } catch {
        $record.Status='Failed'; $record.Error=$_.Exception.Message
        # Checker rolls back a failed activation when its control call succeeds.
        # If execution was interrupted, retain Applying/Failed for manual review.
    }
    try { Write-HuellaJson $record $journal -Replace }
    catch { throw "No se pudo cerrar el diario. Consulta el perfil antes de continuar. Diario: $journal. Error: $($_.Exception.Message)" }
    return [pscustomobject]@{ Path=$journal; Record=$record }
}

function Remove-HuellaStorageProfile {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
        [Parameter(Mandatory)][string]$PnpInstanceId,[string]$Checker='', [uint64]$ExpectedGeneration, [uint32]$ExpectedInstance)
    $null=Get-HuellaSecondaryDisk $DiskNumber $PnpInstanceId -AllowProtectedRead
    $path=Get-HuellaCheckerPath $Checker
    if ($PSCmdlet.ShouldProcess($PnpInstanceId,'Desactivar el perfil de serial; las respuestas nuevas conservan el dato del inferior')) {
        $arguments=@('serial-clear',[string]$DiskNumber)
        if ($PSBoundParameters.ContainsKey('ExpectedGeneration')) { $arguments+=@('--generation',[string]$ExpectedGeneration) }
        if ($PSBoundParameters.ContainsKey('ExpectedInstance')) {
            if (-not $PSBoundParameters.ContainsKey('ExpectedGeneration')) { throw 'La instancia esperada requiere su generacion.' }
            $arguments+=@('--instance',[string]$ExpectedInstance)
        }
        $output=@(Invoke-HuellaSystem Checker @{ Path=$path; CommandArguments=$arguments })
        $status=ConvertFrom-HuellaStorageStatus $output
        if ($status.DiskNumber -ne $DiskNumber -or $status.Enabled) { throw 'El perfil sigue activo o cambio la seleccion.' }
        return $status
    }
}

function Restore-HuellaStorageProfile {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Path,[string]$Checker='')
    $record=Read-HuellaJson $Path
    if ($record.SchemaVersion -ne 1 -or $record.Type -ne 'StorageSerialProfile' -or $record.MachineBinding -ne (Invoke-HuellaSystem MachineBinding)) { throw 'Diario de perfil invalido o de otro equipo.' }
    $state=Get-HuellaStorageProfile $record.DiskNumber $record.PnpInstanceId $Checker
    if (-not $state.Enabled) { return $state }
    if ($record.Status -ne 'Applied' -or $record.Instance -ne $state.Instance -or $record.AppliedGeneration -ne $state.Generation) { throw 'El perfil activo cambio o no fue confirmado por este diario; revisa el estado antes de desactivarlo expresamente.' }
    if ($PSCmdlet.ShouldProcess($record.PnpInstanceId,'Desactivar perfil documentado y restaurar respuestas del inferior')) {
        Remove-HuellaStorageProfile $record.DiskNumber $record.PnpInstanceId $Checker -ExpectedGeneration $record.AppliedGeneration -ExpectedInstance $record.Instance -Confirm:$false
    }
}

function Test-HuellaStorageProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[string]$Checker='')
    $record=Read-HuellaJson $Path
    if ($record.SchemaVersion -ne 1 -or $record.Type -ne 'StorageSerialProfile' -or $record.MachineBinding -ne (Invoke-HuellaSystem MachineBinding)) { throw 'Diario de perfil invalido o de otro equipo.' }
    $state=Get-HuellaStorageProfile $record.DiskNumber $record.PnpInstanceId $Checker
    $verification='ProfileChangedOrInactive'
    if ($record.Status -eq 'Applied' -and $state.Enabled -and $state.Instance -eq $record.Instance -and $state.Generation -eq $record.AppliedGeneration) {
        $checkerPath=Get-HuellaCheckerPath $Checker
        $output=@(Invoke-HuellaSystem Checker @{ Path=$checkerPath; CommandArguments=@('serial-expect',[string]$record.DiskNumber,$record.Serial,'--generation',[string]$record.AppliedGeneration,'--instance',[string]$record.Instance) })
        $after=ConvertFrom-HuellaStorageStatus $output
        if ($after.Enabled -and $after.DiskNumber -eq $record.DiskNumber -and $after.Instance -eq $record.Instance -and $after.Generation -eq $record.AppliedGeneration) { $verification='CheckerVerified' }
    }
    [pscustomobject]@{ Verification=$verification; OperationStatus=$record.Status; Scope=$record.Scope; FirmwareChanged=$false }
}

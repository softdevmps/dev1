function Get-HuellaAdapter {
    param([string]$Target)
    $guid=[Guid]::Empty
    if (-not [Guid]::TryParse($Target,[ref]$guid) -or $guid -eq [Guid]::Empty) { throw 'GUID de adaptador invalido.' }
    $matches=@(Invoke-HuellaSystem Adapters | Where-Object { [string]$_.InterfaceGuid -eq $Target })
    if ($matches.Count -ne 1) { throw 'El adaptador ya no existe o no es unico.' }
    return $matches[0]
}

function Get-HuellaVirtualAdapter {
    param([string]$Target)
    $parts=$Target.Split('|')
    if ($parts.Count -ne 2) { throw 'Destino virtual invalido.' }
    $vm=@(Invoke-HuellaSystem VirtualMachines | Where-Object { [string]$_.Id -eq $parts[0] })
    if ($vm.Count -ne 1 -or [string]$vm[0].State -ne 'Off') { throw 'La VM de laboratorio debe existir y estar apagada.' }
    $adapters=@(Invoke-HuellaSystem VirtualAdapters @{ VM=$vm[0] } | Where-Object { [string]$_.Id -eq $parts[1] })
    if ($adapters.Count -ne 1) { throw 'El adaptador virtual ya no existe o no es unico.' }
    return $adapters[0]
}

function Get-HuellaActionState {
    param([string]$Kind, [string]$Target)
    switch ($Kind) {
        'ComputerName' {
            if ($Target -ne 'Computer') { throw 'Destino de nombre invalido.' }
            $system=@(Invoke-HuellaSystem Cim @{ ClassName='Win32_ComputerSystem' })
            if ($system.Count -ne 1 -or [bool]$system[0].PartOfDomain) { throw 'Este flujo de cambio de nombre requiere un equipo fuera de dominio.' }
            $names=Invoke-HuellaSystem ComputerNames
            return [pscustomobject]@{ Configured=[string]$names.Configured; Effective=[string]$names.Active }
        }
        'MacAddress' {
            $adapter=Get-HuellaAdapter $Target
            if (-not [bool]$adapter.HardwareInterface) { throw 'Usa la accion virtual para adaptadores de laboratorio.' }
            $properties=@(Invoke-HuellaSystem NetworkProperty @{ Name=[WildcardPattern]::Escape($adapter.Name); RegistryKeyword='NetworkAddress' })
            if ($properties.Count -ne 1) { throw 'El controlador no admite NetworkAddress.' }
            $values=@($properties[0].RegistryValue)
            if ($values.Count -gt 1) { throw 'NetworkAddress tiene un formato no admitido.' }
            $configured=if ($values.Count -eq 0 -or $null -eq $values[0]) { '' } else { [string]$values[0] }
            if ($configured -ne '' -and $configured -notmatch '^[0-9a-fA-F]{12}$') { throw 'Override anterior no reconocido; no se puede respaldar con seguridad.' }
            return [pscustomobject]@{ Configured=$configured.ToUpperInvariant(); Effective=([string]$adapter.MacAddress -replace '[:-]','').ToUpperInvariant() }
        }
        'VirtualMacAddress' {
            $adapter=Get-HuellaVirtualAdapter $Target
            return [pscustomobject]@{ Configured=([string]$adapter.MacAddress).ToUpperInvariant(); Effective=([string]$adapter.MacAddress).ToUpperInvariant(); Dynamic=[bool]$adapter.DynamicMacAddressEnabled }
        }
        default { throw 'No hay una accion documentada para este identificador.' }
    }
}

function Set-HuellaActionState {
    param([string]$Kind, [string]$Target, $State)
    switch ($Kind) {
        'ComputerName' { $null=Invoke-HuellaSystem RenameComputer @{ NewName=$State.Configured } }
        'MacAddress' {
            $adapter=Get-HuellaAdapter $Target
            $name=[WildcardPattern]::Escape($adapter.Name)
            if ($State.Configured -eq '') {
                $null=Invoke-HuellaSystem ResetNetworkProperty @{ Name=$name; RegistryKeyword='NetworkAddress' }
            } else {
                $null=Invoke-HuellaSystem SetNetworkProperty @{ Name=$name; RegistryKeyword='NetworkAddress'; RegistryValue=@([string]$State.Configured) }
            }
            $null=Invoke-HuellaSystem RestartAdapter @{ Name=$name }
        }
        'VirtualMacAddress' {
            $adapter=Get-HuellaVirtualAdapter $Target
            $arguments=@{ VMNetworkAdapter=$adapter }
            if ($State.Dynamic) { $arguments.DynamicMacAddress=$true } else { $arguments.StaticMacAddress=$State.Configured }
            $null=Invoke-HuellaSystem SetVirtualAdapter $arguments
        }
        default { throw 'Accion desconocida.' }
    }
}

function Assert-HuellaRecord {
    param($Record)
    if ($Record.SchemaVersion -ne 1 -or $Record.Type -ne 'IdentifierChange' -or $Record.Kind -notin @('ComputerName','MacAddress','VirtualMacAddress')) { throw 'Respaldo no compatible.' }
    if ($Record.MachineBinding -ne (Invoke-HuellaSystem MachineBinding)) { throw 'El respaldo corresponde a otro equipo.' }
    foreach ($state in @($Record.Before,$Record.Desired)) {
        if ($Record.Kind -eq 'ComputerName') { $null=ConvertTo-HuellaComputerName $state.Configured }
        elseif ($state.Configured -ne '' -and $state.Configured -notmatch '^[0-9A-Fa-f]{12}$') { throw 'MAC en respaldo invalida.' }
        if ($Record.Kind -eq 'VirtualMacAddress' -and $state.Dynamic -isnot [bool]) { throw 'Configuracion dinamica invalida.' }
    }
}

function Compare-HuellaState {
    param([string]$Kind, $Actual, $Expected)
    if ($Kind -eq 'VirtualMacAddress' -and $Expected.Dynamic) {
        if ($Actual.Dynamic) { return 'Verified' }
        return 'VerificationPending'
    }
    if ($Actual.Configured -ne $Expected.Configured) { return 'VerificationPending' }
    if ($Kind -eq 'ComputerName') {
        if ($Actual.Effective -eq $Expected.Configured) { return 'Verified' }
        return 'RebootRequired'
    }
    if ($Actual.Effective -eq $Expected.Effective) { return 'Verified' }
    return 'VerificationPending'
}

function Invoke-HuellaTransaction {
    param([string]$Kind,[string]$Target,$Before,$Desired,[string]$Restores='')
    if (-not (Invoke-HuellaSystem Administrator)) { throw 'Abre Huella como administrador para aplicar cambios.' }
    $binding=Invoke-HuellaSystem MachineBinding
    $prefix=if ($env:OS -eq 'Windows_NT') { 'Global\Huella-IdentifierChange-' } else { 'Huella-IdentifierChange-' }
    $mutex=New-Object Threading.Mutex($false, ($prefix + $binding))
    $owned=$false
    try {
        try { $owned=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned=$true }
        if (-not $owned) { throw 'Ya hay un cambio en curso en este equipo.' }
        $current=Get-HuellaActionState $Kind $Target
        if (($current | ConvertTo-Json -Compress) -ne ($Before | ConvertTo-Json -Compress)) { throw 'El dispositivo cambio desde la lectura. Actualiza el inventario.' }
        $directory=Get-HuellaDataDirectory
        $record=[pscustomobject]@{
            SchemaVersion=1; Type='IdentifierChange'; Id=[Guid]::NewGuid().ToString(); MachineBinding=$binding
            Kind=$Kind; Target=$Target; Before=$Before; Desired=$Desired; Restores=$Restores
            CreatedUtc=[DateTime]::UtcNow.ToString('o'); UpdatedUtc=[DateTime]::UtcNow.ToString('o')
            Status='Prepared'; Error=''; Verification='NotChecked'
        }
        $path=Join-Path $directory ($record.Id+'.json')
        # Must be durable BEFORE the first change. Never overwrite another backup.
        Write-HuellaJson $record $path
        $record.Status='Applying'
        Write-HuellaJson $record $path -Replace
        try {
            Set-HuellaActionState $Kind $Target $Desired
            $record.Status='Applied'
            $record.Verification=Compare-HuellaState $Kind (Get-HuellaActionState $Kind $Target) $Desired
        } catch {
            $record.Status='Failed'; $record.Error=$_.Exception.Message
            # A failed restart may follow a successful property write. Preserve
            # the backup and expose the failure; never report success or auto-undo.
        }
        $record.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
        Write-HuellaJson $record $path -Replace
        return [pscustomobject]@{ Path=$path; Record=$record }
    } finally { if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Invoke-HuellaChange {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][ValidateSet('ComputerName','MacAddress','VirtualMacAddress')][string]$Kind,
        [Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$NewValue,[switch]$LabVm)
    if ($Kind -eq 'VirtualMacAddress' -and -not $LabVm) { throw 'Debes seleccionar expresamente una VM de laboratorio.' }
    $value=if ($Kind -eq 'ComputerName') { ConvertTo-HuellaComputerName $NewValue } else { ConvertTo-HuellaMac $NewValue }
    $before=Get-HuellaActionState $Kind $Target
    $desired=[pscustomobject]@{ Configured=$value; Effective=$value }
    if ($Kind -eq 'VirtualMacAddress') { $desired | Add-Member -NotePropertyName Dynamic -NotePropertyValue $false }
    if ($before.Configured -eq $value -and ($Kind -ne 'VirtualMacAddress' -or -not $before.Dynamic)) { throw 'El valor solicitado ya esta configurado.' }
    if ($Kind -in @('MacAddress','VirtualMacAddress')) {
        $macs=@(Invoke-HuellaSystem Adapters | ForEach-Object { ([string]$_.MacAddress -replace '[:-]','').ToUpperInvariant() })
        if ($macs -contains $value) { throw 'La MAC ya esta en uso por otra interfaz visible. Elige otra.' }
        # This check covers only the local host. The application explicitly does
        # not claim to detect duplicates throughout the physical network.
    }
    if ($PSCmdlet.ShouldProcess($Target,"$Kind -> $value (con respaldo)")) { Invoke-HuellaTransaction $Kind $Target $before $desired }
}

function Restore-HuellaChange {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Path,[switch]$LabVm)
    $record=Read-HuellaJson $Path
    Assert-HuellaRecord $record
    if ($record.Kind -eq 'VirtualMacAddress' -and -not $LabVm) { throw 'Confirma que la VM es de laboratorio.' }
    $current=Get-HuellaActionState $record.Kind $record.Target
    if ($PSCmdlet.ShouldProcess($record.Target,'Restaurar configuracion anterior y crear un nuevo respaldo')) {
        Invoke-HuellaTransaction $record.Kind $record.Target $current $record.Before $record.Id
    }
}

function Test-HuellaChange {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $record=Read-HuellaJson $Path
    Assert-HuellaRecord $record
    $actual=Get-HuellaActionState $record.Kind $record.Target
    [pscustomobject]@{ Id=$record.Id; OperationStatus=$record.Status; Verification=(Compare-HuellaState $record.Kind $actual $record.Desired); Actual=$actual; Expected=$record.Desired }
}

function Get-HuellaHistory {
    $directory=Get-HuellaDataDirectory
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object LastWriteTimeUtc -Descending)) {
        try {
            $record=Read-HuellaJson $file.FullName
            if ($record.Type -eq 'IdentifierChange') { [pscustomobject]@{ Path=$file.FullName; Record=$record } }
        } catch { Write-Warning "Respaldo ilegible: $($file.Name): $($_.Exception.Message)" }
    }
}

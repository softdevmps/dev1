function New-HuellaRow {
    param([string]$Category, [string]$Label, $Value, [string]$Source,
        [string]$Status = 'Leido', [string]$Action = 'Observacion',
        [string]$Kind = '', [string]$Target = '', [string]$Detail = '')
    [pscustomobject]@{
        Category=$Category; Label=$Label; Value=(ConvertTo-HuellaText $Value)
        Source=$Source; Status=$Status; Action=$Action; Kind=$Kind; Target=$Target; Detail=$Detail
    }
}

function Get-HuellaInventory {
    [CmdletBinding()]
    param([switch]$IncludeHyperV)
    $rows = New-Object 'Collections.Generic.List[object]'
    $firmwareNote = 'El firmware publica este dato. Actualizarlo no garantiza cambiar el identificador; requiere procedimiento del fabricante para este modelo.'
    $groups = @(
        @{ Category='Placa madre'; Class='Win32_BaseBoard'; Fields=@('SerialNumber','Manufacturer','Product') },
        @{ Category='Sistema'; Class='Win32_ComputerSystemProduct'; Fields=@('UUID','IdentifyingNumber','Vendor','Name') },
        @{ Category='BIOS'; Class='Win32_BIOS'; Fields=@('SerialNumber','SMBIOSBIOSVersion','Manufacturer') },
        @{ Category='Chasis'; Class='Win32_SystemEnclosure'; Fields=@('SerialNumber','SMBIOSAssetTag') },
        @{ Category='RAM'; Class='Win32_PhysicalMemory'; Fields=@('SerialNumber','PartNumber','DeviceLocator') },
        @{ Category='CPU'; Class='Win32_Processor'; Fields=@('Name','ProcessorId'); Note='ProcessorId describe caracteristicas segun plataforma; no demuestra un serial unico.' },
        @{ Category='GPU'; Class='Win32_VideoController'; Fields=@('Name','PNPDeviceID'); Note='El ID PnP completo identifica la instancia/modelo; no se interpreta como serial del chip.' },
        @{ Category='Disco fisico'; Class='Win32_DiskDrive'; Fields=@('Model','SerialNumber','PNPDeviceID'); Note='Serial del dispositivo, distinto del GUID del disco y del serial del volumen. Sin API generica de reescritura.' },
        @{ Category='Volumen'; Class='Win32_Volume'; Fields=@('DeviceID','DriveLetter','SerialNumber'); Note='Identificador del sistema de archivos; no es el serial fisico del disco.' }
    )
    foreach ($group in $groups) {
        try {
            $objects = @(Invoke-HuellaSystem Cim @{ ClassName=$group.Class })
            $index = 0
            foreach ($object in $objects) {
                $index++
                foreach ($field in $group.Fields) {
                    $detail = if ($group.ContainsKey('Note')) { $group.Note } else { $firmwareNote }
                    $action = if ($group.Category -in @('Placa madre','Sistema','BIOS','Chasis')) { 'Plan de fabricante' } else { 'Observacion' }
                    $value = Get-HuellaProperty $object $field
                    $status = if ([string]::IsNullOrWhiteSpace((ConvertTo-HuellaText $value))) { 'Sin dato' } else { 'Leido' }
                    $rows.Add((New-HuellaRow $group.Category "$field [$index]" $value "$($group.Class).$field" $status $action 'FirmwareSystem' 'System' $detail))
                }
            }
            if ($objects.Count -eq 0) { $rows.Add((New-HuellaRow $group.Category 'Consulta' '' $group.Class 'Sin dispositivos')) }
        } catch { $rows.Add((New-HuellaRow $group.Category 'Consulta' '' $group.Class 'Error de lectura' -Detail $_.Exception.Message)) }
    }
    try {
        foreach ($disk in @(Invoke-HuellaSystem Disks)) {
            $style = ConvertTo-HuellaText (Get-HuellaProperty $disk 'PartitionStyle')
            $id = if ($style -eq 'GPT') { Get-HuellaProperty $disk 'Guid' } else { Get-HuellaProperty $disk 'Signature' }
            $rows.Add((New-HuellaRow 'Tabla de particiones' "Disco #$($disk.Number) ($style)" $id 'Get-Disk' -Detail 'Observacion. Huella no reparticiona ni escribe sectores para cambiar identificadores.'))
        }
    } catch { $rows.Add((New-HuellaRow 'Tabla de particiones' 'Consulta' '' 'Get-Disk' 'Error de lectura' -Detail $_.Exception.Message)) }
    try {
        foreach ($adapter in @(Invoke-HuellaSystem Adapters)) {
            $target = [string]$adapter.InterfaceGuid
            $action='Observacion'; $detail='El controlador no publico una propiedad NetworkAddress utilizable.'
            try {
                $property = @(Invoke-HuellaSystem NetworkProperty @{ Name=[WildcardPattern]::Escape($adapter.Name); RegistryKeyword='NetworkAddress' })
                if ($property.Count -eq 1 -and [bool](Get-HuellaProperty $adapter 'HardwareInterface' $false)) {
                    $action='Cambiar MAC'; $detail='Override soportado por el controlador. Persiste hasta restaurar y reinicia el adaptador; se interrumpe la conexion. No cambia la MAC grabada en fabrica.'
                }
            } catch { $detail = 'Propiedad no disponible: ' + $_.Exception.Message }
            $rows.Add((New-HuellaRow 'Red' "$($adapter.Name) MAC" $adapter.MacAddress 'Get-NetAdapter' 'Leido' $action 'MacAddress' $target $detail))
            $rows.Add((New-HuellaRow 'Red' "$($adapter.Name) GUID" $target 'Get-NetAdapter.InterfaceGuid' -Detail 'GUID de la interfaz de Windows, distinto de la MAC.'))
        }
    } catch { $rows.Add((New-HuellaRow 'Red' 'Consulta' '' 'Get-NetAdapter' 'Error de lectura' -Detail $_.Exception.Message)) }
    try {
        foreach ($monitor in @(Invoke-HuellaSystem Cim @{ Namespace='root\wmi'; ClassName='WmiMonitorID' })) {
            $instance = [string]$monitor.InstanceName
            $device = $instance -replace '_\d+$',''
            if ($device -notmatch '^DISPLAY\\[^\\]+\\[^\\]+$') { throw 'InstanceName de monitor invalido.' }
            $name = -join (@($monitor.UserFriendlyName) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
            $serial = -join (@($monitor.SerialNumberID) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
            $detail='EDID asociado por InstanceName: ' + $instance
            try {
                $edid = Invoke-HuellaSystem Edid @{ Path="HKLM:\SYSTEM\CurrentControlSet\Enum\$device\Device Parameters" }
                $decoded = ConvertFrom-HuellaEdid ([byte[]]$edid)
                $detail += "; fabricante $($decoded.Manufacturer), serial numerico $($decoded.NumericSerial)"
            } catch { $detail += '; EDID: ' + $_.Exception.Message }
            $rows.Add((New-HuellaRow 'Monitor' $name $serial 'WmiMonitorID.SerialNumberID' 'Leido' 'Observacion' '' $instance $detail))
        }
    } catch { $rows.Add((New-HuellaRow 'Monitor' 'Consulta' '' 'WmiMonitorID' 'Error de lectura' -Detail $_.Exception.Message)) }
    try {
        foreach ($device in @(Invoke-HuellaSystem Cim @{ ClassName='Win32_PnPEntity'; Filter="PNPDeviceID LIKE 'USB%'" } | Where-Object { $_.PNPDeviceID -like 'USB\*' })) {
            $rows.Add((New-HuellaRow 'USB' $device.Name $device.PNPDeviceID 'Win32_PnPEntity.PNPDeviceID' -Detail 'ID completo de instancia. El sufijo puede ser serial del fabricante o ID generado por Windows; no se afirma unicidad.'))
        }
    } catch { $rows.Add((New-HuellaRow 'USB' 'Consulta' '' 'Win32_PnPEntity' 'Error de lectura' -Detail $_.Exception.Message)) }
    foreach ($entry in @(
        @{ Label='MachineGuid'; Path='HKLM:\SOFTWARE\Microsoft\Cryptography'; Name='MachineGuid' },
        @{ Label='ProductId'; Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Name='ProductId' }
    )) {
        try { $rows.Add((New-HuellaRow 'Windows' $entry.Label (Invoke-HuellaSystem Registry @{ Path=$entry.Path; Name=$entry.Name }) 'Registro' -Detail 'Observacion. Editar este texto no regenera la instalacion, SID ni licencia de Windows.')) }
        catch { $rows.Add((New-HuellaRow 'Windows' $entry.Label '' 'Registro' 'Error de lectura' -Detail $_.Exception.Message)) }
    }
    try {
        $names=Invoke-HuellaSystem ComputerNames
        $rows.Add((New-HuellaRow 'Windows' 'Nombre de la PC' $names.Active 'ComputerName' 'Leido' 'Cambiar nombre' 'ComputerName' 'Computer' "Nombre configurado: $($names.Configured). Requiere reiniciar Windows; el cambio puede revertirse con el respaldo."))
    } catch { $rows.Add((New-HuellaRow 'Windows' 'Nombre de la PC' '' 'ComputerName' 'Error de lectura' -Detail $_.Exception.Message)) }
    try {
        foreach ($account in @(Invoke-HuellaSystem Cim @{ ClassName='Win32_UserAccount'; Filter='LocalAccount=True' })) {
            $rows.Add((New-HuellaRow 'Windows' "SID cuenta local: $($account.Name)" $account.SID 'Win32_UserAccount.SID' -Detail 'SID de esta cuenta; no se presenta como un SID universal del equipo. No se edita SAM.'))
        }
    } catch { $rows.Add((New-HuellaRow 'Windows' 'Cuentas' '' 'Win32_UserAccount' 'Error de lectura' -Detail $_.Exception.Message)) }
    try {
        $enabled=Invoke-HuellaSystem SecureBoot
        $rows.Add((New-HuellaRow 'Protecciones' 'Secure Boot' $enabled 'Confirm-SecureBootUEFI'))
    } catch { $rows.Add((New-HuellaRow 'Protecciones' 'Secure Boot' '' 'Confirm-SecureBootUEFI' 'No disponible / error' -Detail $_.Exception.Message)) }
    try {
        $tpm=Invoke-HuellaSystem Tpm
        $rows.Add((New-HuellaRow 'TPM' 'Presente' $tpm.TpmPresent 'Get-Tpm'))
        $ek=Invoke-HuellaSystem TpmPublic
        $rows.Add((New-HuellaRow 'TPM' 'Hash publico EK' (Get-HuellaProperty $ek 'PublicKeyHash') 'Get-TpmEndorsementKeyInfo' -Detail 'Informacion publica. No se borran claves ni se reprograma el TPM.'))
    } catch { $rows.Add((New-HuellaRow 'TPM' 'Consulta' '' 'TPM' 'No disponible / error' -Detail $_.Exception.Message)) }
    if ($IncludeHyperV) {
        try {
            foreach ($vm in @(Invoke-HuellaSystem VirtualMachines)) {
                foreach ($adapter in @(Invoke-HuellaSystem VirtualAdapters @{ VM=$vm })) {
                    $rows.Add((New-HuellaRow 'Hyper-V' "$($vm.Name): $($adapter.Name) MAC" $adapter.MacAddress 'Get-VMNetworkAdapter' 'Leido' 'MAC virtual de laboratorio' 'VirtualMacAddress' "$($vm.Id)|$($adapter.Id)" 'Solo VM apagada que selecciones como laboratorio. Se respalda la configuracion estatica/dinamica.'))
                }
            }
        } catch { $rows.Add((New-HuellaRow 'Hyper-V' 'Consulta' '' 'Hyper-V' 'No disponible / error' -Detail $_.Exception.Message)) }
    }
    return [pscustomobject]@{ SchemaVersion=1; CapturedUtc=[DateTime]::UtcNow.ToString('o'); Rows=@($rows.ToArray()) }
}

function Export-HuellaInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Path)
    Write-HuellaJson $Inventory $Path
}

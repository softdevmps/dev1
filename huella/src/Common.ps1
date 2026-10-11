function Test-HuellaAdministrator {
    if ($env:OS -ne 'Windows_NT') { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } finally { $identity.Dispose() }
}

function Assert-HuellaWindows {
    if ($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8) {
        throw 'Huella necesita Windows 10/11 y PowerShell de 64 bits.'
    }
}

# All operating-system interactions go through this boundary. Tests replace it
# with synthetic devices; importing the module performs no system queries.
function Invoke-HuellaSystem {
    param([Parameter(Mandatory)][string]$Operation, [hashtable]$Arguments = @{})
    Assert-HuellaWindows
    switch ($Operation) {
        'Cim' { Get-CimInstance @Arguments -ErrorAction Stop }
        'Registry' { Get-ItemPropertyValue @Arguments -ErrorAction Stop }
        'Disks' { Get-Disk -ErrorAction Stop }
        'SecondaryDisk' {
            $disk=Get-Disk -Number $Arguments.DiskNumber -ErrorAction Stop
            $devices=@(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Where-Object { $_.Index -eq $Arguments.DiskNumber })
            if ($devices.Count -ne 1) { throw 'La relacion disco/instancia PnP es ambigua.' }
            [pscustomobject]@{ Number=$disk.Number; IsBoot=$disk.IsBoot; IsSystem=$disk.IsSystem; IsOffline=$disk.IsOffline; PnpInstanceId=[string]$devices[0].PNPDeviceID }
        }
        'Checker' {
            $checkerArgs=[string[]]$Arguments.CommandArguments
            $output=@(& $Arguments.Path @checkerArgs)
            if ($LASTEXITCODE -ne 0) { throw "Checker fallo ($LASTEXITCODE). Revisa su salida; no se declara el cambio verificado." }
            return $output
        }
        'Adapters' { Get-NetAdapter -IncludeHidden -ErrorAction Stop }
        'NetworkProperty' { Get-NetAdapterAdvancedProperty @Arguments -AllProperties -ErrorAction Stop }
        'SetNetworkProperty' { Set-NetAdapterAdvancedProperty @Arguments -NoRestart -ErrorAction Stop }
        'ResetNetworkProperty' { Reset-NetAdapterAdvancedProperty @Arguments -NoRestart -Confirm:$false -ErrorAction Stop }
        'RestartAdapter' { Restart-NetAdapter @Arguments -Confirm:$false -ErrorAction Stop }
        'RenameComputer' { Rename-Computer @Arguments -Force -ErrorAction Stop }
        'ComputerNames' {
            [pscustomobject]@{
                Active = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' 'ComputerName' -ErrorAction Stop
                Configured = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName' -ErrorAction Stop
            }
        }
        'MachineBinding' {
            $value = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid' -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($value)) { throw 'MachineGuid no disponible; no se puede vincular el respaldo.' }
            $sha = [Security.Cryptography.SHA256]::Create()
            try { -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("Huella-v1:$value")) | ForEach-Object { $_.ToString('x2') }) }
            finally { $sha.Dispose() }
        }
        'Administrator' { Test-HuellaAdministrator }
        'SecureBoot' { Confirm-SecureBootUEFI -ErrorAction Stop }
        'Tpm' { Get-Tpm -ErrorAction Stop }
        'TpmPublic' { Get-TpmEndorsementKeyInfo -ErrorAction Stop }
        'Edid' {
            Get-ItemPropertyValue @Arguments -Name EDID -ErrorAction Stop
        }
        'VirtualMachines' { Get-VM -ErrorAction Stop }
        'VirtualAdapters' { Get-VMNetworkAdapter @Arguments -ErrorAction Stop }
        'SetVirtualAdapter' { Set-VMNetworkAdapter @Arguments -ErrorAction Stop }
        'Signature' { Get-AuthenticodeSignature @Arguments -ErrorAction Stop }
        'BitLocker' { Get-BitLockerVolume -ErrorAction Stop }
        'UsbVolume' {
            $volume=Get-Volume -DriveLetter $Arguments.DriveLetter -ErrorAction Stop
            $partitions=@(Get-Partition -DriveLetter $Arguments.DriveLetter -ErrorAction Stop)
            if ($partitions.Count -ne 1) { throw 'Volumen USB ambiguo.' }
            $disk=$partitions[0] | Get-Disk -ErrorAction Stop
            [pscustomobject]@{ FileSystem=[string]$volume.FileSystem; FreeBytes=$volume.SizeRemaining; BusType=[string]$disk.BusType; IsBoot=$disk.IsBoot; IsSystem=$disk.IsSystem; IsReadOnly=$disk.IsReadOnly; IsOffline=$disk.IsOffline; Root=([string]$Arguments.DriveLetter+':\') }
        }
        'SecureDirectory' {
            $path = $Arguments.Path
            if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path -ErrorAction Stop }
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'El directorio de datos no puede ser un enlace.' }
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            try { $sid = $identity.User } finally { $identity.Dispose() }
            $acl.SetOwner($sid)
            foreach ($identity in @($sid, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')), (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
                $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $path -AclObject $acl -ErrorAction Stop
        }
        'LaunchUtility' { Start-Process -FilePath $Arguments.Path -Verb RunAs -Wait -PassThru -ErrorAction Stop }
        default { throw "Operacion del sistema desconocida: $Operation" }
    }
}

function Get-HuellaDataDirectory {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { throw 'No se encontro LocalAppData.' }
    $path = Join-Path $base 'Huella'
    Invoke-HuellaSystem SecureDirectory @{ Path = $path }
    return $path
}

function Write-HuellaJson {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path, [switch]$Replace)
    $full = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($directory)) { throw 'La carpeta de destino no existe.' }
    $temp = Join-Path $directory ([Guid]::NewGuid().ToString('N') + '.tmp')
    $previous = Join-Path $directory ([Guid]::NewGuid().ToString('N') + '.bak')
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 12))
    try {
        $stream = New-Object IO.FileStream($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if ($Replace -and [IO.File]::Exists($full)) { [IO.File]::Replace($temp, $full, $previous) }
        else { [IO.File]::Move($temp, $full) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
        if ([IO.File]::Exists($previous)) { [IO.File]::Delete($previous) }
    }
}

function Read-HuellaJson {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -gt 1MB -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Archivo JSON invalido, demasiado grande o enlazado.'
    }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Get-HuellaProperty {
    param($Object, [string]$Name, $Default = '')
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function ConvertTo-HuellaText {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [array]) { return (($Value | ForEach-Object { [string]$_ }) -join ', ') }
    return ([string]$Value).Replace([string][char]0, '').Trim()
}

function ConvertTo-HuellaMac {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^(?:[0-9a-fA-F]{12}|(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2})$') {
        throw 'La MAC debe tener 12 digitos hexadecimales.'
    }
    $mac = ($Value -replace '[:-]', '').ToUpperInvariant()
    $first = [Convert]::ToByte($mac.Substring(0,2),16)
    if (($first -band 1) -ne 0 -or ($first -band 2) -eq 0 -or $mac -eq '000000000000') {
        throw 'Usa una MAC unicast administrada localmente (por ejemplo, empieza por 02).'
    }
    return $mac
}

function New-HuellaMacAddress {
    $bytes = New-Object byte[] 6
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $bytes[0] = ($bytes[0] -band 0xFC) -bor 2
    -join ($bytes | ForEach-Object { $_.ToString('X2') })
}

function ConvertTo-HuellaComputerName {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$' -or $Value -match '^\d+$') {
        throw 'El nombre debe tener 1 a 15 letras, numeros o guiones; no solo numeros ni guiones en los extremos.'
    }
    $Value.ToUpperInvariant()
}

function ConvertFrom-HuellaEdid {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 128) { throw 'EDID truncado.' }
    $magic = @(0,255,255,255,255,255,255,0)
    for ($i=0; $i -lt 8; $i++) { if ($Bytes[$i] -ne $magic[$i]) { throw 'Cabecera EDID invalida.' } }
    $blocks = 1 + [int]$Bytes[126]
    if ($Bytes.Length -lt 128*$blocks) { throw 'Extensiones EDID truncadas.' }
    for ($block=0; $block -lt $blocks; $block++) {
        $sum = 0
        for ($i=0; $i -lt 128; $i++) { $sum += [int]$Bytes[$block*128+$i] }
        if (($sum -band 255) -ne 0) { throw 'Checksum EDID invalido.' }
    }
    $code = ([int]$Bytes[8] -shl 8) -bor [int]$Bytes[9]
    $letters = @((($code -shr 10) -band 31), (($code -shr 5) -band 31), ($code -band 31))
    if (@($letters | Where-Object { $_ -lt 1 -or $_ -gt 26 }).Count -ne 0) { throw 'Fabricante EDID invalido.' }
    [pscustomobject]@{
        Manufacturer = -join ($letters | ForEach-Object { [char]($_+64) })
        Product = [BitConverter]::ToUInt16($Bytes,10)
        NumericSerial = [BitConverter]::ToUInt32($Bytes,12)
    }
}

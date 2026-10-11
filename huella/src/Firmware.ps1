# These are entry points to official support, not firmware download links.
# Certificate organization checks establish publisher identity only. Model and
# firmware-image compatibility must also be checked by the vendor's utility.
function Get-HuellaVendorPolicy {
    param([string]$Manufacturer)
    $policies=@(
        @{ Match='(?i)^(Dell Inc\.?|Dell Computer Corporation)$'; Vendor='Dell'; Url='https://www.dell.com/support/home'; Publisher='(?i)(?:^|,\s*)O="?Dell (?:Inc\.?|Technologies Inc\.?)"?(?:,|$)' },
        @{ Match='(?i)^(HP|HP Inc\.?|Hewlett-Packard)$'; Vendor='HP'; Url='https://support.hp.com/drivers'; Publisher='(?i)(?:^|,\s*)O=(?:"?HP Inc\.?"?|"HP Development Company, L\.P\."|"Hewlett-Packard Company")(?:,|$)' },
        @{ Match='(?i)^LENOVO$'; Vendor='Lenovo'; Url='https://pcsupport.lenovo.com/'; Publisher='(?i)(?:^|,\s*)O="?(?:Lenovo \(Beijing\) Limited|Lenovo Group Limited|Lenovo)"?(?:,|$)' },
        @{ Match='(?i)^(ASUSTeK COMPUTER INC\.?|ASUS)$'; Vendor='ASUS'; Url='https://www.asus.com/support/download-center/'; Publisher='(?i)(?:^|,\s*)O="?ASUSTeK COMPUTER INC\.?"?(?:,|$)' },
        @{ Match='(?i)^(Acer|Acer Incorporated)$'; Vendor='Acer'; Url='https://www.acer.com/support'; Publisher='(?i)(?:^|,\s*)O="?Acer Incorporated"?(?:,|$)' },
        @{ Match='(?i)^Microsoft Corporation$'; Vendor='Microsoft Surface'; Url='https://support.microsoft.com/surface'; Publisher='(?i)(?:^|,\s*)O="?Microsoft Corporation"?(?:,|$)' },
        @{ Match='(?i)^(Micro-Star International Co\.?[,]? Ltd\.?|MSI)$'; Vendor='MSI'; Url='https://www.msi.com/support'; Publisher='' },
        @{ Match='(?i)^(Gigabyte Technology Co\.?[,]? Ltd\.?|GIGABYTE)$'; Vendor='Gigabyte'; Url='https://www.gigabyte.com/Support'; Publisher='' }
    )
    foreach ($policy in $policies) {
        if ($Manufacturer.Trim() -match $policy.Match) { return [pscustomobject]@{ Vendor=$policy.Vendor; Url=$policy.Url; PublisherPattern=$policy.Publisher } }
    }
    [pscustomobject]@{ Vendor=$Manufacturer; Url=''; PublisherPattern='' }
}

function Get-HuellaFirmwareTarget {
    $systems=@(Invoke-HuellaSystem Cim @{ ClassName='Win32_ComputerSystem' })
    $bios=@(Invoke-HuellaSystem Cim @{ ClassName='Win32_BIOS' })
    $boards=@(Invoke-HuellaSystem Cim @{ ClassName='Win32_BaseBoard' })
    if ($systems.Count -ne 1 -or $bios.Count -ne 1) { throw 'No se pudo determinar un unico equipo y BIOS.' }
    $manufacturer=ConvertTo-HuellaText $systems[0].Manufacturer
    $model=ConvertTo-HuellaText $systems[0].Model
    if ($manufacturer -eq '' -or $model -eq '') { throw 'Fabricante o modelo no disponible.' }
    [pscustomobject]@{
        Manufacturer=$manufacturer; Model=$model
        BoardProducts=@($boards | ForEach-Object { ConvertTo-HuellaText $_.Product })
        BoardManufacturers=@($boards | ForEach-Object { ConvertTo-HuellaText $_.Manufacturer })
        BiosVersion=(ConvertTo-HuellaText $bios[0].SMBIOSBIOSVersion)
    }
}

function Get-HuellaFirmwareRoute {
    param($Target)
    # Exact board profile from the submitted project's model, without any
    # personal serials. Additional boards need documented profiles of their own.
    if ($Target.BoardManufacturers.Count -eq 1 -and $Target.BoardManufacturers[0] -match '(?i)^(ASUS|ASUSTeK COMPUTER INC\.?)$' -and $Target.BoardProducts.Count -eq 1 -and $Target.BoardProducts[0] -ceq 'ROG STRIX X670E-A GAMING WIFI') {
        return [pscustomobject]@{
            Mode='AsusUefi'; SupportUrl='https://rog.asus.com/motherboards/rog-strix/rog-strix-x670e-a-gaming-wifi-model/helpdesk_bios/'
            ManualUrl='https://rog.asus.com/motherboards/rog-strix/rog-strix-x670e-a-gaming-wifi-model/helpdesk_manual/'
            CapsulePattern='^ROG-STRIX-X670E-A-GAMING-WIFI-ASUS-[0-9]+\.CAP$'
            Method='ASUS EZ Flash desde UEFI; seguir el manual exacto de la placa.'
        }
    }
    $policy=Get-HuellaVendorPolicy $Target.Manufacturer
    [pscustomobject]@{ Mode='VendorExe'; SupportUrl=$policy.Url; ManualUrl=$policy.Url; CapsulePattern=''; Method='Asistente oficial autocontenido del fabricante.' }
}

function New-HuellaFirmwarePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $target=Get-HuellaFirmwareTarget
    $policy=Get-HuellaVendorPolicy $target.Manufacturer
    $route=Get-HuellaFirmwareRoute $target
    $secureBoot='Unknown'; $secureBootError=''
    try { $secureBoot=[string](Invoke-HuellaSystem SecureBoot) } catch { $secureBootError=$_.Exception.Message }
    $plan=[pscustomobject]@{
        SchemaVersion=1; Type='VendorFirmwareReview'; MachineBinding=(Invoke-HuellaSystem MachineBinding)
        CreatedUtc=[DateTime]::UtcNow.ToString('o'); Target=$target
        Vendor=$policy.Vendor; SupportUrl=$route.SupportUrl; Route=$route
        SecureBoot=$secureBoot; SecureBootError=$secureBootError
        Status='NeedsVendorProcedure'; ChangesIdentifiers='NotEstablished'
        Requirements=@(
            'Seleccionar el modelo y revision exactos en el soporte oficial.',
            'Confirmar en la documentacion si el fabricante permite editar identificadores; actualizar BIOS no lo garantiza.',
            'Usar el respaldo y recuperacion de firmware que indique el fabricante; Huella no puede crear un dump universal.',
            'Guardar fuera del equipo la recuperacion BitLocker y disponer de alimentacion estable.',
            'El asistente oficial debe comprobar la compatibilidad antes de escribir; no usar imagenes modificadas.',
            'Mantener Secure Boot, TPM y firma de controladores; Huella no cambia estas protecciones.'
        )
    }
    Write-HuellaJson $plan $Path
    return $plan
}

function Assert-HuellaFirmwarePlan {
    param($Plan)
    if ($Plan.SchemaVersion -ne 1 -or $Plan.Type -ne 'VendorFirmwareReview' -or $Plan.MachineBinding -ne (Invoke-HuellaSystem MachineBinding)) {
        throw 'Plan de firmware invalido o de otro equipo.'
    }
    $actual=Get-HuellaFirmwareTarget
    if (($Plan.Target | ConvertTo-Json -Compress) -ne ($actual | ConvertTo-Json -Compress)) {
        throw 'El modelo, placa o BIOS cambiaron; genera un plan nuevo.'
    }
    # Never trust publisher patterns or URLs supplied by a JSON document.
    return (Get-HuellaVendorPolicy $actual.Manufacturer)
}

function Test-HuellaFirmwarePackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$PackagePath)
    $plan=Read-HuellaJson $PlanPath
    $policy=Assert-HuellaFirmwarePlan $plan
    if ((Get-HuellaFirmwareRoute $plan.Target).Mode -ne 'VendorExe') { throw 'Esta placa usa la ruta UEFI/ZIP; usa New-HuellaAsusCapsule.' }
    if ($policy.PublisherPattern -eq '') { throw 'Fabricante sin politica comprobada: usar su procedimiento oficial manual y aportar documentacion del modelo.' }
    $file=Get-Item -LiteralPath $PackagePath -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -ine '.exe' -or $file.Length -eq 0 -or $file.Length -gt 2GB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Selecciona un asistente EXE oficial; no se ejecutan ROM, BIN, ZIP ni enlaces.'
    }
    $signature=Invoke-HuellaSystem Signature @{ LiteralPath=$file.FullName }
    if ([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch $policy.PublisherPattern) {
        throw 'Firma Authenticode invalida o editor diferente del fabricante detectado.'
    }
    [pscustomobject]@{
        PackagePath=$file.FullName; Sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        Publisher=$signature.SignerCertificate.Subject; Model=$plan.Target.Model; SupportUrl=$policy.Url
        Signature='Valid'; Compatibility='RequiresVendorConfirmation'; IdentifierChange='NotEstablished'
    }
}

function New-HuellaAsusCapsule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ReferenceSha256)
    $plan=Read-HuellaJson $PlanPath
    $null=Assert-HuellaFirmwarePlan $plan
    $route=Get-HuellaFirmwareRoute $plan.Target
    if ($route.Mode -ne 'AsusUefi') { throw 'No hay un perfil de capsula UEFI para esta placa.' }
    $file=Get-Item -LiteralPath $ArchivePath -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Extension -ine '.zip' -or $file.Length -gt 128MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Selecciona el ZIP oficial de BIOS del modelo exacto.' }
    Add-Type -AssemblyName System.IO.Compression
    $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $zip=$null; $output=$null
    try {
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=-join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('X2') }) } finally { $sha.Dispose() }
        if ($hash -ne $ReferenceSha256) { throw 'El SHA256 del ZIP no coincide con la referencia del soporte oficial.' }
        $stream.Position=0
        $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Read,$true)
        if ($zip.Entries.Count -eq 0 -or $zip.Entries.Count -gt 32) { throw 'Numero de entradas ZIP no admitido.' }
        $candidates=@(); $total=[long]0
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -match '[\\/:]' -or $entry.FullName -in @('.','..') -or $entry.Length -gt 128MB) { throw 'Ruta o longitud ZIP no admitida.' }
            $total+=$entry.Length
            if ($total -gt 256MB) { throw 'ZIP expandido demasiado grande.' }
            if ($entry.FullName -cmatch $route.CapsulePattern) { $candidates+=,$entry }
        }
        if ($candidates.Count -ne 1 -or $candidates[0].Length -lt 1MB) { throw 'El ZIP debe contener una sola capsula CAP con el nombre del modelo.' }
        $directory=Get-HuellaDataDirectory
        $stage=Join-Path $directory ('capsule-'+[Guid]::NewGuid().ToString('N'))
        Invoke-HuellaSystem SecureDirectory @{ Path=$stage }
        $capsule=Join-Path $stage $candidates[0].Name
        $entryStream=$candidates[0].Open()
        $output=New-Object IO.FileStream($capsule,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $buffer=New-Object byte[] 65536; $written=[long]0
            while (($read=$entryStream.Read($buffer,0,$buffer.Length)) -gt 0) {
                $written+=$read
                if ($written -gt $candidates[0].Length) { throw 'La capsula excede el tamano declarado.' }
                $output.Write($buffer,0,$read)
            }
            if ($written -ne $candidates[0].Length) { throw 'Capsula truncada.' }
            $output.Flush($true)
        } finally { $entryStream.Dispose(); $output.Dispose(); $output=$null }
        $record=[pscustomobject]@{
            SchemaVersion=1; Type='PreparedUefiCapsule'; MachineBinding=$plan.MachineBinding; Target=$plan.Target
            CreatedUtc=[DateTime]::UtcNow.ToString('o'); CapsulePath=$capsule
            CapsuleSha256=(Get-FileHash -LiteralPath $capsule -Algorithm SHA256).Hash
            ArchiveSha256=$hash; ReferenceCheck='MatchesProvidedReference'; SupportUrl=$route.SupportUrl; ManualUrl=$route.ManualUrl
            Authenticity='RequiresOfficialSource'; Compatibility='RequiresUefiValidation'; FlashResult='NotPerformed'; IdentifierChange='NotEstablished'
        }
        $path=Join-Path $stage 'capsule.json'
        Write-HuellaJson $record $path
        return [pscustomobject]@{ Path=$path; Record=$record }
    } finally { if ($null -ne $output) { $output.Dispose() }; if ($null -ne $zip) { $zip.Dispose() }; $stream.Dispose() }
}

function Copy-HuellaFirmwareToUsb {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$PreparedPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter)
    $record=Read-HuellaJson $PreparedPath
    if ($record.SchemaVersion -ne 1 -or $record.Type -ne 'PreparedUefiCapsule') { throw 'Capsula preparada invalida.' }
    $plan=[pscustomobject]@{ SchemaVersion=1; Type='VendorFirmwareReview'; MachineBinding=$record.MachineBinding; Target=$record.Target }
    $null=Assert-HuellaFirmwarePlan $plan
    $route=Get-HuellaFirmwareRoute $record.Target
    $file=Get-Item -LiteralPath $record.CapsulePath -ErrorAction Stop
    if ($route.Mode -ne 'AsusUefi' -or $file.Name -cnotmatch $route.CapsulePattern -or $file.Length -gt 128MB -or $file.Length -lt 1MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Archivo de capsula no reconocido.' }
    if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $record.CapsuleSha256) { throw 'La capsula preparada cambio.' }
    $usb=Invoke-HuellaSystem UsbVolume @{ DriveLetter=$DriveLetter.ToUpperInvariant() }
    if ($usb.BusType -ne 'USB' -or $usb.FileSystem -ne 'FAT32' -or $usb.IsBoot -or $usb.IsSystem -or $usb.IsOffline -or $usb.IsReadOnly -or $usb.FreeBytes -le $file.Length) {
        throw 'Se requiere USB FAT32 con espacio, accesible, ajeno al arranque/sistema.'
    }
    $destination=Join-Path $usb.Root $file.Name
    if (Test-Path -LiteralPath $destination) { throw 'El archivo ya existe en el USB. No se sobrescribe.' }
    if ($PSCmdlet.ShouldProcess($destination,'Copiar CAP verificado por hash para revision desde ASUS EZ Flash')) {
        [IO.File]::Copy($file.FullName,$destination,$false)
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $record.CapsuleSha256) { throw 'La copia USB no coincide; no utilices ese archivo.' }
        [pscustomobject]@{ Path=$destination; HashVerified=$true; FlashResult='NotPerformed'; Compatibility='RequiresUefiValidation'; ManualUrl=$route.ManualUrl }
    }
}

function Start-HuellaFirmwareUtility {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$ReviewedModel,[switch]$VendorProcedureReviewed,
        [switch]$RecoveryKeyAvailable,[switch]$PowerConfirmed)
    $check=Test-HuellaFirmwarePackage $PlanPath $PackagePath
    if ($check.Sha256 -ne $ExpectedSha256) { throw 'El paquete cambio desde la revision.' }
    if (-not $VendorProcedureReviewed -or $ReviewedModel -cne $check.Model -or -not $PowerConfirmed) {
        throw 'Confirma el modelo exacto, procedimiento del fabricante y alimentacion estable.'
    }
    # Key material is never collected or stored. Unknown protection status also
    # requires the user's confirmation that recovery has been prepared.
    $recoveryRequired=$true
    try {
        $volumes=@(Invoke-HuellaSystem BitLocker)
        $recoveryRequired=@($volumes | Where-Object { [string]$_.ProtectionStatus -ne 'Off' }).Count -gt 0
    } catch { $recoveryRequired=$true }
    if ($recoveryRequired -and -not $RecoveryKeyAvailable) { throw 'Prepara la recuperacion BitLocker antes de abrir el asistente.' }
    if (-not $PSCmdlet.ShouldProcess($check.Model,'Abrir asistente oficial de firmware; el fabricante debe confirmar la imagen y operacion')) { return }
    if (-not (Invoke-HuellaSystem Administrator)) { throw 'Abre Huella como administrador.' }
    $directory=Get-HuellaDataDirectory
    $stage=Join-Path $directory ('firmware-' + [Guid]::NewGuid().ToString('N'))
    Invoke-HuellaSystem SecureDirectory @{ Path=$stage }
    # Isolate the reviewed bytes from the download directory. Revalidate the
    # staged copy before the process starts; no CLI flash switches are appended.
    $staged=Join-Path $stage 'VendorUtility.exe'
    [IO.File]::Copy($check.PackagePath,$staged,$false)
    $stagedCheck=Test-HuellaFirmwarePackage $PlanPath $staged
    if ($stagedCheck.Sha256 -ne $ExpectedSha256) { throw 'El archivo copiado no coincide con el revisado.' }
    $record=[pscustomobject]@{
        SchemaVersion=1; Type='FirmwareUtilityLaunch'; CreatedUtc=[DateTime]::UtcNow.ToString('o')
        Model=$check.Model; Sha256=$ExpectedSha256; Publisher=$check.Publisher
        Status='Prepared'; ExitCode=$null; Error=''; FlashResult='NotDetermined'; IdentifierChange='NotEstablished'
    }
    $journal=Join-Path $stage 'launch.json'
    Write-HuellaJson $record $journal
    try {
        $process=Invoke-HuellaSystem LaunchUtility @{ Path=$staged }
        $record.ExitCode=$process.ExitCode; $record.Status='UtilityExited'
    } catch { $record.Status='LaunchFailed'; $record.Error=$_.Exception.Message }
    Write-HuellaJson $record $journal -Replace
    [pscustomobject]@{ Path=$journal; Record=$record }
}

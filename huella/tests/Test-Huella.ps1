# Runs on PowerShell 5.1/7. No host identifiers are read and no host settings
# are changed. The actual exported functions use an injected synthetic OS.
#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Huella.psm1') -Force
$module=Get-Module Huella
$temp=Join-Path ([IO.Path]::GetTempPath()) ('huella-tests-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$script:checks=0
function Assert([bool]$Condition,[string]$Message) {
    $script:checks++
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Throws([scriptblock]$Body,[string]$Pattern) {
    $caught=$false
    try { $null=& $Body } catch { $caught=$true; Assert ($_.Exception.Message -match $Pattern) "Exception: $($_.Exception.Message); expected $Pattern" }
    Assert $caught 'Expected failure'
}
try {
    & $module {
        param($TestDirectory)
        $script:TestDirectory=$TestDirectory
        $script:Fake=[pscustomobject]@{
            Binding=('a'*64); Admin=$true; ActiveName='LAB-OLD'; ConfiguredName='LAB-OLD'; Domain=$false
            AdapterGuid='11111111-1111-4111-8111-111111111111'; FactoryMac='001122334455'; EffectiveMac='001122334455'; Override=''
            VmId='22222222-2222-4222-8222-222222222222'; AdapterId='vm-adapter-1'; VmState='Off'; VirtualMac='00155D010203'; Dynamic=$true
            FailRestart=$false; UnsupportedMac=$false; FailWrites=$false; SecureBootError=$true
            Signature='Valid'; Publisher='CN=LAB, O=Dell Inc., C=US'; ChangedModel=$false; Asus=$false
            UsbUnsafe=$false; UsbRoot=(Join-Path $TestDirectory 'usb')
            StorageEnabled=$false; StorageGeneration=[uint64]0; StorageTransformed=[uint64]0
            StorageBoot=$false; StorageFail=$false; StorageRestricted=$false; StorageCapacity=20
            StorageInstance=33; StoragePnp='SCSI\DISK&VEN_LAB\INSTANCE_LAB'
            StorageSerial=''; StorageRaceOnClear=$false; StorageMismatch=$false
            Calls=(New-Object 'Collections.Generic.List[string]')
        }
        function script:Invoke-HuellaSystem {
            param([string]$Operation,[hashtable]$Arguments=@{})
            $script:Fake.Calls.Add($Operation)
            switch ($Operation) {
                'Administrator' { $script:Fake.Admin }
                'MachineBinding' { $script:Fake.Binding }
                'ComputerNames' { [pscustomobject]@{ Active=$script:Fake.ActiveName; Configured=$script:Fake.ConfiguredName } }
                'RenameComputer' { $script:Fake.ConfiguredName=$Arguments.NewName }
                'Adapters' { [pscustomobject]@{ Name='LAB-NIC'; InterfaceGuid=$script:Fake.AdapterGuid; MacAddress=$script:Fake.EffectiveMac; HardwareInterface=$true } }
                'NetworkProperty' {
                    if ($script:Fake.UnsupportedMac) { throw 'Not supported' }
                    [pscustomobject]@{ RegistryValue=@($script:Fake.Override) }
                }
                'SetNetworkProperty' { $script:Fake.Override=[string]$Arguments.RegistryValue[0] }
                'ResetNetworkProperty' { $script:Fake.Override='' }
                'RestartAdapter' {
                    if ($script:Fake.FailRestart) { throw 'Synthetic restart failure' }
                    $script:Fake.EffectiveMac=if ($script:Fake.Override -eq '') { $script:Fake.FactoryMac } else { $script:Fake.Override }
                }
                'VirtualMachines' { [pscustomobject]@{ Id=$script:Fake.VmId; Name='LAB-VM'; State=$script:Fake.VmState } }
                'VirtualAdapters' { [pscustomobject]@{ Id=$script:Fake.AdapterId; VMId=$script:Fake.VmId; Name='LAB-VNIC'; MacAddress=$script:Fake.VirtualMac; DynamicMacAddressEnabled=$script:Fake.Dynamic } }
                'SetVirtualAdapter' {
                    $script:Fake.Dynamic=$Arguments.ContainsKey('DynamicMacAddress')
                    if (-not $script:Fake.Dynamic) { $script:Fake.VirtualMac=$Arguments.StaticMacAddress }
                }
                'Cim' {
                    switch ($Arguments.ClassName) {
                        'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer=$(if ($script:Fake.Asus) { 'ASUSTeK COMPUTER INC.' } else { 'Dell Inc.' }); Model=$(if ($script:Fake.ChangedModel) { 'OTHER' } else { 'LAB-MODEL' }); PartOfDomain=$script:Fake.Domain } }
                        'Win32_BaseBoard' { [pscustomobject]@{ SerialNumber='SYNTH-BOARD'; Manufacturer=$(if ($script:Fake.Asus) { 'ASUSTeK COMPUTER INC.' } else { 'Dell Inc.' }); Product=$(if ($script:Fake.Asus) { 'ROG STRIX X670E-A GAMING WIFI' } else { 'LAB-BOARD' }) } }
                        'Win32_ComputerSystemProduct' { [pscustomobject]@{ UUID='33333333-3333-4333-8333-333333333333'; IdentifyingNumber='SYNTH-SYSTEM'; Vendor='Dell'; Name='LAB' } }
                        'Win32_BIOS' { [pscustomobject]@{ SerialNumber='SYNTH-BIOS'; SMBIOSBIOSVersion='LAB-1'; Manufacturer='Dell' } }
                        'Win32_VideoController' { [pscustomobject]@{ Name='SYNTH-GPU'; PNPDeviceID='PCI\VEN_1234&DEV_5678\LAB_INSTANCE' } }
                        'Win32_PnPEntity' { [pscustomobject]@{ Name='SYNTH-USB'; PNPDeviceID='USB\VID_1234&PID_5678\LAB_USB' } }
                        'WmiMonitorID' {
                            foreach ($i in 1,2) { [pscustomobject]@{ UserFriendlyName=@(76,65,66,0); SerialNumberID=@(83,(48+$i),0); InstanceName="DISPLAY\LAB000$i\INSTANCE$i`_0" } }
                        }
                        default { @() }
                    }
                }
                'Registry' { 'SYNTH-WINDOWS' }
                'Disks' { @() }
                'Edid' {
                    $bytes=New-Object byte[] 128
                    [byte[]]$magic=0,255,255,255,255,255,255,0
                    [Array]::Copy($magic,$bytes,8); $bytes[8]=4; $bytes[9]=67
                    $bytes[12]=if ($Arguments.Path -like '*INSTANCE1*') { 1 } else { 2 }
                    $sum=0; foreach ($b in $bytes) { $sum+=$b }; $bytes[127]=(256-($sum -band 255)) -band 255
                    return ,$bytes
                }
                'SecureBoot' { if ($script:Fake.SecureBootError) { throw 'Synthetic privilege error' }; $true }
                'Tpm' { [pscustomobject]@{ TpmPresent=$true } }
                'TpmPublic' { [pscustomobject]@{ PublicKeyHash='SYNTH-PUBLIC-HASH' } }
                'SecureDirectory' {
                    if ($script:Fake.FailWrites) { throw 'Synthetic backup failure' }
                    if (-not (Test-Path -LiteralPath $Arguments.Path)) { $null=New-Item -ItemType Directory -Path $Arguments.Path }
                }
                'Signature' { [pscustomobject]@{ Status=$script:Fake.Signature; SignerCertificate=[pscustomobject]@{ Subject=$script:Fake.Publisher } } }
                'BitLocker' { throw 'Synthetic unknown BitLocker state' }
                'UsbVolume' { [pscustomobject]@{ FileSystem='FAT32'; FreeBytes=100MB; BusType='USB'; IsBoot=$script:Fake.UsbUnsafe; IsSystem=$false; IsOffline=$false; IsReadOnly=$false; Root=$script:Fake.UsbRoot } }
                'LaunchUtility' { [pscustomobject]@{ ExitCode=23 } }
                'SecondaryDisk' { [pscustomobject]@{ Number=$Arguments.DiskNumber; IsBoot=$script:Fake.StorageBoot; IsSystem=$false; IsOffline=$false; PnpInstanceId=$script:Fake.StoragePnp } }
                'Checker' {
                    $command=$Arguments.CommandArguments[0]
                    if ($script:Fake.StorageFail) { throw 'Synthetic Checker failure' }
                    if ($command -eq 'serial-clear' -and $script:Fake.StorageRaceOnClear) { $script:Fake.StorageGeneration++; $script:Fake.StorageRaceOnClear=$false }
                    $generationIndex=[array]::IndexOf($Arguments.CommandArguments,'--generation')
                    if ($generationIndex -ge 0 -and [uint64]$Arguments.CommandArguments[$generationIndex+1] -ne $script:Fake.StorageGeneration) { throw 'Profile generation changed; request rejected' }
                    $instanceIndex=[array]::IndexOf($Arguments.CommandArguments,'--instance')
                    if ($instanceIndex -ge 0 -and [uint32]$Arguments.CommandArguments[$instanceIndex+1] -ne $script:Fake.StorageInstance) { throw 'Profile instance changed; request rejected' }
                    if ($command -eq 'serial-set') {
                        $script:Fake.StorageEnabled=$true; $script:Fake.StorageGeneration++; $script:Fake.StorageTransformed++
                        $script:Fake.StorageSerial=$Arguments.CommandArguments[2]
                    } elseif ($command -eq 'serial-clear') {
                        $script:Fake.StorageEnabled=$false; $script:Fake.StorageGeneration++
                    } elseif ($command -eq 'serial-expect') {
                        if (-not $script:Fake.StorageEnabled -or $script:Fake.StorageMismatch -or $script:Fake.StorageSerial -ne $Arguments.CommandArguments[2]) { throw 'Serial response mismatch' }
                        $script:Fake.StorageTransformed++
                    } elseif ($command -ne 'serial-status') { throw 'Unexpected Checker command' }
                    $enabled=[int]$script:Fake.StorageEnabled; $restricted=[int]$script:Fake.StorageRestricted
                    "serial instance=$($script:Fake.StorageInstance) disk=2 enabled=$enabled capacity=$($script:Fake.StorageCapacity) generation=$($script:Fake.StorageGeneration) transformed=$($script:Fake.StorageTransformed) skipped=0 lastResult=0 restricted=$restricted"
                }
                default { throw "Unexpected OS call $Operation" }
            }
        }
        function script:Get-HuellaDataDirectory {
            $path=Join-Path $script:TestDirectory 'data'
            Invoke-HuellaSystem SecureDirectory @{ Path=$path }
            return $path
        }
    } $temp

    # Parsing/protocol validation, not guesses about host hardware.
    foreach ($value in @('010000000001','000000000000','FFFFFFFFFFFF','GG1122334455','02-11-22-33-44','02AA BBCCDDEE')) {
        Assert-Throws { & $module { param($v) ConvertTo-HuellaMac $v } $value } 'MAC|unicast'
    }
    foreach ($name in @('1234','-LAB','LAB-','TOO-LONG-COMPUTER-NAME','LAB NAME','LAB$')) {
        Assert-Throws { & $module { param($v) ConvertTo-HuellaComputerName $v } $name } 'nombre'
    }
    Assert ((& $module { ConvertTo-HuellaMac '02:11:22:33:44:55' }) -eq '021122334455') 'MAC normalization'
    $generated=@{}
    for ($i=0;$i -lt 1000;$i++) {
        $mac=New-HuellaMacAddress
        Assert (($mac -match '^[0-9A-F]{12}$') -and (([Convert]::ToByte($mac.Substring(0,2),16) -band 3) -eq 2)) 'Random locally administered unicast MAC'
        Assert (-not $generated.ContainsKey($mac)) 'No collision in this sample (not a network-wide guarantee)'
        $generated[$mac]=$true
    }
    $inventory=Get-HuellaInventory -IncludeHyperV
    $gpu=@($inventory.Rows | Where-Object { $_.Source -eq 'Win32_VideoController.PNPDeviceID' })
    Assert ($gpu.Count -eq 1 -and $gpu[0].Value -eq 'PCI\VEN_1234&DEV_5678\LAB_INSTANCE') 'GPU full ID retained'
    $monitors=@($inventory.Rows | Where-Object { $_.Category -eq 'Monitor' })
    Assert ($monitors.Count -eq 2 -and $monitors[0].Detail -match 'serial numerico 1' -and $monitors[1].Detail -match 'serial numerico 2') 'Equal-name monitors mapped by InstanceName'
    Assert ($monitors[0].Detail -match 'fabricante ABC') 'EDID byte widening'
    $secure=@($inventory.Rows | Where-Object { $_.Label -eq 'Secure Boot' })
    Assert ($secure[0].Status -eq 'No disponible / error' -and $secure[0].Value -eq '') 'Secure Boot error remains unknown'
    Assert (@($inventory.Rows | Where-Object { $_.Action -match 'enmascarable|unico' }).Count -eq 0) 'No universal identity or masking claims'
    $edid=& $module { Invoke-HuellaSystem Edid @{ Path='INSTANCE1' } }
    for ($i=0;$i -lt 128;$i++) {
        [byte[]]$short=if ($i -eq 0) { @() } else { $edid[0..($i-1)] }
        Assert-Throws { & $module { param($b) ConvertFrom-HuellaEdid $b } $short } 'truncado'
    }
    $edid[12]=99
    Assert-Throws { & $module { param($b) ConvertFrom-HuellaEdid $b } $edid } 'Checksum'
    $export=Join-Path $temp 'inventory.json'
    Export-HuellaInventory $inventory $export
    Assert-Throws { Export-HuellaInventory $inventory $export } 'exist|already|existe'

    # WhatIf must never create a journal or perform a write.
    Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue LAB-NEW -WhatIf
    Assert (-not (Test-Path (Join-Path $temp 'data'))) 'WhatIf creates no backup directory'
    & $module { $script:Fake.Admin=$false }
    Assert-Throws { Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue LAB-NEW -Confirm:$false } 'administrador'
    & $module { $script:Fake.Admin=$true; $script:Fake.Domain=$true }
    Assert-Throws { Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue LAB-NEW -Confirm:$false } 'dominio'
    & $module { $script:Fake.Domain=$false; $script:Fake.FailWrites=$true }
    Assert-Throws { Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue LAB-NEW -Confirm:$false } 'backup failure'
    Assert ((& $module { $script:Fake.ConfiguredName }) -eq 'LAB-OLD') 'Backup failure prevents modification'
    & $module { $script:Fake.FailWrites=$false }
    $rename=Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue LAB-NEW -Confirm:$false
    Assert ($rename.Record.Status -eq 'Applied' -and $rename.Record.Verification -eq 'RebootRequired') 'Rename requires active verification after reboot'
    Assert ((Get-Content $rename.Path -Raw | ConvertFrom-Json).Before.Configured -eq 'LAB-OLD') 'Durable previous name'
    & $module { $script:Fake.ActiveName=$script:Fake.ConfiguredName }
    Assert ((Test-HuellaChange $rename.Path).Verification -eq 'Verified') 'Rename verified after synthetic reboot'
    $restore=Restore-HuellaChange $rename.Path -Confirm:$false
    Assert ($restore.Record.Restores -eq $rename.Record.Id -and $restore.Record.Before.Configured -eq 'LAB-NEW') 'Restore is also journaled'
    & $module { $script:Fake.Binding=('b'*64) }
    Assert-Throws { Restore-HuellaChange $rename.Path -Confirm:$false } 'otro equipo'
    & $module { $script:Fake.Binding=('a'*64) }
    $target='11111111-1111-4111-8111-111111111111'
    $change=Invoke-HuellaChange -Kind MacAddress -Target $target -NewValue '021122334455' -Confirm:$false
    Assert ($change.Record.Verification -eq 'Verified' -and $change.Record.Before.Configured -eq '') 'Physical override applies and backs up empty default'
    $restored=Restore-HuellaChange $change.Path -Confirm:$false
    Assert ($restored.Record.Verification -eq 'Verified' -and (& $module { $script:Fake.Override }) -eq '') 'Restore removes override and verifies original effective MAC'
    & $module { $script:Fake.FailRestart=$true }
    $partial=Invoke-HuellaChange -Kind MacAddress -Target $target -NewValue '02AABBCCDDEE' -Confirm:$false
    Assert ($partial.Record.Status -eq 'Failed' -and $partial.Record.Error -match 'restart failure') 'Partial change never reports success'
    Assert ((& $module { $script:Fake.Override }) -eq '02AABBCCDDEE') 'Test actually exercised a partial write'
    & $module { $script:Fake.FailRestart=$false }
    $undo=Restore-HuellaChange $partial.Path -Confirm:$false
    Assert ($undo.Record.Verification -eq 'Verified') 'Failed partial change remains restorable'
    & $module { $script:Fake.UnsupportedMac=$true }
    Assert-Throws { Invoke-HuellaChange -Kind MacAddress -Target $target -NewValue '021111111111' -Confirm:$false } 'Not supported'
    & $module { $script:Fake.UnsupportedMac=$false }
    $vmTarget='22222222-2222-4222-8222-222222222222|vm-adapter-1'
    Assert-Throws { Invoke-HuellaChange -Kind VirtualMacAddress -Target $vmTarget -NewValue '021111111111' -Confirm:$false } 'laboratorio'
    & $module { $script:Fake.VmState='Running' }
    Assert-Throws { Invoke-HuellaChange -Kind VirtualMacAddress -Target $vmTarget -NewValue '021111111111' -LabVm -Confirm:$false } 'apagada'
    & $module { $script:Fake.VmState='Off' }
    $vmChange=Invoke-HuellaChange -Kind VirtualMacAddress -Target $vmTarget -NewValue '021111111111' -LabVm -Confirm:$false
    Assert ($vmChange.Record.Verification -eq 'Verified') 'Static virtual MAC applied'
    $vmRestore=Restore-HuellaChange $vmChange.Path -LabVm -Confirm:$false
    Assert ($vmRestore.Record.Verification -eq 'Verified' -and (& $module { $script:Fake.Dynamic })) 'Dynamic virtual assignment restored'
    Assert (@(Get-HuellaHistory).Count -ge 8) 'History retains operation backups'

    # Reverting a pending rename must compare the active name to the desired
    # configured name, rather than accepting a captured stale effective name.
    $pending=& $module { Compare-HuellaState 'ComputerName' ([pscustomobject]@{ Configured='LAB-OLD'; Effective='LAB-NEW' }) ([pscustomobject]@{ Configured='LAB-OLD'; Effective='LAB-NEW' }) }
    Assert ($pending -eq 'RebootRequired') 'Restoring pending rename still requires reboot'

    # Hold the same named mutex in another process. A competing change must
    # fail before writing an identifier. No runspaces or host changes needed.
    $signal=Join-Path $temp 'mutex-ready'
    $prefix=if ($env:OS -eq 'Windows_NT') { 'Global\Huella-IdentifierChange-' } else { 'Huella-IdentifierChange-' }
    $mutexName=$prefix+('a'*64)
    $holder=Join-Path $PSScriptRoot 'Hold-Mutex.ps1'
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=(Get-Process -Id $PID).Path
    $start.Arguments='-NoProfile -File "'+$holder+'" -Name "'+$mutexName+'" -Signal "'+$signal+'"'
    $start.UseShellExecute=$false
    $child=[Diagnostics.Process]::Start($start)
    try {
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $signal) -and [DateTime]::UtcNow -lt $deadline -and -not $child.HasExited) { Start-Sleep -Milliseconds 50 }
        Assert (Test-Path -LiteralPath $signal) 'Competing process acquired mutex'
        $previous=& $module { $script:Fake.ConfiguredName }
        Assert-Throws { Invoke-HuellaChange -Kind ComputerName -Target Computer -NewValue 'LAB-RACE' -Confirm:$false } 'curso'
        Assert ((& $module { $script:Fake.ConfiguredName }) -eq $previous) 'Competing process causes no modification'
    } finally { if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit() }; $child.Dispose() }

    # Firmware package tests use a synthetic signature, never a real EXE launch.
    $planPath=Join-Path $temp 'plan.json'; $exe=Join-Path $temp 'SYNTHETIC.exe'
    [IO.File]::WriteAllText($exe,'NOT AN EXECUTABLE; synthetic test bytes')
    $plan=New-HuellaFirmwarePlan $planPath
    Assert ($plan.ChangesIdentifiers -eq 'NotEstablished') 'Firmware update never promises serial changes'
    $review=Test-HuellaFirmwarePackage $planPath $exe
    Assert ($review.Compatibility -eq 'RequiresVendorConfirmation') 'Publisher verification is not model compatibility'
    & $module { $script:Fake.Signature='NotSigned' }
    Assert-Throws { Test-HuellaFirmwarePackage $planPath $exe } 'firma|Firma'
    & $module { $script:Fake.Signature='Valid'; $script:Fake.Publisher='CN=Other, O=Unrelated Corporation, C=US' }
    Assert-Throws { Test-HuellaFirmwarePackage $planPath $exe } 'editor'
    & $module { $script:Fake.Publisher='CN=LAB, O=Dell Inc., C=US'; $script:Fake.ChangedModel=$true }
    Assert-Throws { Test-HuellaFirmwarePackage $planPath $exe } 'cambiaron'
    & $module { $script:Fake.ChangedModel=$false }
    $launchArgs=@{ PlanPath=$planPath; PackagePath=$exe; ExpectedSha256=$review.Sha256; ReviewedModel='LAB-MODEL'; VendorProcedureReviewed=$true; PowerConfirmed=$true; Confirm=$false }
    Assert-Throws { Start-HuellaFirmwareUtility @launchArgs } 'BitLocker'
    $launchArgs.RecoveryKeyAvailable=$true
    $launchArgs.ReviewedModel='OTHER'
    Assert-Throws { Start-HuellaFirmwareUtility @launchArgs } 'modelo'
    $launchArgs.ReviewedModel='LAB-MODEL'
    [IO.File]::AppendAllText($exe,'CHANGED')
    Assert-Throws { Start-HuellaFirmwareUtility @launchArgs } 'paquete cambio'
    $launchArgs.ExpectedSha256=(Get-FileHash $exe -Algorithm SHA256).Hash
    $launched=Start-HuellaFirmwareUtility @launchArgs
    Assert ($launched.Record.Status -eq 'UtilityExited' -and $launched.Record.ExitCode -eq 23) 'Utility exit captured without implying success'
    Assert ($launched.Record.FlashResult -eq 'NotDetermined' -and $launched.Record.IdentifierChange -eq 'NotEstablished') 'No fabricated flash or identifier results'
    Assert ((Get-HuellaVendorPolicy 'Unknown vendor').Url -eq '') 'Unknown manufacturer is not guessed'

    # CAP bytes are deliberately fake. A correct reference hash is NOT proof
    # of a signed/compatible firmware image; only the real UEFI can validate it.
    & $module { $script:Fake.Asus=$true }
    $asusPath=Join-Path $temp 'asus-plan.json'
    $asusPlan=New-HuellaFirmwarePlan $asusPath
    Assert ($asusPlan.Route.Mode -eq 'AsusUefi') 'Exact ASUS board selects UEFI route'
    Assert-Throws { Test-HuellaFirmwarePackage $asusPath $exe } 'UEFI'
    Add-Type -AssemblyName System.IO.Compression
    function New-SyntheticZip([string]$Path,[string[]]$Names) {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew)
        $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            foreach ($name in $Names) {
                $entry=$archive.CreateEntry($name)
                $entryStream=$entry.Open()
                try { $bytes=New-Object byte[] 1MB; $entryStream.Write($bytes,0,$bytes.Length) } finally { $entryStream.Dispose() }
            }
        } finally { $archive.Dispose(); $stream.Dispose() }
    }
    $archivePath=Join-Path $temp 'asus.zip'
    $capName='ROG-STRIX-X670E-A-GAMING-WIFI-ASUS-9999.CAP'
    New-SyntheticZip $archivePath @($capName)
    $archiveHash=(Get-FileHash $archivePath -Algorithm SHA256).Hash
    Assert-Throws { New-HuellaAsusCapsule $asusPath $archivePath ('0'*64) } 'SHA256'
    $traversal=Join-Path $temp 'traversal.zip'
    New-SyntheticZip $traversal @('../escape.CAP')
    Assert-Throws { New-HuellaAsusCapsule $asusPath $traversal (Get-FileHash $traversal -Algorithm SHA256).Hash } 'Ruta'
    $duplicate=Join-Path $temp 'duplicate.zip'
    New-SyntheticZip $duplicate @($capName,'ROG-STRIX-X670E-A-GAMING-WIFI-ASUS-9998.CAP')
    Assert-Throws { New-HuellaAsusCapsule $asusPath $duplicate (Get-FileHash $duplicate -Algorithm SHA256).Hash } 'una sola'
    $capsule=New-HuellaAsusCapsule $asusPath $archivePath $archiveHash
    Assert ($capsule.Record.ReferenceCheck -eq 'MatchesProvidedReference' -and $capsule.Record.Authenticity -eq 'RequiresOfficialSource') 'Reference hash is not fabricated authenticity'
    Assert ($capsule.Record.Compatibility -eq 'RequiresUefiValidation' -and $capsule.Record.FlashResult -eq 'NotPerformed') 'Capsule preparation never claims flash or model validation'
    & $module { $script:Fake.UsbUnsafe=$true }
    Assert-Throws { Copy-HuellaFirmwareToUsb $capsule.Path 'F' -Confirm:$false } 'USB FAT32'
    & $module { $script:Fake.UsbUnsafe=$false }
    $usb=Join-Path $temp 'usb'; $null=New-Item -ItemType Directory -Path $usb
    Copy-HuellaFirmwareToUsb $capsule.Path 'F' -WhatIf
    Assert (@(Get-ChildItem $usb).Count -eq 0) 'USB WhatIf copies nothing'
    $copy=Copy-HuellaFirmwareToUsb $capsule.Path 'F' -Confirm:$false
    Assert ($copy.HashVerified -and (Test-Path -LiteralPath $copy.Path)) 'Synthetic USB copy matches hash'
    Assert-Throws { Copy-HuellaFirmwareToUsb $capsule.Path 'F' -Confirm:$false } 'ya existe'
    [IO.File]::AppendAllText($capsule.Record.CapsulePath,'tamper')
    Assert-Throws { Copy-HuellaFirmwareToUsb $capsule.Path 'F' -Confirm:$false } 'cambio'
    # Real module orchestration against a synthetic Checker boundary. No native
    # EXE or kernel driver is executed here, even on Windows.
    $fakeChecker=Join-Path $temp 'Checker.exe'
    [IO.File]::WriteAllText($fakeChecker,'NOT EXECUTABLE')
    $storageArgs=@{ DiskNumber=2; PnpInstanceId='SCSI\DISK&VEN_LAB\INSTANCE_LAB'; Serial='SYNTH-DISK-01'; PhysicalSecondary=$true; Checker=$fakeChecker; Confirm=$false }
    $state=Get-HuellaStorageProfile -DiskNumber 2 -PnpInstanceId $storageArgs.PnpInstanceId -Checker $fakeChecker
    Assert (-not $state.Enabled -and $state.Instance -eq 33 -and $state.Scope -eq 'StorageDeviceProperty.SerialNumber') 'Storage profile scope and mapping'
    & $module { $script:Fake.StorageBoot=$true }
    Assert-Throws { Set-HuellaStorageProfile @storageArgs } 'arranque/sistema'
    & $module { $script:Fake.StorageBoot=$false }
    Assert-Throws { Set-HuellaStorageProfile -DiskNumber 2 -PnpInstanceId 'OTHER' -Serial SYNTH -PhysicalSecondary -Checker $fakeChecker -Confirm:$false } 'instancia'
    & $module { $script:Fake.StorageRestricted=$true }
    Assert-Throws { Set-HuellaStorageProfile @storageArgs } 'restringido'
    & $module { $script:Fake.StorageRestricted=$false; $script:Fake.StorageCapacity=3 }
    Assert-Throws { Set-HuellaStorageProfile @storageArgs } 'mas largo'
    & $module { $script:Fake.StorageCapacity=20 }
    $journalsBefore=@(Get-HuellaHistory).Count
    Set-HuellaStorageProfile @storageArgs -WhatIf
    Assert (@(Get-HuellaHistory).Count -eq $journalsBefore -and -not (& $module { $script:Fake.StorageEnabled })) 'Storage WhatIf creates no journal and no change'
    $storage=Set-HuellaStorageProfile @storageArgs
    Assert ($storage.Record.Status -eq 'Applied' -and $storage.Record.Verification -eq 'CheckerVerified' -and -not $storage.Record.FirmwareChanged) 'Storage module verifies narrow scope without firmware claims'
    Assert (Test-Path -LiteralPath $storage.Path) 'Storage journal retained'
    Assert ((Test-HuellaStorageProfile $storage.Path -Checker $fakeChecker).Verification -eq 'CheckerVerified') 'Storage verification reads the serial response'
    & $module { $script:Fake.StorageMismatch=$true }
    Assert-Throws { Test-HuellaStorageProfile $storage.Path -Checker $fakeChecker } 'mismatch'
    & $module { $script:Fake.StorageMismatch=$false }
    Assert-Throws { Set-HuellaStorageProfile @storageArgs } 'perfil activo'
    & $module { $script:Fake.StorageGeneration++ }
    Assert ((Test-HuellaStorageProfile $storage.Path -Checker $fakeChecker).Verification -eq 'ProfileChangedOrInactive') 'Storage verifier rejects changed generation'
    Assert-Throws { Restore-HuellaStorageProfile $storage.Path -Checker $fakeChecker -Confirm:$false } 'perfil activo cambio'
    $disabled=Remove-HuellaStorageProfile -DiskNumber 2 -PnpInstanceId $storageArgs.PnpInstanceId -Checker $fakeChecker -Confirm:$false
    Assert (-not $disabled.Enabled) 'Explicit storage disable'
    $storage=Set-HuellaStorageProfile @storageArgs
    & $module { $script:Fake.StorageRaceOnClear=$true }
    Assert-Throws { Restore-HuellaStorageProfile $storage.Path -Checker $fakeChecker -Confirm:$false } 'generation changed'
    Assert (& $module { $script:Fake.StorageEnabled }) 'Restore race cannot clear a newer profile'
    $null=Remove-HuellaStorageProfile -DiskNumber 2 -PnpInstanceId $storageArgs.PnpInstanceId -Checker $fakeChecker -Confirm:$false
    $storage=Set-HuellaStorageProfile @storageArgs
    $disabled=Restore-HuellaStorageProfile $storage.Path -Checker $fakeChecker -Confirm:$false
    Assert (-not $disabled.Enabled) 'Storage journal restores by disabling its own generation'
    & $module { $script:Fake.FailWrites=$true }
    Assert-Throws { Set-HuellaStorageProfile @storageArgs } 'backup failure'
    Assert (-not (& $module { $script:Fake.StorageEnabled })) 'Storage backup failure causes no activation'
    & $module { $script:Fake.FailWrites=$false }
    Write-Output "PASS: $script:checks checks; synthetic OS only. Windows/WPF, real storage/MAC changes, Hyper-V and firmware flashing NOT RUN."
} finally {
    Remove-Module Huella -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}

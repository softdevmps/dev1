#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SignedPackageDirectory,
      [Parameter(Mandatory)][string]$SignTool,
      [Parameter(Mandatory)][switch]$LabVm)
$ErrorActionPreference = 'Stop'
if (!$LabVm) { throw 'Use a disposable VM and a secondary virtual disk.' }
$path = (Resolve-Path $SignedPackageDirectory).Path
$target = Get-Content "$path\lab-target.json" -Raw | ConvertFrom-Json
$disk = Get-Disk -Number $target.DiskNumber
if ($disk.IsBoot -or $disk.IsSystem) { throw 'Target became a boot/system disk.' }
$device = @(Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $target.DiskNumber)
if ($device.Count -ne 1 -or $device[0].PNPDeviceID -ne $target.InstanceId) { throw 'Target changed since packaging.' }
$matching = @(Get-PnpDevice -Class DiskDrive -PresentOnly | Where-Object {
    @((Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_HardwareIds).Data) -contains $target.HardwareId
})
if ($matching.Count -ne 1 -or $matching[0].InstanceId -ne $target.InstanceId) { throw 'Target ID is shared or missing.' }
$inf = [IO.File]::ReadAllText("$path\StorageFilter.inf")
if (!$inf.Contains("%Description%=LabInstall,$($target.HardwareId)")) { throw 'INF target does not match lab metadata.' }
# Verify kernel-policy signatures on the Microsoft-returned artifacts. Do not use test signing.
& $SignTool verify /kp /v "$path\StorageFilter.sys"
if ($LASTEXITCODE -ne 0) { throw 'Kernel signing verification failed.' }
& $SignTool verify /kp /v /c "$path\StorageFilter.cat" "$path\StorageFilter.sys"
if ($LASTEXITCODE -ne 0) { throw 'Catalog verification failed.' }
& $SignTool verify /kp /v /c "$path\StorageFilter.cat" "$path\StorageFilter.inf"
if ($LASTEXITCODE -ne 0) { throw 'INF catalog membership verification failed.' }
& pnputil.exe /add-driver "$path\StorageFilter.inf" /install
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) { throw "PnPUtil failed: $LASTEXITCODE" }
Write-Output 'Package staged/installed. Restart the secondary disk using PnPUtil on supported OS, or reboot the VM, then run Checker. Confirm device status; staging alone does not prove attachment.'

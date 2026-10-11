#Requires -RunAsAdministrator
[CmdletBinding(DefaultParameterSetName='VirtualLab')]
param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
      [Parameter(Mandatory,ParameterSetName='VirtualLab')][switch]$LabVm,
      [Parameter(Mandatory,ParameterSetName='PhysicalSecondary')][switch]$PhysicalSecondary,
      [ValidateSet('Debug','Release')][string]$Configuration = 'Debug',
      [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (!$LabVm -and !$PhysicalSecondary) { throw 'Select a disposable VM or an explicitly selected secondary physical disk.' }
$disk = Get-Disk -Number $DiskNumber
if ($disk.IsBoot -or $disk.IsSystem -or $disk.IsOffline) { throw 'Refusing a boot/system or offline disk.' }
$device = @(Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $DiskNumber)
if ($device.Count -ne 1) { throw 'Disk/PnP mapping is ambiguous.' }
$ids = @((Get-PnpDeviceProperty -InstanceId $device[0].PNPDeviceID -KeyName DEVPKEY_Device_HardwareIds).Data)
if (!$ids.Count -or !$ids[0]) { throw 'No hardware ID.' }
$hardwareId = [string]$ids[0]
if ($hardwareId -notmatch '^[A-Za-z0-9_&\\. -]+$') { throw 'Unsupported hardware ID characters; do not interpolate INF syntax.' }
# An INF targets hardware IDs, not instance IDs. Reject any shared present-disk ID.
$matching = @(Get-PnpDevice -Class DiskDrive -PresentOnly | Where-Object {
    $otherIds = @((Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_HardwareIds).Data)
    $otherIds -contains $hardwareId
})
if ($matching.Count -ne 1 -or $matching[0].InstanceId -ne $device[0].PNPDeviceID) {
    throw 'Hardware ID also matches another disk. Use a lab disk/controller with a distinct ID; never target all disks.'
}
$root = Split-Path $PSScriptRoot -Parent
$binary = "$root\out\x64\$Configuration\driver\StorageFilter.sys"
if (!(Test-Path $binary)) { throw 'Build the driver first.' }
if (Test-Path $OutputDirectory) { throw 'Use a new output directory to preserve existing packages.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$template = [IO.File]::ReadAllText("$root\package\StorageFilter.inf.in")
$template = $template.Replace('DriverVer=10/10/2026,1.1.0.0', ('DriverVer=' + [DateTime]::Now.ToString('MM/dd/yyyy', [Globalization.CultureInfo]::InvariantCulture) + ',1.1.0.0'))
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'StorageFilter.inf'), $template.Replace('__LAB_HARDWARE_ID__', $hardwareId), [Text.Encoding]::ASCII)
Copy-Item $binary (Join-Path $OutputDirectory 'StorageFilter.sys')
@{ DiskNumber=$DiskNumber; InstanceId=$device[0].PNPDeviceID; HardwareId=$hardwareId;
   TargetMode=$(if ($PhysicalSecondary) { 'PhysicalSecondary' } else { 'VirtualLab' });
   Warning='ID applies to any future device with the same hardware ID; keep package in isolated lab.' } |
    ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'lab-target.json')
Write-Output 'Package rendered. Run InfVerif and Inf2Cat, then submit through official Microsoft signing before installation.'

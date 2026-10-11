#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
      [Parameter(Mandatory)][string]$Checker,
      [Parameter(Mandatory)][string]$Baseline,
      [Parameter(Mandatory)][switch]$LabVm,
      [ValidateRange(1,100)][int]$Cycles = 10)
$ErrorActionPreference = 'Stop'
if (!$LabVm) { throw 'Use a disposable VM only.' }
$disk = Get-Disk -Number $DiskNumber
if ($disk.IsBoot -or $disk.IsSystem) { throw 'Refusing boot/system disk.' }
$target = Get-Content "$Baseline.target.json" -Raw | ConvertFrom-Json
$drive = @(Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $DiskNumber)
if ($drive.Count -ne 1 -or $drive[0].PNPDeviceID -ne $target.InstanceId) { throw 'Target changed.' }
$id = $drive[0].PNPDeviceID
for ($i=0; $i -lt $Cycles; $i++) {
    & pnputil.exe /restart-device $id
    if ($LASTEXITCODE -ne 0) { throw "PnP restart failed: $LASTEXITCODE. Windows 10 2004+ required for this command." }
    # Bounded readiness wait; the driver must publish a started instance, not merely a PID.
    $ready = $false
    for ($attempt=0; $attempt -lt 20; $attempt++) {
        & $Checker stress "$DiskNumber" 1 1
        if ($LASTEXITCODE -eq 0) { $ready=$true; break }
        Start-Sleep -Milliseconds 500
    }
    if (!$ready) { throw 'Filter did not become ready after restart.' }
    & $Checker compare "$DiskNumber" $Baseline
    if ($LASTEXITCODE -ne 0) { throw 'Identifier comparison failed after PnP restart.' }
}
Write-Output "PASS: $Cycles sequential PnP restarts and identifier comparisons."

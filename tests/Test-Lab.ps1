#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Baseline','Validate')][string]$Phase,
      [Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
      [Parameter(Mandatory)][string]$Checker,
      [Parameter(Mandatory)][string]$Baseline,
      [Parameter(Mandatory)][switch]$LabVm,
      [ValidateRange(1,32)][int]$Threads = 8,
      [ValidateRange(1,100000)][int]$Iterations = 1000)
$ErrorActionPreference = 'Stop'
if (!$LabVm) { throw 'Use an isolated Windows VM with a secondary virtual disk.' }
$disk = Get-Disk -Number $DiskNumber
if ($disk.IsBoot -or $disk.IsSystem) { throw 'Refusing boot/system disk.' }
$drive = @(Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $DiskNumber)
if ($drive.Count -ne 1) { throw 'Ambiguous disk/PnP mapping.' }
function Run-Checker([string[]]$Arguments) {
    & $Checker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Checker failed: $($Arguments -join ' '); exit=$LASTEXITCODE" }
}
if ($Phase -eq 'Baseline') {
    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='StorageFilter'"
    if ($driver -and $driver.State -eq 'Running') { throw 'Capture baseline before loading StorageFilter.' }
    if (Test-Path "$Baseline.target.json") { throw 'Choose a new baseline path.' }
    Run-Checker -Arguments @('baseline', "$DiskNumber", $Baseline)
    @{ DiskNumber=$DiskNumber; InstanceId=$drive[0].PNPDeviceID } |
        ConvertTo-Json | Set-Content "$Baseline.target.json"
} else {
    $target = Get-Content "$Baseline.target.json" -Raw | ConvertFrom-Json
    if ($target.DiskNumber -ne $DiskNumber -or $target.InstanceId -ne $drive[0].PNPDeviceID) { throw 'Baseline belongs to another disk instance.' }
    Run-Checker -Arguments @('snapshot')
    Run-Checker -Arguments @('compare', "$DiskNumber", $Baseline)
    Run-Checker -Arguments @('stress', "$DiskNumber", "$Threads", "$Iterations")
    Run-Checker -Arguments @('negative', "$DiskNumber")
    Run-Checker -Arguments @('control-negative')
    Run-Checker -Arguments @('compare', "$DiskNumber", $Baseline)
    Run-Checker -Arguments @('snapshot')
}
Write-Output "PASS: $Phase phase completed. No PnP/power/Verifier results are implied."

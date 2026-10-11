# Test helper only; exits after 20 seconds even if its parent dies.
param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Signal)
$ErrorActionPreference='Stop'
$mutex=New-Object Threading.Mutex($false,$Name)
$held=$false
try {
    $held=$mutex.WaitOne(5000)
    if (-not $held) { throw 'Could not acquire test mutex' }
    [IO.File]::WriteAllText($Signal,'ready')
    Start-Sleep -Seconds 20
} finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }

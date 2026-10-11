# Syntax validation only: does not execute the Windows driver workflow.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem "$root/scripts/*.ps1") + @(Get-ChildItem "$root/tests/*.ps1")
$failed = $false
foreach ($file in $files) {
    $tokens = $null
    $syntaxErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$syntaxErrors)
    foreach ($errorRecord in $syntaxErrors) {
        [Console]::Error.WriteLine("$($file.Name): $errorRecord")
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Output "PASS: $($files.Count) PowerShell files parsed; Windows runtime operations not executed."

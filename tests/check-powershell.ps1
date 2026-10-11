# Syntax validation only: does not execute the Windows driver workflow.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem "$root/scripts/*.ps1") + @(Get-ChildItem "$root/tests/*.ps1") +
    @(Get-ChildItem "$root/huella" -Recurse -Include '*.ps1','*.psm1')
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
$xaml = [xml](Get-Content -LiteralPath "$root/huella/Window.xaml" -Raw -Encoding UTF8)
$names = @($xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
})
$interfaceSource = Get-Content -LiteralPath "$root/huella/Run-Huella.ps1" -Raw -Encoding UTF8
$references = @([regex]::Matches($interfaceSource, '\$controls\.([A-Za-z]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($reference in $references) {
    if ($names -notcontains $reference) { throw "XAML control missing: $reference" }
}
Write-Output "PASS: XAML XML and $($references.Count) control references; WPF runtime not executed."

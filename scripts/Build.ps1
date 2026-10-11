[CmdletBinding()]
param([ValidateSet('Debug','Release')][string]$Configuration = 'Debug', [switch]$Analyze)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $vswhere)) { throw 'Install Visual Studio 2022 with C++ and the compatible WDK integration.' }
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (!$msbuild) { throw 'MSBuild not found.' }
$buildArgs = @("$root\StorageFilter.sln", '/m:2', '/t:Build', "/p:Configuration=$Configuration", '/p:Platform=x64', '/v:minimal')
if ($Analyze) { $buildArgs += '/p:RunCodeAnalysis=true' }
& $msbuild @args
if ($LASTEXITCODE -ne 0) { throw "MSBuild failed: $LASTEXITCODE. Preserve the build log and fix the reported error." }
foreach ($file in @("driver\StorageFilter.sys", "checker\Checker.exe")) {
    if (!(Test-Path "$root\out\x64\$Configuration\$file")) { throw "Missing output: $file" }
}

[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackageDirectory,
      [Parameter(Mandatory)][string]$InfVerif,
      [Parameter(Mandatory)][string]$Inf2Cat,
      [Parameter(Mandatory)][string]$OsTargets)
$ErrorActionPreference = 'Stop'
$path = (Resolve-Path $PackageDirectory).Path
# OsTargets must be copied from the installed Inf2Cat /? list for the intended OS builds.
& $InfVerif /w "$path\StorageFilter.inf"
if ($LASTEXITCODE -ne 0) { throw "InfVerif failed: $LASTEXITCODE" }
& $Inf2Cat "/driver:$path" "/os:$OsTargets" /uselocaltime
if ($LASTEXITCODE -ne 0) { throw "Inf2Cat failed: $LASTEXITCODE" }
if (!(Test-Path "$path\StorageFilter.cat")) { throw 'Catalog was not generated.' }

#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
foreach ($file in @('Common.ps1', 'Inventory.ps1', 'Actions.ps1', 'Firmware.ps1', 'Storage.ps1')) {
    . (Join-Path $PSScriptRoot "src/$file")
}
Export-ModuleMember -Function Get-HuellaInventory, Export-HuellaInventory, New-HuellaMacAddress,
    Invoke-HuellaChange, Restore-HuellaChange, Test-HuellaChange, Get-HuellaHistory,
    New-HuellaFirmwarePlan, Test-HuellaFirmwarePackage, Start-HuellaFirmwareUtility,
    Get-HuellaVendorPolicy, Test-HuellaAdministrator, New-HuellaAsusCapsule,
    Copy-HuellaFirmwareToUsb, Get-HuellaStorageProfile, Set-HuellaStorageProfile,
    Remove-HuellaStorageProfile, Restore-HuellaStorageProfile, Test-HuellaStorageProfile

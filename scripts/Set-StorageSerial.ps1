#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([Parameter(Mandatory)][ValidateSet('Set','Clear','Status','Test')][string]$Action,
    [Parameter(Mandatory)][ValidateRange(1,1024)][int]$DiskNumber,
    [Parameter(Mandatory)][string]$PnpInstanceId,
    [ValidatePattern('^[A-Za-z0-9_-]{1,31}$')][string]$Serial,
    [string]$Checker='', [switch]$PhysicalSecondary)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module "$root\huella\Huella.psm1" -Force
if ($Action -eq 'Status') { Get-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker; return }
if ($Action -eq 'Clear') {
    if ($PSCmdlet.ShouldProcess($PnpInstanceId,'Desactivar perfil')) { Remove-HuellaStorageProfile $DiskNumber $PnpInstanceId $Checker -Confirm:$false }
    return
}
if (-not $PhysicalSecondary -or [string]::IsNullOrWhiteSpace($Serial)) { throw 'Indica -PhysicalSecondary y -Serial para el disco seleccionado.' }
if (-not $PSCmdlet.ShouldProcess($PnpInstanceId,"$Action perfil de almacenamiento y verificar respuestas")) { return }
if ($Action -eq 'Set') {
    $result=Set-HuellaStorageProfile $DiskNumber $PnpInstanceId $Serial -PhysicalSecondary -Checker $Checker -Confirm:$false
    if ($result.Record.Status -ne 'Applied') { throw "El cambio fallo: $($result.Record.Error). Diario: $($result.Path)" }
    $result
} else {
    $module=Get-Module Huella
    & $module {
        param($Number,$Instance,$Value,$Executable)
        $null=Get-HuellaSecondaryDisk $Number $Instance
        $path=Get-HuellaCheckerPath $Executable
        Invoke-HuellaSystem Checker @{ Path=$path; CommandArguments=@('serial-test',[string]$Number,$Value,'--secondary') }
    } $DiskNumber $PnpInstanceId $Serial $Checker
}

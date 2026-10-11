# Real Windows checks. VirtualMac writes only to an explicitly selected,
# powered-off lab VM; finally restores its previous static/dynamic assignment.
#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param([ValidateSet('Inventory','VirtualMac')][string]$Phase='Inventory',
    [string]$VmName,[string]$AdapterName,[switch]$LabVm)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or [IntPtr]::Size -ne 8) { throw 'Necesita Windows x64.' }
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'Huella.psm1') -Force
if ($Phase -eq 'Inventory') {
    $inventory=Get-HuellaInventory
    if (@($inventory.Rows | Where-Object { $_.Kind -eq 'ComputerName' -and $_.Status -eq 'Leido' }).Count -ne 1) { throw 'No se pudo leer el nombre del equipo.' }
    if (@($inventory.Rows | Where-Object { $_.Category -eq 'GPU' -and $_.Source -like '*.PNPDeviceID' -and $_.Value -eq 'PCI' }).Count -gt 0) { throw 'ID GPU truncado.' }
    $errors=@($inventory.Rows | Where-Object { $_.Status -like '*error*' })
    foreach ($row in $errors) { Write-Warning "$($row.Category): $($row.Detail)" }
    Write-Output "Inventario: $($inventory.Rows.Count) filas, $($errors.Count) consultas con error. Revisa los avisos; no se verifico exhaustividad de seriales ni acciones de cambio."
    exit 0
}
if (-not $LabVm -or $VmName -eq '' -or $AdapterName -eq '') { throw 'Indica -LabVm, -VmName y -AdapterName de una VM descartable.' }
if (-not (Test-HuellaAdministrator)) { throw 'Ejecuta como administrador.' }
$vms=@(Get-VM -ErrorAction Stop | Where-Object { $_.Name -ceq $VmName })
if ($vms.Count -ne 1 -or [string]$vms[0].State -ne 'Off') { throw 'La VM debe existir una sola vez y estar apagada.' }
$adapters=@(Get-VMNetworkAdapter -VM $vms[0] -ErrorAction Stop | Where-Object { $_.Name -ceq $AdapterName })
if ($adapters.Count -ne 1) { throw 'Selecciona un unico adaptador virtual.' }
$target="$($vms[0].Id)|$($adapters[0].Id)"
if (-not $PSCmdlet.ShouldProcess($VmName,'Cambiar, verificar y restaurar la MAC virtual de laboratorio')) { return }
$change=$null
try {
    $change=Invoke-HuellaChange -Kind VirtualMacAddress -Target $target -NewValue (New-HuellaMacAddress) -LabVm -Confirm:$false
    if ($change.Record.Status -ne 'Applied' -or (Test-HuellaChange $change.Path).Verification -ne 'Verified') { throw "Cambio no verificado. Respaldo: $($change.Path)" }
    Write-Output 'PASS: MAC virtual nueva leida por Get-VMNetworkAdapter.'
} finally {
    if ($null -ne $change) {
        $restored=Restore-HuellaChange $change.Path -LabVm -Confirm:$false
        if ($restored.Record.Status -ne 'Applied' -or (Test-HuellaChange $restored.Path).Verification -ne 'Verified') { throw "Restauracion no verificada; revisar $($change.Path) y $($restored.Path)." }
        Write-Output 'PASS: configuracion estatica/dinamica anterior restaurada.'
    }
}

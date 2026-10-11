# Resultados y pendientes de Huella

Validacion ejecutada en el anfitrion Linux con PowerShell 7.5.4; el producto esta dirigido a Windows y el lanzador usa Windows PowerShell 5.1. No hay conexion de ejecucion al Windows del usuario.

| Comprobacion | Resultado |
|---|---|
| Importacion del modulo y parser PowerShell | Ejecutado; 19 fuentes PowerShell del repositorio sin errores de sintaxis encontrados |
| Layout | XML XAML y 20 referencias a controles comprobados; no equivale a ejecutar WPF |
| Suite `tests/Test-Huella.ps1` | 2387 comprobaciones pasadas con sistema operativo inyectado y dispositivos sinteticos |
| Competidor del mutex | Ejecutado en proceso PowerShell separado; rechazo antes de modificar el estado sintetico |
| EDID | Todas las longitudes menores de 128 rechazadas; checksum y fabricante; monitores iguales asociados por instancia |
| Motor de cambios | WhatIf sin escritura, respaldo antes del cambio, error de respaldo, error parcial, restauracion, vinculo a equipo, reinicio requerido y VM apagada |
| Firmware | Firma/editor simulado, modelo cambiado, recuperacion desconocida, hash cambiado y salida de proceso simulado; no implica firma real ni flasheo |
| Preparacion ASUS UEFI/USB | ZIP/CAP sintetico: SHA256 distinto, rutas maliciosas, capsula ambigua, USB de sistema, WhatIf, archivo existente y manipulacion posterior; copia comprobada por hash |
| Orquestacion del serial de disco | Checker simulado; identidad PnP, disco protegido, capacidad, WhatIf, diario previo, valor observado distinto, perfil cambiado y carrera durante restauracion; no ejecuta un EXE ni un IOCTL real |
| WPF y cmdlets en Windows PowerShell 5.1 | **NO EJECUTADO** |
| Cambio/restauracion real de nombre o MAC, ACL y concurrencia Windows | **NO EJECUTADO** |
| Hyper-V real | **NO EJECUTADO** |
| Serial de disco fisico secundario: activacion, consultas, concurrencia y restauracion reales | **NO EJECUTADO**; procedimiento en `../docs/storage-serial.md` y `../tests/Test-StorageSerial.ps1` |
| Firma de scripts, EXE de fabricante real y firmware | **NO EJECUTADO** |
| Descarga oficial ASUS | Paginas BIOS/manual/FAQ consultadas via HTTPS: HTTP 403. No se descargaron imagenes ni se comprobaron versiones disponibles |
| Escritura de identificadores fisicos de todos los componentes | **PENDIENTE de interfaces oficiales por modelo; no implementado como accion universal** |

Se corrigieron dos errores durante las pruebas: el reemplazo atomico del JSON necesita una ruta de backup explicita al invocar .NET desde PowerShell, y la verificacion de una restauracion de nombre pendiente debe comparar el nombre activo con el nombre configurado solicitado. El restablecimiento de MAC sin override usa el cmdlet documentado `Reset-NetAdapterAdvancedProperty`.

La revision inicial del `.rar` identifico perdida del ID GPU, desbordamiento en fabricante EDID, asociacion por orden/nombre de monitores, errores silenciados y capacidades sin comprobacion. Los nuevos recolectores conservan IDs completos, usan cast entero/checksum, asocian por instancia y muestran errores. No atribuyen `Win32_BIOS.SerialNumber` a SMBIOS tipo 0 ni prometen unicidad universal.

La aplicacion configura el perfil del filtro de almacenamiento cuando ya esta instalado. No instala ni carga automaticamente el SYS. La validacion WDK, firma e instalacion siguen pendientes en `../docs/validation.md`. La publicacion del codigo en GitHub no equivale a ninguna de las pruebas Windows pendientes.

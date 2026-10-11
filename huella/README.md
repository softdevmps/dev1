# Huella para Windows

Aplicacion local para Windows 10/11 x64, escrita en PowerShell 5.1 y WPF. Abre `Abrir-Huella.cmd` despues de extraer el repositorio. No necesita WDK para observar ni para las acciones de usuario. **La interfaz y las acciones reales todavia deben probarse en Windows.**

Selecciona una fila para ver el origen y las acciones disponibles. `Aplicar y respaldar` guarda la configuracion anterior antes de cambiarla; `Verificar respaldo` vuelve a leer el dispositivo; `Restaurar respaldo` crea otra operacion con su propio respaldo. `Generar MAC` genera una direccion unicast administrada localmente. Revisa la conexion antes de reiniciar una interfaz de red.

El inventario puede abrirse sin elevar permisos y muestra los errores de cada consulta. Para aplicar cambios usa `Abrir como administrador`, que pide UAC. La aplicacion conserva la politica de ejecucion de PowerShell y las protecciones de Windows.

## Capacidades

| Dato | Accion implementada | Persistencia / dependencia |
|---|---|---|
| Nombre de la PC | `Rename-Computer`, respaldo y verificacion | Equipo fuera de dominio; reinicio; reversible con respaldo |
| MAC de NIC fisica | Propiedad `NetworkAddress` publicada por su controlador, reinicio, verificacion, restauracion/reset de la propiedad | Hasta restaurar; requiere controlador compatible; no regraba la MAC de fabrica |
| MAC virtual Hyper-V | `Set-VMNetworkAdapter`, respaldo de modo dinamico/estatico, verificacion y restauracion | Solo VM de laboratorio apagada; requiere Hyper-V |
| BIOS/UEFI con asistente EXE | Plan del modelo/placa/version, soporte oficial, validacion Authenticode y SHA256, apertura del asistente firmado | Revision manual del procedimiento y validacion de imagen por fabricante; no garantiza cambio de seriales |
| ASUS ROG STRIX X670E-A GAMING WIFI | Perfil de UEFI: comprobar SHA256 de ZIP oficial, extraer CAP, copiar y verificar en USB FAT32 | Validacion de firma/compatibilidad y actualizacion desde UEFI segun el manual; no cambia seriales por si solo |
| Seriales placa/sistema/chasis/RAM/discos, GPU, CPU, USB, monitores | Consulta e identificacion de la fuente | Modificacion fisica pendiente de interfaces y procedimientos documentados por modelo |
| GUID/firma de disco, serial del volumen | Consulta separada del serial fisico | Sin escrituras de sectores ni reparticionado dentro de Huella |
| MachineGuid, ProductId, SID de cuentas | Observacion con significado separado | No se simula una reinstalacion ni se cambia SAM/licenciamiento |
| TPM y Secure Boot | Observacion; errores quedan como desconocidos | Sin borrado de claves ni cambios de protecciones |

Una actualizacion de BIOS, SSD o VBIOS puede conservar los identificadores. El firmware ejecutable y los datos de fabricacion pueden estar en regiones distintas, protegidas o con aprovisionamiento especifico. No existe una imagen universal que resuelva todos esos casos. El desarrollo de cada escritura fisica requiere modelo, revision, documentacion y recuperacion propios; [firmware.md](firmware.md) detalla el flujo implementado y lo pendiente.

## Archivos y datos

`Huella.psm1` carga los recolectores, el motor de cambios y la gestion de firmware. `Run-Huella.ps1` y `Window.xaml` forman la interfaz. Los recolectores usan CIM, Storage, NetAdapter, WMI de monitores y cmdlets de seguridad documentados; no necesitan el filtro de almacenamiento para cambiar nombre o MAC.

Los respaldos se guardan en `%LOCALAPPDATA%\Huella`. El directorio tiene permisos para el usuario, administradores y SYSTEM; un hash de MachineGuid vincula cada respaldo al equipo. Cada cambio se serializa mediante un mutex global de Windows, verifica de nuevo el estado antes de escribir y conserva `Prepared`, `Applying`, `Applied` o `Failed` en un diario con escritura atomica. Una caida puede dejar `Applying`: vuelve a consultar y restaura desde el respaldo si corresponde. No hay rollback automatico tras un cambio parcial.

`Verified` significa que la API consultada devuelve el valor esperado. `RebootRequired` significa que el nuevo nombre esta configurado pero aun no activo. `VerificationPending` requiere otra lectura o investigar el controlador. Estos estados no demuestran que todas las aplicaciones o protocolos vean el mismo identificador.

`Guardar inventario` exporta JSON local y no sobrescribe un archivo existente. Contiene identificadores reales del equipo; no lo publiques. El `.rar` original y el informe personal recibido no se incluyen en el repositorio.

## Si Windows bloquea el script

Conserva el error que deja el lanzador. En equipos que exigen firma, un editor de confianza debe firmar todos los `.ps1` y `.psm1` con un certificado de firma de codigo aceptado por la politica del equipo. No se incluye ningun `ExecutionPolicy Bypass`, certificado autofirmado ni cambio de politica.

Ejemplo para el responsable de distribuir el proyecto, con su certificado de firma de codigo ya instalado y su servicio de timestamp corporativo:

```powershell
$cert = Get-Item 'Cert:\CurrentUser\My\HUELLA_CERT_THUMBPRINT'
Get-ChildItem .\huella -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $result = Set-AuthenticodeSignature -LiteralPath $_.FullName -Certificate $cert -TimestampServer 'https://TU_SERVICIO_DE_TIMESTAMP'
    if ($result.Status -ne 'Valid') { throw "Firma fallida: $($_.Name): $($result.Status)" }
}
```

Los valores son marcadores que debe sustituir el responsable; no son un certificado ni un servidor disponibles. La firma no sustituye la politica de confianza de la organizacion. La firma oficial del controlador kernel sigue su propio procedimiento en `docs/build-sign-install.md`.

## Pruebas

```powershell
.\huella\tests\Test-Huella.ps1
.\huella\tests\Test-HuellaWindows.ps1 -Phase Inventory
```

La primera prueba inyecta dispositivos sinteticos y no consulta ni cambia los identificadores del anfitrion. La segunda requiere Windows y consulta sus dispositivos. Para cambiar un adaptador virtual descartable en un host Hyper-V elevado:

```powershell
.\huella\tests\Test-HuellaWindows.ps1 -Phase VirtualMac -VmName 'Huella-Lab' -AdapterName 'Network Adapter' -LabVm
```

La VM debe estar apagada. La prueba cambia, vuelve a leer y restaura en `finally`. Los nombres se deben sustituir por los del laboratorio. Las pruebas de NIC fisica y nombre requieren seguir [testing.md](testing.md), porque afectan conectividad y reinicio. No ejecutes pruebas de firmware como prueba automatica de CI.

Consulta [validation.md](validation.md) para resultados ejecutados y pendientes. El driver de almacenamiento sigue observando IRP y respuestas sin transformarlas; no controla SMBIOS, GPU, RAM ni TPM.

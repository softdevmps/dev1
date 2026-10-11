# Pruebas en Windows pendientes de ejecutar

Usa primero una VM Windows 10/11 x64 descartable con instantanea y protecciones normales. Las comprobaciones de PowerShell sinteticas se pueden ejecutar sin privilegios. No prueban WPF ni drivers reales.

## Lecturas

Abre `Abrir-Huella.cmd`, actualiza, selecciona filas y guarda el inventario en un archivo nuevo. Compara los IDs PnP completos de GPU y USB con el Administrador de dispositivos y `Get-CimInstance`. Comprueba monitores iguales por `InstanceName`, no por nombre u orden. Ejecuta sin elevar y como administrador: una consulta denegada debe aparecer como error, no como `False` o dato vacio exitoso. Repite en Windows PowerShell 5.1, que es el runtime del lanzador.

## Nombre del equipo

En una VM fuera de dominio, anota el nombre y guarda una instantanea. Aplica un nombre valido diferente: debe guardar respaldo y mostrar `RebootRequired`. Reinicia desde Windows y verifica el respaldo: debe devolver `Verified`. Restaura, reinicia y verifica el nuevo registro de restauracion. Prueba nombre invalido, nombre numerico y equipo de dominio: debe rechazar antes de escribir. Los respaldos permanecen en `%LOCALAPPDATA%\Huella`.

## Red

En un equipo de laboratorio usa una NIC secundaria cuya desconexion no afecte la sesion de control. `Get-NetAdapterAdvancedProperty -Name NOMBRE -RegistryKeyword NetworkAddress -AllProperties` debe publicar esa propiedad. Huella no crea propiedades que el controlador no tenga. Compara MAC antes/despues mediante `Get-NetAdapter` y, si corresponde al uso, captura trafico en otra maquina. El resultado local no demuestra ausencia de MAC duplicadas en toda la red. Prueba restauracion de un valor anterior y reset cuando no habia override. Un driver que rechaza/ignora el valor debe dejar `Failed` o `VerificationPending`, nunca una confirmacion fabricada.

Para MAC virtual ejecuta `Test-HuellaWindows.ps1 -Phase VirtualMac` con la VM/adaptador indicados en README. Verifica rechazo si esta encendida y restauracion del modo dinamico anterior. Hyper-V requiere una edicion/host compatible y privilegios.

## Fallos y concurrencia

Dos instancias que aplican simultaneamente deben serializarse o rechazar al competidor mientras el mutex esta ocupado. El diario debe estar escrito antes de modificar. Simula directorio de respaldo sin permisos y confirma ausencia de cambios. Conserva una copia local del respaldo antes de probar corrupcion/otro equipo. Un fallo de reinicio de adaptador tras escribir la propiedad es un cambio parcial: conserva el diario, consulta, restaura y vuelve a consultar. Tras una terminacion abrupta revisa `Prepared`/`Applying`; no hay rollback al arrancar sin intervencion.

Las pruebas sinteticas cubren el competidor en otro proceso, fallos de respaldo y reinicio, restauraciones y entradas truncadas. Falta reproducir esos escenarios con cmdlets y dispositivos reales, asi como validar ACL efectivas en Windows.

## Firmware

La revision de un EXE se puede probar sin abrirlo. Prueba rechazo de paquete sin firma, editor diferente, SHA256 cambiado y plan de otro modelo/equipo. Una firma valida debe seguir mostrando que falta confirmacion de compatibilidad. Probar el flasheo requiere hardware de laboratorio del modelo exacto y procedimiento de recuperacion del fabricante; no es una prueba generica de VM ni de CI. Consulta `firmware.md`.

En la placa ASUS contemplada, prueba primero la preparacion y copia a un USB FAT32 secundario: hash publicado del ZIP, una sola capsula del modelo, ausencia de sobrescrituras, rechazo de volumen del sistema y hash de la copia. La suite sintetica usa bytes que **no son firmware**; jamas se deben escribir desde UEFI. La validacion de una capsula oficial y cualquier flasheo siguen pendientes.

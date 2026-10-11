# Firmware: alcance y trabajo pendiente

Huella crea un plan de BIOS/UEFI a partir de `Win32_ComputerSystem`, `Win32_BaseBoard` y `Win32_BIOS`. Guarda fabricante, modelo del sistema, productos de placas y version actual. Detecta cambios de ese objetivo al revisar el plan. El modelo de placa por si solo no sustituye al modelo del equipo OEM.

1. Crea el plan desde la interfaz y abre el soporte oficial. Selecciona modelo, revision y sistema operativo exactos. Confirma si el fabricante permite **editar los identificadores que buscas**, ademas de actualizar la version de firmware.
2. Sigue su procedimiento de respaldo/recuperacion. Huella respalda la configuracion de sus acciones Windows; el plan de firmware **no es una copia recuperable de la flash**. Prepara alimentacion estable y recuperacion BitLocker externa al equipo. Huella no lee ni guarda claves de recuperacion.
3. Descarga el asistente EXE oficial autocontenido y pulsa `Revisar paquete oficial`. Huella exige Authenticode `Valid`, una organizacion firmante contemplada para el fabricante detectado y calcula SHA256. La firma identifica al editor; no demuestra compatibilidad de una imagen ni que el asistente permita cambiar seriales.
4. Para abrirlo, escribe el modelo exacto y confirma las preparaciones. Huella vuelve a comprobar objetivo, firma y hash; copia el asistente a un directorio privado y comprueba otra vez esa copia. Lo abre mediante UAC sin agregar argumentos de flasheo. El asistente debe comprobar la compatibilidad de la imagen y presentar la operacion al usuario. Algunos asistentes podrian iniciar operaciones al abrirse: revisa su documentacion antes de lanzarlos.
5. Sigue las comprobaciones y reinicios indicados por el fabricante. Huella registra la salida del proceso como `UtilityExited` o `LaunchFailed`; un codigo de salida no se presenta como confirmacion de flasheo ni de seriales nuevos. Genera un inventario posterior y comprueba cada valor.

Los enlaces de soporte contemplan Dell, HP, Lenovo, ASUS, Acer, Microsoft, MSI y Gigabyte. La apertura de EXE se limita a las organizaciones firmantes declaradas en el codigo; MSI/Gigabyte tienen enlace pero aun requieren revision manual de su herramienta. Un fabricante desconocido, certificado nuevo no contemplado, imagen raw o paquete que necesita archivos externos requiere integrar su procedimiento documentado; no se inventa compatibilidad. La fecha o revision de una imagen no se valida mediante su nombre de archivo.

## Ruta UEFI para ASUS ROG STRIX X670E-A GAMING WIFI

Esta placa tiene un perfil separado de los asistentes EXE. Se activa solo cuando las consultas del equipo actual devuelven fabricante ASUS y ese producto exacto de placa. El plan abre su pagina de BIOS y enlaza el manual. En este entorno las paginas ASUS respondieron HTTP 403; no se ha obtenido ni validado una descarga real ni se ha establecido que exista una version superior a la instalada.

Descarga el ZIP oficial del modelo y copia su SHA256 publicado en el campo de Huella. El hash debe corresponder al **ZIP**, no al CAP ni a un hash calculado localmente para aparentar una referencia oficial. Si no hay una referencia confiable, queda pendiente la preparacion mediante este flujo. `New-HuellaAsusCapsule` abre el archivo una sola vez para comprobar hash y extraer, limita tamano/numero de entradas, rechaza rutas y exige una sola entrada CAP con el nombre largo del modelo. No ejecuta BIOSRenamer ni otros archivos del ZIP.

La capsula extraida se guarda localmente y puede copiarse con `Copiar CAP al USB`. Debe existir ya un volumen USB FAT32 con espacio que no sea de arranque/sistema; Huella no formatea y no sobrescribe archivos. Comprueba el hash despues de copiar. El nombre largo esta pensado para la seleccion desde **EZ Flash**; **USB BIOS FlashBack tiene sus propias instrucciones de nombre/puerto y no se presenta como equivalente**. Sigue el manual exacto antes de entrar a UEFI y conserva el metodo de recuperacion.

La coincidencia de SHA256 es `MatchesProvidedReference`: acredita igualdad con la referencia que aportaste. Huella no verifica la firma interna de ASUS, la compatibilidad binaria ni si la capsula puede cambiar seriales. Eso queda en `RequiresOfficialSource`, `RequiresUefiValidation` y `IdentifierChange=NotEstablished`. El estado de copia nunca se convierte en una afirmacion de flasheo.

| Componente | Que falta para implementar escrituras especificas |
|---|---|
| SMBIOS / serial placa / UUID / chasis | Procedimiento oficial de provisionamiento/servicio, revision exacta, reglas de serial/UUID y recuperacion |
| SSD SATA/NVMe | Utilidad/API oficial para el modelo, confirmacion de que expone escritura del serial y estrategia de recuperacion; firmware nuevo por si solo puede conservarlo |
| NIC EEPROM | Herramienta del fabricante y limites del adaptador; el override de Windows ya implementado es otro mecanismo |
| GPU VBIOS | Modelo/revision/imagen firmada y herramienta oficial; IDs PCI no equivalen a un serial editable de VBIOS |
| RAM SPD, monitor EDID, USB | Interfaz de aprovisionamiento autorizada para ese producto; los datos publicados por Windows no prueban que la memoria permita escrituras |
| TPM | Procedimientos oficiales de aprovisionamiento y sus consecuencias; no se equipara cambiar firmware a cambiar una identidad criptografica |

No se han generado ni modificado imagenes de firmware. Tampoco se ha ejecutado ningun asistente de fabricante. Resolver los casos de esta tabla requiere datos del hardware concreto y documentacion de sus interfaces; no puede darse por terminado como un cambio universal de todos los seriales.

Referencias: [Get-AuthenticodeSignature](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/get-authenticodesignature), [SHA256 / Get-FileHash](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/get-filehash), [actualizaciones de firmware en Windows](https://learn.microsoft.com/windows-hardware/drivers/bringup/windows-uefi-firmware-update-platform), [recuperacion BitLocker](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/recovery-overview).

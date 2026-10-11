# Continuar este proyecto con Codex en Windows

Este archivo resume la conversacion y el estado del proyecto para una nueva sesion local. No es una transcripcion completa. El producto se dirige a Windows; el entorno de desarrollo anterior era una nube Linux y no tenia acceso al equipo Windows del usuario.

## Abrir el proyecto localmente

1. Instala Git y Visual Studio Code en Windows, si todavia no los tienes.
2. Clona `https://github.com/softdevmps/dev1.git` y abre la carpeta `dev1` en VS Code. Tambien puedes extraer el ZIP del repositorio y abrir la carpeta extraida.
3. Instala la extension oficial Codex de OpenAI siguiendo https://developers.openai.com/codex/ide y accede con tu cuenta de ChatGPT. Trabaja en la carpeta local de Windows.
4. Pega: **Lee CONTINUAR-CON-CODEX.md y los informes de validacion. Inspecciona el repositorio y las herramientas disponibles en mi Windows. Continua con la compilacion WDK y corrige los errores reales antes de preparar pruebas de carga.**

La sesion local puede leer los archivos y ejecutar comandos que sus permisos permitan. Este chat de nube no se convierte automaticamente en una conexion remota al equipo. La extension de VS Code y Visual Studio 2022/WDK cumplen funciones distintas: VS Code permite trabajar con Codex; Visual Studio/WDK compilan el controlador.

## Alternativa: terminal Windows

Con Node.js LTS y npm instalados, abre PowerShell en la carpeta del proyecto:

```powershell
npm.cmd install -g @openai/codex
codex.cmd
```

Selecciona **Sign in with ChatGPT** y pega el mismo mensaje del punto 4. Los wrappers `.cmd` permiten usar npm/Codex sin cambiar la politica de ejecucion de PowerShell. La instalacion por npm y el inicio con la cuenta estan documentados en https://github.com/openai/codex.

## Objetivo y alcance acordados

- Crear un proyecto real C/WDM para Windows 10 1903+ y Windows 11 x64, con DriverEntry, AddDevice, contexto por instancia, PnP, power, IRP y completions, sincronizacion, retirada, trazas, control Ring 3, Checker, INF y pruebas reproducibles.
- El objetivo ampliado del usuario es poder cambiar los principales identificadores observados por Huella. La cobertura actual es parcial; no afirmar que existe un spoofer completo.
- La limitacion inicial del perfil de almacenamiento a transformaciones sinteticas/virtuales se amplio expresamente a **un disco fisico secundario seleccionado**. Excluir disco 0, arranque/sistema y uso especial. Conservar el alcance documentado de cada modulo y sus dependencias reales.
- Conservar Secure Boot, Driver Signature Enforcement y las protecciones normales. No usar test signing ni evasiones de firma. La carga requiere los mecanismos oficiales de Microsoft.
- Inspeccionar los archivos existentes primero, corregir errores comprobados, crear commits por modulo y documentar funcionalidades y pendientes. El usuario pidio publicar el codigo completo en este repositorio.

## Estado del codigo

La referencia publicada antes de este resumen era `5ea7f19`. Consulta el HEAD actual; este archivo se agrega despues de esa referencia.

| Modulo | Implementacion |
| --- | --- |
| StorageFilter | Filtro superior PnP por dispositivo, remove locks, reenvio/completions, PnP/power, propiedades de hardware y callback de registro opcional con altitud oficial |
| Perfil de almacenamiento | Sustitucion temporal de SerialNumber en IOCTL_STORAGE_QUERY_PROPERTY / StorageDeviceProperty / PropertyStandardQuery, por instancia y numero de disco |
| Concurrencia | ExpectedGeneration en el IOCTL; comparacion de instancia/generacion desde Huella y Checker; invalidacion del perfil por ciclo PnP/uso especial |
| Checker | Baseline, comparacion, stress, entradas invalidas, serial-status/set/clear/expect/test/negative; verificacion directa y restauracion |
| Huella | Inventario PowerShell 5.1/WPF, nombre de equipo, MAC compatible, MAC virtual Hyper-V y perfiles del secundario con diario previo, verificacion y restauracion |
| Firmware | Revision de asistentes oficiales y preparacion ASUS CAP/USB; no implementa escritura de seriales de fabrica |
| Paquete | INF Extension AddFilter 1.1.0.0, generacion e instalacion con seleccion -LabVm o -PhysicalSecondary, validacion y firma oficial |

El perfil nuevo admite 1..31 caracteres ASCII permitidos y debe caber en el campo original. No amplia el descriptor; borra el resto del serial anterior dentro de ese campo y conserva los bytes externos. Se activa expresamente y no se reactiva al arrancar. No reprograma firmware, GUID GPT, firma MBR, serial de volumen ni VPD/NVMe. CIM u otras rutas pueden seguir mostrando otros valores.

## Comprobaciones ya ejecutadas

- 50.314 comprobaciones del parser/inmutabilidad y 50.660 del transformador/perfil, con ASan/UBSan sobre buffers sinteticos.
- 2.387 comprobaciones de Huella con sistema operativo y Checker simulados.
- Parser de 19 fuentes PowerShell y XML XAML con 20 referencias de controles.
- Compilacion cruzada de Checker como PE x64 con MinGW y warnings como errores; EXE no ejecutado en Windows.
- Sintaxis MinGW de driver.c, pnp.c, storage.c, control.c, hardware.c, descriptor.c y transform.c. Esto no constituye build WDK ni enlace SYS. registry.c requiere las declaraciones del WDK moderno.

**No se ejecutaron compilacion WDK, firma, instalacion, WPF, consultas reales, cambios reales de serial/MAC, concurrencia kernel, PnP/power, Verifier, HVCI ni HLK en Windows.** No declarar el driver funcional/estable/certificado sin resultados de esas pruebas.

## Proximo trabajo local

1. Comprobar Windows x64, Git, Visual Studio 2022, MSVC v143, SDK/WDK compatibles e integracion WDK. El usuario tiene Windows y anteriormente indico que aun no habia instalado VS/WDK; consultar el estado real local antes de asumir que falta algo.
2. Compilar Debug y Release con analisis, guardar logs y corregir los primeros errores de compilacion/enlace. Usar `Compilar-Windows.cmd`, `StorageFilter.sln` y `scripts/Build.ps1`.
3. Validar INF/CAT mediante InfVerif/Inf2Cat. La firma oficial requiere el proceso y credenciales correspondientes; no inventar un SYS firmado.
4. Seleccionar y comprobar el disco secundario actual por numero, instancia PnP y hardware ID exclusivo. No asumir que el numero de ejemplo de la documentacion es el del equipo.
5. Con el paquete firmado y el dispositivo comprobado, ejecutar la suite correspondiente, preservar baseline y resultados locales y registrar cada PASS/FAIL/UNRUN con su alcance.

## Otros identificadores pendientes

SMBIOS/UUID/placa/chasis requieren un procedimiento oficial de aprovisionamiento por modelo; actualizar BIOS puede conservar los datos. GPU requiere precisar el identificador y una interfaz soportada del fabricante. RAM necesita identificar SPD frente a SMBIOS y el procedimiento del modulo. Monitores/USB, CPU, TPM e identidad de Windows tienen fuentes y mecanismos distintos. No hay una API general del filtro de almacenamiento para cambiar todos ellos en una PC fisica.

Modelos relevantes mencionados en el informe original: ASUS ROG STRIX X670E-A GAMING WIFI, GPU RTX 4060 Ti y RAM Corsair CMH32GX5M2B5200C40. El informe mostraba solamente el disco 0; no demostraba que hubiera un secundario disponible. Las paginas ASUS consultadas devolvieron HTTP 403 y no se descargaron ni validaron imagenes reales de firmware.

## Documentacion a leer

- `COMENZAR-WINDOWS.txt`: herramientas y compilacion.
- `docs/architecture.md`: arquitectura, IRQL y protocolo.
- `docs/build-sign-install.md`: validacion, firma e instalacion.
- `docs/storage-serial.md`: seleccion, activacion y pruebas del perfil.
- `docs/identifier-coverage.md`: cobertura y dependencias por identificador.
- `docs/validation.md` y `huella/validation.md`: pruebas ejecutadas y pendientes.
- `docs/testing.md` y `tests/Test-StorageSerial.ps1`: pruebas reales reproducibles.

El RAR original y el informe personal de Huella no se publicaron. No incorporar seriales reales, inventarios personales, baselines, resultados sensibles ni binarios generados a commits por accidente.

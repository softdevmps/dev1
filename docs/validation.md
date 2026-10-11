# Informe de implementación y validación

## Estado

Código y proyectos implementados; **driver no compilado con WDK, no firmado, no instalado y no ejecutado en Windows**. El entorno de esta sesión es Debian 13 x64. No dispone de Windows/WDK, hipervisor Windows ni credenciales de Microsoft Hardware Developer Program. No se declara el driver estable, cargable ni certificado.

El repositorio estaba vacío, con HEAD unborn y sin refs remotos. La implementación está versionada en commits. Publicar el código en GitHub no acredita compilación WDK, firma ni pruebas de kernel. No se han cambiado protecciones del sistema ni configuraciones de firma. El código nuevo fue autorizado como tarea de desarrollo posterior al onboarding inicial.

## Funcionalidades implementadas

| Área | Implementación | Validación pendiente en Windows |
| --- | --- | --- |
| DriverEntry / AddDevice | Dispatch table, contexto por PDO, attach y unwind de errores | Compilación WDK, adjunción real y múltiples instancias |
| IRP / pending | Copia de stack, completions, PendingReturned, remove lock por IRP | I/O verification, cancelación y completions tardías |
| PnP | START síncrono al inferior, STOP, surprise/remove, detach y liberación | Ciclos y hot-remove con carga |
| Power | PoCallDriver, flags no pageable para uso especial | Suspend/resume, reboot, hibernación si la VM lo admite |
| Storage | Observacion por defecto y sustitucion acotada del serial con perfil por instancia, sin escritura de firmware | Descriptor real, activacion, comparaciones y restauracion en secundario seleccionado |
| Ring 3 | Dispositivo seguro, snapshot v1 y IOCTL buffered de perfil con compare-and-set | ACL, entradas invalidas, generaciones concurrentes y retiro con handles abiertos |
| Hardware | BusTypeGuid y RemovalPolicy mediante IoGetDevicePropertyData | Resultados del PDO real; propiedades no soportadas diferenciadas |
| Registro | Callback documentado, altitud configurable, path canonicalizado, unregister | Obtener altitud asignada y ejecutar eventos/descarga |
| Diagnóstico | DbgPrintEx y contadores/status consultables | Captura WinDbg; ETW/WPP no implementado |
| Checker | Consultas descriptor/número/longitud, baseline, comparación, workers y entradas inválidas | Ejecutar el EXE contra disco y control reales |
| Instalación | INF Extension AddFilter, DIRID 13, scripts de selección y verificación | InfVerif, Inf2Cat, firma oficial, staging/attachment |

Se implementa la sustitucion temporal del serial de `StorageDeviceProperty` activada expresamente para un secundario. El usuario autorizo ampliar el alcance a un disco fisico secundario seleccionado. Las pruebas ejecutadas aqui usan exclusivamente datos sinteticos. No hay transformacion VPD/NVMe, acceso a memoria fisica ni escritura de sectores. La cobertura de otros identificadores se documenta en [identifier-coverage.md](identifier-coverage.md).

## Comprobaciones ejecutadas

| Comprobación | Resultado y alcance |
| --- | --- |
| `tests/run-portable.sh` | PASS, exit 0: **50.314** comprobaciones de descriptor/inmutabilidad y **50.660** de sustitucion acotada/perfiles con GCC 14.2, ASan y UBSan; ABI y offsets verificados |
| Fuzz determinista | 50.000 entradas en cada suite portable; comprueba rechazo/inmutabilidad y limites, no son pruebas de kernel |
| Límites de página | 257 prefijos de 0..256 bytes antes de PROT_NONE en cada suite; incluidos en sus totales |
| Consistencia de proyectos | PASS: ambos XML parsean, 18 referencias fuente/header existen, configuraciones Debug/Release x64 e INF coherentes |
| PowerShell | PASS: 19 archivos parseados mediante PowerShell 7.5.4 y XAML/20 referencias de controles; **no se ejecutaron sus operaciones Windows** |
| Huella sintetica | PASS: 2387 comprobaciones, incluido perfil/diario y carrera de restauracion con Checker simulado; no son pruebas de driver |
| Compilación cruzada de Checker | PASS: GCC MinGW-w64 14-posix, `-Wall -Wextra -Wconversion -Werror`, link PE32+ x64; `out/cross/Checker.exe` generado, **no ejecutado** |
| Sintaxis de módulos kernel con MinGW | PASS para driver.c, pnp.c, storage.c, control.c, hardware.c, descriptor.c y transform.c, warnings como errores y `-fsyntax-only`; **no es build WDK ni enlazado SYS** |
| MSBuild/WDK, InfVerif, Inf2Cat | UNRUN: herramientas Windows ausentes |
| Carga, consultas reales, ACL, concurrencia Windows | UNRUN: máquina Windows y paquete firmado ausentes |
| PnP/power/Verifier/HVCI/HLK | UNRUN: requieren la VM y el flujo de firma |
| Callback de registro activo | UNRUN: además necesita altitud asignada por Microsoft |

No se ejecutó una suite con cero tests para afirmar readiness. Los tests que aparecen PASS ejecutaron el código señalado y terminaron con exit 0. Los scripts de laboratorio se entregan como procedimientos; su existencia no se cuenta como resultado funcional.

## Fallos encontrados y diagnóstico

- La revisión con cabeceras MinGW inicialmente detectó `LOCALE_NEUTRAL` no declarado en el entorno kernel y ausencia de CmCallbackGetKeyObjectIDEx, CmCallbackReleaseKeyObjectIDEx y las constantes de TYPECHECK. El LCID se cambió al valor documentado neutral, 0. Los cuatro símbolos de registro pertenecen al WDK moderno y están documentados por Microsoft; las cabeceras MinGW empleadas no los exponen. **No se inventaron prototipos ni macros para fingir una compilación completa.** registry.c requiere validación con WDK; esa comprobación permanece pendiente.
- La revisión de IRQL detectó que un fast mutex convencional elevaría a APC_LEVEL durante creación/borrado/espera del control. Se usa la variante Unsafe dentro de una región crítica para conservar PASSIVE_LEVEL. La corrección es revisión de código, no prueba de Driver Verifier.
- Se añadió INITGUID antes de devpkey.h para emitir las definiciones de property keys en una sola unidad de compilación, sin depender de símbolos externos no definidos. El link final WDK sigue pendiente.
- Se canonicaliza la rama de servicio con ZwQueryKey para que el alias CurrentControlSet no impida reconocer nombres ControlSetNNN de callbacks.
- Se corrigió el paso explícito del array de argumentos a la función Run-Checker en PowerShell. El parser de PowerShell verifica sintaxis, no la semántica de los cmdlets Windows.
- La comprobacion estricta de C detecto conversiones de complementos de flags y una constante multichar dependiente del compilador. Se fijaron los casts ULONG y el valor numerico del pool tag conservando sus bytes.
- La revision del perfil detecto una carrera entre consultar y restaurar. El IOCTL exige ExpectedGeneration; Huella transmite instancia/generacion esperadas hasta Checker y el kernel. La suite sintetica comprueba rechazo de una carrera durante clear. La concurrencia real de IRP/PnP sigue pendiente.
- La herramienta PowerShell descargada publica el archivo de hashes en UTF-16; se interpretó ese formato y se verificó SHA-256 antes de extraer/ejecutar. Su primer inicio falló porque intentaba usar cache en un home de sólo lectura; se corrigieron las rutas XDG hacia /tmp. No se desactivó ninguna verificación TLS/checksum.

Los paquetes MinGW se obtuvieron desde el repositorio oficial Debian mediante metadata firmada y se extrajeron en `/tmp/sf-mingw`, sin instalación global. PowerShell se obtuvo del release oficial de Microsoft y su hash publicado se verificó. Estos toolchains auxiliares no son parte del WDK ni prueban su compatibilidad.

## Reproducción local

```sh
./tests/run-portable.sh
# Con MinGW-w64 instalado normalmente:
./scripts/build-checker-cross.sh
# En esta máquina, las dependencias se extrajeron en /tmp:
MINGW_ROOT=/tmp/sf-mingw MINGW_CC=/tmp/sf-mingw/usr/bin/x86_64-w64-mingw32-gcc-posix ./scripts/build-checker-cross.sh
```

Con PowerShell disponible, `pwsh -NoProfile -File tests/check-powershell.ps1` ejecuta sólo la validación de sintaxis. El log portable se conserva localmente en `out/validation/portable.log`; las salidas `out/` están ignoradas por Git. El EXE MinGW es auxiliar sin firma Authenticode; reconstruya Checker con MSVC para el flujo de validación Windows principal.

## Paquete para el equipo Windows del usuario

Se añadió Compilar-Windows.cmd y COMENZAR-WINDOWS.txt para compilar desde Windows sin ejecutar scripts Linux ni cambiar la política de PowerShell. Se corrigió Build.ps1 para pasar el array completo `@buildArgs` a MSBuild y seleccionar Visual Studio 2022 con herramientas C++. El archivo CMD y la compilación WDK siguen pendientes de ejecución en el equipo Windows; no se cuentan como PASS. El ZIP contiene fuentes y configuración, no un driver compilado o firmado.

## Acciones pendientes y limitaciones

1. Compilar Debug y Release con Visual Studio/SDK/WDK compatibles, ejecutar análisis estático y corregir cualquier error real que reporte ese toolchain. No se puede anticipar un build aprobado sin ejecutarlo.
2. Seleccionar una VM/disco virtual secundario para la validacion inicial, o el disco fisico secundario autorizado con `-PhysicalSecondary`, siempre ajeno a arranque/sistema y con hardware ID no compartido. El INF es una plantilla no instalable hasta renderizar ese ID; el numero de disco no se usa como identidad INF.
3. Ejecutar InfVerif/Inf2Cat con los targets exactos, obtener firma oficial de Microsoft y verificar SYS/INF/CAT. Sin esa firma no se puede cargar con las protecciones exigidas.
4. Ejecutar las fases baseline/validate con perfil desactivado; luego `Test-StorageSerial.ps1` para activacion/valor/concurrencia/restauracion. Repetir ACL, ciclos, surprise removal y power. Registrar resultados por Windows 10/11 y por configuracion HVCI.
5. Obtener la altitud oficial si se quiere activar el módulo del registro y ejecutar su prueba específica. La ausencia de altitud no impide desarrollar el resto del filtro, pero deja ese módulo sin validación funcional.
6. Ejecutar Driver Verifier, pruebas de recursos/cancelación y HLK según el producto. La simulación de escasez debe diferenciar reenvío correcto de cobertura incompleta de observación.

ETW/WPP, telemetría persistente, decodificación de otras propiedades de almacenamiento y distribución comercial quedan fuera de lo implementado. Windows 10 anterior a 1903 no está soportado por este INF declarativo. Ningún resultado confirma publicación de un entorno nuevo, restauración futura ni instalación en una máquina del usuario.

# Huella y Windows Storage Upper Filter

**Huella:** aplicacion Windows para inventario, cambio de nombre, MAC compatible, MAC virtual de laboratorio y revision de asistentes de firmware oficiales. Extrae el repositorio y abre `Abrir-Huella.cmd`. Consulta [uso y capacidades](huella/README.md), [firmware](huella/firmware.md) y [pruebas pendientes](huella/validation.md). Su interfaz y acciones reales aun necesitan validacion en Windows; los cambios fisicos de todos los seriales no estan resueltos mediante una API universal.

**Controlador StorageFilter:**

Proyecto C/WDM para Windows 10 **1903 o posterior** y Windows 11 x64. Observa `IOCTL_STORAGE_QUERY_PROPERTY` / `StorageDeviceProperty`, reenvía los IRP y ofrece un canal de diagnóstico a administradores y SYSTEM. No altera seriales, identificadores ni respuestas del disco. No realiza escrituras en sectores.

El repositorio original estaba vacío y sin commits. Se han creado el controlador, Checker, la solución Visual Studio/WDK, una plantilla INF de extensión y pruebas. **El controlador todavía no está validado en Windows ni firmado para carga.** Consulte [el informe de validación](docs/validation.md) antes de instalar.

- [Arquitectura, IRQL y protocolo](docs/architecture.md)
- [Compilación, firma Microsoft e instalación](docs/build-sign-install.md)
- [Pruebas reproducibles en VM](docs/testing.md)
- [Resultados y pendientes](docs/validation.md)

## Empezar en tu equipo Windows

Extrae el proyecto y abre `COMENZAR-WINDOWS.txt`. Con Visual Studio 2022 y WDK instalados, haz doble clic en `Compilar-Windows.cmd`: compila driver y Checker, muestra el resultado y conserva el log. El driver generado estará en `out\x64\Debug\driver\StorageFilter.sys`; requiere firma oficial antes de instalarlo.

## Archivos

| Ruta | Función |
| --- | --- |
| `driver/` | DriverEntry, AddDevice, PnP, power, IRP, control seguro, almacenamiento, hardware y registro |
| `shared/` | Protocolo de tamaño fijo y parser de descriptores sin escrituras |
| `checker/` | Aplicación C para consultas reales, baseline/comparación, concurrencia y errores |
| `StorageFilter.sln` | Proyectos x64 Debug/Release para Visual Studio 2022 y WDK |
| `package/StorageFilter.inf.in` | Extensión PnP con AddFilter superior; requiere renderizar un hardware ID de laboratorio |
| `scripts/` | Build, generación, validación e instalación de paquete firmado |
| `tests/` | Parser con sanitizers, validación estructural y fases Windows |

## Comprobaciones disponibles en Linux

```sh
./tests/run-portable.sh
```

Ejecuta el parser real compartido con el controlador: buffers truncados, offsets inválidos, falta de terminadores, tamaños extremos, 50.000 entradas deterministas y límites de páginas protegidas. Comprueba que no cambia ningún byte de entrada y valida el ABI. Las comprobaciones de XML/INF son estructurales, no equivalen a MSBuild ni InfVerif.

## Flujo Windows

En una VM Windows x64 con WDK compatible, disco virtual secundario y Secure Boot/protecciones normales activos:

```powershell
.\scripts\Build.ps1 -Configuration Debug -Analyze
.\tests\Test-Lab.ps1 -Phase Baseline -DiskNumber 1 -Checker .\out\x64\Debug\checker\Checker.exe -Baseline C:\Lab\before.bin -LabVm
.\scripts\New-LabPackage.ps1 -DiskNumber 1 -LabVm -OutputDirectory C:\Lab\Unsigned
```

Después: InfVerif/Inf2Cat, firma oficial Microsoft, instalación del paquete devuelto, reinicio PnP del disco y fase `Validate`. Las instrucciones completas están en [compilación e instalación](docs/build-sign-install.md). No se incluyen certificados de prueba, firmas falsas ni instrucciones para desactivar protecciones.

Los archivos baseline contienen el descriptor y sus identificadores del disco de laboratorio. Guárdelos localmente; Checker imprime sólo metadatos y resultados de comparación. Ninguna transformación se ejecuta sobre respuestas reales; la única modificación sintética aparece dentro del test portable.

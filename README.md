# Windows Storage Upper Filter

Proyecto C/WDM para Windows 10 **1903 o posterior** y Windows 11 x64. Observa `IOCTL_STORAGE_QUERY_PROPERTY` / `StorageDeviceProperty`, reenvía los IRP y ofrece un canal de diagnóstico a administradores y SYSTEM. No altera seriales, identificadores ni respuestas del disco. No realiza escrituras en sectores.

El repositorio original estaba vacío y sin commits. Se han creado el controlador, Checker, la solución Visual Studio/WDK, una plantilla INF de extensión y pruebas. **El controlador todavía no está validado en Windows ni firmado para carga.** Consulte [el informe de validación](docs/validation.md) antes de instalar.

- [Arquitectura, IRQL y protocolo](docs/architecture.md)
- [Compilación, firma Microsoft e instalación](docs/build-sign-install.md)
- [Pruebas reproducibles en VM](docs/testing.md)
- [Resultados y pendientes](docs/validation.md)

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

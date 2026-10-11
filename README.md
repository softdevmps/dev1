# Huella y Windows Storage Upper Filter

**Huella:** aplicacion Windows para inventario, cambio de nombre, MAC compatible, MAC virtual de laboratorio, perfil temporal de serial de un disco secundario y revision de asistentes de firmware oficiales. Extrae el repositorio y abre `Abrir-Huella.cmd`. Consulta [uso y capacidades](huella/README.md), [cobertura por identificador](docs/identifier-coverage.md) y [pruebas pendientes](huella/validation.md). Su interfaz y acciones reales aun necesitan validacion en Windows.

**Controlador StorageFilter:**

Proyecto C/WDM para Windows 10 **1903 o posterior** y Windows 11 x64. Observa `IOCTL_STORAGE_QUERY_PROPERTY` / `StorageDeviceProperty`, reenvía los IRP y ofrece un canal de control a administradores y SYSTEM. Permite activar un perfil para sustituir el serial de esa respuesta en un disco secundario seleccionado; por defecto observa. El perfil no reprograma el firmware ni escribe sectores. Los detalles de seleccion, activacion, verificacion y restauracion estan en [serial de almacenamiento](docs/storage-serial.md).

El repositorio original estaba vacío y sin commits. Se han creado el controlador, Checker, la solución Visual Studio/WDK, una plantilla INF de extensión y pruebas. **El controlador todavía no está validado en Windows ni firmado para carga.** Consulte [el informe de validación](docs/validation.md) antes de instalar.

- [Arquitectura, IRQL y protocolo](docs/architecture.md)
- [Compilación, firma Microsoft e instalación](docs/build-sign-install.md)
- [Pruebas reproducibles en VM](docs/testing.md)
- [Perfil de serial y pruebas en disco fisico secundario](docs/storage-serial.md)
- [Identificadores implementados y pendientes](docs/identifier-coverage.md)
- [Resultados y pendientes](docs/validation.md)

## Empezar en tu equipo Windows

Extrae el proyecto y abre `COMENZAR-WINDOWS.txt`. Con Visual Studio 2022 y WDK instalados, haz doble clic en `Compilar-Windows.cmd`: compila driver y Checker, muestra el resultado y conserva el log. El driver generado estará en `out\x64\Debug\driver\StorageFilter.sys`; requiere firma oficial antes de instalarlo.

## Archivos

| Ruta | Función |
| --- | --- |
| `driver/` | DriverEntry, AddDevice, PnP, power, IRP, control seguro, almacenamiento, hardware y registro |
| `shared/` | Protocolo de tamaño fijo, parser y sustitucion acotada del serial |
| `checker/` | Aplicación C para consultas reales, baseline/comparación, concurrencia y errores |
| `StorageFilter.sln` | Proyectos x64 Debug/Release para Visual Studio 2022 y WDK |
| `package/StorageFilter.inf.in` | Extensión PnP con AddFilter superior; requiere renderizar un hardware ID exclusivo del secundario |
| `scripts/` | Build, generación, validación e instalación de paquete firmado |
| `tests/` | Parser con sanitizers, validación estructural y fases Windows |

## Comprobaciones disponibles en Linux

```sh
./tests/run-portable.sh
```

Ejecuta el parser y la sustitucion real compartidos con el controlador sobre buffers sinteticos: truncacion, offsets, terminadores, solapamientos, fuzz determinista y paginas protegidas. Comprueba la inmutabilidad del parser, el borrado del serial anterior, la conservacion de bytes ajenos y el ABI. Las comprobaciones de XML/INF son estructurales, no equivalen a MSBuild ni InfVerif.

## Flujo Windows

En una VM Windows x64 con WDK compatible, disco virtual secundario y Secure Boot/protecciones normales activos:

```powershell
.\scripts\Build.ps1 -Configuration Debug -Analyze
.\tests\Test-Lab.ps1 -Phase Baseline -DiskNumber 1 -Checker .\out\x64\Debug\checker\Checker.exe -Baseline C:\Lab\before.bin -LabVm
.\scripts\New-LabPackage.ps1 -DiskNumber 1 -LabVm -OutputDirectory C:\Lab\Unsigned
```

Después: InfVerif/Inf2Cat, firma oficial Microsoft, instalación del paquete devuelto, reinicio PnP del disco y fase `Validate`. Las instrucciones completas están en [compilación e instalación](docs/build-sign-install.md). No se incluyen certificados de prueba, firmas falsas ni instrucciones para desactivar protecciones.

Los archivos baseline contienen el descriptor y sus identificadores. Guárdelos localmente; Checker imprime sólo metadatos y resultados de comparación. El flujo anterior prueba observacion con perfil desactivado. La ampliacion autorizada a un disco fisico secundario usa `-PhysicalSecondary`; consulte el procedimiento y las limitaciones en [storage-serial.md](docs/storage-serial.md). WDK, firma oficial y pruebas reales siguen pendientes.

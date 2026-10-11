# Compilación, firma e instalación

## Requisitos y límites

El driver se dirige a Windows 10 **1903+** / Windows 11 x64 por el mecanismo INF AddFilter. Versiones anteriores de Windows 10 quedan fuera del objetivo de esta implementación. No se sustituye AddFilter por edición global de la clase DiskDrive.

Prepare una máquina Windows de compilación con Visual Studio 2022, workload C++ para escritorio, herramientas MSVC v143 x64 (incluidas las bibliotecas Spectre si la integración WDK las requiere), SDK y WDK de **versiones compatibles**, más la extensión WDK de Visual Studio según la versión instalada. Consulte la tabla oficial; no mezcle arbitrariamente las versiones SDK/WDK. El entorno Linux actual no contiene MSBuild/WDK y no puede compilar, ejecutar ni firmar un .sys mediante WDK.

Mantenga una VM Windows aislada con un checkpoint, Secure Boot, Code Integrity, DSE y Memory Integrity/HVCI en la configuración normal. Use un disco virtual secundario prescindible, sin paginación, hibernación, volcados, volúmenes del sistema ni datos que conservar. La selección debe ser un hardware ID distinto del disco de arranque y de cualquier otro disco presente. Si el hipervisor asigna el mismo ID a todos los discos, el generador lo rechaza: cambie el controlador virtual/tipo de disco en el laboratorio o use una configuración virtual que publique un ID distinguible.

## Build con errores visibles

En PowerShell desde el checkout:

```powershell
.\scripts\Build.ps1 -Configuration Debug -Analyze 2>&1 | Tee-Object C:\Lab\build-debug.log
.\scripts\Build.ps1 -Configuration Release -Analyze 2>&1 | Tee-Object C:\Lab\build-release.log
```

Build.ps1 conserva el fallo de MSBuild como excepción aunque capture el log. Abre `StorageFilter.sln` para inspeccionar errores desde Visual Studio. Salidas: `out\x64\<config>\driver\StorageFilter.sys` y `checker\Checker.exe`, con PDB del driver en su directorio de salida. Los warnings se tratan como errores; sólo se suprime 4996 en el kernel para ExAllocatePoolWithTag, usado con NonPagedPoolNx para permitir Windows 10 1903. El API es documentado pero deprecado en WDK reciente; no se usa pool ejecutable ni se desactiva NX.

Errores que requieren diagnóstico:

| Resultado | Acción |
| --- | --- |
| MSB8020, toolset WindowsKernelModeDriver10.0 ausente | Instalar/reparar WDK y su integración VS, luego repetir |
| Cabeceras o libs de kernel ausentes | Verificar versiones SDK/WDK e instalación x64 |
| Bibliotecas Spectre ausentes | Instalar el componente MSVC requerido por el WDK |
| Error C/LNK o análisis estático | Conservar archivo/línea y log completo; corregir la causa antes de empaquetar |
| InfVerif/Inf2Cat no cero | No firmar ni instalar; revisar sección/destino/fecha/OS objetivo reportado |
| Code Integrity rechaza .sys | Confirmar firma devuelta por Microsoft, política y eventos; no desactivar protecciones |

La validación portable de XML sólo verifica que el proyecto es parseable y apunta a archivos existentes; no elimina la necesidad de estas compilaciones.

## Baseline y generación INF

Antes de cargar el driver, desde PowerShell elevado en la VM:

```powershell
New-Item -ItemType Directory C:\Lab -ErrorAction SilentlyContinue
.\tests\Test-Lab.ps1 -Phase Baseline -DiskNumber 1 -Checker .\out\x64\Debug\checker\Checker.exe -Baseline C:\Lab\before.bin -LabVm
.\scripts\New-LabPackage.ps1 -DiskNumber 1 -LabVm -Configuration Debug -OutputDirectory C:\Lab\Unsigned
```

El número 1 es un ejemplo; verifique `Get-Disk` y `Win32_DiskDrive` antes de seleccionarlo. `-LabVm` es su declaración de que se trata de una VM de laboratorio: el script no puede demostrar por sí mismo que todo hardware virtual sea descartable.

El generador rechaza discos boot/system, mapeos ambiguos e IDs compartidos entre discos presentes. Renderiza el hardware ID principal dentro de `StorageFilter.inf`, ajusta DriverVer a la fecha local, copia el .sys y guarda `lab-target.json` para las verificaciones de instalación. No modifica la plantilla ni el código. El INF sólo declara una extensión de dispositivo y un filtro superior de servicio demand-start; no reemplaza disk.sys ni escribe UpperFilters de clase. El binario se ejecuta desde Driver Store (DIRID 13).

Un hardware ID no es un instance ID: un disco conectado más tarde con el mismo ID también puede recibir la extensión. Mantenga el paquete limitado a la VM y vuelva a comprobar IDs antes de cada instalación. No copie este paquete a una máquina de producción. Para distribuir el producto, defina con el fabricante los IDs reales autorizados y la política de orden de filtros.

## Validación del paquete

Obtenga los paths exactos de InfVerif.exe, Inf2Cat.exe y SignTool.exe del WDK/SDK instalado. Consulte `Inf2Cat /?` para los nombres de OSTargets que esa versión admite; Windows 10/11 se subdividen por builds y no deben adivinarse.

```powershell
.\scripts\Validate-Package.ps1 -PackageDirectory C:\Lab\Unsigned -InfVerif 'C:\ruta\InfVerif.exe' -Inf2Cat 'C:\ruta\Inf2Cat.exe' -OsTargets '<lista exacta para los builds x64 elegidos>'
```

InfVerif `/w` valida requisitos de Windows Driver. Inf2Cat genera el catálogo y valida la capacidad de firma para los OS seleccionados. No firma el catálogo ni acredita que el driver funciona. Cambiar INF o SYS después de generar/firmar invalida el catálogo: repita generación y firma.

## Firma oficial con protecciones activas

Para cargar en Windows moderno con Secure Boot use el flujo oficial de Microsoft Hardware Developer Program / Partner Center. Necesita una cuenta autorizada y cumplir los requisitos actuales de certificados/identidad y envío. Para el ámbito que Microsoft permita, use attestation signing; para distribución y certificación use HLK/WHCP y los requisitos de publicación correspondientes. La elegibilidad de attestation para pruebas no implica elegibilidad para retail o Windows Update.

1. Compile, analice y valide el paquete sin alterar sus artefactos después.
2. Prepare el CAB y los metadatos exigidos por la modalidad de envío elegida; firme la **presentación** con el certificado empresarial que Microsoft requiera. Esa firma de presentación no convierte el .sys en un driver cargable.
3. Envíe por Partner Center y descargue el paquete firmado por Microsoft.
4. Preserve el `lab-target.json` local correspondiente sin modificar INF/SYS/CAT devueltos. Si el servicio devuelve varios directorios, identifique el paquete x64 de esta extensión.
5. Verifique `signtool verify /kp /v StorageFilter.sys` y la pertenencia de SYS e INF al catálogo con `/kp /c StorageFilter.cat`.
6. Si cualquier verificación falla, investigue la firma/política/eventos de Code Integrity. No use test signing, no desactive DSE ni Secure Boot, no añada un certificado autofirmado como sustituto de la firma requerida.

La firma de catálogo/kernel y la compatibilidad HVCI son verificaciones distintas. Los buffers de pool son NX, pero sólo la prueba de carga con HVCI y sus validadores confirma compatibilidad completa. No hay binario firmado ni credencial de Partner Center en este repositorio.

## Instalación y retirada

Ejecute elevado después de recibir el paquete firmado:

```powershell
.\scripts\Install-Lab.ps1 -SignedPackageDirectory C:\Lab\Signed -SignTool 'C:\ruta\signtool.exe' -LabVm
```

El script repite la selección del disco y la unicidad de ID, verifica que el INF coincide con el target, comprueba firmas de kernel y pertenencia de ambos archivos al catálogo y ejecuta PnPUtil `/add-driver ... /install`. Confirme que la extensión se aplicó: staging del Driver Store no prueba adjunción. Reboot de la VM es la opción común; `/restart-device <instance-id>` está disponible desde Windows 10 2004. Verifique el estado de Device Manager/PnP, el log `%windir%\inf\setupapi.dev.log` y `Checker snapshot`.

Identifique el **oemNN.inf de esta extensión** mediante `pnputil /enum-drivers`, proveedor, nombre original y versión. Para retirarla:

```powershell
pnputil /delete-driver oemNN.inf /uninstall
```

Sustituya oemNN.inf por el publicado exacto. Respete la solicitud de reinicio y confirme que el canal desaparece cuando se retira la última instancia. No borre manualmente SYS/CAT en Driver Store, no elimine filtros de terceros ni use `/force` por defecto. En caso de bugcheck o fallo de arranque, recupere el checkpoint de la VM; conserve el dump, PDB y paquete utilizados.

## Referencias oficiales

- [Descarga e instalación WDK y compatibilidad SDK/VS](https://learn.microsoft.com/windows-hardware/drivers/download-the-wdk)
- [DDInstall.Filters y AddFilter](https://learn.microsoft.com/windows-hardware/drivers/install/inf-ddinstall-filters-section)
- [AddFilter](https://learn.microsoft.com/windows-hardware/drivers/install/inf-addfilter-directive)
- [Extension INF](https://learn.microsoft.com/windows-hardware/drivers/install/using-an-extension-inf-file)
- [Firma de código kernel](https://learn.microsoft.com/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)
- [Attestation signing](https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-attestation)
- [InfVerif](https://learn.microsoft.com/windows-hardware/drivers/devtest/infverif)
- [Inf2Cat](https://learn.microsoft.com/windows-hardware/drivers/devtest/inf2cat)
- [PnPUtil](https://learn.microsoft.com/windows-hardware/drivers/devtest/pnputil-command-syntax)

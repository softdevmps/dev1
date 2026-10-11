# Modulo de serial de almacenamiento

Implementa sustitucion temporal de `STORAGE_DEVICE_DESCRIPTOR.SerialNumberOffset` en la respuesta de `IOCTL_STORAGE_QUERY_PROPERTY`, `StorageDeviceProperty`, `PropertyStandardQuery`. El usuario autorizo ampliar las pruebas a **un disco fisico secundario seleccionado**. El filtro permanece en observacion hasta activar expresamente un perfil para una instancia y numero de disco determinados.

No reprograma el serial del firmware, GUID GPT, firma MBR, serial de volumen ni identificadores SCSI VPD/NVMe. Esas rutas pueden seguir exponiendo otros valores. CIM/WMI y aplicaciones que conservaron resultados pueden seguir mostrando el valor anterior. El modulo es una implementacion acotada, no una afirmacion de cobertura completa de todos los identificadores del equipo.

## Seleccion y activacion

1. Instala Visual Studio 2022, SDK/WDK compatibles y compila con `Compilar-Windows.cmd`. Sigue `build-sign-install.md` para analisis, InfVerif/Inf2Cat y firma oficial Microsoft. El codigo fuente no equivale a un SYS cargable ni firmado.
2. Selecciona un disco secundario de pruebas, fuera de arranque/sistema y con hardware ID no compartido por otros discos presentes. `New-LabPackage.ps1 -PhysicalSecondary` conserva esas comprobaciones. El INF de extension AddFilter es por hardware ID, no por numero de disco ni por clase completa. Si el hardware ID es compartido, el script rechaza el paquete.
3. Genera el paquete, obtiene la firma oficial y verifica/instala el paquete devuelto mediante `Install-Lab.ps1 -PhysicalSecondary`. Mantiene Secure Boot, DSE y otras protecciones normales.
4. Consulta numero e instancia PnP actuales. El driver aprende el numero mediante una completion documentada de `IOCTL_STORAGE_GET_DEVICE_NUMBER`; Checker verifica el mapeo antes de configurar el perfil.
5. Activa desde Huella en la fila `SerialNumber` del disco, o mediante `Set-StorageSerial.ps1`. La interfaz habilita la accion solo si Checker y el filtro responden para ese disco y el campo tiene capacidad suficiente. Si Windows conserva un valor CIM en cache, usa Checker para evaluar la consulta directa.

```powershell
$diskNumber = 2 # Sustituir por el secundario elegido, nunca copiar sin comprobar.
$disk = Get-Disk -Number $diskNumber
if ($disk.IsBoot -or $disk.IsSystem) { throw 'Disco protegido' }
$device = @(Get-CimInstance Win32_DiskDrive | Where-Object Index -eq $diskNumber)
if ($device.Count -ne 1) { throw 'Mapeo ambiguo' }
$pnpId = $device[0].PNPDeviceID

.\scripts\New-LabPackage.ps1 -DiskNumber $diskNumber -PhysicalSecondary -OutputDirectory C:\Lab\Unsigned-Secondary
# Continuar con la validacion/firma oficial antes de instalar.
.\scripts\Install-Lab.ps1 -PhysicalSecondary -SignedPackageDirectory C:\Lab\MicrosoftSigned -SignTool 'RUTA_REAL_A_SIGNTOOL.exe'

.\scripts\Set-StorageSerial.ps1 -Action Status -DiskNumber $diskNumber -PnpInstanceId $pnpId
.\scripts\Set-StorageSerial.ps1 -Action Set -DiskNumber $diskNumber -PnpInstanceId $pnpId -Serial 'LAB-0001' -PhysicalSecondary
.\scripts\Set-StorageSerial.ps1 -Action Clear -DiskNumber $diskNumber -PnpInstanceId $pnpId
```

La activacion solicita confirmacion. Los nombres de carpetas y SignTool son ejemplos, no archivos entregados. Huella registra el perfil en `%LOCALAPPDATA%\Huella`; contiene el valor nuevo y el objetivo seleccionado, nunca una copia del firmware. El estado `CheckerVerified` acredita la consulta directa cubierta. `Restaurar respaldo` desactiva la misma generacion del perfil; evita borrar uno posterior que otra instancia haya cambiado.

## Limites y vida del perfil

El serial nuevo admite de 1 a 31 caracteres ASCII `A-Z`, `a-z`, `0-9`, `_` o `-`, y debe caber en la longitud existente del campo original. No se amplia el descriptor ni se cambia `IoStatus.Status`, `IoStatus.Information`, `Size` u offsets. Antes de escribir se validan el descriptor completo, terminadores y solapamientos con vendor/product/revision/raw properties. Se borra el resto del serial anterior dentro de su campo; todos los bytes externos permanecen intactos. Los campos originales de mas de 255 caracteres se rechazan para mantener corta la seccion bajo spin lock.

El IOCTL de activacion requiere lectura/escritura sobre el control, cuyo ACL admite SYSTEM y administradores. Compara instancia, numero y generacion antes de aplicar. Cada IRP conserva una copia del perfil y su generacion; una completion comprueba que siga vigente bajo el mismo spin lock usado al desactivar. El borrado acotado y la sustitucion ocurren bajo ese lock, de modo que una completion pendiente con un perfil antiguo no lo reaplica despues de la desactivacion.

STOP, nuevo START, surprise removal o uso especial del dispositivo desactivan el perfil. Paging/hibernacion/dump y otros `DEVICE_USAGE_NOTIFICATION` con `InPath` restringen la instancia hasta retirarla. La memoria se libera solo tras drenar remove locks. Un reinicio de Windows o retirada del dispositivo pierde el perfil: **no hay reactivacion automatica al arrancar**.

El kernel aplica las restricciones de instancia/numero/uso especial. La exclusion de arranque/sistema se comprueba ademas en scripts con `Get-Disk` y en Checker con el volumen de Windows y particiones EFI/MBR activas. El bit `ACK_SECONDARY` es una confirmacion de alcance, no una comprobacion criptografica de que un disco no sea de arranque; no debe sustituirse el flujo seleccionado por llamadas IOCTL arbitrarias.

## Comandos Checker

```text
Checker serial-status <disco-secundario>
Checker serial-set <disco-secundario> <serial-ASCII> --secondary
Checker serial-clear <disco-secundario>
Checker serial-expect <disco-secundario> <serial-ASCII>
Checker serial-test <disco-secundario> <serial-ASCII> --secondary
Checker serial-negative
```

`serial-set` y `serial-test` requieren perfil inicialmente desactivado. `serial-test` guarda la baseline en memoria, activa, envia al kernel un clear con generacion obsoleta y exige ERROR_REVISION_MISMATCH, verifica 64 consultas y contadores, desactiva mediante compare-and-set y compara los cuatro strings y propiedades estables con la baseline original. En error intenta desactivar solo su propia generacion; un perfil cambiado concurrentemente no se borra. `serial-expect` verifica el serial de una respuesta nueva, con estado de perfil consultado antes y despues; no activa ni desactiva. `serial-negative` prueba entradas/version incorrectas y rechazo de escritura mediante handle de solo lectura. No imprime seriales originales.

Los comandos set/test/clear/expect aceptan `--generation <n>` y, a continuacion, `--instance <n>` para exigir el perfil esperado. Huella utiliza ambos para que una retirada o cambio concurrente no redirija la operacion a un perfil posterior. Una restauracion desde diario no cruza generaciones; la desactivacion expresa sin esas opciones retira el perfil actualmente seleccionado.

Para una sola instancia adjunta y un secundario de pruebas:

```powershell
.\tests\Test-StorageSerial.ps1 -DiskNumber $diskNumber -PnpInstanceId $pnpId -PhysicalSecondary -Serial 'LAB-0001' -ResultDirectory C:\Lab\Serial-Test-01
```

La suite incluye baseline local, pruebas negativas, ciclo de 64 consultas, 4 workers con 200 iteraciones, contadores de transformacion, restauracion y comparacion final. `finally` intenta restaurar su perfil confirmado y escribe `result.json`. Si falla, revisa el diario y `serial-status` antes de una desactivacion expresa. `before.bin` contiene identificadores reales: guardalo localmente. Las pruebas PnP/power/Verifier existentes deben repetirse con este cambio; ninguna se ha ejecutado todavia en Windows.

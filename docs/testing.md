# Pruebas reproducibles

Ninguna prueba aquí documentada constituye un resultado hasta que se ejecute y se guarde su evidencia. Los resultados ya ejecutados están en validation.md.

Esta suite comprueba observacion con perfil de serial desactivado. Para la sustitucion temporal autorizada en un secundario fisico, use [storage-serial.md](storage-serial.md) y `Test-StorageSerial.ps1`. Complete tambien los casos PnP/power/Verifier siguientes con el codigo nuevo; la prueba de serial no los sustituye.

## Preparación de VM

1. VM Windows 10 1903+ o Windows 11 x64, checkpoint antes de instalar, Secure Boot y protecciones normales activas. Para el script de ciclos PnP use Windows 10 2004+.
2. Disco de arranque separado y disco virtual secundario prescindible con hardware ID distinguible. No seleccione un volumen de sistema, pagefile, hibernación ni crash dump. Desmonte aplicaciones que usen el disco secundario.
3. Anote build Windows, SDK/WDK/MSVC, configuración HVCI, hipervisor, controlador virtual, versión/commit, hash de SYS/CAT y PDB. Configure depuración/dumps por mecanismos soportados sin reducir Code Integrity.
4. Compile ambas configuraciones, guarde logs y confirme cero errores. Ejecute InfVerif, Inf2Cat y firma oficial. Copie Checker y scripts a la VM; el binario cruzado no sustituye el build WDK/MSVC.
5. Ejecute Baseline **antes de cargar el filtro**, instale el paquete firmado y reinicie la instancia/VM. El archivo baseline se crea con CREATE_NEW; nunca se sobrescribe.

## Suite funcional automática

```powershell
.\tests\Test-Lab.ps1 -Phase Validate -DiskNumber 1 -Checker C:\Lab\Checker.exe -Baseline C:\Lab\before.bin -LabVm -Threads 8 -Iterations 1000
```

Debe completar:

- Snapshot v1 válido del control con tamaños/límites correctos.
- Comparación de vendor, product, revision, serial, BusType y Removable con baseline del mismo PnP instance. No imprime los valores.
- 8 workers con handles independientes, cada uno realiza 1000 consultas de header + descriptor y compara identificadores. Requiere una única instancia STARTED, al menos 16.000 nuevas completions observadas, sin nueva corrupción, query failures ni observaciones perdidas.
- Consultas del disco con entrada/salida demasiado pequeñas: se espera error del driver inferior, sin imponer un código arbitrario.
- Control: salida de 1567 bytes -> ERROR_INSUFFICIENT_BUFFER; entrada no vacía -> ERROR_INVALID_PARAMETER; IOCTL desconocido -> ERROR_INVALID_FUNCTION.
- Comparación final y snapshot de diagnóstico.

La suite devuelve error/excepción si una operación falla; no trata como éxito un canal ausente, cero instancias ni respuestas malformadas. Los snapshots pueden incluir la última respuesta del test negativo; LastQueryStatus/Flags no tienen que mostrar el resultado del stress anterior. Otros procesos que consulten el disco pueden incrementar contadores; nuevos fallos ajenos también hacen fallar el stress para no ocultar problemas.

## ACL de Ring 3

Con el filtro STARTED, abra una consola **de usuario estándar no administrador** y ejecute:

```powershell
C:\Lab\Checker.exe access-denied
```

Sólo ERROR_ACCESS_DENIED se acepta. ERROR_FILE_NOT_FOUND no valida la ACL. El mismo `snapshot` debe funcionar en consola elevada. No pruebe únicamente con un administrador con UAC si pretende demostrar exclusión de un usuario estándar.

## Reinicio PnP secuencial

```powershell
.\tests\Cycle-LabDevice.ps1 -DiskNumber 1 -Checker C:\Lab\Checker.exe -Baseline C:\Lab\before.bin -LabVm -Cycles 20
```

Cada ciclo solicita restart al PnP manager, espera de forma acotada una consulta real con aumento de contador y compara identificadores. Debe concluir sin bugcheck, objetos huérfanos ni control duplicado. Reiniciar el único dispositivo prueba la retirada/recreación del canal. El script no prueba por sí solo surprise removal ni carreras de cancelación.

## Surprise removal / carrera con I/O

En checkpoint independiente:

1. Inicie `Checker stress 1 16 100000` y capture su salida/exit.
2. Desde el hipervisor, desconecte **sólo el disco secundario** mediante hot-remove soportado, manteniendo vivo el sistema. No emule desconexión del disco de arranque.
3. Es esperado que las consultas pendientes fallen con códigos de retirada y que este stress termine FAIL; no contabilice esa ejecución como stress pasado. Se exige ausencia de bugcheck/deadlock y retirada completa del filtro/control. Use WinDbg/Verifier para confirmar que las completions terminaron antes de liberar extensión.
4. Reconecte el mismo disco, espere START, haga una nueva baseline sólo si cambió legítimamente el disco/instance y ejecute la suite normal nuevamente. Documente el cambio; no sustituya automáticamente una baseline para ocultar diferencias.
5. Repita con un handle de control abierto durante la desconexión: IOCTL posteriores deben fallar y CLOSE/CLEANUP deben concluir; nuevos handles deben abrir la nueva instancia.

Checker usa I/O síncrono, no fabrica IRP pendientes ni garantiza que cada ejecución ejercite cancelación. Pruebe cancelación y completions tardías con cargas/infraestructura de almacenamiento virtual que produzcan pending de forma controlada y documente el procedimiento adicional. No se incluye un mock que suplante las garantías del kernel.

## Power y estabilidad

- Suspend/resume soportado por la VM y reboot: consultar antes/después, conservar IDs y verificar que el filtro sigue atendiendo. Si el hipervisor no permite suspensión, marque SKIPPED por capacidad, no PASS.
- Probar apagado y retirada con consultas concurrentes.
- Driver Verifier **sólo para StorageFilter.sys** en la VM: `verifier /standard /driver StorageFilter.sys`, reinicie y repita suite/ciclos/hot-remove. Guarde `verifier /querysettings`, dumps y resultados. Nunca seleccione todos los drivers del equipo por comodidad.
- Añada de manera explícita las opciones de verificación compatibles con HVCI, I/O verification, IRQL, deadlock detection y low-resource simulation según el Verifier de ese OS. En simulación de falta de memoria, ObservationsSkipped puede aumentar: la prueba de cobertura falla correctamente; compruebe por separado que el IRP se reenvió y no hubo corrupción.
- Concluida la prueba, `verifier /reset` y reinicie. Esto retira instrumentación de prueba; no desactiva las protecciones de firma ni Secure Boot.
- Ejecute las pruebas de compatibilidad Code Integrity/HVCI y almacenamiento del HLK apropiadas al producto y al OS objetivo. No se reclama certificación con pruebas manuales.

Recoger al menos una corrida de concurrencia prolongada (p. ej. 32 workers × 100.000 iteraciones), ciclos PnP y las pruebas power/retirada en Windows 10 y 11. Registre duración y configuración de VM. Un proceso vivo, puerto abierto o INF instalado no demuestra estabilidad.

## Registro opcional

Requiere altitud asignada por Microsoft y la firma/carga ya válidas. Configure `HKLM\SYSTEM\CurrentControlSet\Services\StorageFilter\Parameters\RegistryAltitude` como REG_SZ con su asignación y reinicie el driver por PnP/reboot. No use números encontrados en ejemplos de otros drivers.

Confirme RegistryCallbackStatus == STATUS_SUCCESS. Tome snapshot; cree/cambie/elimine un valor **de prueba** dentro de Parameters, tome otro snapshot y confirme incremento. Repita operaciones fuera de la rama y confirme que no incrementan si no hay otra actividad interna. No modifique configuración esencial del driver. Pruebe retirada/descarga mientras se ejecutan cambios de valores de prueba; unregister debe concluir antes de liberar el contexto. En ausencia de altitud, marque este módulo SKIPPED/configuración pendiente, no PASS.

## Parser local

`tests/run-portable.sh` usa el mismo parser que el controlador con ASan/UBSan, límites de página PROT_NONE, casos deterministas y fuzz seed 0x12345678. También comprueba que no se escriben entradas y el ABI x64. No simula PnP, IRQL, firmas, acceso de kernel ni los tiempos del dispositivo.

La segunda suite usa el transformador compartido y seed 0x1D3A51: valida ASCII/perfil, descriptor completo, capacidad, solapamientos, borrado del serial anterior, conservacion de bytes externos y ausencia de escrituras en errores. Ambas suites se ejecutan sobre buffers sinteticos.

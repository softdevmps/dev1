# Arquitectura técnica

## Instancias y publicación

`DriverEntry` configura todos los MajorFunction y el callback opcional del registro. `AddDevice` crea un objeto sin nombre por PDO, inicializa `IO_REMOVE_LOCK`, adjunta el filtro mediante `IoAttachDeviceToDeviceStack` y hereda DeviceType, Characteristics y flags de buffering/power del objeto inferior. Un error de creación, adjunción o publicación deshace lo realizado y devuelve el NTSTATUS.

Cada extensión `SF_FILTER` conserva su PDO, objeto inferior, instancia numérica y registro de diagnóstico. No hay estado de identidad compartido entre discos. El identificador Instance es efímero y no identifica el hardware; cambia tras una nueva adjunción.

Una lista global protegida por spin lock permite copiar un snapshot acotado de hasta 16 instancias sin retener punteros después de soltar el lock. DeviceCount indica el total; RecordsReturned indica la parte devuelta. El canal de control se crea al publicar la primera instancia y se retira con la última; no deja un objeto nombrado que impida retirar el driver PnP. Handles viejos reciben DELETE_PENDING para nuevos IOCTL y pueden ejecutar CLOSE/CLEANUP.

La publicación y retirada del objeto de control usan `KeEnterCriticalRegion` + `ExAcquireFastMutexUnsafe`: deshabilitan APC normales, **conservan PASSIVE_LEVEL** y serializan AddDevice/RemoveDevice. No se mantienen spin locks durante llamadas de creación, propiedades o espera. Las solicitudes de control no toman ese mutex, evitando un ciclo con su remove lock.

## Reenvío, pending y retirada

Cada IRP del filtro adquiere el remove lock antes de usar la extensión. El reenvío copia la stack location y registra una completion para éxito, error y cancelación. La completion propaga PendingReturned con IoMarkIrpPending, suelta el lock y devuelve STATUS_CONTINUE_COMPLETION. No se crean colas privadas ni se instala una cancel routine: el driver inferior conserva la gestión de cancelación de sus solicitudes.

El lock cubre toda la vida del IRP inferior, incluso cuando IoCallDriver devuelve STATUS_PENDING. Las completions no son pageable y no adquieren mutexes, no esperan y no consultan propiedades. La inspección se limita a 64 KiB, sin asignación de memoria dentro de la completion. El contexto se asigna previamente en NonPagedPoolNx; si falla, se contabiliza ObservationsSkipped y se reenvía sin inspección. Ese resultado debe fallar la prueba de cobertura de stress.

`IRP_MN_START_DEVICE` se envía primero al inferior con una completion que señala un evento y devuelve MORE_PROCESSING_REQUIRED. Si queda pending, el dispatch espera en PASSIVE_LEVEL. Después inspecciona IoStatus.Status, obtiene propiedades, registra STARTED sólo en éxito y completa el IRP. La completion que detiene el IRP no marca pending: el dispatch conserva la propiedad del IRP y devuelve el resultado final.

QUERY_STOP, CANCEL_STOP, QUERY_REMOVE y CANCEL_REMOVE se reenvían sin vetar decisiones PnP; este filtro no tiene recursos de hardware que negociar. STOP limpia el estado STARTED. SURPRISE_REMOVAL marca el estado, pero conserva objetos y memoria hasta REMOVE. Las solicitudes posteriores se reenvían al inferior mientras el remove lock siga admitiéndolas; no se inventa éxito tras desconexión.

REMOVE retira la instancia de la lista; si era la última, elimina el enlace de control y espera sus solicitudes. A continuación `IoReleaseRemoveLockAndWait` bloquea nuevas adquisiciones del filtro y espera las completions existentes. Sólo entonces reenvía REMOVE, desacopla y llama IoDeleteDevice. No toca la extensión tras la eliminación. No retiene una completion del REMOVE sobre memoria eliminada.

Power usa PoCallDriver y la misma política de completions/locks. Windows 10/11 no requiere PoStartNextPowerIrp. DEVICE_USAGE_NOTIFICATION hace al filtro conservadoramente no pageable; todo el dispatch/completion está en memoria no pageable y no se vuelve a activar DO_POWER_PAGABLE tras ese aviso. No gestiona energía de hardware ni registra un power policy owner.

## Consultas de almacenamiento

Sólo se interpreta la consulta estándar StorageDeviceProperty del IOCTL METHOD_BUFFERED. El filtro comprueba longitud mínima hasta AdditionalParameters y SystemBuffer antes de leer PropertyId/QueryType. Los demás IOCTL, propiedades, tipos de consulta y entradas incompletas se reenvían intactos para que el inferior decida su resultado.

La completion no cambia IoStatus.Status, IoStatus.Information ni SystemBuffer. El límite leído es `min(IoStatus.Information, OutputBufferLength, 65536)`; nunca se interpreta un buffer de error como descriptor válido. El parser usa lecturas byte a byte para aceptar datos no alineados y comprueba Version, Size, offsets de strings, terminadores y longitud de RawDeviceProperties. Las solicitudes de sólo 8 bytes reciben HEADER_ONLY/TRUNCATED sin contarse como malformadas. Truncación no equivale a corrupción.

Los strings no se copian a la extensión y no se imprimen. Se conserva únicamente presencia de vendor/product/revision/serial, BusType, Removable, flags de validación, NTSTATUS y contadores. `QueriesCompleted` cuenta observaciones con contexto, no todo el tráfico del dispositivo; dos consultas de Checker (header y descriptor) producen normalmente dos completions. No se observan identidades SCSI VPD/NVMe ni comandos de protocolo directo.

El parser portable y el kernel utilizan el mismo código. El test transforma un carácter de un serial **sintético**, fuera del driver. No hay una ruta de transformación en producción.

## Hardware y registro

Tras START satisfactorio, IoGetDevicePropertyData consulta DEVPKEY_Device_BusTypeGuid y DEVPKEY_Device_RemovalPolicy del PDO. Valida NTSTATUS, DEVPROPTYPE y longitud devuelta; propiedades no soportadas se exponen como fallos independientes y no impiden el inicio del filtro. Estos datos no se utilizan para falsificar IDs ni para realizar accesos físicos.

El callback es opcional y está inactivo sin `Parameters\RegistryAltitude` REG_SZ. Debe contener una altitud asignada por Microsoft al propietario del driver; no se distribuye una altitud inventada. DriverEntry valida tipo y tamaño mediante RtlQueryRegistryValues/TYPECHECK y registra con CmRegisterCallbackEx. El estado de registro, incluido el error por falta de configuración, está en el snapshot.

El path del servicio se canonicaliza con ZwOpenKey/ZwQueryKey (KeyNameInformation) antes de registrar el callback, para resolver CurrentControlSet frente a ControlSetNNN. Los handles son OBJ_KERNEL_HANDLE y los tamaños se validan antes de copiar.

El callback observa PRE_SET_VALUE, PRE_DELETE_VALUE, PRE_DELETE_KEY y PRE_RENAME_KEY sólo dentro de la rama de servicio que Windows proporcionó a DriverEntry. Obtiene nombres mediante CmCallbackGetKeyObjectIDEx, los libera con CmCallbackReleaseKeyObjectIDEx, comprueba el límite del prefijo y sólo incrementa un contador. No lee datos de valores, no modifica parámetros, no bloquea operaciones y no hace I/O recursivo al registro. CmUnRegisterCallback se ejecuta en unload antes de liberar el path; se registra su NTSTATUS.

## Ring 3 y seguridad

`\\.\StorageFilterCtl` es un dispositivo independiente, sin acceso arbitrario al disco, memoria, registro o comandos kernel. IoCreateDeviceSecure con SDDL_DEVOBJ_SYS_ALL_ADM_ALL limita la apertura a SYSTEM y administradores. FILE_DEVICE_SECURE_OPEN cubre aperturas relativas; nombres no vacíos se rechazan.

SF_IOCTL_SNAPSHOT usa un DeviceType privado 0x8337, Function 0x800, METHOD_BUFFERED y FILE_READ_DATA. Exige InputBufferLength == 0 y salida de al menos 1568 bytes. Otros IOCTL se rechazan; las salidas se inicializan a cero, incluidos huecos de padding. El protocolo v1 está en shared/protocol.h y contiene enteros de ancho fijo sin punteros. Compile-time assertions verifican los tamaños en kernel y Checker. El test también verifica offsets y layout.

Los handles de disco de Checker se abren GENERIC_READ y no solicitan escritura. Cada worker, creado con _beginthreadex para integrar el runtime C, tiene un handle síncrono propio. Checker también comprueba el número físico y la longitud del disco con IOCTL_STORAGE_GET_DEVICE_NUMBER / IOCTL_DISK_GET_LENGTH_INFO. Checker valida tamaños del descriptor, compara únicamente strings de identificación y propiedades estables con la baseline, y no imprime los strings. El stress comprueba tanto respuestas como el incremento de contadores de **una sola** instancia started; una ejecución sin adjunción no pasa.

## Trazas

DbgPrintEx, componente IHVDRIVER e INFO_LEVEL, registra carga, adjunción, START, REMOVE, unregister y descarga con instancia y estado. No registra seriales ni buffers. Capture con WinDbg; ajuste exclusivamente el mask de diagnóstico si INFO está filtrado. El snapshot permite observar actividad sin depender de mensajes de depuración. ETW/WPP queda pendiente; DbgPrintEx no es un registro de auditoría persistente.

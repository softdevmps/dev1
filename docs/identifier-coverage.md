# Cobertura real y modulos prioritarios pendientes

El objetivo solicitado es cambiar los identificadores principales. El estado actual sigue siendo parcial. Esta tabla diferencia codigo ejecutable implementado de dependencias que no se pueden resolver escribiendo funciones vacias o actualizando una imagen generica.

| Identificador | Modulo actual | Pendiente para lograr la cobertura solicitada |
|---|---|---|
| Serial devuelto por StorageDeviceProperty | C/WDK por dispositivo, activacion/desactivacion Ring 3, Checker y pruebas sinteticas | Compilar con WDK, firma oficial, ejecutar pruebas Windows en secundario seleccionado |
| Serial ATA/NVMe/VPD por consultas directas u otras propiedades | Reenvio conservando respuestas | Parsers/protocolos y politicas especificas documentadas; pruebas de coherencia por cada ruta |
| Serial grabado en firmware SSD | Observacion y guia de fabricante | Confirmar una interfaz oficial de escritura para el modelo y su recuperacion; actualizar firmware puede conservar el serial |
| UUID/serial sistema, placa y chasis (SMBIOS) | Recoleccion CIM; flujo ASUS de actualizacion UEFI | Herramienta/procedimiento oficial de aprovisionamiento del modelo; el flujo de actualizacion de BIOS no implementa escritura de seriales |
| GPU | ID PnP completo observado | Determinar cual identificador se quiere cambiar y la interfaz oficial del modelo; IDs PCI y serial del producto son datos diferentes |
| RAM | Serial/part number publicados por SMBIOS | Interfaz de aprovisionamiento del fabricante para SPD/metadata y validacion por modulo |
| Monitor / USB | Lecturas por instancia | Interfaz de provisionamiento del producto o mecanismos de override documentados para el alcance buscado; no implica regrabar EEPROM |
| CPU | ProcessorId observado | Precisar su significado/plataforma; no se trata como serial regrabable genericamente |
| MAC | Override compatible Windows y MAC virtual Hyper-V | Validacion real del adaptador y otras vistas; EEPROM fisica es otro mecanismo |
| Identidad Windows | Nombre con Rename-Computer; MachineGuid/ProductId/SID observados | Mecanismos de despliegue soportados para identidad de instalacion; editar un string no regenera todas las identidades |
| TPM | Informacion publica | Aprovisionamiento oficial y sus consecuencias; firmware y clave criptografica no son intercambiables |

El modulo de almacenamiento nuevo no depende de parchear kernel, registros internos no documentados ni desactivar protecciones. Tiene cobertura deliberadamente limitada a una propiedad; no se presenta como spoofer completo del equipo. Los pendientes de esta tabla siguen abiertos aunque el usuario ejecute las pruebas del modulo implementado.

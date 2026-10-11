#ifndef SF_FILTER_H
#define SF_FILTER_H
#define SF_KERNEL 1
#include <ntddk.h>
#include <ntddstor.h>
#include <wdmsec.h>
#include "../shared/protocol.h"
#include "../shared/descriptor.h"
#define SF_TAG 'tlFS'
#define SF_FILTER_KIND 1u
#define SF_CONTROL_KIND 2u
#define SF_TRACE(...) DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_INFO_LEVEL, "StorageFilter: " __VA_ARGS__)
typedef struct SF_COMMON {
    ULONG Kind;
    IO_REMOVE_LOCK RemoveLock;
} SF_COMMON;
typedef struct SF_FILTER {
    SF_COMMON Common;
    PDEVICE_OBJECT Self;
    PDEVICE_OBJECT Lower;
    PDEVICE_OBJECT Pdo;
    LIST_ENTRY Link;
    SF_DEVICE_RECORD Record; /* Protected by global ListLock. */
} SF_FILTER;
typedef struct SF_GLOBAL {
    PDRIVER_OBJECT Driver;
    FAST_MUTEX LifecycleMutex; /* Serializes publication and control deletion. */
    KSPIN_LOCK ListLock;
    LIST_ENTRY Devices;
    ULONG DeviceCount;
    LONG NextInstance;
    PDEVICE_OBJECT Control;
    UNICODE_STRING RegistryPath;
    LARGE_INTEGER RegistryCookie;
    BOOLEAN RegistryRegistered;
    NTSTATUS RegistryStatus;
    DECLSPEC_ALIGN(8) volatile LONG64 RegistryEvents;
} SF_GLOBAL;
extern SF_GLOBAL SfGlobal;
DRIVER_INITIALIZE DriverEntry;
DRIVER_ADD_DEVICE SfAddDevice;
DRIVER_UNLOAD SfUnload;
DRIVER_DISPATCH SfDispatch;
DRIVER_DISPATCH SfPnp;
DRIVER_DISPATCH SfPower;
DRIVER_DISPATCH SfDeviceControl;
IO_COMPLETION_ROUTINE SfForwardCompletion;
NTSTATUS SfForward(PDEVICE_OBJECT Device, PIRP Irp);
NTSTATUS SfFinish(PIRP Irp, NTSTATUS Status, ULONG_PTR Information);
NTSTATUS SfControlDispatch(PDEVICE_OBJECT Device, PIRP Irp);
NTSTATUS SfPublish(SF_FILTER *Filter);
void SfUnpublish(SF_FILTER *Filter);
void SfReadHardware(SF_FILTER *Filter);
NTSTATUS SfStorageControl(PDEVICE_OBJECT Device, PIRP Irp);
void SfRegistryInitialize(PUNICODE_STRING RegistryPath);
void SfRegistryShutdown(void);
#endif

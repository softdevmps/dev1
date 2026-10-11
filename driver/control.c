#include "filter.h"
/* Private control-device setup class: ACL never exposes arbitrary kernel operations. */
static const GUID SfControlClass = {0x7fb58f80,0x7f0b,0x4866,{0xa8,0x6b,0x74,0x28,0x3d,0xc3,0x58,0x35}};
static UNICODE_STRING SfControlName = RTL_CONSTANT_STRING(L"\\Device\\StorageFilterCtl");
static UNICODE_STRING SfControlLink = RTL_CONSTANT_STRING(L"\\DosDevices\\StorageFilterCtl");
NTSTATUS SfPublish(SF_FILTER *filter)
{
    NTSTATUS status = STATUS_SUCCESS;
    KIRQL oldIrql;
    PDEVICE_OBJECT control;
    SF_COMMON *common;
    KeEnterCriticalRegion();
    ExAcquireFastMutexUnsafe(&SfGlobal.LifecycleMutex);
    if (SfGlobal.Control == NULL) {
        status = IoCreateDeviceSecure(SfGlobal.Driver, sizeof(SF_COMMON),
            &SfControlName, SF_DEVICE_TYPE, FILE_DEVICE_SECURE_OPEN, FALSE,
            &SDDL_DEVOBJ_SYS_ALL_ADM_ALL, &SfControlClass, &control);
        if (!NT_SUCCESS(status)) goto Exit;
        common = control->DeviceExtension;
        RtlZeroMemory(common, sizeof(*common)); common->Kind = SF_CONTROL_KIND;
        IoInitializeRemoveLock(&common->RemoveLock, SF_TAG, 0, 0);
        control->Flags |= DO_BUFFERED_IO;
        status = IoCreateSymbolicLink(&SfControlLink, &SfControlName);
        if (!NT_SUCCESS(status)) { IoDeleteDevice(control); goto Exit; }
        SfGlobal.Control = control;
        control->Flags &= ~DO_DEVICE_INITIALIZING;
    }
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    InsertTailList(&SfGlobal.Devices, &filter->Link);
    ++SfGlobal.DeviceCount;
    KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
Exit:
    ExReleaseFastMutexUnsafe(&SfGlobal.LifecycleMutex);
    KeLeaveCriticalRegion();
    return status;
}
void SfUnpublish(SF_FILTER *filter)
{
    KIRQL oldIrql;
    PDEVICE_OBJECT control;
    SF_COMMON *common;
    NTSTATUS status;
    KeEnterCriticalRegion();
    ExAcquireFastMutexUnsafe(&SfGlobal.LifecycleMutex);
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    RemoveEntryList(&filter->Link);
    --SfGlobal.DeviceCount;
    KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
    if (SfGlobal.DeviceCount == 0 && SfGlobal.Control != NULL) {
        control = SfGlobal.Control; SfGlobal.Control = NULL;
        common = control->DeviceExtension;
        IoDeleteSymbolicLink(&SfControlLink);
        status = IoAcquireRemoveLock(&common->RemoveLock, control);
        NT_ASSERT(NT_SUCCESS(status));
        if (NT_SUCCESS(status)) IoReleaseRemoveLockAndWait(&common->RemoveLock, control);
        IoDeleteDevice(control);
    }
    ExReleaseFastMutexUnsafe(&SfGlobal.LifecycleMutex);
    KeLeaveCriticalRegion();
}
NTSTATUS SfControlDispatch(PDEVICE_OBJECT device, PIRP irp)
{
    SF_COMMON *common = device->DeviceExtension;
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    NTSTATUS status;
    ULONG_PTR information = 0;
    SF_SNAPSHOT *snapshot;
    PLIST_ENTRY entry;
    KIRQL oldIrql;
    ULONG index = 0;
    /* File close/cleanup must succeed even after the control link was removed. */
    if (stack->MajorFunction == IRP_MJ_CLOSE || stack->MajorFunction == IRP_MJ_CLEANUP)
        return SfFinish(irp, STATUS_SUCCESS, 0);
    status = IoAcquireRemoveLock(&common->RemoveLock, irp);
    if (!NT_SUCCESS(status)) return SfFinish(irp, status, 0);
    if (stack->MajorFunction == IRP_MJ_CREATE) {
        status = stack->FileObject->FileName.Length == 0 ? STATUS_SUCCESS : STATUS_OBJECT_NAME_NOT_FOUND;
    } else if (stack->MajorFunction != IRP_MJ_DEVICE_CONTROL) {
        status = STATUS_INVALID_DEVICE_REQUEST;
    } else if (stack->Parameters.DeviceIoControl.IoControlCode != SF_IOCTL_SNAPSHOT) {
        status = STATUS_INVALID_DEVICE_REQUEST;
    } else if (stack->Parameters.DeviceIoControl.InputBufferLength != 0) {
        status = STATUS_INVALID_PARAMETER;
    } else if (stack->Parameters.DeviceIoControl.OutputBufferLength < sizeof(SF_SNAPSHOT) ||
               irp->AssociatedIrp.SystemBuffer == NULL) {
        status = STATUS_BUFFER_TOO_SMALL;
    } else {
        snapshot = irp->AssociatedIrp.SystemBuffer;
        RtlZeroMemory(snapshot, sizeof(*snapshot));
        snapshot->Version = SF_PROTOCOL_VERSION; snapshot->Size = sizeof(*snapshot);
        snapshot->RegistryCallbackStatus = SfGlobal.RegistryStatus;
        snapshot->RegistryEvents = (SF_U64)InterlockedCompareExchange64(&SfGlobal.RegistryEvents, 0, 0);
        KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
        snapshot->DeviceCount = SfGlobal.DeviceCount;
        for (entry = SfGlobal.Devices.Flink; entry != &SfGlobal.Devices && index < SF_MAX_DEVICES;
             entry = entry->Flink) {
            SF_FILTER *filter = CONTAINING_RECORD(entry, SF_FILTER, Link);
            snapshot->Devices[index++] = filter->Record;
        }
        KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        snapshot->RecordsReturned = index;
        status = STATUS_SUCCESS; information = sizeof(*snapshot);
    }
    IoReleaseRemoveLock(&common->RemoveLock, irp);
    return SfFinish(irp, status, information);
}

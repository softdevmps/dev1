#include "filter.h"
static NTSTATUS SfStartCompletion(PDEVICE_OBJECT device, PIRP irp, PVOID context)
{
    UNREFERENCED_PARAMETER(device); UNREFERENCED_PARAMETER(irp);
    KeSetEvent((PKEVENT)context, IO_NO_INCREMENT, FALSE);
    return STATUS_MORE_PROCESSING_REQUIRED;
}
NTSTATUS SfPnp(PDEVICE_OBJECT device, PIRP irp)
{
    SF_COMMON *common = device->DeviceExtension;
    SF_FILTER *filter = device->DeviceExtension;
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    NTSTATUS status;
    KIRQL oldIrql;
    KEVENT event;
    ULONG instance;
    if (common->Kind == SF_CONTROL_KIND) return SfControlDispatch(device, irp);
    status = IoAcquireRemoveLock(&common->RemoveLock, irp);
    if (!NT_SUCCESS(status)) return SfFinish(irp, status, 0);
    switch (stack->MinorFunction) {
    case IRP_MN_START_DEVICE:
        KeInitializeEvent(&event, NotificationEvent, FALSE);
        IoCopyCurrentIrpStackLocationToNext(irp);
        IoSetCompletionRoutine(irp, SfStartCompletion, &event, TRUE, TRUE, TRUE);
        status = IoCallDriver(filter->Lower, irp);
        if (status == STATUS_PENDING) {
            NTSTATUS waitStatus = KeWaitForSingleObject(&event, Executive, KernelMode, FALSE, NULL);
            /* Nonalertable, no-timeout event wait has only the success outcome. */
            NT_ASSERT(waitStatus == STATUS_SUCCESS);
            UNREFERENCED_PARAMETER(waitStatus);
        }
        status = irp->IoStatus.Status;
        if (NT_SUCCESS(status)) {
            SfReadHardware(filter);
            KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
            ++filter->Epoch; ++filter->ProfileGeneration;
            filter->DiskMapped = FALSE; filter->OriginalSerialCapacity = 0;
            filter->SerialLength = 0; RtlZeroMemory(filter->Serial, sizeof(filter->Serial));
            filter->Record.State = SF_STATE_STARTED | (filter->UsageRestricted ? SF_STATE_USAGE_RESTRICTED : 0u);
            KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        }
        SF_TRACE("start instance=%lu status=0x%08lx\n", filter->Record.Instance, status);
        IoReleaseRemoveLock(&common->RemoveLock, irp);
        IoCompleteRequest(irp, IO_NO_INCREMENT);
        return status;
    case IRP_MN_DEVICE_USAGE_NOTIFICATION:
        /* All dispatch/completion code is nonpageable. Stay nonpageable once
           the stack announces paging/hibernation/crash-dump use. */
        device->Flags &= ~(ULONG)DO_POWER_PAGABLE;
        if (stack->Parameters.UsageNotification.InPath) {
            KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
            filter->UsageRestricted = TRUE; filter->Record.State |= SF_STATE_USAGE_RESTRICTED;
            ++filter->ProfileGeneration;
            filter->SerialLength = 0; RtlZeroMemory(filter->Serial, sizeof(filter->Serial));
            KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        }
        return SfForward(device, irp);
    case IRP_MN_STOP_DEVICE:
        KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
        filter->Record.State &= ~SF_STATE_STARTED;
        ++filter->Epoch; ++filter->ProfileGeneration;
        filter->SerialLength = 0; RtlZeroMemory(filter->Serial, sizeof(filter->Serial));
        KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        return SfForward(device, irp);
    case IRP_MN_SURPRISE_REMOVAL:
        KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
        filter->Record.State = SF_STATE_SURPRISE_REMOVED;
        ++filter->Epoch; ++filter->ProfileGeneration;
        filter->SerialLength = 0; RtlZeroMemory(filter->Serial, sizeof(filter->Serial));
        KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        return SfForward(device, irp);
    case IRP_MN_REMOVE_DEVICE:
        instance = filter->Record.Instance;
        SfUnpublish(filter);
        /* Wait for every forwarded completion before detach/free. No list lock held. */
        IoReleaseRemoveLockAndWait(&common->RemoveLock, irp);
        IoSkipCurrentIrpStackLocation(irp);
        status = IoCallDriver(filter->Lower, irp);
        IoDetachDevice(filter->Lower);
        IoDeleteDevice(device);
        SF_TRACE("removed instance=%lu lower status=0x%08lx\n", instance, status);
        return status;
    default:
        /* Query/cancel stop/remove, relations, usage notifications: preserve lower policy. */
        return SfForward(device, irp);
    }
}

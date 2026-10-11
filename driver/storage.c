#include "filter.h"
typedef struct SF_QUERY_CONTEXT {
    SF_FILTER *Filter;
    ULONG OutputLength;
} SF_QUERY_CONTEXT;
static NTSTATUS SfStorageCompletion(PDEVICE_OBJECT device, PIRP irp, PVOID context)
{
    SF_QUERY_CONTEXT *query = context;
    SF_FILTER *filter = query->Filter;
    SF_DESCRIPTOR_INFO descriptor;
    ULONG bytes = 0;
    KIRQL oldIrql;
    BOOLEAN successful = NT_SUCCESS(irp->IoStatus.Status);
    UNREFERENCED_PARAMETER(device);
    RtlZeroMemory(&descriptor, sizeof(descriptor));
    if (successful) {
        bytes = (ULONG)min(irp->IoStatus.Information, (ULONG_PTR)query->OutputLength);
        SfInspectDescriptor(irp->AssociatedIrp.SystemBuffer, min(bytes, 65536u), &descriptor);
    }
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    ++filter->Record.QueriesCompleted;
    if (!successful) ++filter->Record.QueryFailures;
    if (descriptor.Flags & (SF_PARSE_BAD_SIZE | SF_PARSE_BAD_OFFSET |
        SF_PARSE_UNTERMINATED | SF_PARSE_BAD_RAW_LENGTH | SF_PARSE_TOO_SHORT))
        ++filter->Record.MalformedResponses;
    filter->Record.LastQueryStatus = irp->IoStatus.Status;
    filter->Record.LastReturnedBytes = bytes;
    filter->Record.Descriptor = descriptor;
    KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
    ExFreePoolWithTag(query, SF_TAG);
    if (irp->PendingReturned) IoMarkIrpPending(irp);
    IoReleaseRemoveLock(&filter->Common.RemoveLock, irp);
    return STATUS_CONTINUE_COMPLETION;
}
NTSTATUS SfStorageControl(PDEVICE_OBJECT device, PIRP irp)
{
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    SF_FILTER *filter = device->DeviceExtension;
    PSTORAGE_PROPERTY_QUERY input;
    SF_QUERY_CONTEXT *context;
    /* IOCTL_STORAGE_QUERY_PROPERTY is METHOD_BUFFERED. Only standard device
       descriptors are interpreted; other properties/queries pass unchanged. */
    if (stack->Parameters.DeviceIoControl.IoControlCode != IOCTL_STORAGE_QUERY_PROPERTY ||
        stack->Parameters.DeviceIoControl.InputBufferLength <
            FIELD_OFFSET(STORAGE_PROPERTY_QUERY, AdditionalParameters) ||
        irp->AssociatedIrp.SystemBuffer == NULL) return SfForward(device, irp);
    input = irp->AssociatedIrp.SystemBuffer;
    if (input->PropertyId != StorageDeviceProperty || input->QueryType != PropertyStandardQuery)
        return SfForward(device, irp);
    context = ExAllocatePoolWithTag(NonPagedPoolNx, sizeof(*context), SF_TAG);
    /* Observation must not change the lower driver's behavior under memory pressure. */
    if (context == NULL) {
        KIRQL oldIrql;
        KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
        ++filter->Record.ObservationsSkipped;
        KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        return SfForward(device, irp);
    }
    context->Filter = filter;
    context->OutputLength = stack->Parameters.DeviceIoControl.OutputBufferLength;
    IoCopyCurrentIrpStackLocationToNext(irp);
    IoSetCompletionRoutine(irp, SfStorageCompletion, context, TRUE, TRUE, TRUE);
    return IoCallDriver(filter->Lower, irp);
}

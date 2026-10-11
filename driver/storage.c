#include "filter.h"
typedef struct SF_QUERY_CONTEXT {
    SF_FILTER *Filter;
    ULONG OutputLength;
    ULONG Ioctl;
    ULONG SerialLength;
    unsigned char Serial[SF_SERIAL_BYTES];
    SF_U64 Epoch, Generation;
} SF_QUERY_CONTEXT;
static NTSTATUS SfStorageCompletion(PDEVICE_OBJECT device, PIRP irp, PVOID context)
{
    SF_QUERY_CONTEXT *query = context;
    SF_FILTER *filter = query->Filter;
    SF_DESCRIPTOR_INFO descriptor;
    SF_SERIAL_SPAN span;
    SF_U32 result = SF_TRANSFORM_BAD_DESCRIPTOR;
    ULONG bytes = 0;
    KIRQL oldIrql;
    BOOLEAN successful = NT_SUCCESS(irp->IoStatus.Status);
    UNREFERENCED_PARAMETER(device);
    RtlZeroMemory(&descriptor, sizeof(descriptor));
    RtlZeroMemory(&span, sizeof(span));
    if (successful) {
        bytes = (ULONG)min(irp->IoStatus.Information, (ULONG_PTR)query->OutputLength);
        if (query->Ioctl == IOCTL_STORAGE_QUERY_PROPERTY) {
            SfInspectDescriptor(irp->AssociatedIrp.SystemBuffer, min(bytes, 65536u), &descriptor);
            result = SfAnalyzeSerial(irp->AssociatedIrp.SystemBuffer, min(bytes, 65536u), &span);
        }
    }
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    if (query->Ioctl == IOCTL_STORAGE_GET_DEVICE_NUMBER) {
        if (successful && bytes >= sizeof(STORAGE_DEVICE_NUMBER) &&
            query->Epoch == filter->Epoch && (filter->Record.State & SF_STATE_STARTED)) {
            PSTORAGE_DEVICE_NUMBER number = irp->AssociatedIrp.SystemBuffer;
            if (number->DeviceType == FILE_DEVICE_DISK && number->DeviceNumber <= 1024) {
                filter->DiskMapped = TRUE; filter->DiskNumber = number->DeviceNumber;
            }
        }
    } else {
        ++filter->Record.QueriesCompleted;
        if (!successful) ++filter->Record.QueryFailures;
        if (descriptor.Flags & (SF_PARSE_BAD_SIZE | SF_PARSE_BAD_OFFSET |
            SF_PARSE_UNTERMINATED | SF_PARSE_BAD_RAW_LENGTH | SF_PARSE_TOO_SHORT | SF_PARSE_BAD_VERSION))
            ++filter->Record.MalformedResponses;
        filter->Record.LastQueryStatus = irp->IoStatus.Status;
        filter->Record.LastReturnedBytes = bytes;
        filter->Record.Descriptor = descriptor;
        if (query->Epoch == filter->Epoch && (filter->Record.State & SF_STATE_STARTED)) {
            if (query->OutputLength >= 36)
                filter->OriginalSerialCapacity = result == SF_TRANSFORM_OK ? span.Capacity : 0;
            if (query->SerialLength != 0 && query->OutputLength >= 36) {
                if (filter->ProfileGeneration != query->Generation || filter->SerialLength == 0 ||
                    filter->UsageRestricted) result = SF_TRANSFORM_NOT_ACTIVE;
                else if (result == SF_TRANSFORM_OK)
                    result = SfApplySerial(irp->AssociatedIrp.SystemBuffer, bytes, &span,
                                           query->Serial, query->SerialLength);
                filter->TransformResult = result;
                if (result == SF_TRANSFORM_OK) ++filter->Transformed;
                else ++filter->TransformSkipped;
            }
        }
    }
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
    ULONG ioctl = stack->Parameters.DeviceIoControl.IoControlCode;
    KIRQL oldIrql;
    /* IOCTL_STORAGE_QUERY_PROPERTY is METHOD_BUFFERED. Only standard device
       descriptors are interpreted; other properties/queries pass unchanged. */
    if (ioctl == IOCTL_STORAGE_GET_DEVICE_NUMBER) {
        if (stack->Parameters.DeviceIoControl.InputBufferLength != 0 ||
            stack->Parameters.DeviceIoControl.OutputBufferLength < sizeof(STORAGE_DEVICE_NUMBER) ||
            irp->AssociatedIrp.SystemBuffer == NULL) return SfForward(device, irp);
    } else {
        if (ioctl != IOCTL_STORAGE_QUERY_PROPERTY ||
            stack->Parameters.DeviceIoControl.InputBufferLength <
                FIELD_OFFSET(STORAGE_PROPERTY_QUERY, AdditionalParameters) ||
            irp->AssociatedIrp.SystemBuffer == NULL) return SfForward(device, irp);
        input = irp->AssociatedIrp.SystemBuffer;
        if (input->PropertyId != StorageDeviceProperty || input->QueryType != PropertyStandardQuery)
            return SfForward(device, irp);
    }
    context = ExAllocatePoolWithTag(NonPagedPoolNx, sizeof(*context), SF_TAG);
    /* Observation must not change the lower driver's behavior under memory pressure. */
    if (context == NULL) {
        KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
        if (ioctl == IOCTL_STORAGE_QUERY_PROPERTY) ++filter->Record.ObservationsSkipped;
        KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
        return SfForward(device, irp);
    }
    RtlZeroMemory(context, sizeof(*context));
    context->Filter = filter; context->Ioctl = ioctl;
    context->OutputLength = stack->Parameters.DeviceIoControl.OutputBufferLength;
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    context->Epoch = filter->Epoch; context->Generation = filter->ProfileGeneration;
    if (!filter->UsageRestricted && (filter->Record.State & SF_STATE_STARTED)) {
        context->SerialLength = filter->SerialLength;
        RtlCopyMemory(context->Serial, filter->Serial, sizeof(context->Serial));
    }
    KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
    IoCopyCurrentIrpStackLocationToNext(irp);
    IoSetCompletionRoutine(irp, SfStorageCompletion, context, TRUE, TRUE, TRUE);
    return IoCallDriver(filter->Lower, irp);
}

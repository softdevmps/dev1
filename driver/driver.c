#include "filter.h"
SF_GLOBAL SfGlobal;
NTSTATUS SfFinish(PIRP irp, NTSTATUS status, ULONG_PTR information)
{
    irp->IoStatus.Status = status;
    irp->IoStatus.Information = information;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}
NTSTATUS DriverEntry(PDRIVER_OBJECT driver, PUNICODE_STRING registryPath)
{
    ULONG i;
    RtlZeroMemory(&SfGlobal, sizeof(SfGlobal));
    SfGlobal.Driver = driver;
    ExInitializeFastMutex(&SfGlobal.LifecycleMutex);
    KeInitializeSpinLock(&SfGlobal.ListLock);
    InitializeListHead(&SfGlobal.Devices);
    for (i = 0; i <= IRP_MJ_MAXIMUM_FUNCTION; ++i) driver->MajorFunction[i] = SfDispatch;
    driver->MajorFunction[IRP_MJ_PNP] = SfPnp;
    driver->MajorFunction[IRP_MJ_POWER] = SfPower;
    driver->MajorFunction[IRP_MJ_DEVICE_CONTROL] = SfDeviceControl;
    driver->DriverExtension->AddDevice = SfAddDevice;
    driver->DriverUnload = SfUnload;
    SfRegistryInitialize(registryPath); /* Optional; failure recorded, never hidden. */
    SF_TRACE("loaded, registry callback status=0x%08lx\n", SfGlobal.RegistryStatus);
    return STATUS_SUCCESS;
}
NTSTATUS SfAddDevice(PDRIVER_OBJECT driver, PDEVICE_OBJECT pdo)
{
    NTSTATUS status;
    PDEVICE_OBJECT device;
    SF_FILTER *filter;
    status = IoCreateDevice(driver, sizeof(SF_FILTER), NULL, pdo->DeviceType,
                            FILE_DEVICE_SECURE_OPEN, FALSE, &device);
    if (!NT_SUCCESS(status)) return status;
    filter = (SF_FILTER *)device->DeviceExtension;
    RtlZeroMemory(filter, sizeof(*filter));
    filter->Common.Kind = SF_FILTER_KIND;
    IoInitializeRemoveLock(&filter->Common.RemoveLock, SF_TAG, 0, 0);
    filter->Self = device; filter->Pdo = pdo;
    filter->Record.Instance = (ULONG)InterlockedIncrement(&SfGlobal.NextInstance);
    filter->Record.BusPropertyStatus = STATUS_NOT_SUPPORTED;
    filter->Record.RemovalPropertyStatus = STATUS_NOT_SUPPORTED;
    filter->Lower = IoAttachDeviceToDeviceStack(device, pdo);
    if (filter->Lower == NULL) { IoDeleteDevice(device); return STATUS_NO_SUCH_DEVICE; }
    device->DeviceType = filter->Lower->DeviceType;
    device->Characteristics |= filter->Lower->Characteristics;
    device->Flags |= filter->Lower->Flags & (DO_BUFFERED_IO | DO_DIRECT_IO | DO_POWER_PAGABLE);
    status = SfPublish(filter);
    if (!NT_SUCCESS(status)) {
        IoDetachDevice(filter->Lower); IoDeleteDevice(device); return status;
    }
    device->Flags &= ~DO_DEVICE_INITIALIZING;
    SF_TRACE("attached instance=%lu\n", filter->Record.Instance);
    return STATUS_SUCCESS;
}
void SfUnload(PDRIVER_OBJECT driver)
{
    UNREFERENCED_PARAMETER(driver);
    NT_ASSERT(SfGlobal.DeviceCount == 0 && SfGlobal.Control == NULL);
    SfRegistryShutdown();
    SF_TRACE("unloaded\n");
}
NTSTATUS SfForwardCompletion(PDEVICE_OBJECT device, PIRP irp, PVOID context)
{
    SF_FILTER *filter = context;
    UNREFERENCED_PARAMETER(device);
    if (irp->PendingReturned) IoMarkIrpPending(irp);
    IoReleaseRemoveLock(&filter->Common.RemoveLock, irp);
    return STATUS_CONTINUE_COMPLETION;
}
/* Caller owns one remove-lock reference, transferred to completion. */
NTSTATUS SfForward(PDEVICE_OBJECT device, PIRP irp)
{
    SF_FILTER *filter = device->DeviceExtension;
    IoCopyCurrentIrpStackLocationToNext(irp);
    IoSetCompletionRoutine(irp, SfForwardCompletion, filter, TRUE, TRUE, TRUE);
    return IoCallDriver(filter->Lower, irp);
}
NTSTATUS SfDispatch(PDEVICE_OBJECT device, PIRP irp)
{
    SF_COMMON *common = device->DeviceExtension;
    NTSTATUS status;
    if (common->Kind == SF_CONTROL_KIND) return SfControlDispatch(device, irp);
    status = IoAcquireRemoveLock(&common->RemoveLock, irp);
    if (!NT_SUCCESS(status)) return SfFinish(irp, status, 0);
    return SfForward(device, irp);
}
NTSTATUS SfDeviceControl(PDEVICE_OBJECT device, PIRP irp)
{
    SF_COMMON *common = device->DeviceExtension;
    NTSTATUS status;
    if (common->Kind == SF_CONTROL_KIND) return SfControlDispatch(device, irp);
    status = IoAcquireRemoveLock(&common->RemoveLock, irp);
    if (!NT_SUCCESS(status)) return SfFinish(irp, status, 0);
    return SfStorageControl(device, irp);
}
NTSTATUS SfPower(PDEVICE_OBJECT device, PIRP irp)
{
    SF_COMMON *common = device->DeviceExtension;
    SF_FILTER *filter = device->DeviceExtension;
    NTSTATUS status;
    if (common->Kind == SF_CONTROL_KIND) return SfControlDispatch(device, irp);
    status = IoAcquireRemoveLock(&common->RemoveLock, irp);
    if (!NT_SUCCESS(status)) return SfFinish(irp, status, 0);
    /* Windows 10/11: no PoStartNextPowerIrp requirement. */
    IoCopyCurrentIrpStackLocationToNext(irp);
    IoSetCompletionRoutine(irp, SfForwardCompletion, filter, TRUE, TRUE, TRUE);
    return PoCallDriver(filter->Lower, irp);
}

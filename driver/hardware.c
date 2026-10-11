#include "filter.h"
#include <initguid.h>
#include <devpkey.h>
void SfReadHardware(SF_FILTER *filter)
{
    GUID bus = {0};
    ULONG policy = 0, size = 0;
    DEVPROPTYPE type = 0;
    NTSTATUS busStatus, policyStatus;
    KIRQL oldIrql;
    PAGED_CODE();
    busStatus = IoGetDevicePropertyData(filter->Pdo, &DEVPKEY_Device_BusTypeGuid,
        0 /* language-neutral LCID */, 0, sizeof(bus), &bus, &size, &type);
    if (NT_SUCCESS(busStatus) && (type != DEVPROP_TYPE_GUID || size != sizeof(bus)))
        busStatus = STATUS_OBJECT_TYPE_MISMATCH;
    size = 0; type = 0;
    policyStatus = IoGetDevicePropertyData(filter->Pdo, &DEVPKEY_Device_RemovalPolicy,
        0 /* language-neutral LCID */, 0, sizeof(policy), &policy, &size, &type);
    if (NT_SUCCESS(policyStatus) && (type != DEVPROP_TYPE_UINT32 || size != sizeof(policy)))
        policyStatus = STATUS_OBJECT_TYPE_MISMATCH;
    KeAcquireSpinLock(&SfGlobal.ListLock, &oldIrql);
    filter->Record.BusPropertyStatus = busStatus;
    filter->Record.RemovalPropertyStatus = policyStatus;
    if (NT_SUCCESS(busStatus)) RtlCopyMemory(filter->Record.BusTypeGuid, &bus, sizeof(bus));
    if (NT_SUCCESS(policyStatus)) filter->Record.RemovalPolicy = policy;
    KeReleaseSpinLock(&SfGlobal.ListLock, oldIrql);
}

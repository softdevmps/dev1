#include "filter.h"
#include <ntstrsafe.h>
static NTSTATUS SfRegistryCallback(PVOID context, PVOID argument1, PVOID argument2)
{
    REG_NOTIFY_CLASS operation = (REG_NOTIFY_CLASS)(ULONG_PTR)argument1;
    PVOID object = NULL;
    PCUNICODE_STRING name = NULL;
    NTSTATUS status;
    UNREFERENCED_PARAMETER(context);
    switch (operation) {
    case RegNtPreSetValueKey: object = ((PREG_SET_VALUE_KEY_INFORMATION)argument2)->Object; break;
    case RegNtPreDeleteValueKey: object = ((PREG_DELETE_VALUE_KEY_INFORMATION)argument2)->Object; break;
    case RegNtPreDeleteKey: object = ((PREG_DELETE_KEY_INFORMATION)argument2)->Object; break;
    case RegNtPreRenameKey: object = ((PREG_RENAME_KEY_INFORMATION)argument2)->Object; break;
    default: return STATUS_SUCCESS;
    }
    status = CmCallbackGetKeyObjectIDEx(&SfGlobal.RegistryCookie, object, NULL, &name, 0);
    if (NT_SUCCESS(status)) {
        if (RtlPrefixUnicodeString(&SfGlobal.RegistryPath, name, TRUE) &&
            (name->Length == SfGlobal.RegistryPath.Length ||
             name->Buffer[SfGlobal.RegistryPath.Length / sizeof(WCHAR)] == L'\\'))
            InterlockedIncrement64(&SfGlobal.RegistryEvents);
        CmCallbackReleaseKeyObjectIDEx(name);
    }
    /* Observer only: never blocks or rewrites registry operations. */
    return STATUS_SUCCESS;
}
void SfRegistryInitialize(PUNICODE_STRING registryPath)
{
    UNICODE_STRING altitude;
    WCHAR altitudeBuffer[64] = {0};
    RTL_QUERY_REGISTRY_TABLE table[2];
    PWCHAR parameters;
    SIZE_T bytes = registryPath->Length + sizeof(L"\\Parameters");
    NTSTATUS status;
    SfGlobal.RegistryStatus = STATUS_NOT_SUPPORTED;
    SfGlobal.RegistryPath.Buffer = ExAllocatePoolWithTag(NonPagedPoolNx,
        registryPath->Length + sizeof(WCHAR), SF_TAG);
    if (SfGlobal.RegistryPath.Buffer == NULL) {
        SfGlobal.RegistryStatus = STATUS_INSUFFICIENT_RESOURCES; return;
    }
    SfGlobal.RegistryPath.Length = registryPath->Length;
    SfGlobal.RegistryPath.MaximumLength = registryPath->Length + sizeof(WCHAR);
    RtlCopyMemory(SfGlobal.RegistryPath.Buffer, registryPath->Buffer, registryPath->Length);
    SfGlobal.RegistryPath.Buffer[registryPath->Length / sizeof(WCHAR)] = L'\0';
    parameters = ExAllocatePoolWithTag(PagedPool, bytes, SF_TAG);
    if (parameters == NULL) { SfGlobal.RegistryStatus = STATUS_INSUFFICIENT_RESOURCES; return; }
    status = RtlStringCbPrintfW(parameters, bytes, L"%wZ\\Parameters", registryPath);
    if (!NT_SUCCESS(status)) { ExFreePoolWithTag(parameters, SF_TAG); SfGlobal.RegistryStatus = status; return; }
    RtlInitEmptyUnicodeString(&altitude, altitudeBuffer, sizeof(altitudeBuffer));
    RtlZeroMemory(table, sizeof(table));
    table[0].Flags = RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_REQUIRED | RTL_QUERY_REGISTRY_TYPECHECK;
    table[0].Name = L"RegistryAltitude";
    table[0].EntryContext = &altitude;
    table[0].DefaultType = REG_SZ << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT;
    status = RtlQueryRegistryValues(RTL_REGISTRY_ABSOLUTE, parameters, table, NULL, NULL);
    ExFreePoolWithTag(parameters, SF_TAG);
    if (!NT_SUCCESS(status)) { SfGlobal.RegistryStatus = status; return; }
    if (altitude.Length == 0) { SfGlobal.RegistryStatus = STATUS_INVALID_PARAMETER; return; }
    status = CmRegisterCallbackEx(SfRegistryCallback, &altitude, SfGlobal.Driver,
        NULL, &SfGlobal.RegistryCookie, NULL);
    SfGlobal.RegistryStatus = status;
    SfGlobal.RegistryRegistered = NT_SUCCESS(status);
}
void SfRegistryShutdown(void)
{
    if (SfGlobal.RegistryRegistered) {
        NTSTATUS status = CmUnRegisterCallback(SfGlobal.RegistryCookie);
        NT_ASSERT(NT_SUCCESS(status));
        SF_TRACE("registry unregister status=0x%08lx\n", status);
        SfGlobal.RegistryRegistered = FALSE;
    }
    if (SfGlobal.RegistryPath.Buffer != NULL) {
        ExFreePoolWithTag(SfGlobal.RegistryPath.Buffer, SF_TAG);
        SfGlobal.RegistryPath.Buffer = NULL;
    }
}

#include "filter.h"
static void SfCloseKey(HANDLE key)
{
    NTSTATUS status = ZwClose(key);
    if (!NT_SUCCESS(status)) SF_TRACE("key close status=0x%08lx\n", status);
}
/* Resolve CurrentControlSet aliases before comparing callback object names. */
static NTSTATUS SfCanonicalServicePath(PUNICODE_STRING path)
{
    OBJECT_ATTRIBUTES attributes;
    HANDLE key;
    PKEY_NAME_INFORMATION name;
    ULONG required = 0, capacity;
    NTSTATUS status;
    InitializeObjectAttributes(&attributes, path, OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    status = ZwOpenKey(&key, KEY_READ, &attributes);
    if (!NT_SUCCESS(status)) return status;
    status = ZwQueryKey(key, KeyNameInformation, NULL, 0, &required);
    if ((status != STATUS_BUFFER_TOO_SMALL && status != STATUS_BUFFER_OVERFLOW) ||
        required < FIELD_OFFSET(KEY_NAME_INFORMATION, Name) || required > 65536) {
        SfCloseKey(key);
        return NT_SUCCESS(status) ? STATUS_INVALID_BUFFER_SIZE : status;
    }
    name = ExAllocatePoolWithTag(NonPagedPoolNx, required, SF_TAG);
    if (name == NULL) { SfCloseKey(key); return STATUS_INSUFFICIENT_RESOURCES; }
    capacity = required;
    status = ZwQueryKey(key, KeyNameInformation, name, capacity, &required);
    SfCloseKey(key);
    if (NT_SUCCESS(status)) {
        if (required > capacity || required < FIELD_OFFSET(KEY_NAME_INFORMATION, Name) ||
            name->NameLength > required - FIELD_OFFSET(KEY_NAME_INFORMATION, Name) ||
            name->NameLength > MAXUSHORT - sizeof(WCHAR) || (name->NameLength & 1)) {
            status = STATUS_INVALID_BUFFER_SIZE;
        } else {
            SfGlobal.RegistryPath.Buffer = ExAllocatePoolWithTag(NonPagedPoolNx,
                name->NameLength + sizeof(WCHAR), SF_TAG);
            if (SfGlobal.RegistryPath.Buffer == NULL) status = STATUS_INSUFFICIENT_RESOURCES;
            else {
                SfGlobal.RegistryPath.Length = (USHORT)name->NameLength;
                SfGlobal.RegistryPath.MaximumLength = (USHORT)(name->NameLength + sizeof(WCHAR));
                RtlCopyMemory(SfGlobal.RegistryPath.Buffer, name->Name, name->NameLength);
                SfGlobal.RegistryPath.Buffer[name->NameLength / sizeof(WCHAR)] = L'\0';
            }
        }
    }
    ExFreePoolWithTag(name, SF_TAG);
    return status;
}

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
    if (bytes > MAXUSHORT || registryPath->Length > MAXUSHORT - sizeof(WCHAR)) {
        SfGlobal.RegistryStatus = STATUS_NAME_TOO_LONG; return;
    }
    status = SfCanonicalServicePath(registryPath);
    if (!NT_SUCCESS(status)) { SfGlobal.RegistryStatus = status; return; }
    parameters = ExAllocatePoolWithTag(PagedPool, bytes, SF_TAG);
    if (parameters == NULL) { SfGlobal.RegistryStatus = STATUS_INSUFFICIENT_RESOURCES; return; }
    RtlCopyMemory(parameters, registryPath->Buffer, registryPath->Length);
    RtlCopyMemory((PUCHAR)parameters + registryPath->Length, L"\\Parameters", sizeof(L"\\Parameters"));
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

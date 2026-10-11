#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <string.h>
#include <process.h>
#include <errno.h>
#include "../shared/descriptor.h"
#include "../shared/transform.h"
#define MAX_DESCRIPTOR 65536u
#define BAD_FLAGS (SF_PARSE_BAD_SIZE | SF_PARSE_BAD_OFFSET | SF_PARSE_UNTERMINATED | SF_PARSE_BAD_RAW_LENGTH | SF_PARSE_TOO_SHORT | SF_PARSE_HEADER_ONLY | SF_PARSE_TRUNCATED | SF_PARSE_BAD_VERSION)
typedef struct BLOB { unsigned char *Data; DWORD Length; } BLOB;
typedef struct WORK { DWORD Disk, Iterations; const BLOB *Baseline; LONG Failures; } WORK;
static int Snapshot(SF_SNAPSHOT *snapshot, int print);
static void Error(const wchar_t *operation)
{
    fwprintf(stderr, L"%ls: Win32 error %lu\n", operation, GetLastError());
}
static int Number(const wchar_t *text, DWORD max, DWORD *result)
{
    wchar_t *end;
    unsigned long value;
    if (!text[0] || text[0] < L'0' || text[0] > L'9') return 0;
    errno = 0; value = wcstoul(text, &end, 10);
    if (*end != L'\0' || errno == ERANGE || value > max) return 0;
    *result = (DWORD)value; return 1;
}
static int Generation(const wchar_t *text, SF_U64 *result)
{
    wchar_t *end;
    unsigned long long value;
    if (!text[0] || text[0] < L'0' || text[0] > L'9') return 0;
    errno = 0; value = wcstoull(text, &end, 10);
    if (*end != L'\0' || errno == ERANGE) return 0;
    *result = (SF_U64)value; return 1;
}
static int ProfileOptions(int argc, wchar_t **argv, int first, SF_U64 *generation, DWORD *instance)
{
    *instance = 0;
    if (argc == first) return 1;
    if ((argc != first + 2 && argc != first + 4) ||
        wcscmp(argv[first], L"--generation") != 0 || !Generation(argv[first + 1], generation)) return 0;
    return argc == first + 2 || (wcscmp(argv[first + 2], L"--instance") == 0 &&
        Number(argv[first + 3], 0xffffffffu, instance) && *instance != 0);
}
static HANDLE OpenDisk(DWORD disk)
{
    wchar_t path[64];
    _snwprintf_s(path, _countof(path), _TRUNCATE, L"\\\\.\\PhysicalDrive%lu", disk);
    return CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                       NULL, OPEN_EXISTING, 0, NULL);
}
static int Query(HANDLE disk, BLOB *blob)
{
    STORAGE_PROPERTY_QUERY query;
    STORAGE_DESCRIPTOR_HEADER header;
    SF_DESCRIPTOR_INFO info;
    DWORD returned = 0;
    blob->Data = NULL; blob->Length = 0;
    ZeroMemory(&query, sizeof(query)); ZeroMemory(&header, sizeof(header));
    query.PropertyId = StorageDeviceProperty; query.QueryType = PropertyStandardQuery;
    if (!DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
        &header, sizeof(header), &returned, NULL)) { Error(L"descriptor header"); return 0; }
    if (returned < sizeof(header) || header.Size < 36 || header.Size > MAX_DESCRIPTOR) {
        fputs("Invalid or unsupported descriptor size\n", stderr); return 0;
    }
    blob->Data = (unsigned char *)calloc(1, header.Size);
    if (blob->Data == NULL) return 0;
    if (!DeviceIoControl(disk, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query),
        blob->Data, header.Size, &returned, NULL)) {
        Error(L"descriptor"); free(blob->Data); blob->Data = NULL; return 0;
    }
    if (returned > header.Size) {
        fputs("Returned length exceeds capacity\n", stderr); free(blob->Data); blob->Data = NULL; return 0;
    }
    blob->Length = returned;
    SfInspectDescriptor(blob->Data, blob->Length, &info);
    if (info.Flags & BAD_FLAGS) {
        fprintf(stderr, "Descriptor validation flags=0x%lx\n", (unsigned long)info.Flags);
        free(blob->Data); blob->Data = NULL; return 0;
    }
    return 1;
}
static DWORD Read32(const unsigned char *p)
{
    return (DWORD)p[0] | ((DWORD)p[1] << 8) | ((DWORD)p[2] << 16) | ((DWORD)p[3] << 24);
}
static int SameIdentifiers(const BLOB *a, const BLOB *b)
{
    DWORD i, x, y;
    SF_DESCRIPTOR_INFO ai, bi;
    SfInspectDescriptor(a->Data, a->Length, &ai); SfInspectDescriptor(b->Data, b->Length, &bi);
    if ((ai.Flags | bi.Flags) & BAD_FLAGS) return 0;
    if (ai.BusType != bi.BusType || ai.Removable != bi.Removable) return 0;
    for (i = 0; i < 4; ++i) {
        x = Read32(a->Data + 12 + i * 4); y = Read32(b->Data + 12 + i * 4);
        if ((x == 0) != (y == 0)) return 0;
        if (x != 0 && strcmp((const char *)a->Data + x, (const char *)b->Data + y) != 0) return 0;
    }
    return 1;
}
static int DescribeDisk(HANDLE disk, DWORD expectedNumber)
{
    STORAGE_DEVICE_NUMBER number;
    GET_LENGTH_INFORMATION length;
    DWORD returned = 0;
    if (!DeviceIoControl(disk, IOCTL_STORAGE_GET_DEVICE_NUMBER, NULL, 0,
        &number, sizeof(number), &returned, NULL)) { Error(L"device number"); return 0; }
    if (returned != sizeof(number) || number.DeviceType != FILE_DEVICE_DISK || number.DeviceNumber != expectedNumber) {
        fputs("Unexpected physical disk mapping\n", stderr); return 0;
    }
    if (!DeviceIoControl(disk, IOCTL_DISK_GET_LENGTH_INFO, NULL, 0,
        &length, sizeof(length), &returned, NULL)) { Error(L"disk length"); return 0; }
    if (returned != sizeof(length) || length.Length.QuadPart <= 0) {
        fputs("Invalid disk length\n", stderr); return 0;
    }
    printf("Physical disk=%lu length=%llu bytes\n", number.DeviceNumber,
           (unsigned long long)length.Length.QuadPart);
    return 1;
}

static HANDLE OpenControl(void)
{
    return CreateFileW(L"\\\\.\\StorageFilterCtl", GENERIC_READ,
                       FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
}
static int ProfileCall(DWORD code, const void *input, DWORD inputSize, SF_SERIAL_STATUS *status, int quiet)
{
    DWORD returned = 0, error;
    BOOL ok;
    HANDLE control = CreateFileW(L"\\\\.\\StorageFilterCtl",
        code == SF_IOCTL_SERIAL_SET ? GENERIC_READ | GENERIC_WRITE : GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (control == INVALID_HANDLE_VALUE) { if (!quiet) Error(L"profile control"); return 0; }
    ZeroMemory(status, sizeof(*status));
    ok = DeviceIoControl(control, code, (void *)input, inputSize, status, sizeof(*status), &returned, NULL);
    error = GetLastError(); CloseHandle(control);
    if (!ok) { SetLastError(error); if (!quiet) Error(L"serial profile"); return 0; }
    if (returned != sizeof(*status) || status->Version != SF_PROTOCOL_VERSION || status->Size != sizeof(*status)) {
        fputs("Serial profile ABI mismatch\n", stderr); return 0;
    }
    return 1;
}
static int StatusForDisk(DWORD disk, SF_SERIAL_STATUS *status)
{
    SF_SNAPSHOT snapshot;
    SF_SERIAL_TARGET target;
    SF_SERIAL_STATUS candidate;
    DWORD i, matches = 0;
    if (!Snapshot(&snapshot, 0)) return 0;
    if (snapshot.RecordsReturned != snapshot.DeviceCount) {
        fputs("Too many filter instances for an unambiguous control snapshot\n", stderr); return 0;
    }
    ZeroMemory(&target, sizeof(target));
    target.Version = SF_PROTOCOL_VERSION; target.Size = sizeof(target); target.DiskNumber = disk;
    for (i = 0; i < snapshot.RecordsReturned; ++i) {
        target.Instance = snapshot.Devices[i].Instance;
        if (ProfileCall(SF_IOCTL_SERIAL_STATUS, &target, sizeof(target), &candidate, 1)) {
            *status = candidate; ++matches;
        }
    }
    if (matches != 1) { fputs("Disk does not map to exactly one visible filter instance\n", stderr); return 0; }
    return 1;
}
static void PrintProfile(const SF_SERIAL_STATUS *status)
{
    printf("serial instance=%lu disk=%lu enabled=%d capacity=%lu generation=%llu transformed=%llu skipped=%llu lastResult=%lu restricted=%d\n",
        (unsigned long)status->Instance, (unsigned long)status->DiskNumber,
        !!(status->Flags & SF_SERIAL_STATE_ENABLED), (unsigned long)status->OriginalCapacity,
        (unsigned long long)status->Generation, (unsigned long long)status->Transformed,
        (unsigned long long)status->Skipped, (unsigned long)status->LastResult,
        !!(status->Flags & SF_SERIAL_STATE_RESTRICTED));
}
static int SecondaryDisk(HANDLE disk, DWORD diskNumber)
{
    wchar_t windowsPath[MAX_PATH], root[MAX_PATH], volumeName[MAX_PATH];
    unsigned char *buffer = (unsigned char *)calloc(1, MAX_DESCRIPTOR);
    HANDLE volume = INVALID_HANDLE_VALUE;
    DWORD returned = 0, i, count;
    VOLUME_DISK_EXTENTS *extents;
    DRIVE_LAYOUT_INFORMATION_EX *layout;
    static const GUID efi = {0xc12a7328,0xf81f,0x11d2,{0xba,0x4b,0x00,0xa0,0xc9,0x3e,0xc9,0x3b}};
    int ok = 0;
    if (diskNumber == 0 || buffer == NULL) goto Done;
    count = GetSystemWindowsDirectoryW(windowsPath, _countof(windowsPath));
    if (count == 0 || count >= _countof(windowsPath) ||
        !GetVolumePathNameW(windowsPath, root, _countof(root)) ||
        !GetVolumeNameForVolumeMountPointW(root, volumeName, _countof(volumeName))) goto Done;
    count = (DWORD)wcslen(volumeName);
    if (count == 0 || volumeName[count - 1] != L'\\') goto Done;
    volumeName[count - 1] = L'\0';
    volume = CreateFileW(volumeName, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                         NULL, OPEN_EXISTING, 0, NULL);
    if (volume == INVALID_HANDLE_VALUE) goto Done;
    if (!DeviceIoControl(volume, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, NULL, 0,
        buffer, MAX_DESCRIPTOR, &returned, NULL) || returned < FIELD_OFFSET(VOLUME_DISK_EXTENTS, Extents)) goto Done;
    extents = (VOLUME_DISK_EXTENTS *)buffer;
    count = extents->NumberOfDiskExtents;
    if (count == 0 || count > (returned - FIELD_OFFSET(VOLUME_DISK_EXTENTS, Extents)) / sizeof(DISK_EXTENT)) goto Done;
    for (i = 0; i < count; ++i) if (extents->Extents[i].DiskNumber == diskNumber) goto Done;
    CloseHandle(volume); volume = INVALID_HANDLE_VALUE;
    ZeroMemory(buffer, MAX_DESCRIPTOR);
    if (!DeviceIoControl(disk, IOCTL_DISK_GET_DRIVE_LAYOUT_EX, NULL, 0,
        buffer, MAX_DESCRIPTOR, &returned, NULL) || returned < FIELD_OFFSET(DRIVE_LAYOUT_INFORMATION_EX, PartitionEntry)) goto Done;
    layout = (DRIVE_LAYOUT_INFORMATION_EX *)buffer;
    if (layout->PartitionCount > (returned - FIELD_OFFSET(DRIVE_LAYOUT_INFORMATION_EX, PartitionEntry)) / sizeof(PARTITION_INFORMATION_EX)) goto Done;
    for (i = 0; i < layout->PartitionCount; ++i) {
        PARTITION_INFORMATION_EX *p = &layout->PartitionEntry[i];
        if ((p->PartitionStyle == PARTITION_STYLE_MBR && p->Mbr.BootIndicator) ||
            (p->PartitionStyle == PARTITION_STYLE_GPT && memcmp(&p->Gpt.PartitionType, &efi, sizeof(efi)) == 0)) goto Done;
    }
    ok = 1;
Done:
    if (volume != INVALID_HANDLE_VALUE) CloseHandle(volume);
    free(buffer);
    if (!ok) fputs("Cannot confirm a secondary disk without Windows/EFI/active boot partitions; refusing activation\n", stderr);
    return ok;
}
static int MakeUpdate(SF_SERIAL_UPDATE *update, DWORD disk, DWORD instance, SF_U64 generation, const wchar_t *value)
{
    size_t i, length = value != NULL ? wcslen(value) : 0;
    ZeroMemory(update, sizeof(*update));
    update->Version = SF_PROTOCOL_VERSION; update->Size = sizeof(*update);
    update->DiskNumber = disk; update->Instance = instance;
    update->ExpectedGeneration = generation;
    if (value != NULL) {
        if (length == 0 || length >= SF_SERIAL_BYTES) return 0;
        update->Flags = SF_SERIAL_ENABLE | SF_SERIAL_ACK_SECONDARY; update->SerialLength = (SF_U32)length;
        for (i = 0; i < length; ++i) {
            if (value[i] > 127) return 0;
            update->Serial[i] = (unsigned char)value[i];
        }
    }
    return SfValidateSerialUpdate(update);
}
static int SerialCommand(const wchar_t *command, DWORD diskNumber, const wchar_t *value, const SF_U64 *generation, DWORD instance)
{
    HANDLE disk;
    BLOB original, expected, observed;
    SF_SERIAL_STATUS status, after;
    SF_SERIAL_UPDATE update, clear, stale;
    SF_SERIAL_SPAN span;
    DWORD i;
    int ok = 0, activated = 0, cycle = wcscmp(command, L"serial-test") == 0;
    ZeroMemory(&original, sizeof(original)); ZeroMemory(&expected, sizeof(expected));
    disk = OpenDisk(diskNumber);
    if (disk == INVALID_HANDLE_VALUE) { Error(L"serial disk"); return 0; }
    if (!DescribeDisk(disk, diskNumber) || !Query(disk, &original) || !StatusForDisk(diskNumber, &status)) goto Done;
    if (wcscmp(command, L"serial-status") == 0) { PrintProfile(&status); ok = 1; goto Done; }
    if ((generation != NULL && status.Generation != *generation) || (instance != 0 && status.Instance != instance)) {
        fputs("Profile instance or generation changed; request rejected\n", stderr); goto Done;
    }
    if (wcscmp(command, L"serial-expect") == 0) {
        /* Re-read between two status samples to reject concurrent profile changes. */
        if (!(status.Flags & SF_SERIAL_STATE_ENABLED) ||
            !MakeUpdate(&update, diskNumber, status.Instance, status.Generation, value)) goto Done;
        if (!Query(disk, &observed)) goto Done;
        ok = SfAnalyzeSerial(observed.Data, observed.Length, &span) == SF_TRANSFORM_OK &&
             span.Capacity == update.SerialLength &&
             memcmp(observed.Data + span.Offset, update.Serial, update.SerialLength) == 0;
        free(observed.Data);
        if (!StatusForDisk(diskNumber, &after) || after.Instance != status.Instance ||
            after.Generation != status.Generation || !(after.Flags & SF_SERIAL_STATE_ENABLED) ||
            after.Transformed <= status.Transformed || after.Skipped != status.Skipped) ok = 0;
        if (ok) PrintProfile(&after);
        else fputs("Serial response mismatch or profile changed\n", stderr);
        goto Done;
    }
    if (!MakeUpdate(&clear, diskNumber, status.Instance, status.Generation, NULL)) goto Done;
    if (wcscmp(command, L"serial-clear") == 0) {
        ok = ProfileCall(SF_IOCTL_SERIAL_SET, &clear, sizeof(clear), &status, 0);
        if (ok) { PrintProfile(&status); puts("Profile disabled; new completions retain lower-driver serial responses."); }
        goto Done;
    }
    if (!SecondaryDisk(disk, diskNumber) || !MakeUpdate(&update, diskNumber, status.Instance, status.Generation, value)) goto Done;
    if (status.Flags & SF_SERIAL_STATE_ENABLED) {
        fputs("Activation requires an initially disabled profile\n", stderr); goto Done;
    }
    expected.Length = original.Length; expected.Data = (unsigned char *)malloc(expected.Length);
    if (expected.Data == NULL) goto Done;
    memcpy(expected.Data, original.Data, expected.Length);
    if (SfAnalyzeSerial(expected.Data, expected.Length, &span) != SF_TRANSFORM_OK ||
        SfApplySerial(expected.Data, expected.Length, &span, update.Serial, update.SerialLength) != SF_TRANSFORM_OK) {
        fputs("Replacement does not fit a valid independent serial field\n", stderr); goto Done;
    }
    if (!ProfileCall(SF_IOCTL_SERIAL_SET, &update, sizeof(update), &status, 0)) goto Done;
    clear.ExpectedGeneration = status.Generation;
    activated = 1; ok = 1;
    if (cycle) {
        /* Exercise the kernel CAS check, bypassing the CLI's preliminary check. */
        stale = clear; stale.ExpectedGeneration ^= 1u;
        if (ProfileCall(SF_IOCTL_SERIAL_SET, &stale, sizeof(stale), &after, 1) ||
            GetLastError() != ERROR_REVISION_MISMATCH) {
            fputs("Kernel accepted stale profile generation or returned an unexpected status\n", stderr);
            ok = 0; goto Done;
        }
    }
    for (i = 0; i < (cycle ? 64u : 1u); ++i) {
        if (!Query(disk, &observed)) { ok = 0; break; }
        if (!SameIdentifiers(&expected, &observed)) ok = 0;
        free(observed.Data);
        if (!ok) break;
    }
    if (!StatusForDisk(diskNumber, &after) || after.Transformed < status.Transformed + (cycle ? 64u : 1u) ||
        after.Skipped != status.Skipped || after.Generation != status.Generation || !(after.Flags & SF_SERIAL_STATE_ENABLED)) ok = 0;
    else PrintProfile(&after);
Done:
    if (activated && (cycle || !ok)) {
        int restored = ProfileCall(SF_IOCTL_SERIAL_SET, &clear, sizeof(clear), &status, 0);
        if (restored && cycle) {
            restored = Query(disk, &observed);
            if (restored) { restored = SameIdentifiers(&original, &observed); free(observed.Data); }
        }
        if (!restored) { fputs("RESTORATION FAILED: run serial-clear and inspect the device\n", stderr); ok = 0; }
    }
    free(original.Data); free(expected.Data); CloseHandle(disk);
    if (cycle) printf("Serial transformation/restore: %s\n", ok ? "PASS" : "FAIL");
    return ok;
}
static int Snapshot(SF_SNAPSHOT *snapshot, int print)
{
    DWORD returned = 0, i;
    HANDLE control = OpenControl();
    BOOL success;
    DWORD error;
    if (control == INVALID_HANDLE_VALUE) { Error(L"open filter control"); return 0; }
    ZeroMemory(snapshot, sizeof(*snapshot));
    success = DeviceIoControl(control, SF_IOCTL_SNAPSHOT, NULL, 0,
        snapshot, sizeof(*snapshot), &returned, NULL);
    error = GetLastError();
    CloseHandle(control);
    if (!success) { SetLastError(error); Error(L"snapshot"); return 0; }
    if (returned != sizeof(*snapshot) || snapshot->Version != SF_PROTOCOL_VERSION ||
        snapshot->Size != sizeof(*snapshot) || snapshot->RecordsReturned > SF_MAX_DEVICES ||
        snapshot->RecordsReturned > snapshot->DeviceCount) {
        fputs("Control protocol mismatch\n", stderr); return 0;
    }
    if (print) {
        printf("devices=%lu returned=%lu registryStatus=0x%08lx registryEvents=%llu\n",
            (unsigned long)snapshot->DeviceCount, (unsigned long)snapshot->RecordsReturned,
            (unsigned long)(DWORD)snapshot->RegistryCallbackStatus,
            (unsigned long long)snapshot->RegistryEvents);
        for (i = 0; i < snapshot->RecordsReturned; ++i) {
            SF_DEVICE_RECORD *r = &snapshot->Devices[i];
            printf("instance=%lu state=0x%lx completed=%llu failed=%llu malformed=%llu skipped=%lu lastStatus=0x%08lx flags=0x%lx busStatus=0x%08lx removalStatus=0x%08lx\n",
                (unsigned long)r->Instance, (unsigned long)r->State,
                (unsigned long long)r->QueriesCompleted, (unsigned long long)r->QueryFailures,
                (unsigned long long)r->MalformedResponses, (unsigned long)r->ObservationsSkipped,
                (unsigned long)(DWORD)r->LastQueryStatus, (unsigned long)r->Descriptor.Flags,
                (unsigned long)(DWORD)r->BusPropertyStatus, (unsigned long)(DWORD)r->RemovalPropertyStatus);
        }
    }
    return 1;
}
static int SaveBlob(const wchar_t *path, const BLOB *blob)
{
    DWORD written = 0;
    HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    BOOL success;
    if (file == INVALID_HANDLE_VALUE) { Error(L"create baseline (will not overwrite)"); return 0; }
    success = WriteFile(file, blob->Data, blob->Length, &written, NULL);
    CloseHandle(file);
    if (!success || written != blob->Length) { Error(L"write baseline"); DeleteFileW(path); return 0; }
    return 1;
}
static int LoadBlob(const wchar_t *path, BLOB *blob)
{
    LARGE_INTEGER size;
    DWORD read = 0;
    SF_DESCRIPTOR_INFO info;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    blob->Data = NULL; blob->Length = 0;
    if (file == INVALID_HANDLE_VALUE) { Error(L"open baseline"); return 0; }
    if (!GetFileSizeEx(file, &size) || size.QuadPart < 36 || size.QuadPart > MAX_DESCRIPTOR) {
        CloseHandle(file); fputs("Invalid baseline size\n", stderr); return 0;
    }
    blob->Length = (DWORD)size.QuadPart; blob->Data = (unsigned char *)malloc(blob->Length);
    if (blob->Data == NULL) { CloseHandle(file); return 0; }
    if (!ReadFile(file, blob->Data, blob->Length, &read, NULL) || read != blob->Length) {
        CloseHandle(file); free(blob->Data); blob->Data = NULL; return 0;
    }
    CloseHandle(file); SfInspectDescriptor(blob->Data, blob->Length, &info);
    if (info.Flags & BAD_FLAGS) { free(blob->Data); blob->Data = NULL; return 0; }
    return 1;
}
static unsigned __stdcall Worker(void *argument)
{
    WORK *work = argument;
    HANDLE disk = OpenDisk(work->Disk);
    DWORD i;
    if (disk == INVALID_HANDLE_VALUE) { Error(L"worker disk"); work->Failures = 1; return 1; }
    for (i = 0; i < work->Iterations; ++i) {
        BLOB value;
        if (!Query(disk, &value)) { ++work->Failures; break; }
        if (!SameIdentifiers(work->Baseline, &value)) ++work->Failures;
        free(value.Data);
        if (work->Failures) break;
    }
    CloseHandle(disk); return work->Failures ? 1 : 0;
}
static int Stress(DWORD diskNumber, DWORD threadCount, DWORD iterations)
{
    HANDLE threads[32], disk;
    WORK work[32];
    BLOB baseline;
    SF_SNAPSHOT before, after;
    DWORD i, created = 0;
    int success = 1;
    if (!Snapshot(&before, 0) || before.DeviceCount != 1 || before.RecordsReturned != 1 ||
        !(before.Devices[0].State & SF_STATE_STARTED)) {
        fputs("Stress requires exactly one started lab filter instance\n", stderr); return 0;
    }
    disk = OpenDisk(diskNumber);
    if (disk == INVALID_HANDLE_VALUE) { Error(L"stress disk"); return 0; }
    success = Query(disk, &baseline); CloseHandle(disk);
    if (!success) return 0;
    ZeroMemory(work, sizeof(work));
    for (i = 0; i < threadCount; ++i) {
        work[i].Disk = diskNumber; work[i].Iterations = iterations; work[i].Baseline = &baseline;
        threads[i] = (HANDLE)_beginthreadex(NULL, 0, Worker, &work[i], 0, NULL);
        if (threads[i] == NULL) { fprintf(stderr, "_beginthreadex: %s\n", strerror(errno)); success = 0; break; }
        ++created;
    }
    for (i = 0; i < created; ++i) {
        if (WaitForSingleObject(threads[i], INFINITE) != WAIT_OBJECT_0) {
            /* Do not free worker data while an unjoined thread may still use it. */
            Error(L"worker wait"); ExitProcess(1);
        }
        if (work[i].Failures) success = 0;
        CloseHandle(threads[i]);
    }
    free(baseline.Data);
    if (!Snapshot(&after, 1)) return 0;
    if (after.DeviceCount != 1 || after.RecordsReturned != 1 ||
        after.Devices[0].Instance != before.Devices[0].Instance ||
        after.Devices[0].QueriesCompleted < before.Devices[0].QueriesCompleted ||
        after.Devices[0].QueriesCompleted - before.Devices[0].QueriesCompleted <
            2ull * threadCount * iterations ||
        after.Devices[0].MalformedResponses != before.Devices[0].MalformedResponses ||
        after.Devices[0].ObservationsSkipped != before.Devices[0].ObservationsSkipped ||
        after.Devices[0].QueryFailures != before.Devices[0].QueryFailures) success = 0;
    printf("Stress: threads=%lu iterations=%lu result=%s\n", threadCount, iterations, success ? "PASS" : "FAIL");
    return success;
}
static int ExpectFailure(HANDLE device, DWORD code, void *input, DWORD inputSize,
                         void *output, DWORD outputSize, DWORD expected)
{
    DWORD returned = 0, error;
    BOOL ok = DeviceIoControl(device, code, input, inputSize, output, outputSize, &returned, NULL);
    error = GetLastError();
    if (ok || (expected != 0 && error != expected)) {
        fprintf(stderr, "Unexpected result code=0x%lx success=%d error=%lu\n", code, ok, error); return 0;
    }
    printf("Rejected IOCTL 0x%lx error=%lu\n", code, error); return 1;
}
static int Negative(DWORD number, int controlMode)
{
    HANDLE device = controlMode ? OpenControl() : OpenDisk(number);
    SF_SNAPSHOT snapshot;
    STORAGE_PROPERTY_QUERY query;
    DWORD junk = 0;
    int success;
    if (device == INVALID_HANDLE_VALUE) { Error(L"negative open"); return 0; }
    ZeroMemory(&query, sizeof(query)); query.PropertyId = StorageDeviceProperty;
    query.QueryType = PropertyStandardQuery;
    if (controlMode) {
        success = ExpectFailure(device, SF_IOCTL_SNAPSHOT, NULL, 0, &snapshot, sizeof(snapshot) - 1, ERROR_INSUFFICIENT_BUFFER);
        success &= ExpectFailure(device, SF_IOCTL_SNAPSHOT, &junk, sizeof(junk), &snapshot, sizeof(snapshot), ERROR_INVALID_PARAMETER);
        success &= ExpectFailure(device, SF_IOCTL_SNAPSHOT + 4, NULL, 0, &snapshot, sizeof(snapshot), ERROR_INVALID_FUNCTION);
    } else {
        /* Lower storage driver decides exact error codes; only failure is required. */
        success = ExpectFailure(device, IOCTL_STORAGE_QUERY_PROPERTY, &query, 1, &snapshot, sizeof(snapshot), 0);
        success &= ExpectFailure(device, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), &snapshot, 1, 0);
    }
    CloseHandle(device); return success;
}
static int SerialNegative(void)
{
    SF_SERIAL_UPDATE update;
    SF_SERIAL_STATUS output;
    HANDLE control, readOnly;
    int ok;
    control = CreateFileW(L"\\\\.\\StorageFilterCtl", GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (control == INVALID_HANDLE_VALUE) { Error(L"serial negative control"); return 0; }
    ZeroMemory(&update, sizeof(update));
    update.Version = SF_PROTOCOL_VERSION; update.Size = sizeof(update);
    update.Instance = 1; update.DiskNumber = 1; update.Reserved = 1;
    ok = ExpectFailure(control, SF_IOCTL_SERIAL_SET, &update, sizeof(update), &output, sizeof(output), ERROR_INVALID_PARAMETER);
    ok &= ExpectFailure(control, SF_IOCTL_SERIAL_SET, &update, sizeof(update) - 1, &output, sizeof(output), ERROR_INVALID_PARAMETER);
    update.Reserved = 0; update.Version = SF_PROTOCOL_VERSION + 1;
    ok &= ExpectFailure(control, SF_IOCTL_SERIAL_SET, &update, sizeof(update), &output, sizeof(output), ERROR_INVALID_PARAMETER);
    CloseHandle(control);
    readOnly = OpenControl();
    if (readOnly == INVALID_HANDLE_VALUE) return 0;
    ok &= ExpectFailure(readOnly, SF_IOCTL_SERIAL_SET, &update, sizeof(update), &output, sizeof(output), ERROR_ACCESS_DENIED);
    CloseHandle(readOnly); return ok;
}
int wmain(int argc, wchar_t **argv)
{
    DWORD diskNumber = 0, threads = 0, iterations = 0;
    HANDLE disk;
    BLOB value, baseline;
    SF_SNAPSHOT snapshot;
    SF_DESCRIPTOR_INFO info;
    int success;
    SF_U64 generation;
    DWORD profileInstance = 0;
    if (argc == 2 && wcscmp(argv[1], L"snapshot") == 0) return Snapshot(&snapshot, 1) ? 0 : 1;
    if (argc == 2 && wcscmp(argv[1], L"control-negative") == 0) return Negative(0, 1) ? 0 : 1;
    if (argc == 2 && wcscmp(argv[1], L"serial-negative") == 0) return SerialNegative() ? 0 : 1;
    if (argc == 2 && wcscmp(argv[1], L"access-denied") == 0) {
        DWORD error;
        disk = OpenControl(); error = GetLastError();
        if (disk != INVALID_HANDLE_VALUE) { CloseHandle(disk); fputs("Access unexpectedly granted\n", stderr); return 1; }
        if (error != ERROR_ACCESS_DENIED) { SetLastError(error); Error(L"Expected access denied"); return 1; }
        puts("PASS: standard user denied"); return 0;
    }
    if (argc < 3 || !Number(argv[2], 1024, &diskNumber)) goto Usage;
    if (argc == 3 && diskNumber != 0 &&
        (wcscmp(argv[1], L"serial-status") == 0 || wcscmp(argv[1], L"serial-clear") == 0))
        return SerialCommand(argv[1], diskNumber, NULL, NULL, 0) ? 0 : 1;
    if (diskNumber != 0 && wcscmp(argv[1], L"serial-clear") == 0) {
        if (!ProfileOptions(argc, argv, 3, &generation, &profileInstance)) goto Usage;
        return SerialCommand(argv[1], diskNumber, NULL, argc > 3 ? &generation : NULL, profileInstance) ? 0 : 1;
    }
    if (argc >= 4 && diskNumber != 0 && wcscmp(argv[1], L"serial-expect") == 0) {
        if (!ProfileOptions(argc, argv, 4, &generation, &profileInstance)) goto Usage;
        return SerialCommand(argv[1], diskNumber, argv[3], argc > 4 ? &generation : NULL, profileInstance) ? 0 : 1;
    }
    if (argc >= 5 && diskNumber != 0 && wcscmp(argv[4], L"--secondary") == 0 &&
        (wcscmp(argv[1], L"serial-set") == 0 || wcscmp(argv[1], L"serial-test") == 0))
    {
        if (!ProfileOptions(argc, argv, 5, &generation, &profileInstance)) goto Usage;
        return SerialCommand(argv[1], diskNumber, argv[3], argc > 5 ? &generation : NULL, profileInstance) ? 0 : 1;
    }
    if (argc == 5 && wcscmp(argv[1], L"stress") == 0) {
        if (!Number(argv[3], 32, &threads) || !threads ||
            !Number(argv[4], 100000, &iterations) || !iterations) goto Usage;
        return Stress(diskNumber, threads, iterations) ? 0 : 1;
    }
    if (argc == 3 && wcscmp(argv[1], L"negative") == 0) return Negative(diskNumber, 0) ? 0 : 1;
    if (!((argc == 3 && wcscmp(argv[1], L"query") == 0) ||
          (argc == 4 && (wcscmp(argv[1], L"baseline") == 0 || wcscmp(argv[1], L"compare") == 0)))) goto Usage;
    disk = OpenDisk(diskNumber);
    if (disk == INVALID_HANDLE_VALUE) { Error(L"open disk"); return 1; }
    success = DescribeDisk(disk, diskNumber);
    if (success) success = Query(disk, &value);
    CloseHandle(disk);
    if (!success) return 1;
    if (wcscmp(argv[1], L"baseline") == 0) success = SaveBlob(argv[3], &value);
    else if (wcscmp(argv[1], L"compare") == 0) {
        success = LoadBlob(argv[3], &baseline);
        if (success) { success = SameIdentifiers(&baseline, &value); free(baseline.Data); }
        printf("Identifier comparison: %s\n", success ? "PASS" : "FAIL");
    } else {
        SfInspectDescriptor(value.Data, value.Length, &info);
        printf("Descriptor: bytes=%lu bus=%lu removable=%lu stringPresence=0x%lx flags=0x%lx\n",
            value.Length, (unsigned long)info.BusType, (unsigned long)info.Removable,
            (unsigned long)info.StringPresence, (unsigned long)info.Flags);
    }
    free(value.Data); return success ? 0 : 1;
Usage:
    fputs("Checker query <disk>\nChecker baseline <disk> <new-file>\nChecker compare <disk> <file>\nChecker stress <disk> <threads 1..32> <iterations 1..100000>\nChecker negative <disk>\nChecker snapshot | control-negative | access-denied | serial-negative\nChecker serial-status <secondary-disk>\nChecker serial-set <secondary-disk> <ASCII-serial> --secondary [--generation <n> [--instance <n>]]\nChecker serial-clear <secondary-disk> [--generation <n> [--instance <n>]]\nChecker serial-expect <secondary-disk> <ASCII-serial> [--generation <n> [--instance <n>]]\nChecker serial-test <secondary-disk> <ASCII-serial> --secondary [--generation <n> [--instance <n>]]\n", stderr);
    return 2;
}

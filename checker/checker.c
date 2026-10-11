#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <string.h>
#include "../shared/descriptor.h"
#define MAX_DESCRIPTOR 65536u
#define BAD_FLAGS (SF_PARSE_BAD_SIZE | SF_PARSE_BAD_OFFSET | SF_PARSE_UNTERMINATED | SF_PARSE_BAD_RAW_LENGTH | SF_PARSE_TOO_SHORT | SF_PARSE_HEADER_ONLY | SF_PARSE_TRUNCATED)
typedef struct BLOB { unsigned char *Data; DWORD Length; } BLOB;
typedef struct WORK { DWORD Disk, Iterations; const BLOB *Baseline; LONG Failures; } WORK;
static void Error(const wchar_t *operation)
{
    fwprintf(stderr, L"%ls: Win32 error %lu\n", operation, GetLastError());
}
static int Number(const wchar_t *text, DWORD max, DWORD *result)
{
    wchar_t *end;
    unsigned long value;
    if (!text[0] || text[0] < L'0' || text[0] > L'9') return 0;
    value = wcstoul(text, &end, 10);
    if (*end != L'\0' || value > max) return 0;
    *result = (DWORD)value; return 1;
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
static HANDLE OpenControl(void)
{
    return CreateFileW(L"\\\\.\\StorageFilterCtl", GENERIC_READ,
                       FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
}
static int Snapshot(SF_SNAPSHOT *snapshot, int print)
{
    DWORD returned = 0, i;
    HANDLE control = OpenControl();
    BOOL success;
    if (control == INVALID_HANDLE_VALUE) { Error(L"open filter control"); return 0; }
    ZeroMemory(snapshot, sizeof(*snapshot));
    success = DeviceIoControl(control, SF_IOCTL_SNAPSHOT, NULL, 0,
        snapshot, sizeof(*snapshot), &returned, NULL);
    CloseHandle(control);
    if (!success) { Error(L"snapshot"); return 0; }
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
static DWORD WINAPI Worker(LPVOID argument)
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
        threads[i] = CreateThread(NULL, 0, Worker, &work[i], 0, NULL);
        if (threads[i] == NULL) { Error(L"CreateThread"); success = 0; break; }
        ++created;
    }
    for (i = 0; i < created; ++i) {
        if (WaitForSingleObject(threads[i], INFINITE) != WAIT_OBJECT_0) success = 0;
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
int wmain(int argc, wchar_t **argv)
{
    DWORD diskNumber = 0, threads = 0, iterations = 0;
    HANDLE disk;
    BLOB value, baseline;
    SF_SNAPSHOT snapshot;
    SF_DESCRIPTOR_INFO info;
    int success;
    if (argc == 2 && wcscmp(argv[1], L"snapshot") == 0) return Snapshot(&snapshot, 1) ? 0 : 1;
    if (argc == 2 && wcscmp(argv[1], L"control-negative") == 0) return Negative(0, 1) ? 0 : 1;
    if (argc == 2 && wcscmp(argv[1], L"access-denied") == 0) {
        DWORD error;
        disk = OpenControl(); error = GetLastError();
        if (disk != INVALID_HANDLE_VALUE) { CloseHandle(disk); fputs("Access unexpectedly granted\n", stderr); return 1; }
        if (error != ERROR_ACCESS_DENIED) { SetLastError(error); Error(L"Expected access denied"); return 1; }
        puts("PASS: standard user denied"); return 0;
    }
    if (argc < 3 || !Number(argv[2], 1024, &diskNumber)) goto Usage;
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
    success = Query(disk, &value); CloseHandle(disk);
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
    fputs("Checker query <disk>\nChecker baseline <disk> <new-file>\nChecker compare <disk> <file>\nChecker stress <disk> <threads 1..32> <iterations 1..100000>\nChecker negative <disk>\nChecker snapshot | control-negative | access-denied\n", stderr);
    return 2;
}

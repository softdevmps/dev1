#ifndef SF_PROTOCOL_H
#define SF_PROTOCOL_H
/* Fixed-width wire layout. Original storage identifiers are never exported. */
#ifdef SF_KERNEL
#include <ntddk.h>
typedef ULONG SF_U32;
typedef LONG SF_I32;
typedef ULONGLONG SF_U64;
#else
#include <stdint.h>
typedef uint32_t SF_U32;
typedef int32_t SF_I32;
typedef uint64_t SF_U64;
#endif
#define SF_PROTOCOL_VERSION 1u
#define SF_MAX_DEVICES 16u
#define SF_DEVICE_TYPE 0x8337u
/* METHOD_BUFFERED, FILE_READ_DATA; private vendor function. */
#define SF_IOCTL_SNAPSHOT ((SF_DEVICE_TYPE << 16) | (1u << 14) | (0x800u << 2))
#define SF_IOCTL_SERIAL_SET ((SF_DEVICE_TYPE << 16) | (3u << 14) | (0x801u << 2))
#define SF_IOCTL_SERIAL_STATUS ((SF_DEVICE_TYPE << 16) | (1u << 14) | (0x802u << 2))
#define SF_SERIAL_BYTES 32u
#define SF_SERIAL_ORIGINAL_LIMIT 255u
#define SF_SERIAL_ENABLE 1u
#define SF_SERIAL_ACK_SECONDARY 2u
#define SF_SERIAL_STATE_ENABLED 1u
#define SF_SERIAL_STATE_MAPPED 2u
#define SF_SERIAL_STATE_RESTRICTED 4u
#define SF_PARSE_HEADER_ONLY 1u
#define SF_PARSE_TRUNCATED 2u
#define SF_PARSE_BAD_SIZE 4u
#define SF_PARSE_BAD_OFFSET 8u
#define SF_PARSE_UNTERMINATED 16u
#define SF_PARSE_BAD_RAW_LENGTH 32u
#define SF_PARSE_TOO_SHORT 64u
#define SF_PARSE_BAD_VERSION 128u
#define SF_STATE_STARTED 1u
#define SF_STATE_SURPRISE_REMOVED 2u
#define SF_STATE_USAGE_RESTRICTED 4u
#pragma pack(push, 8)
typedef struct SF_SERIAL_TARGET {
    SF_U32 Version, Size, Instance, DiskNumber;
} SF_SERIAL_TARGET;
typedef struct SF_SERIAL_UPDATE {
    SF_U32 Version, Size, Instance, DiskNumber;
    SF_U32 Flags, SerialLength, Reserved;
    unsigned char Serial[SF_SERIAL_BYTES]; /* Supplied replacement, never firmware data. */
    SF_U64 ExpectedGeneration; /* Compare-and-set; never overwrite a newer profile. */
} SF_SERIAL_UPDATE;
typedef struct SF_SERIAL_STATUS {
    SF_U32 Version, Size, Instance, DiskNumber;
    SF_U32 Flags, SerialLength, OriginalCapacity, LastResult;
    SF_U64 Generation, Transformed, Skipped;
} SF_SERIAL_STATUS;
typedef struct SF_DESCRIPTOR_INFO {
    SF_U32 Flags;
    SF_U32 DeclaredSize;
    SF_U32 BusType;
    SF_U32 Removable;
    SF_U32 StringPresence; /* Bits: vendor, product, revision, serial; values omitted. */
} SF_DESCRIPTOR_INFO;
typedef struct SF_DEVICE_RECORD {
    SF_U32 Instance;
    SF_U32 State;
    SF_U64 QueriesCompleted;
    SF_U64 QueryFailures;
    SF_U64 MalformedResponses;
    SF_I32 LastQueryStatus;
    SF_U32 LastReturnedBytes;
    SF_DESCRIPTOR_INFO Descriptor;
    SF_I32 BusPropertyStatus;
    SF_I32 RemovalPropertyStatus;
    SF_U32 RemovalPolicy;
    unsigned char BusTypeGuid[16];
    SF_U32 ObservationsSkipped;
} SF_DEVICE_RECORD;
typedef struct SF_SNAPSHOT {
    SF_U32 Version;
    SF_U32 Size;
    SF_U32 DeviceCount; /* Total attached; RecordsReturned can be smaller. */
    SF_U32 RecordsReturned;
    SF_U64 RegistryEvents;
    SF_I32 RegistryCallbackStatus;
    SF_U32 Reserved;
    SF_DEVICE_RECORD Devices[SF_MAX_DEVICES];
} SF_SNAPSHOT;
#pragma pack(pop)
/* Fail the build if a compiler changes the kernel/user wire ABI. */
typedef char SF_ASSERT_RECORD_SIZE[(sizeof(SF_DEVICE_RECORD) == 96) ? 1 : -1];
typedef char SF_ASSERT_SNAPSHOT_SIZE[(sizeof(SF_SNAPSHOT) == 1568) ? 1 : -1];
typedef char SF_ASSERT_SERIAL_TARGET[(sizeof(SF_SERIAL_TARGET) == 16) ? 1 : -1];
typedef char SF_ASSERT_SERIAL_UPDATE[(sizeof(SF_SERIAL_UPDATE) == 72) ? 1 : -1];
typedef char SF_ASSERT_SERIAL_STATUS[(sizeof(SF_SERIAL_STATUS) == 56) ? 1 : -1];
#endif

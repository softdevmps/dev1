#ifndef SF_PROTOCOL_H
#define SF_PROTOCOL_H
/* Fixed-width wire layout: contains no pointers and no storage identifiers. */
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
#define SF_PARSE_HEADER_ONLY 1u
#define SF_PARSE_TRUNCATED 2u
#define SF_PARSE_BAD_SIZE 4u
#define SF_PARSE_BAD_OFFSET 8u
#define SF_PARSE_UNTERMINATED 16u
#define SF_PARSE_BAD_RAW_LENGTH 32u
#define SF_PARSE_TOO_SHORT 64u
#define SF_STATE_STARTED 1u
#define SF_STATE_SURPRISE_REMOVED 2u
#pragma pack(push, 8)
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
#endif

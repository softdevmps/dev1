#include "transform.h"
static SF_U32 Read32(const unsigned char *p)
{
    return (SF_U32)p[0] | ((SF_U32)p[1] << 8) |
           ((SF_U32)p[2] << 16) | ((SF_U32)p[3] << 24);
}
static int ValidText(const unsigned char *text, SF_U32 length)
{
    SF_U32 i;
    if (text == 0 || length == 0 || length >= SF_SERIAL_BYTES) return 0;
    for (i = 0; i < length; ++i) {
        unsigned char c = text[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '-' || c == '_')) return 0;
    }
    return 1;
}
int SfValidateSerialUpdate(const SF_SERIAL_UPDATE *update)
{
    SF_U32 i;
    if (update == 0 || update->Version != SF_PROTOCOL_VERSION ||
        update->Size != sizeof(*update) || update->Instance == 0 ||
        update->DiskNumber == 0 || update->DiskNumber > 1024 || update->Reserved != 0) return 0;
    if (update->Flags == 0) {
        if (update->SerialLength != 0) return 0;
    } else if (update->Flags != (SF_SERIAL_ENABLE | SF_SERIAL_ACK_SECONDARY) ||
               !ValidText(update->Serial, update->SerialLength)) return 0;
    for (i = update->SerialLength; i < SF_SERIAL_BYTES; ++i)
        if (update->Serial[i] != 0) return 0;
    return 1;
}
SF_U32 SfAnalyzeSerial(const unsigned char *data, SF_U32 length, SF_SERIAL_SPAN *span)
{
    SF_DESCRIPTOR_INFO info;
    SF_U32 offset, end, i, other, otherEnd, raw;
    if (span == 0) return SF_TRANSFORM_BAD_DESCRIPTOR;
    span->Offset = 0; span->Capacity = 0;
    if (length > 65536u) return SF_TRANSFORM_BAD_DESCRIPTOR;
    SfInspectDescriptor(data, length, &info);
    if (info.Flags != 0) return SF_TRANSFORM_BAD_DESCRIPTOR;
    offset = Read32(data + 24);
    if (offset == 0) return SF_TRANSFORM_NO_SERIAL;
    for (end = offset; end < info.DeclaredSize && data[end] != 0; ++end) { }
    if (end == offset) return SF_TRANSFORM_NO_SERIAL;
    if (end - offset > SF_SERIAL_ORIGINAL_LIMIT) return SF_TRANSFORM_TOO_LONG;
    raw = Read32(data + 32);
    if (raw != 0 && offset < 36u + raw) return SF_TRANSFORM_OVERLAP;
    for (i = 0; i < 3; ++i) {
        other = Read32(data + 12 + 4 * i);
        if (other == 0) continue;
        for (otherEnd = other; otherEnd < info.DeclaredSize && data[otherEnd] != 0; ++otherEnd) { }
        /* Include terminators in both spans. */
        if (offset <= otherEnd && other <= end) return SF_TRANSFORM_OVERLAP;
    }
    span->Offset = offset; span->Capacity = end - offset;
    return SF_TRANSFORM_OK;
}
SF_U32 SfApplySerial(unsigned char *data, SF_U32 length, const SF_SERIAL_SPAN *span,
                     const unsigned char *serial, SF_U32 serialLength)
{
    SF_U32 i;
    if (data == 0 || span == 0 || span->Offset < 36u || span->Offset >= length ||
        span->Capacity == 0 || span->Capacity > SF_SERIAL_ORIGINAL_LIMIT ||
        span->Capacity >= length - span->Offset || data[span->Offset + span->Capacity] != 0)
        return SF_TRANSFORM_BAD_DESCRIPTOR;
    if (!ValidText(serial, serialLength)) return SF_TRANSFORM_INVALID_PROFILE;
    if (serialLength > span->Capacity) return SF_TRANSFORM_TOO_LONG;
    /* Validate completely before any write. Erase the old serial's tail too. */
    for (i = 0; i <= span->Capacity; ++i) data[span->Offset + i] = 0;
    for (i = 0; i < serialLength; ++i) data[span->Offset + i] = serial[i];
    return SF_TRANSFORM_OK;
}

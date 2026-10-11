#include "descriptor.h"
static SF_U32 Read32(const unsigned char *p)
{
    return (SF_U32)p[0] | ((SF_U32)p[1] << 8) |
           ((SF_U32)p[2] << 16) | ((SF_U32)p[3] << 24);
}
void SfInspectDescriptor(const unsigned char *data, SF_U32 length,
                         SF_DESCRIPTOR_INFO *info)
{
    SF_U32 limit, i, offset, j;
    info->Flags = 0; info->DeclaredSize = 0; info->BusType = 0;
    info->Removable = 0; info->StringPresence = 0;
    if (data == 0 || length < 8) { info->Flags = SF_PARSE_TOO_SHORT; return; }
    info->DeclaredSize = Read32(data + 4);
    if (info->DeclaredSize < 36) { info->Flags = SF_PARSE_BAD_SIZE; return; }
    if (length < info->DeclaredSize) info->Flags |= SF_PARSE_TRUNCATED;
    limit = length < info->DeclaredSize ? length : info->DeclaredSize;
    if (limit < 36) { info->Flags |= SF_PARSE_HEADER_ONLY; return; }
    info->BusType = Read32(data + 28);
    info->Removable = data[10] != 0;
    if (Read32(data + 32) > info->DeclaredSize - 36)
        info->Flags |= SF_PARSE_BAD_RAW_LENGTH;
    for (i = 0; i < 4; ++i) {
        offset = Read32(data + 12 + 4 * i);
        if (offset == 0) continue;
        if (offset < 36 || offset >= info->DeclaredSize) {
            info->Flags |= SF_PARSE_BAD_OFFSET; continue;
        }
        if (offset >= limit) { info->Flags |= SF_PARSE_TRUNCATED; continue; }
        for (j = offset; j < limit && data[j] != 0; ++j) { }
        if (j == limit) {
            if (limit < info->DeclaredSize) info->Flags |= SF_PARSE_TRUNCATED;
            else info->Flags |= SF_PARSE_UNTERMINATED;
        } else info->StringPresence |= 1u << i;
    }
}

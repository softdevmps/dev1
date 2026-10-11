#ifndef SF_DESCRIPTOR_H
#define SF_DESCRIPTOR_H
#include "protocol.h"
/* Byte-wise parser accepts unaligned data. Never reads beyond Length. */
void SfInspectDescriptor(const unsigned char *Data, SF_U32 Length,
                         SF_DESCRIPTOR_INFO *Info);
#endif

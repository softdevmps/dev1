#ifndef SF_TRANSFORM_H
#define SF_TRANSFORM_H
#include "descriptor.h"
#define SF_TRANSFORM_OK 0u
#define SF_TRANSFORM_BAD_DESCRIPTOR 1u
#define SF_TRANSFORM_NO_SERIAL 2u
#define SF_TRANSFORM_TOO_LONG 3u
#define SF_TRANSFORM_OVERLAP 4u
#define SF_TRANSFORM_INVALID_PROFILE 5u
#define SF_TRANSFORM_NOT_ACTIVE 6u
typedef struct SF_SERIAL_SPAN {
    SF_U32 Offset, Capacity;
} SF_SERIAL_SPAN;
int SfValidateSerialUpdate(const SF_SERIAL_UPDATE *Update);
/* Analysis never writes; rejects overlap with other strings and raw properties. */
SF_U32 SfAnalyzeSerial(const unsigned char *Data, SF_U32 Length, SF_SERIAL_SPAN *Span);
/* Span must come from SfAnalyzeSerial on the same unchanged buffer. Bounded to
   255 bytes, allowing the kernel to serialize this write with profile removal. */
SF_U32 SfApplySerial(unsigned char *Data, SF_U32 Length, const SF_SERIAL_SPAN *Span,
                     const unsigned char *Serial, SF_U32 SerialLength);
#endif

#define _GNU_SOURCE
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifndef _WIN32
#include <sys/mman.h>
#include <unistd.h>
#endif
#include "../shared/transform.h"
_Static_assert(sizeof(SF_SERIAL_UPDATE) == 72, "update ABI");
_Static_assert(offsetof(SF_SERIAL_UPDATE, ExpectedGeneration) == 64, "generation update ABI");
_Static_assert(sizeof(SF_SERIAL_STATUS) == 56, "status ABI");
_Static_assert(offsetof(SF_SERIAL_STATUS, Generation) == 32, "generation ABI");
static unsigned Checks;
static void Put32(unsigned char *p, uint32_t n)
{
    p[0]=(unsigned char)n; p[1]=(unsigned char)(n>>8);
    p[2]=(unsigned char)(n>>16); p[3]=(unsigned char)(n>>24);
}
static void Valid(unsigned char *data, uint32_t length)
{
    memset(data, 0, length);
    Put32(data, 36); Put32(data+4, length); Put32(data+28, 17);
    Put32(data+12, 36); memcpy(data+36,"LAB",4);
    Put32(data+16, 40); memcpy(data+40,"MODEL",6);
    Put32(data+20, 48); memcpy(data+48,"1",2);
    Put32(data+24, 64); memcpy(data+64,"SYNTHETIC-SERIAL-0001",21);
}
static uint32_t Random(uint32_t *state)
{
    *state ^= *state << 13; *state ^= *state >> 17; *state ^= *state << 5;
    return *state;
}
static uint32_t Attempt(unsigned char *data, uint32_t length)
{
    unsigned char before[1024];
    SF_SERIAL_SPAN span;
    uint32_t result, i;
    assert(length <= sizeof(before));
    if (length) memcpy(before,data,length);
    result=SfAnalyzeSerial(data,length,&span);
    if (result==SF_TRANSFORM_OK) result=SfApplySerial(data,length,&span,(const unsigned char *)"LAB0001",7);
    if (result!=SF_TRANSFORM_OK) {
        if (length) assert(memcmp(before,data,length)==0);
    } else {
        assert(span.Capacity>=7);
        assert(memcmp(data+span.Offset,"LAB0001",7)==0);
        for(i=7;i<=span.Capacity;++i) assert(data[span.Offset+i]==0);
        for(i=0;i<length;++i)
            if(i<span.Offset || i>span.Offset+span.Capacity) assert(data[i]==before[i]);
    }
    ++Checks; return result;
}
int main(void)
{
    unsigned char data[1024], original[1024];
    SF_SERIAL_SPAN span;
    SF_SERIAL_UPDATE update;
    uint32_t i,j,n,seed=0x1D3A51u;
    memset(&update,0,sizeof(update));
    update.Version=SF_PROTOCOL_VERSION; update.Size=sizeof(update); update.Instance=1; update.DiskNumber=1;
    assert(SfValidateSerialUpdate(&update)); ++Checks;
    update.Flags=SF_SERIAL_ENABLE|SF_SERIAL_ACK_SECONDARY;
    update.SerialLength=7; memcpy(update.Serial,"LAB0001",7);
    assert(SfValidateSerialUpdate(&update)); ++Checks;
    update.Flags=SF_SERIAL_ENABLE; assert(!SfValidateSerialUpdate(&update)); ++Checks;
    update.Flags=3; update.Reserved=1; assert(!SfValidateSerialUpdate(&update)); ++Checks;
    update.Reserved=0; update.DiskNumber=0; assert(!SfValidateSerialUpdate(&update)); ++Checks;
    update.DiskNumber=1; update.SerialLength=UINT32_MAX; assert(!SfValidateSerialUpdate(&update)); ++Checks;
    update.SerialLength=7; update.Serial[31]='X'; assert(!SfValidateSerialUpdate(&update)); ++Checks;
    update.Serial[31]=0;
    for(i=0;i<256;++i) {
        int valid=(i>='A'&&i<='Z') || (i>='a'&&i<='z') || (i>='0'&&i<='9') || i=='-' || i=='_';
        update.Serial[0]=(unsigned char)i;
        assert(SfValidateSerialUpdate(&update)==valid); ++Checks;
    }
    Valid(data,128); assert(Attempt(data,128)==SF_TRANSFORM_OK);
    /* Every incomplete response and invalid descriptor remains byte-for-byte unchanged. */
    for(i=0;i<128;++i) { Valid(data,128); assert(Attempt(data,i)!=SF_TRANSFORM_OK); }
    Valid(data,128); Put32(data+24,0); assert(Attempt(data,128)==SF_TRANSFORM_NO_SERIAL);
    Valid(data,128); Put32(data+24,36); assert(Attempt(data,128)==SF_TRANSFORM_OVERLAP);
    Valid(data,128); Put32(data+16,65); assert(Attempt(data,128)==SF_TRANSFORM_OVERLAP);
    Valid(data,128); Put32(data+32,64); assert(Attempt(data,128)==SF_TRANSFORM_OVERLAP);
    Valid(data,128); data[67]=0; assert(Attempt(data,128)==SF_TRANSFORM_TOO_LONG);
    Valid(data,128); memset(data+64,'X',64); assert(Attempt(data,128)==SF_TRANSFORM_BAD_DESCRIPTOR);
    Valid(data,128); assert(SfAnalyzeSerial(data,128,&span)==SF_TRANSFORM_OK);
    memcpy(original,data,128);
    assert(SfApplySerial(data,128,&span,(const unsigned char *)"bad.value",9)==SF_TRANSFORM_INVALID_PROFILE);
    assert(memcmp(original,data,128)==0); ++Checks;
    span.Offset=UINT32_MAX;
    assert(SfApplySerial(data,128,&span,(const unsigned char *)"LAB0001",7)==SF_TRANSFORM_BAD_DESCRIPTOR);
    assert(memcmp(original,data,128)==0); ++Checks;
    assert(SfAnalyzeSerial(NULL,0,&span)==SF_TRANSFORM_BAD_DESCRIPTOR); ++Checks;
    assert(SfAnalyzeSerial(data,65537,&span)==SF_TRANSFORM_BAD_DESCRIPTOR); ++Checks;
    Valid(data,1024); memset(data+64,'S',256); data[320]=0;
    assert(Attempt(data,1024)==SF_TRANSFORM_TOO_LONG);
    for(i=0;i<50000;++i) {
        n=Random(&seed)%256;
        for(j=0;j<256;++j) data[j]=(unsigned char)Random(&seed);
        if(n>=96 && (i&3u)==0) {
            Valid(data,n);
            if(i&4u) Put32(data+24,Random(&seed)%300);
            if(i&8u) Put32(data+16,Random(&seed)%300);
        }
        (void)Attempt(data,n);
    }
#ifndef _WIN32
    {
        long page=sysconf(_SC_PAGESIZE);
        unsigned char *mapping;
        assert(page>256);
        mapping=mmap(NULL,(size_t)page*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
        assert(mapping!=MAP_FAILED); assert(mprotect(mapping+page,(size_t)page,PROT_NONE)==0);
        for(i=0;i<=256;++i) {
            unsigned char *prefix=mapping+page-i;
            Valid(data,256); if(i) memcpy(prefix,data,i);
            (void)Attempt(prefix,i);
        }
        assert(munmap(mapping,(size_t)page*2)==0);
    }
#endif
    printf("PASS: %u bounded transformation/profile checks; original tail erased; unrelated bytes unchanged\n",Checks);
    return 0;
}

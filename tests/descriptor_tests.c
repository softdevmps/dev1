#define _GNU_SOURCE
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <sys/mman.h>
#include <unistd.h>
#endif
#include "../shared/descriptor.h"
_Static_assert(sizeof(SF_DESCRIPTOR_INFO) == 20, "descriptor ABI");
_Static_assert(sizeof(SF_DEVICE_RECORD) == 96, "record ABI");
_Static_assert(offsetof(SF_DEVICE_RECORD, Descriptor) == 40, "descriptor offset");
_Static_assert(offsetof(SF_DEVICE_RECORD, BusTypeGuid) == 72, "GUID offset");
_Static_assert(sizeof(SF_SNAPSHOT) == 1568, "snapshot ABI");
static unsigned Checks;
static void Put32(unsigned char *p, uint32_t n)
{
    p[0]=(unsigned char)n; p[1]=(unsigned char)(n>>8);
    p[2]=(unsigned char)(n>>16); p[3]=(unsigned char)(n>>24);
}
static void Valid(unsigned char *p, size_t n)
{
    memset(p, 0, n); Put32(p, 40); Put32(p+4, (uint32_t)n);
    p[10]=1; Put32(p+28, 7); Put32(p+12, 36); memcpy(p+36, "LAB", 4);
    Put32(p+24, 40); memcpy(p+40, "SYNTHETIC", 10);
}
static SF_DESCRIPTOR_INFO Inspect(unsigned char *p, uint32_t n)
{
    SF_DESCRIPTOR_INFO info;
    unsigned char *copy = n ? malloc(n) : NULL;
    if(n) { assert(copy); memcpy(copy,p,n); }
    SfInspectDescriptor(p,n,&info);
    if(n) { assert(memcmp(copy,p,n)==0); free(copy); }
    ++Checks; return info;
}
static uint32_t Random(uint32_t *state)
{
    *state ^= *state << 13; *state ^= *state >> 17; *state ^= *state << 5;
    return *state;
}
int main(void)
{
    unsigned char data[256];
    SF_DESCRIPTOR_INFO info;
    uint32_t i, j, seed=0x12345678u;
    Valid(data,64); info=Inspect(data,64);
    assert(info.Flags==0 && info.BusType==7 && info.Removable==1 && info.StringPresence==9);
    SfInspectDescriptor(NULL,0,&info); assert(info.Flags==SF_PARSE_TOO_SHORT); ++Checks;
    for(i=0;i<8;++i) assert(Inspect(data,i).Flags==SF_PARSE_TOO_SHORT);
    assert(Inspect(data,8).Flags==(SF_PARSE_HEADER_ONLY|SF_PARSE_TRUNCATED));
    assert(Inspect(data,36).Flags & SF_PARSE_TRUNCATED);
    for(i=1;i<36;++i) { Valid(data,64); Put32(data+24,i); assert(Inspect(data,64).Flags & SF_PARSE_BAD_OFFSET); }
    Valid(data,64); Put32(data,0); assert(Inspect(data,64).Flags==SF_PARSE_BAD_VERSION);
    Valid(data,64); Put32(data+24,64); assert(Inspect(data,64).Flags & SF_PARSE_BAD_OFFSET);
    Valid(data,64); Put32(data+24,UINT32_MAX); assert(Inspect(data,64).Flags & SF_PARSE_BAD_OFFSET);
    Valid(data,64); memset(data+40,'X',24); assert(Inspect(data,64).Flags & SF_PARSE_UNTERMINATED);
    Valid(data,64); Put32(data+32,29); assert(Inspect(data,64).Flags & SF_PARSE_BAD_RAW_LENGTH);
    Valid(data,64); Put32(data+4,35); assert(Inspect(data,64).Flags==SF_PARSE_BAD_SIZE);
    Valid(data,64); Put32(data+24,63); data[63]=0; assert(Inspect(data,64).Flags==0);
    Valid(data,64); Put32(data+4,40); Put32(data+24,40); assert(Inspect(data,64).Flags & SF_PARSE_BAD_OFFSET);
    Valid(data,64); Put32(data+4,UINT32_MAX); assert(Inspect(data,64).Flags & SF_PARSE_TRUNCATED);
    /* Controlled synthetic transformation: only this test changes the serial. */
    Valid(data,64); data[40]='T'; info=Inspect(data,64); assert(info.Flags==0);
    /* Deterministic malformed/fuzz inputs; parser must leave every byte unchanged. */
    for(i=0;i<50000;++i) {
        uint32_t n=Random(&seed)%sizeof(data);
        for(j=0;j<sizeof(data);++j) data[j]=(unsigned char)Random(&seed);
        if(n>=8 && (i&1)) {
            Put32(data,40); Put32(data+4,Random(&seed)%300);
            for(j=0;j<4;++j) Put32(data+12+4*j,Random(&seed)%300);
            Put32(data+32,Random(&seed)%300);
        }
        (void)Inspect(data,n);
    }
#ifndef _WIN32
    /* Every prefix ends immediately before an inaccessible page. */
    {
        long page=sysconf(_SC_PAGESIZE);
        unsigned char *mapping;
        assert(page>256);
        mapping=mmap(NULL,(size_t)page*2,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
        assert(mapping!=MAP_FAILED);
        assert(mprotect(mapping+page,(size_t)page,PROT_NONE)==0);
        for(i=0;i<=256;++i) {
            unsigned char *p=mapping+page-i;
            Valid(data,256);
            if(i) memcpy(p,data,i);
            (void)Inspect(p,i);
        }
        assert(munmap(mapping,(size_t)page*2)==0);
    }
#endif
    printf("PASS: %u descriptor/immutability checks; wire ABI verified\n",Checks);
    return 0;
}

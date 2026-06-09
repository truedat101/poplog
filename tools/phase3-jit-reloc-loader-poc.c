/* Phase 3 PoC: load a Pop-image-like blob into MAP_JIT, relocate its pointer
   fields (stored as blob-relative offsets) to the JIT base, toggle RX, execute.
   This is the mechanism the real corepop startup loader will use. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>

/* --- a synthetic seed "blob" (what the codegen/linker would emit) ---
   layout (16-byte aligned words):
     [0]  code: movz w0,#99 ; ret           (8 bytes) -- an entry procedure
     [8]  ptr_field = 0  (blob-relative offset; must become JIT_base+0)        */
static const uint32_t BLOB[] = {
    0x52800C60u, 0xd65f03c0u,   /* movz w0,#99 ; ret  -> returns 99 */
    0x00000000u, 0x00000000u,   /* ptr_field: offset 0 (-> &code after reloc) */
};
#define BLOB_SIZE   sizeof(BLOB)
#define PTR_FIELD_OFF 8                 /* byte offset of the pointer field */
static const uint32_t RELOC_TABLE[] = { PTR_FIELD_OFF };  /* offsets of pointer fields */
#define RELOC_COUNT (sizeof(RELOC_TABLE)/sizeof(RELOC_TABLE[0]))

int main(void) {
    /* 1. allocate a MAP_JIT region (the only way to get exec'able dynamic mem) */
    void *jit = mmap(NULL, BLOB_SIZE, PROT_READ|PROT_WRITE|PROT_EXEC,
                     MAP_PRIVATE|MAP_ANON|MAP_JIT, -1, 0);
    if (jit == MAP_FAILED) { perror("mmap MAP_JIT"); return 1; }

    /* 2. write phase: copy the blob + relocate offset-pointers to the JIT base */
    pthread_jit_write_protect_np(0);            /* make JIT region writable */
    memcpy(jit, BLOB, BLOB_SIZE);
    for (size_t i = 0; i < RELOC_COUNT; i++) {
        uintptr_t *field = (uintptr_t *)((char *)jit + RELOC_TABLE[i]);
        *field += (uintptr_t)jit;               /* offset -> absolute JIT pointer */
    }
    pthread_jit_write_protect_np(1);            /* back to executable */
    sys_icache_invalidate(jit, BLOB_SIZE);

    /* 3. verify the relocation + execute the entry procedure */
    uintptr_t relocated = *(uintptr_t *)((char *)jit + PTR_FIELD_OFF);
    int (*entry)(void) = (int (*)(void))jit;
    int r = entry();
    printf("entry() = %d  (want 99)\n", r);
    printf("ptr_field = %p  base = %p  -> %s\n",
           (void*)relocated, jit,
           relocated == (uintptr_t)jit ? "RELOCATED CORRECTLY" : "WRONG");
    return (r == 99 && relocated == (uintptr_t)jit) ? 0 : 1;
}

/* --- Apple M-silicon Poplog. Distributed under the Free Poplog licence. ---
 * File:    pop/extern/lib/pop_seed_loader.c
 * Purpose: macOS arm64 process entry: make the Pop seed image executable.
 *
 * On Mach-O, PIE is mandatory and the Pop seed (procedure records with
 * absolute, dyld-rebased pointer fields, contiguous with their code) cannot
 * live in read-only __TEXT, so popc/poplink emit it into a dedicated
 * __POPSEED segment (see syscomp/arm64/asmout.p ASM_TEXT_STR).  dyld maps
 * that segment read-write, non-executable.
 *
 * This loader is the real `main` (in __TEXT): it replaces __POPSEED's pages
 * IN PLACE with an anonymous mapping, copies the seed back, and mprotects it
 * read+execute.  Same address, so nothing needs relocating: intra-seed
 * pointers were already rebased by dyld, and all PC-relative references
 * between the seed and the C runtime stay valid.  (mprotect(RX) is refused
 * on dyld's own file-backed pages, but allowed on a fresh anonymous mapping
 * under ad-hoc signing -- verified on Apple Silicon.  MAP_JIT cannot be used
 * with MAP_FIXED, and is not needed for this.)
 *
 * It then tail-calls the Pop entry `_pop_seed_main` (arm64/amain.s), which
 * never returns.
 */
#if defined(__APPLE__)

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <mach-o/getsect.h>
#include <mach-o/ldsyms.h>
#include <libkern/OSCacheControl.h>

extern int pop_seed_main(int argc, char **argv, char **envp)
    __asm__("_pop_seed_main");

int main(int argc, char **argv, char **envp) {
    unsigned long segsize;
    uint8_t *seg = getsegmentdata(&_mh_execute_header, "__POPSEED", &segsize);
    if (seg == NULL) {
        fprintf(stderr, "poplog: no __POPSEED segment in this executable\n");
        return 70;  /* EX_SOFTWARE */
    }
    long pagesz = sysconf(_SC_PAGESIZE);
    unsigned long maplen = (segsize + pagesz - 1) & ~((unsigned long)pagesz - 1);

    uint8_t *save = malloc(maplen);
    if (save == NULL) {
        fprintf(stderr, "poplog: cannot allocate %lu bytes for seed copy\n", maplen);
        return 71;
    }
    memcpy(save, seg, maplen);

    if (mmap(seg, maplen, PROT_READ | PROT_WRITE,
             MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) != (void *)seg) {
        perror("poplog: remap of __POPSEED failed");
        return 71;
    }
    memcpy(seg, save, maplen);
    free(save);

    if (mprotect(seg, maplen, PROT_READ | PROT_EXEC) != 0) {
        perror("poplog: mprotect(RX) of __POPSEED failed");
        return 71;
    }
    sys_icache_invalidate(seg, maplen);

    return pop_seed_main(argc, argv, envp);   /* does not return */
}

#endif /* __APPLE__ */

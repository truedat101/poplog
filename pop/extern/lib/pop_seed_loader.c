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
#include <spawn.h>
#include <sys/mman.h>
#include <mach-o/getsect.h>
#include <mach-o/dyld.h>
#include <mach-o/ldsyms.h>
#include <libkern/OSCacheControl.h>

extern int pop_seed_main(int argc, char **argv, char **envp)
    __asm__("_pop_seed_main");

/* private but long-stable (it is how debuggers run ASLR-free targets) */
#ifndef _POSIX_SPAWN_DISABLE_ASLR
#define _POSIX_SPAWN_DISABLE_ASLR 0x0100
#endif

/* Saved images (.psv) embed absolute addresses of seed procedures and heap
 * structures, so the process layout must repeat across runs.  This is the
 * Darwin analogue of linux_setper()'s ADDR_NO_RANDOMIZE re-exec on Linux:
 * if we are running with a nonzero PIE slide, re-exec ourselves with ASLR
 * disabled (slide 0; mmap layout then repeats too).  If the re-exec is not
 * permitted, continue -- everything works except cross-run image restore. */
static void disable_aslr_reexec(char **argv) {
    if (_dyld_get_image_vmaddr_slide(0) == 0) return;      /* already fixed */
    if (getenv("POP_ASLR_REEXEC") != NULL) return;         /* loop guard */

    char path[4096];
    uint32_t pathsz = sizeof path;
    if (_NSGetExecutablePath(path, &pathsz) != 0) return;

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) return;
    /* SETEXEC = replace this image, exec-style */
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC
                                    | _POSIX_SPAWN_DISABLE_ASLR);
    setenv("POP_ASLR_REEXEC", "1", 1);
    extern char **environ;
    posix_spawn(NULL, path, NULL, &attr, argv, environ);   /* no return on success */
    posix_spawnattr_destroy(&attr);
    unsetenv("POP_ASLR_REEXEC");                           /* failed: carry on */
}

int main(int argc, char **argv, char **envp) {
    /* C-side diagnostics (printf via the pop_w_printf wrapper) must not be
       lost when Pop exits abnormally: unbuffer stdout. */
    setvbuf(stdout, NULL, _IONBF, 0);

    disable_aslr_reexec(argv);

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

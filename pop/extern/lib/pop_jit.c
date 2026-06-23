/* W^X JIT memory helpers.  See pop_jit.h. */
#include "pop_jit.h"

#include <sys/mman.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <pthread.h>                 /* pthread_jit_write_protect_np      */
#include <libkern/OSCacheControl.h>  /* sys_icache_invalidate            */
#endif

void *pop_jit_alloc(size_t size)
{
    int prot  = PROT_READ | PROT_WRITE | PROT_EXEC;
    int flags = MAP_PRIVATE | MAP_ANON;
#if defined(__APPLE__)
    flags |= MAP_JIT;                /* required for W^X JIT on Apple Silicon */
#endif
    void *p = mmap(NULL, size, prot, flags, -1, 0);
    return (p == MAP_FAILED) ? NULL : p;
}

void pop_jit_free(void *addr, size_t size)
{
    if (addr)
        munmap(addr, size);
}

void pop_jit_write_enable(void)
{
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);  /* 0 => writable, not executable */
#endif
}

void pop_jit_write_disable(void)
{
#if defined(__APPLE__)
    pthread_jit_write_protect_np(1);  /* 1 => executable, not writable */
#endif
}

void pop_jit_flush(void *addr, size_t size)
{
#if defined(__APPLE__)
    sys_icache_invalidate(addr, size);
#else
    __builtin___clear_cache((char *)addr, (char *)addr + size);
#endif
}

/* Smoke test for the W^X JIT cycle (PORTING-ARM64-M-SILICON-OSX.md Phase 4).
 *
 * Allocates JIT memory, writes a tiny AArch64 function into it, flips it from
 * writable to executable, flushes the I-cache, then CALLS it -- proving the
 * MAP_JIT + pthread_jit_write_protect_np + sys_icache_invalidate path that
 * Poplog's runtime code generators need on Apple Silicon.  No Poplog required.
 *
 *   make jit-smoke && ./jit-smoke
 *
 * Exit codes: 0 ok, 1 wrong result, 2 alloc failed.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "pop_jit.h"

int main(void)
{
#if defined(__aarch64__)
    /* int f(int x) { return x + 41; }  (verified with clang's assembler)
     *   add w0, w0, #41   ->  0x1100A400
     *   ret               ->  0xD65F03C0
     */
    static const uint32_t code[] = { 0x1100A400u, 0xD65F03C0u };

    const size_t sz = 4096;
    void *mem = pop_jit_alloc(sz);
    if (!mem) {
        fprintf(stderr, "pop_jit_alloc failed\n");
        return 2;
    }

    pop_jit_write_enable();
    memcpy(mem, code, sizeof code);
    pop_jit_write_disable();
    pop_jit_flush(mem, sizeof code);

    int (*f)(int) = (int (*)(int))mem;
    int got  = f(1);
    int want = 42;
    pop_jit_free(mem, sz);

    if (got != want) {
        fprintf(stderr, "jit FAIL: f(1) = %d, want %d\n", got, want);
        return 1;
    }
    printf("jit ok: f(1) = %d  (W^X MAP_JIT write->execute cycle works)\n", got);
    return 0;
#else
    printf("jit-smoke: host is not aarch64; machine-code test skipped\n");
    return 0;
#endif
}

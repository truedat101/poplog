/* W^X JIT memory for Poplog's runtime code generators (ass.p, array_cons.p,
 * closure_cons.p, pdr_compose.p, and the GC's code-movement paths) on platforms
 * that forbid simultaneously-writable+executable pages -- i.e. Apple Silicon.
 * See PORTING-ARM64-M-SILICON-OSX.md sec. 6 / Phase 4 ("the headline hurdle").
 *
 * Per emit:  pop_jit_write_enable();  <write machine code>;
 *            pop_jit_write_disable(); pop_jit_flush(addr, n);  <execute>
 *
 * On Apple the enable/disable calls toggle pthread_jit_write_protect_np, which
 * is THREAD-LOCAL and covers every MAP_JIT region on the calling thread -- so
 * all Poplog codegen + the GC must run on one thread (Poplog is cooperatively
 * single-threaded, so this holds).  On other platforms the toggles are no-ops
 * and the region is simply mapped RWX.
 *
 * Note: a plain (non-hardened, non-sandboxed) executable needs NO entitlement
 * for MAP_JIT.  A notarized/hardened-runtime Poplog.app will need the
 * com.apple.security.cs.allow-jit entitlement.
 */
#ifndef POP_JIT_H
#define POP_JIT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void *pop_jit_alloc(size_t size);             /* JIT region, or NULL on failure */
void  pop_jit_free(void *addr, size_t size);
void  pop_jit_write_enable(void);             /* make JIT memory writable        */
void  pop_jit_write_disable(void);            /* make JIT memory executable       */
void  pop_jit_flush(void *addr, size_t size); /* sync I/D caches after writing    */

#ifdef __cplusplus
}
#endif

#endif /* POP_JIT_H */

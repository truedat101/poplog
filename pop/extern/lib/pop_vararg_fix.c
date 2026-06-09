/* --- Apple M-silicon Poplog. Distributed under the Free Poplog licence. ---
 * File:    pop/extern/lib/pop_vararg_fix.c
 * Purpose: fixed-arity wrappers for the variadic libc functions Poplog calls.
 *
 * On Darwin arm64 the variadic portion of a call goes on the STACK, but
 * Poplog's _extern calls pass every argument in registers (AAPCS64).  So a
 * direct call to open(2)/fcntl(2)/ioctl(2)/printf(3) reads garbage for the
 * variadic arguments -- e.g. syssave created its image with mode 000.
 *
 * popc routes these names here via extern_name_translate
 * (syscomp/arm64/asmout.p): open -> pop_w_open etc.  The wrappers take a
 * FIXED argument list (registers, matching what Pop emits) and forward to
 * the real variadic function from C, which uses the correct ABI.
 *
 * pop_w_printf forwards 4 integer/pointer words; no Poplog call site passes
 * more than 3 format arguments, and none uses float formats (%e/%f/%g).
 */
#if defined(__APPLE__)

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

int pop_w_open(const char *path, int flags, long mode) {
    return open(path, flags, (int) mode);
}

int pop_w_fcntl(int fd, int cmd, long arg) {
    return fcntl(fd, cmd, arg);
}

int pop_w_ioctl(int fd, unsigned long request, void *arg) {
    return ioctl(fd, request, arg);
}

int pop_w_printf(const char *fmt, long a, long b, long c, long d) {
    return printf(fmt, a, b, c, d);
}

#endif /* __APPLE__ */

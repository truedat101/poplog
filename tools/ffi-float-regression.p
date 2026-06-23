/* tools/ffi-float-regression.p
 *
 * Regression for the AArch64 (and aarch64-darwin) external-call
 * floating-point ABI.  Two distinct bugs lived in pop/extern/lib/ext_arm.c
 * and were exposed only by calls passing multiple FP arguments:
 *
 *   1. The reg_buff f_reg[] array used an 8-byte stride, but the
 *      hand-written caller (pop/src/arm64/aextern.s) loads d0-d7 at a
 *      16-byte stride -- so every OTHER float/double argument was dropped.
 *
 *   2. A boxed ddecimal's double was read at offset 0 from the structure
 *      pointer instead of @@DD_1 (two words back), so every double-valued
 *      external argument read the wrong heap word.
 *
 * Both are caught here: pow / atan2 / hypot each pass two doubles, and
 * cbrt passes one -- all wrong if either bug is present.  Run with:
 *
 *     ./poplog ./target/pop/basepop11 tools/ffi-float-regression.p
 *
 * Prints FFI-FLOAT-REGRESSION-PASSED on success (exit-style marker for
 * scripted validation), or a FAILED line naming the offending call.
 */

exload ffi_float_regression []
(language C)
    lconstant
        cbrt(x)      :dfloat,
        pow(x, y)    :dfloat,
        atan2(y, x)  :dfloat,
        hypot(x, y)  :dfloat,
    ;
endexload;

define close(a, b);
    abs(a - b) < 0.0001
enddefine;

lvars ok = true;

define check(name, got, want);
    lvars name, got, want;
    unless close(got, want) then
        false -> ok;
        [FAILED ^name got ^got want ^want] =>
    endunless;
enddefine;

check('cbrt(27)',     exacc cbrt(27.0),       3.0);          ;;; 1 double
check('cbrt(8)',      exacc cbrt(8.0),        2.0);
check('pow(2,10)',    exacc pow(2.0, 10.0),   1024.0);       ;;; 2 doubles
check('pow(3,4)',     exacc pow(3.0, 4.0),    81.0);
check('atan2(1,1)',   exacc atan2(1.0, 1.0),  0.7853981633974483);
check('hypot(3,4)',   exacc hypot(3.0, 4.0),  5.0);

if ok then
    'FFI-FLOAT-REGRESSION-PASSED' =>
else
    'FFI-FLOAT-REGRESSION-FAILED' =>
endif;

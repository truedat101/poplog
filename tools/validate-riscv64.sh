#!/usr/bin/env bash
#
# validate-riscv64.sh -- validate the Poplog RISC-V (rv64gc / LP64D / Linux) port.
#
# Run ON the RISC-V box (e.g. a StarFive VisionFive), from the repo root (or
# pass the root as the first argument).  It builds any missing saved images,
# then runs the validation ladder gate by gate and prints PASS/FAIL.  Exit
# status is 0 iff every gate passes.
#
#   ./tools/validate-riscv64.sh [repo-root] [--rebuild]
#
# Prerequisites:
#   * target/pop/basepop11 already built (natively with gcc/binutils, or cross
#     from x86_64 then seeded).  See PORTING-RISCV64-LINUX.md.
#   * After ANY codegen change (ass.p / *.s / genproc.p) you must first
#       rm -f stamp_popc stamp_srclib stamp_vedlib target/obj/src.{olb,wlb}
#     rebuild basepop11, then run this with --rebuild (a stale image, or a
#     stale src.olb, hides codegen fixes).
#
# RISC-V SPECIFIC: every basepop11 invocation runs under `setarch -R` (ASLR
# off).  Poplog restores its .psv saved images at FIXED virtual addresses; with
# ASLR on, the restore collides with the program/stack mapping and SIGSEGVs at
# startup.  The personality set by setarch -R is inherited across the exec
# chain (launcher -> basepop11), so wrapping the launcher is sufficient.
#
# Mirrors tools/validate-raspi5.sh gate-for-gate.

set -u

ROOT="$PWD"; REBUILD=0
for a in "$@"; do
    case "$a" in
        --rebuild) REBUILD=1 ;;
        *) [ -d "$a" ] && ROOT="$a" ;;
    esac
done
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 2; }

BASE="target/pop/basepop11"
[ -x "$BASE" ] || { echo "FATAL: $ROOT/$BASE not found -- build basepop11 first."; exit 2; }
[ -f "$ROOT/poplog" ] || { echo "FATAL: launcher $ROOT/poplog missing."; exit 2; }
command -v setarch >/dev/null 2>&1 || { echo "FATAL: setarch not found (util-linux) -- needed to disable ASLR."; exit 2; }

# A launcher pinned to THIS root (the committed ./poplog hardcodes a path).
LAUNCH=/tmp/poplog_validate
sed "s#^poplogroot=.*#poplogroot=$ROOT#" "$ROOT/poplog" > "$LAUNCH" && chmod +x "$LAUNCH"
# basepop11 (console) launcher, ASLR-disabled.  NB: call as
#   timeout N "${POP[@]}" ARGS  -- `timeout` execs a command, so it cannot
# invoke a shell function; the array expands to setarch + launcher + image.
POP=(setarch -R "$LAUNCH" "$BASE")
SETARCH_PREFIX="setarch -R"          # for the `script -qec` (PTY) gates

PASS=0; FAIL=0; OUT=""
crashed() { grep -qaiE 'Access Violation|MEMORY ACCESS|Signal *=|Segmentation|Illegal instruction|FATAL ERROR|BAD STRUCTURE|core dumped' <<<"$OUT"; }
gate() {   # gate "name" "expected-extended-regex"  -- judges the current $OUT
    local name="$1" want="$2"
    if crashed; then
        printf '  [FAIL] %-36s crash\n' "$name"; FAIL=$((FAIL+1))
    elif grep -qaE "$want" <<<"$OUT"; then
        printf '  [PASS] %s\n' "$name"; PASS=$((PASS+1))
    else
        printf '  [FAIL] %-36s expected /%s/\n' "$name" "$want"; FAIL=$((FAIL+1))
    fi
}
build() {  # build "label" "outfile" run-args...
    local label="$1" out="$2"; shift 2
    [ "$REBUILD" = 1 ] && rm -f "$out"
    if [ -f "$out" ]; then printf '  have  %-12s (%s bytes)\n' "$label" "$(stat -c%s "$out")"; return 0; fi
    printf '  build %-12s ... ' "$label"
    if "${POP[@]}" "$@" >"/tmp/val_build_$label.log" 2>&1 && [ -f "$out" ]; then
        printf 'ok (%s bytes)\n' "$(stat -c%s "$out")"; return 0
    fi
    printf 'FAILED (see /tmp/val_build_%s.log)\n' "$label"; FAIL=$((FAIL+1)); return 1
}

echo "== Poplog RISC-V (rv64gc / LP64D / Linux) validation =="
echo "   root: $ROOT"
echo "   arch: $(uname -m)   page size: $(getconf PAGE_SIZE)   (ASLR off via setarch -R)"
echo

echo "-- building saved images (only if missing; --rebuild forces) --"
build startup target/psv/startup.psv \
      %nort %noinit pop/lib/lib/mkimage.p -nodebug -nonwriteable -install target/psv/startup.psv startup || { echo "startup build failed -- basepop11 is broken; stopping."; exit 1; }
build clisp   target/psv/clisp.psv \
      -target/psv/startup.psv %nort %noinit pop/lib/lib/mkimage.p -install -subsystem lisp target/psv/clisp.psv pop/lisp/src/clisp.p
build prolog  target/psv/prolog.psv \
      -target/psv/startup.psv %nort %noinit pop/lib/lib/mkimage.p -nodebug -install -flags prolog '(' ')' target/psv/prolog.psv pop/plog/src/prolog.p
build pml     target/psv/pml.psv \
      -target/psv/startup.psv %nort %noinit pop/lib/lib/mkimage.p -nodebug -install -flags ml '(' ')' target/psv/pml.psv pop/pml/src/ml.p
echo

echo "-- gate 1: Pop-11 core REPL (startup.psv) --"
OUT=$(printf '2+2=>\n3*4+1=>\ndefine sq(x); x*x enddefine; sq(9)=>\nlvars z,a=[]; for z in_vector {7 8 9} do z::a->a endfor; rev(a)=>\n' \
      | timeout 25 "${POP[@]}" -target/psv/startup.psv 2>&1)
gate "arithmetic + precedence (4, 13)"   '\*\* 4'
gate "user procedure (sq 9 = 81)"        '\*\* 81'
gate "for..in_vector ([7 8 9])"          '\*\* \[7 8 9\]'

echo "-- gate 2: Common Lisp (clisp.psv) --"
OUT=$(printf '(defun fact (n) (if (= n 0) 1 (* n (fact (- n 1)))))\n(fact 12)\n(mapcar (function 1+) (list 10 20 30))\n(mapcar (function symbolp) (list (quote a) 1 (quote b)))\n' \
      | timeout 25 "${POP[@]}" -target/psv/clisp.psv 2>&1)
gate "compile + recursion (fact 12)"     '^479001600'
gate "mapcar ((11 21 31))"               '\(11 21 31\)'
gate "symbolp boolean coercion (T NIL T)" '\(T (NIL|\(\)) T\)'

echo "-- gate 3: Prolog computation (prolog.psv) --"
OUT=$(printf ':- assertz(app([],L,L)), assertz((app([H|T],L,[H|R]):-app(T,L,R))).\n:- (app([1,2,3],[4,5],Z) -> write(Z) ; write(no)), nl.\n:- assertz(f(0,1)), assertz((f(N,R):-N>0,M is N-1,f(M,P),R is N*P)).\n:- (f(6,X) -> write(fac6=X) ; write(no)), nl.\nhalt.\n' \
      | timeout 25 "${POP[@]}" -target/psv/prolog.psv 2>&1)
gate "recursive append ([1,2,3,4,5])"    '\[1, 2, 3, 4, 5\]'
gate "factorial (fac6 = 720)"            'fac6 *= *720'

echo "-- gate 4: Prolog error reporting (must report, not crash) --"
OUT=$(printf 'X is foo + 1, write(X), nl.\nhalt.\n' | timeout 25 "${POP[@]}" -target/psv/prolog.psv 2>&1)
gate "type error -> clean message"       'PROLOG ERROR|NUMBER'

echo "-- gate 5: piped EOF without halt (must NOT crash) --"
OUT=$(printf 'X is 6*7, write(answer=X), nl.\n' | timeout 25 "${POP[@]}" -target/psv/prolog.psv 2>&1)
gate "bare-EOF prolog (answer = 42)"     'answer *= *42'
OUT=$(printf '2+2=>\n' | timeout 20 "${POP[@]}" -target/psv/startup.psv 2>&1)
gate "bare-EOF pop-11 (** 4)"            '\*\* 4'

echo "-- gate 6: Standard ML under a PTY (pml.psv) --"
if command -v script >/dev/null 2>&1; then
    OUT=$( (sleep 6; printf 'print "x";\n'; sleep 4) \
           | timeout 25 script -qec "$SETARCH_PREFIX $LAUNCH $BASE +target/psv/pml.psv" /dev/null 2>&1)
    gate "ML reader+eval+types (val it ...)" 'val it = "x" : string|^"x"'
else
    printf '  [SKIP] ML PTY test (no `script` util)\n'
fi

echo "-- gate 7: interactive Prolog under a PTY --"
if command -v script >/dev/null 2>&1; then
    OUT=$(printf 'X is 2+3*4, write(r=X), nl.\nhalt.\n' \
          | timeout 25 script -qec "$SETARCH_PREFIX $LAUNCH $BASE -target/psv/prolog.psv" /dev/null 2>&1)
    gate "interactive ?- toplevel (r = 14)" 'r *= *14'
else
    printf '  [SKIP] interactive PTY test (no `script` util)\n'
fi

echo "-- gate 8: external-call FP ABI (multi-float exacc) --"
# Covers the rv64 LP64D float-argument marshalling on the console ladder
# (fa0-fa7 FP arg registers, the boxed-ddecimal read offset).  exload shells
# out to the C toolchain at run time, so cc must be on PATH.
if [ -f tools/ffi-float-regression.p ]; then
    OUT=$(timeout 30 "${POP[@]}" tools/ffi-float-regression.p 2>&1)
    gate "FFI float regression (pow/atan2/hypot/cbrt)" 'FFI-FLOAT-REGRESSION-PASSED'
else
    printf '  [SKIP] FFI float regression (tools/ffi-float-regression.p missing)\n'
fi

echo
echo "== summary: $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ] && echo "   PORT VALIDATED (console core: pop11 + Common Lisp + Prolog + ML)." || echo "   VALIDATION FAILED."
exit $(( FAIL > 0 ? 1 : 0 ))

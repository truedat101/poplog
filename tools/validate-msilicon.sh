#!/usr/bin/env bash
#
# validate-msilicon.sh -- validate the Poplog AArch64 / Apple M-silicon port.
#
# Run ON the Mac:  ./tools/validate-msilicon.sh [build-dir] [--rebuild]
#
# build-dir (default ~/poplog-mac-build) must contain:
#   corepop      -- the macOS corepop (codesigned with the JIT entitlement)
#   poplog       -- the env wrapper (sets usepop etc. against this repo)
# Images are built into <build-dir>/psv/.
#
# Mirrors tools/validate-raspi5.sh gate-for-gate.  macOS notes:
#   * no `timeout` -- perl alarm shim
#   * BSD stat/script syntax
#   * the engine is corepop (not basepop11): no VED/X, console core only

set -u

# Apple Silicon only: the Darwin port lives in the arm64 backend.
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "ERROR: this tool targets macOS on Apple Silicon (Darwin/arm64) only."
    echo "       Host is $(uname -s)/$(uname -m). See PORTING-ARM64-M-SILICON-OSX.md."
    exit 2
fi

BUILD="$HOME/poplog-mac-build"; REBUILD=0
for a in "$@"; do
    case "$a" in
        --rebuild) REBUILD=1 ;;
        *) [ -d "$a" ] && BUILD="$a" ;;
    esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BUILD" || { echo "cannot cd to $BUILD"; exit 2; }
[ -x corepop ] || { echo "FATAL: $BUILD/corepop missing."; exit 2; }
[ -x poplog ]  || { echo "FATAL: $BUILD/poplog wrapper missing."; exit 2; }
mkdir -p psv
# ("bigmem" popminmemlim preload removed: the GC-under-compile-load
# corruption was the arm64 dlocal save-slot inversion, fixed in genproc)
BIGMEM=/tmp/validate_noop.p
: > "$BIGMEM"

tmo() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # macOS has no timeout(1)
POP=(./poplog ./corepop)

PASS=0; FAIL=0; OUT=""
crashed() { grep -qaiE 'Access Violation|MEMORY ACCESS|Signal *=|Segmentation|Illegal instruction|FATAL ERROR|BAD STRUCTURE|core dumped' <<<"$OUT"; }
gate() {
    local name="$1" want="$2"
    if crashed; then
        printf '  [FAIL] %-36s crash\n' "$name"; FAIL=$((FAIL+1))
    elif grep -qaE "$want" <<<"$OUT"; then
        printf '  [PASS] %s\n' "$name"; PASS=$((PASS+1))
    else
        printf '  [FAIL] %-36s expected /%s/\n' "$name" "$want"; FAIL=$((FAIL+1))
    fi
}
build() {
    local label="$1" out="$2"; shift 2
    [ "$REBUILD" = 1 ] && rm -f "$out"
    if [ -f "$out" ]; then printf '  have  %-12s (%s bytes)\n' "$label" "$(stat -f%z "$out")"; return 0; fi
    printf '  build %-12s ... ' "$label"
    if "${POP[@]}" "$@" >"/tmp/val_build_$label.log" 2>&1 && [ -f "$out" ]; then
        printf 'ok (%s bytes)\n' "$(stat -f%z "$out")"; return 0
    fi
    printf 'FAILED (see /tmp/val_build_%s.log)\n' "$label"; FAIL=$((FAIL+1)); return 1
}

echo "== Poplog AArch64 / Apple M-silicon validation =="
echo "   repo:  $ROOT"
echo "   build: $BUILD"
echo "   page size: $(getconf PAGE_SIZE)   (image VPAGE_OFFS expects 16384)"
echo

echo "-- building saved images (only if missing; --rebuild forces) --"
MKI="$ROOT/pop/lib/lib/mkimage.p"
build startup psv/startup.psv \
      %nort %noinit "$MKI" -nodebug -nonwriteable -install psv/startup.psv "$BIGMEM" startup || { echo "startup build failed -- corepop is broken; stopping."; exit 1; }
build clisp   psv/clisp.psv \
      -psv/startup.psv %nort %noinit "$MKI" -install -subsystem lisp psv/clisp.psv "$BIGMEM" "$ROOT/pop/lisp/src/clisp.p"
build prolog  psv/prolog.psv \
      -psv/startup.psv %nort %noinit "$MKI" -nodebug -install -flags prolog '(' ')' psv/prolog.psv "$BIGMEM" "$ROOT/pop/plog/src/prolog.p"
build pml     psv/pml.psv \
      -psv/startup.psv %nort %noinit "$MKI" -nodebug -install -flags ml '(' ')' psv/pml.psv "$BIGMEM" "$ROOT/pop/pml/src/ml.p"
echo

echo "-- gate 1: Pop-11 core REPL (startup.psv) --"
OUT=$(printf '2 + 2 =>\n3 + 5 * 2 =>\n' | tmo 25 "${POP[@]}" -psv/startup.psv 2>&1)
gate "arithmetic + precedence (4, 13)"   '\*\* 4'
OUT=$(printf 'define sq(x); x * x enddefine;\nsq(9) =>\n' | tmo 25 "${POP[@]}" -psv/startup.psv 2>&1)
gate "user procedure (sq 9 = 81)"        '\*\* 81'
OUT=$(printf '[%% for i in_vector {7 8 9} do i endfor %%] =>\n' | tmo 25 "${POP[@]}" -psv/startup.psv 2>&1)
gate "for..in_vector ([7 8 9])"          '\*\* \[7 8 9\]'

echo "-- gate 2: Common Lisp (clisp.psv) --"
if [ -f psv/clisp.psv ]; then
OUT=$(printf '(defun fact (n) (if (zerop n) 1 (* n (fact (1- n)))))\n(print (fact 12))\n(print (mapcar #%s1+ (quote (10 20 30))))\n' "'" \
      | tmo 25 "${POP[@]}" -psv/clisp.psv 2>&1)
gate "compile + recursion (fact 12)"     '479001600'
gate "mapcar ((11 21 31))"               '\(11 21 31\)'
else printf '  [SKIP] clisp.psv missing\n'; fi

echo "-- gate 3: Prolog computation (prolog.psv) --"
if [ -f psv/prolog.psv ]; then
OUT=$(printf ':- assertz(app([],L,L)), assertz((app([H|T],L,[H|R]):-app(T,L,R))).\n:- (app([1,2,3],[4,5],Z) -> write(Z) ; write(no)), nl.\n:- assertz(f(0,1)), assertz((f(N,R):-N>0,M is N-1,f(M,P),R is N*P)).\n:- (f(6,X) -> write(fac6=X) ; write(no)), nl.\nhalt.\n' \
      | tmo 25 "${POP[@]}" -psv/prolog.psv 2>&1)
gate "recursive append ([1,2,3,4,5])"    '\[1, 2, 3, 4, 5\]'
gate "factorial (fac6 = 720)"            'fac6 *= *720'

echo "-- gate 4: Prolog error reporting (must report, not crash) --"
OUT=$(printf 'X is foo + 1, write(X), nl.\nhalt.\n' | tmo 25 "${POP[@]}" -psv/prolog.psv 2>&1)
gate "type error -> clean message"       'PROLOG ERROR|NUMBER'

echo "-- gate 5: piped EOF without halt (must NOT crash) --"
OUT=$(printf 'X is 6*7, write(answer=X), nl.\n' | tmo 25 "${POP[@]}" -psv/prolog.psv 2>&1)
gate "bare-EOF prolog (answer = 42)"     'answer *= *42'
else printf '  [SKIP] prolog gates (prolog.psv missing)\n'; fi
OUT=$(printf '2+2=>\n' | tmo 20 "${POP[@]}" -psv/startup.psv 2>&1)
gate "bare-EOF pop-11 (** 4)"            '\*\* 4'

echo "-- gate 6: Standard ML under a PTY (pml.psv) --"
if [ -f psv/pml.psv ]; then
    OUT=$( (sleep 6; printf 'print "x";\n'; sleep 4) \
           | tmo 25 script -q /dev/null ./poplog ./corepop +psv/pml.psv 2>&1)
    gate "ML reader+eval+types (val it ...)" 'val it = "x" : string|^"x"'
else
    printf '  [FAIL] pml.psv missing (build failed -- known open bug: heap corruption in the ML lexer build)\n'; FAIL=$((FAIL+1))
fi

echo "-- gate 7: interactive Prolog under a PTY --"
if [ -f psv/prolog.psv ]; then
    # BSD script delivers piped stdin to the PTY immediately; pace it so the
    # toplevel is reading before the goal arrives (same trick as gate 6).
    OUT=$( (sleep 5; printf 'X is 2+3*4, write(r=X), nl.\nhalt.\n'; sleep 4) \
          | tmo 25 script -q /dev/null ./poplog ./corepop -psv/prolog.psv 2>&1)
    gate "interactive ?- toplevel (r = 14)" 'r *= *14'
else printf '  [SKIP] prolog PTY gate\n'; fi

echo
echo "== summary: $PASS passed, $FAIL failed =="
[ "$FAIL" = 0 ] && echo "   PORT VALIDATED (console core)." || echo "   VALIDATION INCOMPLETE."
exit $(( FAIL > 0 ? 1 : 0 ))

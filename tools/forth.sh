#!/bin/sh
# forth.sh -- run Poplog Forth locally (native macOS / Linux, no qemu).
#
#   tools/forth.sh                 # interactive Forth REPL
#   tools/forth.sh foo.fth         # load foo.fth, then drop into the REPL
#   tools/forth.sh -c '2 3 + .'    # run one line of Forth and exit
#   tools/forth.sh -t              # run the built-in testbench and exit
#   tools/forth.sh -b              # run the performance benchmark and exit
#
# Inside the REPL:  words  testbench  bye   (bye / pop11 returns to Pop-11)

set -e
U=$(cd "$(dirname "$0")/.." && pwd)          # repo root

# --- full Poplog environment (so the subsystem + uses forth work) ---
export usepop="$U" popsrc="$U/pop/src" popsys="$U/target/pop"
export popautolib="$U/pop/lib/auto" popdatalib="$U/pop/lib/data"
export popliblib="$U/pop/lib/lib"   popvedlib="$U/pop/lib/ved"
export poplocal="${poplocal:-$HOME/.poplog}" poplocalauto="$poplocal/auto" poplocalbin="$poplocal/bin"
export poplib="${poplib:-$HOME}"    popsavelib="$U/target/psv"
export popcomppath=":$poplib:$poplocalauto:$popautolib:$popliblib"
export popsavepath=":$poplib:$poplocalbin:$popsavelib"

POP="$U/target/pop/pop11 +$U/target/psv/startup.psv %nort"

case "$1" in
  -c) # run one line of Forth, non-interactively
    printf "uses forth;\nforth_run('%s');\n" "$2" | $POP ;;
  -t) # run the testbench
    printf "uses forth;\nforth_run('testbench');\n" | $POP ;;
  -b) # run the performance benchmark
    printf "uses forth;\nforth_run('bench');\n" | $POP ;;
  '') # interactive REPL: echo the setup, then hand the terminal to Forth via cat
    { echo 'uses forth; forth();'; cat; } | $POP ;;
  *)  # load a .fth file, then drop into the REPL
    { printf "uses forth; loadcompiler('%s'); forth();\n" "$1"; cat; } | $POP ;;
esac

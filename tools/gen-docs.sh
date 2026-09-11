#!/bin/sh
# gen-docs.sh — generate the static documentation site + llms.txt.
#
#   tools/gen-docs.sh [engine-command]
#
# Runs tools/gen-docs.p (a Pop-11 program) over the HELP/TEACH/REF
# corpus; output lands in dist/docs/ (index.html, llms.txt, one page
# per doc file, cross-references linked).  Serve it with any static
# host, e.g.:  python3 -m http.server -d dist/docs
set -e

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

if [ -n "$1" ]; then
    engine="$1"
else
    [ -x "$repo/target/pop/basepop11" ] || {
        echo "gen-docs: no target/pop/basepop11 (build first, or pass an engine)" >&2; exit 2; }
    engine="$repo/poplog $repo/target/pop/basepop11"
fi
# riscv64 Poplog must run with ASLR off (see PORTING-RISCV64-LINUX.md)
case "$(uname -m)" in
    riscv64) engine="setarch -R $engine" ;;
esac

# shellcheck disable=SC2086  # $engine may be "wrapper binary"
$engine "$repo/tools/gen-docs.p" 2>&1 | grep -E '^\*\*|MISHAP' | sed 's/^\*\* //'

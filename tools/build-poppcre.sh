#!/bin/sh
# build-poppcre.sh — build the PCRE2 shim used by LIB * PCRE.
#
#   tools/build-poppcre.sh
#
# Compiles pop/extern/poppcre/poppcre_shim.c to poppcre.{so|dylib} in
# the same directory.  Needs a C compiler and the PCRE2 development
# headers (Debian/Ubuntu: libpcre2-dev; macOS: brew install pcre2).
set -e

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo/pop/extern/poppcre/poppcre_shim.c"

case "$(uname -s)" in
    Darwin) lib="$repo/pop/extern/poppcre/poppcre.dylib" ;;
    *)      lib="$repo/pop/extern/poppcre/poppcre.so" ;;
esac

if [ -f "$lib" ] && [ ! "$src" -nt "$lib" ]; then
    echo "up to date: $lib"
    exit 0
fi

command -v cc >/dev/null 2>&1 || { echo "build-poppcre: needs a C compiler" >&2; exit 2; }

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libpcre2-8 2>/dev/null; then
    flags="$(pkg-config --cflags --libs libpcre2-8)"
else
    flags="-lpcre2-8"
fi

# shellcheck disable=SC2086
cc -O2 -shared -fPIC -o "$lib" "$src" $flags
echo "built $lib"

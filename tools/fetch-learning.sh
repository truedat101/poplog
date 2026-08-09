#!/bin/sh
# fetch-learning.sh — download open educational Pop-11 / Prolog material
# (teach files, instructor packs, classic AI toolkits) into learn/.
#
#   tools/fetch-learning.sh list             # show available packs
#   tools/fetch-learning.sh <pack> [...]     # fetch named packs
#   tools/fetch-learning.sh --all            # fetch every pack
#   tools/fetch-learning.sh --update         # re-fetch / pull already-fetched packs
#
# Content lands in learn/<pack>/ (gitignored — this repository distributes
# only this fetch script, never the material itself; upstream licences
# apply to each pack).  Each pack records its provenance in
# learn/<pack>/.source.  After fetching, learn/learn.p is regenerated: it
# extends Poplog's teach/help/lib search lists so the material is reachable
# from ved (e.g. "teach respond") once loaded.
#
# Overrides (env):
#   POPLOG_LEARN_DIR   destination directory (default <repo>/learn)
set -e

repo="$(cd "$(dirname "$0")/.." && pwd)"
dest="${POPLOG_LEARN_DIR:-$repo/learn}"

PACKS="hidden-gems examples packages bhamteach paradigms primer screamer"

# archive of the former Birmingham "Free Poplog" site (cs.bham.ac.uk
# redirects here); maintained by the GetPoplog project
ARCHIVE=https://poplogarchive.getpoplog.org

pack_kind() {
    case "$1" in
        hidden-gems|examples|packages|paradigms) echo git ;;
        bhamteach) echo zip ;;
        screamer)  echo tar ;;
        primer)    echo file ;;
    esac
}

pack_url() {
    case "$1" in
        hidden-gems) echo https://github.com/sfkleach/hidden-gems-of-pop11 ;;
        examples)    echo https://github.com/GetPoplog/examples ;;
        packages)    echo https://github.com/hebisch/poplog_packages ;;
        paradigms)   echo https://github.com/GetPoplog/paradigms_lectures ;;
        bhamteach)   echo "$ARCHIVE/bhamteach.zip" ;;
        screamer)    echo "$ARCHIVE/packages/screamer.tar.gz" ;;
        primer)      echo "$ARCHIVE/primer.pdf" ;;
    esac
}

pack_desc() {
    case "$1" in
        hidden-gems) echo "small idiomatic Pop-11 feature demos (open stack, updaters, coroutines...; CC0)" ;;
        examples)    echo "GetPoplog teaching examples from the Poplog Archive (othello, life, robolang...)" ;;
        packages)    echo "classic package tree: SimAgent+Poprulebase (newkit), popvision, rclib, neural, teaching" ;;
        bhamteach)   echo "Birmingham intro-AI course TEACH files (chatbots, grammars, story generation)" ;;
        paradigms)   echo "UMASS programming-language-paradigms course taught in Pop-11" ;;
        primer)      echo "the Pop-11 Primer (PDF) — the standard 'learn Pop-11' text" ;;
        screamer)    echo "constraint programming (nondeterministic search) package" ;;
    esac
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# extract an archive staged in $1 into pack dir $2, collapsing a single
# top-level directory if the archive has one
place() {
    stage="$1"; packdir="$2"
    set -- "$stage"/*
    if [ $# -eq 1 ] && [ -d "$1" ]; then
        mv "$1" "$packdir"
    else
        mkdir -p "$packdir"
        mv "$stage"/* "$packdir"/
    fi
}

write_source() {
    # $1 pack dir, $2 url, $3 provenance line
    {
        echo "url: $2"
        echo "fetched: $(date -u +%Y-%m-%d)"
        echo "$3"
    } > "$1/.source"
}

fetch_pack() {
    pack="$1"
    url="$(pack_url "$pack")"
    [ -n "$url" ] || { echo "fetch-learning: unknown pack '$pack' (try: list)" >&2; exit 2; }
    packdir="$dest/$pack"

    if [ -e "$packdir/.source" ] && [ "$update" != yes ]; then
        echo "$pack: already fetched (--update to refresh)"
        return
    fi

    echo "fetching $pack from $url ..."
    case "$(pack_kind "$pack")" in
    git)
        if [ -d "$packdir/.git" ]; then
            git -C "$packdir" pull --ff-only
        else
            rm -rf "$packdir"
            git clone --depth 1 "$url" "$packdir"
        fi
        write_source "$packdir" "$url" "commit: $(git -C "$packdir" rev-parse HEAD)"
        ;;
    tar|zip|file)
        tmp="$(mktemp -d)"
        # shellcheck disable=SC2064  # expand $tmp now, not at exit
        trap "rm -rf '$tmp'" EXIT
        f="$tmp/$(basename "$url")"
        curl -fL --progress-bar -o "$f" "$url"
        hash="$(sha256 "$f")"
        rm -rf "$packdir"
        case "$(pack_kind "$pack")" in
        tar)
            mkdir "$tmp/x"; tar -xzf "$f" -C "$tmp/x"; place "$tmp/x" "$packdir" ;;
        zip)
            mkdir "$tmp/x"
            if command -v unzip >/dev/null 2>&1; then unzip -q "$f" -d "$tmp/x"
            else python3 -m zipfile -e "$f" "$tmp/x"; fi
            place "$tmp/x" "$packdir" ;;
        file)
            mkdir -p "$packdir"; mv "$f" "$packdir/" ;;
        esac
        write_source "$packdir" "$url" "sha256: $hash"
        rm -rf "$tmp"; trap - EXIT
        ;;
    esac
    echo "$pack: ok -> $packdir"
}

# regenerate learn/learn.p: extend Poplog search lists with every
# teach/help/ref/lib/auto directory found under the fetched packs
gen_learn_p() {
    out="$dest/learn.p"
    {
        echo ";;; learn.p — GENERATED by tools/fetch-learning.sh; do not edit."
        echo ";;; Makes fetched teaching material reachable from Poplog/ved:"
        echo ";;;   load $out"
        echo ";;; (or add that line to your \$poplib/init.p)"
        echo "compile_mode :pop11 +strict;"
        echo "section;"
        for kind in teach help ref lib auto; do
            case "$kind" in
                teach) list=vedteachlist ;;
                help)  list=vedhelplist ;;
                ref)   list=vedreflist ;;
                lib)   list=popuseslist ;;
                auto)  list=popautolist ;;
            esac
            find "$dest" -mindepth 2 -maxdepth 5 -type d -name "$kind" 2>/dev/null | LC_ALL=C sort |
            while read -r d; do
                echo "extend_searchlist('$d/', $list, true) -> $list;"
            done
        done
        echo "endsection;"
    } > "$out"
    echo "regenerated $out"
}

case "${1:-}" in
""|-h|--help)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
list)
    for p in $PACKS; do
        printf '  %-12s %s\n' "$p" "$(pack_desc "$p")"
    done
    exit 0 ;;
--all)
    update=no
    set -- $PACKS ;;
--update)
    update=yes
    shift $#
    for p in $PACKS; do
        [ -e "$dest/$p/.source" ] && set -- "$@" "$p"
    done
    [ $# -gt 0 ] || { echo "fetch-learning: nothing fetched yet (try: --all)"; exit 0; } ;;
*)
    update=no ;;
esac

command -v curl >/dev/null 2>&1 || { echo "fetch-learning: needs curl" >&2; exit 2; }
mkdir -p "$dest"
for p in "$@"; do fetch_pack "$p"; done
gen_learn_p
echo
echo "Use it:  pop11 -> load $dest/learn.p  then e.g. ved + <ENTER> teach"
echo "(browse packs under $dest/; see LEARNING.md for a guided tour)"

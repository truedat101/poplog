#!/bin/sh
# install.sh — one-command setup for the pop11 Claude skill.
#
#   sh .claude/skills/pop11/install.sh [--poplog-root DIR] [--copy]
#
# What it does:
#   1. finds a built Poplog tree (--poplog-root, $POPLOG_ROOT, or probes)
#   2. persists it to ~/.cache/pop11-skill/config.json (no env var needed after)
#   3. links this skill into ~/.claude/skills/pop11 (all projects see it;
#      --copy copies instead of symlinking)
#   4. builds the popcurl HTTPS shim if a C compiler is available
#   5. runs a live smoke test: start session -> compute -> stop
#
# Uninstall: rm ~/.claude/skills/pop11; rm -rf ~/.cache/pop11-skill
set -e

here="$(cd "$(dirname "$0")" && pwd)"
cache="$HOME/.cache/pop11-skill"
skills_dir="$HOME/.claude/skills"
mode="link"
root="${POPLOG_ROOT:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --poplog-root) root="$2"; shift 2 ;;
        --copy)        mode="copy"; shift ;;
        *) echo "usage: install.sh [--poplog-root DIR] [--copy]" >&2; exit 2 ;;
    esac
done

# 1. find the engine
if [ -z "$root" ]; then
    for cand in "$here/../../.." "$HOME/poplog" /usr/local/poplog /opt/poplog; do
        if [ -x "$cand/target/pop/basepop11" ]; then root="$cand"; break; fi
    done
fi
[ -n "$root" ] && [ -x "$root/target/pop/basepop11" ] || {
    echo "install: no built Poplog tree found." >&2
    echo "  Build one (see INSTALL) then rerun with --poplog-root /path/to/tree" >&2
    exit 2
}
root="$(cd "$root" && pwd)"
echo "engine:  $root"

# 2. persist config
mkdir -p "$cache"
printf '{"root": "%s"}\n' "$root" > "$cache/config.json"
echo "config:  $cache/config.json"

# 3. install the skill
mkdir -p "$skills_dir"
if [ -e "$skills_dir/pop11" ] || [ -L "$skills_dir/pop11" ]; then
    rm -rf "$skills_dir/pop11"
fi
if [ "$mode" = "link" ]; then
    ln -s "$here" "$skills_dir/pop11"
else
    cp -R "$here" "$skills_dir/pop11"
fi
echo "skill:   $skills_dir/pop11 ($mode)"

# 4. popcurl (best-effort)
if command -v cc >/dev/null 2>&1; then
    "$here/bin/build-popcurl" || echo "install: popcurl build failed; curl-CLI fallback still works"
else
    echo "install: no C compiler; skipping popcurl (curl-CLI fallback still works)"
fi

# 5. smoke test
echo "smoke:   starting a session..."
"$here/bin/popsession" stop --name install-smoke >/dev/null 2>&1 || true
"$here/bin/popsession" start --name install-smoke --poplog-root "$root" >/dev/null
out="$("$here/bin/popsession" send --name install-smoke -c "npr('pop11 skill ok: ' sys_>< (6 * 7));")"
"$here/bin/popsession" stop --name install-smoke >/dev/null
case "$out" in
    *"pop11 skill ok: 42"*) echo "smoke:   $out" ;;
    *) echo "smoke:   FAILED: $out" >&2; exit 1 ;;
esac

echo
echo "Done. Try:   $skills_dir/pop11/bin/popsession start"
echo "In Claude Code, the pop11 skill is now available in every project."

#!/bin/sh
# install-skill.sh — one-command installer for the pop11 Claude skill.
# No clone, no build: pulls a relocatable binary tarball from GitHub releases.
#
#   curl -fsSL https://raw.githubusercontent.com/IoTone/poplog/master/tools/install-skill.sh | sh
#
# Overrides (env):
#   POP11_SKILL_PREFIX   install prefix   (default ~/.local/share/pop11-skill)
#   POP11_SKILL_URL      tarball URL      (default: latest GitHub release asset
#                        for this OS/arch; any curl-able URL incl. file://)
#
# What it does: download tarball -> unpack to prefix -> rewrite the poplog
# wrapper for the unpack path -> run the bundled skill/install.sh (persists
# engine config, links skill into ~/.claude/skills, builds the popcurl shim,
# runs a live session smoke test).
#
# Uninstall: rm -rf "$POP11_SKILL_PREFIX" ~/.claude/skills/pop11 ~/.cache/pop11-skill
set -e

prefix="${POP11_SKILL_PREFIX:-$HOME/.local/share/pop11-skill}"

case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux)  os=linux ;;
    *) echo "install-skill: unsupported OS $(uname -s)" >&2; exit 2 ;;
esac
arch="$(uname -m)"
url="${POP11_SKILL_URL:-https://github.com/IoTone/poplog/releases/latest/download/pop11-skill-$os-$arch.tar.gz}"

command -v curl >/dev/null 2>&1 || { echo "install-skill: needs curl" >&2; exit 2; }

echo "pop11-skill installer"
echo "  platform: $os-$arch"
echo "  source:   $url"
echo "  prefix:   $prefix"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "downloading..."
curl -fL --progress-bar -o "$tmp/pop11-skill.tar.gz" "$url" || {
    echo "install-skill: download failed. No prebuilt tarball for $os-$arch?" >&2
    echo "  Build from source instead: github.com/IoTone/poplog (see INSTALL)," >&2
    echo "  then: sh .claude/skills/pop11/install.sh --poplog-root <tree>" >&2
    exit 1
}

rm -rf "$prefix"
mkdir -p "$prefix"
tar -xzf "$tmp/pop11-skill.tar.gz" -C "$prefix" --strip-components 1

# the single relocation fix-up: point the env wrapper at the unpack path
sed "s#^poplogroot=.*#poplogroot=$prefix#" "$prefix/poplog" > "$prefix/poplog.new"
mv "$prefix/poplog.new" "$prefix/poplog"
chmod +x "$prefix/poplog"

sh "$prefix/skill/install.sh" --poplog-root "$prefix"

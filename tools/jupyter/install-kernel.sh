#!/bin/sh
# install-kernel.sh — register the Pop-11 Jupyter kernel.
#
#   tools/jupyter/install-kernel.sh
#
# Uses the running python3 if it already has ipykernel; otherwise creates
# a small dedicated venv at ~/.cache/pop11-skill/jupyter-venv (alongside
# the skill's other machine state) and installs ipykernel there.  Then
# writes the kernelspec so `jupyter lab` / `jupyter console` list
# "Pop-11".
#
# Env overrides:
#   POP11_SESSION_BIN   popsession executable
#                       (default ~/.claude/skills/pop11/bin/popsession)
#   POP11_KERNEL_PYTHON python to run the kernel with (skips venv logic)
set -e

here="$(cd "$(dirname "$0")" && pwd)"
kernel_py="$here/pop11_kernel.py"
popsession="${POP11_SESSION_BIN:-$HOME/.claude/skills/pop11/bin/popsession}"

[ -x "$popsession" ] || {
    echo "install-kernel: popsession not found at $popsession" >&2
    echo "  (install the pop11 skill first, or set POP11_SESSION_BIN)" >&2
    exit 2
}

# ---- pick a python with ipykernel -----------------------------------------
py="$POP11_KERNEL_PYTHON"
if [ -z "$py" ] && python3 -c 'import ipykernel' 2>/dev/null; then
    py="$(command -v python3)"
fi
if [ -z "$py" ]; then
    venv="$HOME/.cache/pop11-skill/jupyter-venv"
    if [ ! -x "$venv/bin/python3" ]; then
        echo "install-kernel: creating venv at $venv"
        python3 -m venv "$venv"
    fi
    "$venv/bin/python3" -c 'import ipykernel' 2>/dev/null || {
        echo "install-kernel: installing ipykernel into the venv"
        "$venv/bin/pip" -q install ipykernel
    }
    py="$venv/bin/python3"
fi
echo "install-kernel: kernel python: $py"

# ---- write the kernelspec --------------------------------------------------
case "$(uname -s)" in
    Darwin) kdir="$HOME/Library/Jupyter/kernels/pop11" ;;
    *)      kdir="${XDG_DATA_HOME:-$HOME/.local/share}/jupyter/kernels/pop11" ;;
esac
mkdir -p "$kdir"
cat > "$kdir/kernel.json" <<EOF
{
  "argv": ["$py", "$kernel_py", "-f", "{connection_file}"],
  "display_name": "Pop-11",
  "language": "pop11",
  "env": { "POP11_SESSION_BIN": "$popsession" }
}
EOF
echo "install-kernel: kernelspec written to $kdir"
echo "Try:  jupyter console --kernel pop11    (or pick Pop-11 in JupyterLab)"

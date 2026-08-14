# Pop-11 Jupyter kernel

A thin adapter (2030plan 1.3): each notebook cell is one `popsession
send` into a persistent Poplog engine, so the hard parts — FIFO stdin,
sentinel framing, mishap survival — are the pop11 skill's field-proven
machinery. Defines are native-compiled as cells run and survive between
cells; a mishap shows its diagnostics red and the session lives on. The
🌈 line after each cell is the real wall-clock cost.

## Install

Prereqs: the pop11 skill installed (`install.sh` or the curl one-liner)
and `python3`. Then:

```sh
tools/jupyter/install-kernel.sh
```

Uses your `python3` if it already has ipykernel; otherwise creates a
small venv at `~/.cache/pop11-skill/jupyter-venv`. Registers the
"Pop-11" kernelspec for JupyterLab / `jupyter console --kernel pop11` /
VS Code notebooks.

## Try it

`examples/notebooks/pop11-live.ipynb` — executed for real through this
kernel (the committed outputs are genuine).

## Files

- `pop11_kernel.py` — the kernel (ipykernel wrapper class, ~150 lines)
- `install-kernel.sh` — python resolution + kernelspec registration

# Pop-11 for Zed

Tree-sitter highlighting, outline symbols, brackets, and comment
support for Pop-11 (`.p`, `.ph`, `.pop11`), built on
[IoTone/tree-sitter-pop11](https://github.com/IoTone/tree-sitter-pop11).

## Install (dev extension)

Zed → `zed: install dev extension` (command palette) → pick this
directory (`editors/zed` in the poplog checkout). Zed fetches and
builds the grammar itself from the pinned commit in `extension.toml`.

## `.p` is contested

Pascal/Gnuplot/OpenEdge also use `.p`, and Zed has no content sniffing.
This extension claims `.p`; in a project where that's wrong, override
per-project in `.zed/settings.json`:

```json
{ "file_types": { "Pascal": ["p"] } }
```

## Language server

Zed can only launch language servers through extension WASM code, which
this pure-config extension doesn't ship yet. The Pop-11 LSP server
(`tools/pop11-lsp` — real-compiler diagnostics, HELP hover, dictionary
completion) works today in Neovim (`editors/nvim/`) and any client that
can run a stdio command; Zed wiring is a planned follow-up.

## Registry

Publishing to the Zed extension registry requires the extension to live
in its own repository (zed-industries/extensions takes it as a
submodule). This directory is the source of truth until then.

## Keeping queries in sync

`highlights.scm` / `injections.scm` are vendored from the grammar
repo's `queries/` (the source of truth), same as `editors/nvim/`.
`outline.scm` and `brackets.scm` are Zed-specific.

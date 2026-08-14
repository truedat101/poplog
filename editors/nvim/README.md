# Pop-11 for Neovim

Filetype detection and tree-sitter highlighting for Pop-11 (`.p`,
`.pop11`, `.ph`). `.p` files are content-sniffed so Pascal and Gnuplot
files keep their own filetypes.

## Install

With lazy.nvim, point a plugin spec at this directory of the Poplog
checkout:

```lua
{
  dir = '~/path/to/poplog/editors/nvim',
  name = 'pop11',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
}
```

then install the grammar (registered automatically from
[IoTone/tree-sitter-pop11](https://github.com/IoTone/tree-sitter-pop11)):

```vim
:TSInstall pop11
```

The `queries/pop11/` directory here is vendored from the grammar repo
(its `queries/` are the source of truth); it rides Neovim's runtimepath
so highlights work as soon as the parser is installed.

## What you get

- filetype + `;;; ` commentstring
- highlighting, folds (`define`/blocks/comments), textobjects
  (`af`/`if` on definitions with nvim-treesitter-textobjects)

LSP wiring (`poplog-lsp`) lands with phase P2 of
`poplog-language-binding-plugins.md`.

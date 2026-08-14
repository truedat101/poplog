-- Pop-11 filetype detection + tree-sitter grammar registration.
--
-- `.p` is contested (Vim defaults it to Pascal; linguist adds Gnuplot and
-- OpenEdge), so `.p` files are sniffed with the content heuristics from
-- poplog-language-binding-plugins.md §3 — near-unambiguous against both.
-- `.pop11` and `.ph` are claimed outright.

local function looks_like_pop11(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 80, false)
  for _, line in ipairs(lines) do
    if line:find(';;;', 1, true)
      or line:match('^%s*define%f[%W].*;')
      or line:find('enddefine', 1, true)
      or line:match('^%s*l?vars%f[%W]')
      or line:find('compile_mode', 1, true)
    then
      return true
    end
  end
  return false
end

vim.filetype.add {
  extension = {
    pop11 = 'pop11',
    ph = 'pop11',
    p = function(path, bufnr)
      if looks_like_pop11(bufnr) then
        return 'pop11'
      end
      -- fall through to Vim's default for .p (pascal)
    end,
  },
}

-- Register the grammar with nvim-treesitter until it is upstreamed.
-- After this loads:  :TSInstall pop11
local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
if ok and parsers.get_parser_configs then
  local parser_config = parsers.get_parser_configs()
  if not parser_config.pop11 then
    parser_config.pop11 = {
      install_info = {
        url = 'https://github.com/IoTone/tree-sitter-pop11',
        files = { 'src/parser.c', 'src/scanner.c' },
        branch = 'main',
      },
      filetype = 'pop11',
      maintainers = { '@IoTone' },
    }
  end
end

-- Comment string for commenting plugins / 'gc'
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'pop11',
  callback = function()
    vim.bo.commentstring = ';;; %s'
  end,
})

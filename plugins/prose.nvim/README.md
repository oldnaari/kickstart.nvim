# prose.nvim

Tools for writing prose in Neovim. Each one answers a different question.

| Feature   | Question                        | Entry points                          | Needs                |
| :-------- | :------------------------------ | :------------------------------------ | :------------------- |
| Vale      | Mechanical problems, as I type? | diagnostics from `vale_ls`            | `vale`, `vale-ls`    |
| Spell     | Is this word known?             | `zgl` (local list), `zgg` (global)    | nothing              |
| Review    | Is the structure clear?         | `<leader>pr`, `:ProseReview`          | `claude` CLI         |
| Synonyms  | What else means this?           | `<leader>ps`, `:Synonyms`, `<C-x><C-t>` | WordNet (`wn`)     |
| Fill      | What else fits here?            | `<leader>pf`, `:Fill`                 | `uv`                 |
| Highlight | Where are the asides?           | dims `(parentheticals)`, colours `"quotes"` | `mini.hipatterns` |
| Keyboard  | Type Armenian or Russian?       | `<leader>k` picker, `<C-^>` in Insert | `telescope.nvim` (optional) |

`:checkhealth prose` reports which of these tools are installed.

## Layout

```
lua/prose/init.lua          setup(), commands, keymaps, vale_ls config
lua/prose/review.lua        claude -p review into quickfix
lua/prose/alternatives.lua  synonyms and fill
lua/prose/spell.lua         the two word lists
lua/prose/highlight.lua     mini.hipatterns highlighters
lua/prose/layout.lua        keyboard layout switching
lua/prose/health.lua        :checkhealth prose
keymap/                     Armenian keymap matching the macOS HM QWERTY layout
bin/syn, bin/fill           command-line tools; setup() puts bin/ on $PATH
vale/                       Vale config and the Prompt style
```

## Setup (lazy.nvim)

Load it at startup. The spell lists must exist before any buffer turns spell on.

```lua
{
  dir = vim.fn.stdpath 'config' .. '/plugins/prose.nvim',
  name = 'prose.nvim',
  main = 'prose',
  lazy = false,
  opts = {},
}
```

The defaults:

```lua
{
  filetypes = { 'markdown' },
  keys = { review = '<leader>pr', synonym = '<leader>ps', fill = '<leader>pf', layout = '<leader>k' }, -- each may be false
  layouts = { -- in the <leader>k picker, `key` picks at once; keymap = '' means English
    { key = 'e', name = 'English', keymap = '' },
    { key = 'a', name = 'Armenian', keymap = 'armenian-hmqwerty' },
    { key = 'r', name = 'Russian', keymap = 'russian-jcukenmac' },
  },
  thesaurus = true, -- 'thesaurusfunc' for <C-x><C-t>
  path = true,      -- put bin/ on $PATH
  spell = {},       -- { local_list = ..., global_list = ... }, or false to skip
  vale = true,      -- configure vale_ls with vale/.vale.ini
}
```

Two parts stay in your own config:

- **Enabling vale_ls.** The plugin configures the server but does not start it. Use mason-lspconfig or `vim.lsp.enable 'vale_ls'`.
- **Highlighting.** mini.hipatterns has one global config, so pass the highlighters in yourself:

  ```lua
  require('mini.hipatterns').setup { highlighters = require('prose.highlight').highlighters() }
  ```

  The groups `MarkdownProseParen` and `MarkdownProseString` link to `Comment` and `String` unless your theme defines them.

The keyboard layouts use Vim's `'keymap'`, so the OS layout stays on English and Normal-mode commands keep working. The `<leader>k` picker opens in Normal mode: pick with j/k or the arrows and Enter, or press a layout's key. Without Telescope it falls back to `vim.ui.select`. The Armenian keymap's Option-layer letters (ը, շ, է, …) need a terminal that sends Option as Alt, such as iTerm2 with Option set to Esc+.

The global spell list is personal data. It defaults to `spell/en.utf-8.add` in your config, not in this plugin.

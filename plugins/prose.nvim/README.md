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
| Roles     | Who does what to whom?          | `<leader>pg`, `:ProseRoles [status\|stop]` | `uv`            |
| Keyboard  | Type Armenian or Russian?       | `<leader>k` picker, `<C-^>` in Insert | `telescope.nvim` (optional) |
| Emoji     | Which emoji is that?            | `<leader>pe`, `:Emoji`                | `telescope.nvim`, `telescope-symbols.nvim` |

`:checkhealth prose` reports which of these tools are installed.

## Layout

```
lua/prose/init.lua          setup(), commands, keymaps, vale_ls config
lua/prose/review.lua        claude -p review into quickfix
lua/prose/alternatives.lua  synonyms and fill
lua/prose/spell.lua         the two word lists, plus compiling spell/*.add
lua/prose/highlight.lua     mini.hipatterns highlighters
lua/prose/roles.lua         subject/action/object colouring from bin/roles
lua/prose/layout.lua        keyboard layout switching
lua/prose/emoji.lua         emoji picker (Telescope's symbols picker)
lua/prose/health.lua        :checkhealth prose
keymap/                     Armenian keymap matching the macOS HM QWERTY layout
bin/syn, bin/fill, bin/roles  command-line tools; setup() puts bin/ on $PATH
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
  keys = { review = '<leader>pr', synonym = '<leader>ps', fill = '<leader>pf', roles = '<leader>pg', layout = '<leader>k', emoji = '<leader>pe' }, -- each may be false
  layouts = { -- in the <leader>k picker, `key` picks at once; keymap = '' means English
    { key = 'e', name = 'English', keymap = '' },
    { key = 'a', name = 'Armenian', keymap = 'armenian-hmqwerty' },
    { key = 'r', name = 'Russian', keymap = 'russian-jcukenmac' },
  },
  thesaurus = true, -- 'thesaurusfunc' for <C-x><C-t>
  path = true,      -- put bin/ on $PATH
  spell = {},       -- { local_list = ..., global_list = ... }, or false to skip
  vale = true,      -- configure vale_ls with vale/.vale.ini
  roles = false,    -- true: colour grammar roles in every file of `filetypes` as it opens
}
```

Two parts stay in your own config:

- **Enabling vale_ls.** The plugin configures the server but does not start it. Use mason-lspconfig or `vim.lsp.enable 'vale_ls'`.
- **Highlighting.** mini.hipatterns has one global config, so pass the highlighters in yourself:

  ```lua
  require('mini.hipatterns').setup { highlighters = require('prose.highlight').highlighters() }
  ```

  The groups `MarkdownProseParen` and `MarkdownProseString` link to `Comment` and `String` unless your theme defines them.

## Roles

`<leader>pg` colours each sentence's subject, action (the verb, with its auxiliaries: "did not give up", "գրում եմ") and object, and puts a dotted underline under the other nouns. A dependency parser (Stanza, in `bin/roles`) labels the words; treesitter and regex cannot, because word order does not give it away ("Книгу читает мальчик": the object comes first). The language is picked from the letters, sentence by sentence, so a paragraph may mix English, Russian and Armenian.

What to expect:

- **Accuracy.** On the test sentences, English and Russian were right throughout, and Armenian in 19 of 20. Armenian uses Stanza's transformer-based package, because the default one got 15 of 20. Expect mistakes on long or unusual Armenian sentences.
- **No subject is not a bug.** Imperatives ("Write a function") have no subject word, and neither does Armenian when the verb ending carries it ("Գնացի տուն"). Roles are grammatical, so "The bug was fixed by Ann" has *bug* as its subject.
- **On or off.** It is off until you toggle it, unless `setup { roles = true }`, which turns it on in every markdown file as it opens (files only: LSP hover windows are markdown too, and stay plain). `<leader>pg` still turns it off in a buffer, and it stays off there when the file reloads.
- **Cost.** The first buffer with roles on starts one shared parser (`bin/roles --daemon`) that every Neovim connects to, so three tabs cost one set of models, not three. It loads English at once and keeps it: about 0.9 GB. Russian and Armenian load the first time they appear (5-15 s) and unload after 30 minutes unused, which takes the memory back down to the English level; change that with `require('prose.roles').keep_alive`. The first run downloads the models: about 300 MB each for English and Russian, and about 1.6 GB for Armenian.
- **It keeps running.** The parser outlives Neovim on purpose, so the next tab or Claude Code prompt colours English at once. It runs detached, writing only to `stdpath('state')/prose-roles.log`, so it never keeps an editor from closing. `:ProseRoles status` shows what it holds; `:ProseRoles stop` ends it and frees the memory, and turns roles off in that Neovim's buffers; with `roles = true`, the next file you open starts it again. When `bin/roles` changes, the old parser hands over to a fresh one. While it runs, `uv cache clean` waits for it (or pass `--force`).
- **Only what you see.** It parses the paragraphs in view and a screen either side, and more as you scroll, so a 3,000-paragraph file costs no more than a short one. After an edit, only the paragraphs whose text changed are parsed again, about 60 ms each.

`bin/roles --show < file.md` prints the roles in brackets, which is handy for checking a sentence. The groups `ProseSubject`, `ProseAction`, `ProseObject` and `ProseNoun` link to `Identifier`, `Statement` and `Type`, and a dotted underline, unless your theme defines them.

The keyboard layouts use Vim's `'keymap'`, so the OS layout stays on English and Normal-mode commands keep working. The `<leader>k` picker opens in Normal mode: pick with j/k or the arrows and Enter, or press a layout's key. Without Telescope it falls back to `vim.ui.select`. The Armenian keymap's Option-layer letters (ը, շ, է, …) need a terminal that sends Option as Alt, such as iTerm2 with Option set to Esc+.

`<leader>pe` opens Telescope's symbols picker on the emoji list from [telescope-symbols.nvim](https://github.com/nvim-telescope/telescope-symbols.nvim); add it to Telescope's `dependencies`. Search by English name ("thumbs up", "red heart"); Enter inserts the emoji after the cursor.

The global spell list is personal data. It defaults to `spell/en.utf-8.add` in your config, not in this plugin.

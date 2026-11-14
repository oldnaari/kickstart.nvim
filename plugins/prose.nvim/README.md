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
| Patterns  | What could be clearer?          | `<leader>pp`, `:ProsePatterns`, `]d` / `[d` | `uv`; WordNet (optional) |
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
lua/prose/roles.lua         the shared parser's client; subject/action/object colouring
lua/prose/patterns.lua      bad-pattern flags as diagnostics, from the same parse
lua/prose/layout.lua        keyboard layout switching
lua/prose/emoji.lua         emoji picker (Telescope's symbols picker)
lua/prose/health.lua        :checkhealth prose
keymap/                     Armenian keymap matching the macOS HM QWERTY layout
bin/syn, bin/fill, bin/roles  command-line tools; setup() puts bin/ on $PATH
patterns/                   the pattern checks bin/roles runs, and their word lists
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
  keys = { review = '<leader>pr', synonym = '<leader>ps', fill = '<leader>pf', roles = '<leader>pg', patterns = '<leader>pp', layout = '<leader>k', emoji = '<leader>pe' }, -- each may be false
  layouts = { -- in the <leader>k picker, `key` picks at once; keymap = '' means English
    { key = 'e', name = 'English', keymap = '' },
    { key = 'a', name = 'Armenian', keymap = 'armenian-hmqwerty' },
    { key = 'r', name = 'Russian', keymap = 'russian-jcukenmac' },
  },
  thesaurus = true, -- 'thesaurusfunc' for <C-x><C-t>
  path = true,      -- put bin/ on $PATH
  spell = {},       -- { local_list = ..., global_list = ... }, or false to skip
  vale = true,      -- configure vale_ls with vale/.vale.ini; its flags arrive as Hints
  roles = false,    -- true: colour grammar roles in every file of `filetypes` as it opens
  patterns = false, -- true: flag bad patterns in every such file; or { off = { 'Repetition' } }
}
```

Prose flags are advice, often fine to ignore, so they are never drawn as errors. Every Vale flag below `error` level arrives as a Hint (the Vale levels still decide what is shown at all, through `MinAlertLevel`). Style `DiagnosticUnderlineHint` to taste; this config uses a straight underline in Nord's bright black.

Three parts stay in your own config:

- **Enabling vale_ls.** The plugin configures the server but does not start it. Use mason-lspconfig or `vim.lsp.enable 'vale_ls'`.
- **Highlighting.** mini.hipatterns has one global config, so pass the highlighters in yourself:

  ```lua
  require('mini.hipatterns').setup { highlighters = require('prose.highlight').highlighters() }
  ```

  The groups `MarkdownProseParen` and `MarkdownProseString` link to `Comment` and `String` unless your theme defines them.
- **Reading a flag.** `]d` and `[d` jump between flags but, since Neovim 0.11, do not show the message. To see it on arrival:

  ```lua
  vim.diagnostic.config {
    jump = {
      on_jump = function(d, bufnr)
        if d then vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false } end
      end,
    },
  }
  ```

## Patterns

`<leader>pp` flags what in a draft could be clearer: a subject far from its verb, a passive, "make a decision" for "decide", a chain of genitives, a dangling modifier. It does not say what to write instead. Each flag is a dim underline (a Hint, never an error), `]d` and `[d` walk through them, and the message opens as you land on one, ending with the check's name, such as `[Prose.Passive]`.

The checks ride on the parser behind the role colours, so they cover English, Russian and Armenian, and turning on both costs one parse. Unlike the colours, they cover the whole file, so `]d` finds every flag: what is on screen is parsed first, the rest after it. Files over 2,000 lines (`require('prose.patterns').whole_file_lines`) are checked in view only.

| Check | What it flags | Trust (en / ru / hy) |
| :---- | :------------ | :------------------- |
| SubjectGap | 8+ words between a subject and its verb (Gopen & Swan) | medium / medium / low |
| ObjectGap | 6+ words between a verb and its object | medium / medium / low |
| LongOpener | 13+ words before the main clause starts | medium / medium / low |
| Nesting | clauses embedded in the middle of others, or nested 4 deep | medium / medium / low |
| Passive | each passive; notes the actor if it is named | high / medium / medium |
| Nominalization | an action noun with its object attached: "the implementation of the feature", «осуществление проверки» | medium / medium / low |
| LightVerb | a light verb with an action noun: "make a decision", «оказать помощь», «որոշում կայացնել» | medium / high / medium |
| EmptyOpener | "There are…", "It is important to note that…", «Следует отметить, что…» | high / high / medium |
| Wordy, Filler, Cliche, Hedge, Intensifier | phrases from the word lists in `patterns/lexicon/` | high / high / medium |
| NounStack | 3+ nouns stacked ("model evaluation pipeline config"), or a chain of 3+ genitives or "of" phrases | medium / high / medium |
| Negation | a double negative: "not uncommon", «не невозможно» | medium / low / low |
| Adverb | a manner adverb on a verb: "quickly", «быстро», «արագորեն» | high / high / medium |
| Dangling | an opening participle or converb whose implied doer is not the main subject | low / medium / low |
| Parallel | list items, or joined verbs, that open in different forms | high for lists |
| Acronym | an all-caps word used before it is defined (whole file only) | medium |
| Repetition | the same noun, adjective or adverb twice within 10 words | high, but often fine |
| Cohesion | a sentence whose subject the two before it never mention (old before new) | low |
| Monotony, RepeatedOpening | 4 sentences of the same length; 3 opening with the same word | high |
| ParagraphLength, Readability | over 6 sentences or 150 words; Flesch reading ease under 30 (en, ru) | high (as numbers) |
| Abstract | 45%+ of a paragraph's words rated abstract (en only) | medium |

"Trust" is how often a flag is a real instance of the pattern, not whether it needs changing: many passives and repetitions are right as they are. The ratings come from Stanza's accuracy per language and from checking the rules on sample sentences; Armenian parses least reliably. On 400 paragraphs of the prompt archive, Repetition flagged 38% of paragraphs and Passive 27%; every other check under 20%, most under 5%. Hide the ones you do not want:

```lua
opts = { patterns = { off = { 'Repetition', 'Cohesion' } } }
```

- **Word lists.** `patterns/lexicon/en.txt`, `ru.txt` and `hy.txt`, one entry per line under a `[section]`. Entries match the word as written or its dictionary form, so «являться» finds «является». Edits apply from the next paragraph parsed; no restart. The Armenian lists are a short start: there is no published list to take them from.
- **English extras, both optional.** WordNet (`brew install wordnet`) confirms English nominalizations ("decision" comes from "decide", "nation" from no verb). The Abstract check needs the concreteness ratings of Brysbaert, Warriner & Kuperman (2014); the first English paragraph downloads them once, 2 MB from the publisher, into `~/Library/Caches/prose.nvim` (`~/.cache/prose.nvim` on Linux). Without them that check is skipped.
- **Checking a rule.** `bin/roles --show --flags < file.md` lists every flag with its text and message.
- **Not here.** Sentence length stays a Vale rule (`Prompt.LongSentence`, and `Prompt.LongSentenceHyRu` for Armenian and Russian), and so does the vague "This is…" opener.

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

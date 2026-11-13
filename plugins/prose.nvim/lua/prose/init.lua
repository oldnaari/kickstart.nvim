-- prose.nvim: tools for writing prose, each answering a different question.
--
--   Vale        mechanical problems, as you type (vale_ls; rules in vale/)
--   Spell       two word lists: `zgl` local, `zgg` global (prose.spell)
--   Review      judgment calls by `claude -p`, into quickfix (prose.review)
--   Synonyms    what else MEANS this? WordNet (prose.alternatives, bin/syn)
--   Fill        what else FITS HERE? a masked model (prose.alternatives, bin/fill)
--   Highlight   dim parentheticals, colour quotes (prose.highlight)
--   Roles       colour subject, action, object: a parser, bin/roles (prose.roles)
--   Keyboard    type Armenian or Russian with the OS on English (prose.layout)
--
-- setup() only registers things: commands, a FileType autocmd, the spell lists,
-- the vale_ls config. The modules behind them load on first use.
--
-- Load it at startup, not lazily: the spell lists must be in place before any
-- buffer turns spell on (see prose/spell.lua).
--
-- `:checkhealth prose` lists the external tools each feature needs.

local M = {}

-- This file is <root>/lua/prose/init.lua.
M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')

M.defaults = {
  -- Where the keymaps, 'thesaurusfunc' and vale_ls apply.
  filetypes = { 'markdown' },
  -- Buffer-local, in `filetypes` only. Set any of them to false to skip it.
  keys = {
    review = '<leader>pr',
    synonym = '<leader>ps',
    fill = '<leader>pf',
    roles = '<leader>pg', -- toggles subject/action/object colouring
    layout = '<leader>k', -- opens the keyboard layout picker
  },
  -- Insert-mode keyboard layouts (Vim's 'keymap'); see prose/layout.lua.
  -- `key` picks the layout straight from the picker, so avoid the picker's own
  -- Normal-mode keys (j, k, i, q, G, ...). keymap = '' is none: the keys type
  -- what the OS layout says.
  layouts = {
    { key = 'e', name = 'English', keymap = '' },
    { key = 'a', name = 'Armenian', keymap = 'armenian-hmqwerty' },
    { key = 'r', name = 'Russian', keymap = 'russian-jcukenmac' },
  },
  -- `<C-x><C-t>` in insert mode completes with WordNet synonyms.
  thesaurus = true,
  -- Put bin/ on $PATH, so `:r !syn happy` and `:w !fill` work with no shell setup.
  path = true,
  -- Word list paths; see prose/spell.lua for the defaults. false skips spell setup.
  spell = {},
  -- Configure vale_ls with this plugin's Vale config. Enabling the server is
  -- still up to you (mason-lspconfig, or vim.lsp.enable 'vale_ls').
  vale = true,
}

M.config = vim.deepcopy(M.defaults)

local function attach(buf)
  local keys = M.config.keys or {}
  local function map(lhs, fn, desc)
    if lhs then
      vim.keymap.set('n', lhs, fn, { buffer = buf, desc = desc })
    end
  end

  -- Judgment-based review by `claude -p` (buried request, unclear referent,
  -- packed instruction) into quickfix -- what Vale's patterns cannot catch.
  -- Only ever on demand; see prose/review.lua.
  map(keys.review, function()
    require('prose.review').run(0)
  end, '[P]rose [R]eview')

  -- Synonyms = same meaning (WordNet). Fill = what fits here (language model).
  map(keys.synonym, function()
    require('prose.alternatives').pick_synonym()
  end, '[P]rose [S]ynonyms')
  map(keys.fill, function()
    require('prose.alternatives').pick_fill()
  end, '[P]rose [F]ill (what fits here)')

  map(keys.roles, function()
    require('prose.roles').toggle(0)
  end, '[P]rose [G]rammar roles (subject, action, object)')

  map(keys.layout, function()
    require('prose.layout').pick(M.config.layouts)
  end, '[K]eyboard layout')

  if M.config.thesaurus then
    vim.bo[buf].thesaurusfunc = "v:lua.require'prose.alternatives'.complete"
  end
end

-- Fallbacks for the groups prose/highlight.lua uses, so it works with any
-- colorscheme. `default`: a theme that defines them wins, whichever runs first.
local function default_highlights()
  vim.api.nvim_set_hl(0, 'MarkdownProseParen', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'MarkdownProseString', { link = 'String', default = true })
  vim.api.nvim_set_hl(0, 'ProseSubject', { link = 'Identifier', default = true })
  vim.api.nvim_set_hl(0, 'ProseAction', { link = 'Statement', default = true })
  vim.api.nvim_set_hl(0, 'ProseObject', { link = 'Type', default = true })
  vim.api.nvim_set_hl(0, 'ProseNoun', { underdotted = true, default = true })
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts)
  -- tbl_deep_extend merges lists index by index, so a shorter list would keep
  -- the defaults' tail. Lists given in opts replace the default outright.
  for _, list in ipairs { 'filetypes', 'layouts' } do
    if opts[list] ~= nil then
      M.config[list] = opts[list]
    end
  end
  local cfg = M.config

  if cfg.spell then
    require('prose.spell').setup(cfg.spell)
  end

  if cfg.path then
    local bin = M.root .. '/bin'
    if not vim.tbl_contains(vim.split(vim.env.PATH or '', ':', { plain = true }), bin) then
      vim.env.PATH = bin .. ':' .. (vim.env.PATH or '')
    end
  end

  vim.api.nvim_create_user_command('Synonyms', function(o)
    require('prose.alternatives').pick_synonym(o.args ~= '' and o.args or nil)
  end, { nargs = '?', desc = 'Replace the word under the cursor with a synonym, or yank a synonym of {word} (WordNet)' })
  vim.api.nvim_create_user_command('Fill', function()
    require('prose.alternatives').pick_fill()
  end, { desc = 'Words that fit in place of the one under the cursor (masked language model)' })
  vim.api.nvim_create_user_command('ProseRoles', function()
    require('prose.roles').toggle(0)
  end, { desc = 'Toggle colouring of subjects, actions and objects (Stanza parser, bin/roles)' })
  vim.api.nvim_create_user_command('ProseReview', function()
    require('prose.review').run(0)
  end, { desc = 'Review the buffer with `claude -p`; findings go to quickfix' })

  -- Vale on every buffer of these filetypes, Claude prompt temp files included.
  -- Those live outside any project, where no `.vale.ini` exists, so the config
  -- path is passed explicitly: one global config, kept in this plugin so it
  -- travels with it. Only `configPath` is needed -- a fixed root_dir or
  -- VALE_CONFIG_PATH were tried and changed nothing (verified headless).
  -- vim.lsp.config merges, so this may run before or after nvim-lspconfig.
  if cfg.vale then
    vim.lsp.config('vale_ls', {
      filetypes = cfg.filetypes,
      init_options = {
        configPath = M.root .. '/vale/.vale.ini',
        installVale = false, -- use the vale on PATH (Mason's), never a second downloaded copy
        syncOnStartup = false, -- no Packages to sync; skip the startup cost
      },
    })
  end

  local group = vim.api.nvim_create_augroup('prose', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    desc = 'Prose keymaps and synonym completion',
    group = group,
    pattern = cfg.filetypes,
    callback = function(args)
      attach(args.buf)
    end,
  })
  -- Buffers whose FileType fired before setup ran.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(cfg.filetypes, vim.bo[buf].filetype) then
      attach(buf)
    end
  end

  default_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Prose highlight fallbacks',
    group = group,
    callback = default_highlights,
  })
end

return M

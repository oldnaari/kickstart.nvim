--[[

=====================================================================
==================== READ THIS BEFORE CONTINUING ====================
=====================================================================
========                                    .-----.          ========
========         .----------------------.   | === |          ========
========         |.-""""""""""""""""""-.|   |-----|          ========
========         ||                    ||   | === |          ========
========         ||   KICKSTART.NVIM   ||   |-----|          ========
========         ||                    ||   | === |          ========
========         ||                    ||   |-----|          ========
========         ||:Tutor              ||   |:::::|          ========
========         |'-..................-'|   |____o|          ========
========         `"")----------------(""`   ___________      ========
========        /::::::::::|  |::::::::::\  \ no mouse \     ========
========       /:::========|  |==hjkl==:::\  \ required \    ========
========      '""""""""""""'  '""""""""""""'  '""""""""""'   ========
========                                                     ========
=====================================================================
=====================================================================

What is Kickstart?

  Kickstart.nvim is *not* a distribution.

  Kickstart.nvim is a starting point for your own configuration.
    The goal is that you can read every line of code, top-to-bottom, understand
    what your configuration is doing, and modify it to suit your needs.

    Once you've done that, you can start exploring, configuring and tinkering to
    make Neovim your own! That might mean leaving Kickstart just the way it is for a while
    or immediately breaking it into modular pieces. It's up to you!

    If you don't know anything about Lua, I recommend taking some time to read through
    a guide. One possible example which will only take 10-15 minutes:
      - https://learnxinyminutes.com/docs/lua/

    After understanding a bit more about Lua, you can use `:help lua-guide` as a
    reference for how Neovim integrates Lua.
    - :help lua-guide
    - (or HTML version): https://neovim.io/doc/user/lua-guide.html

Kickstart Guide:

  TODO: The very first thing you should do is to run the command `:Tutor` in Neovim.

    If you don't know what this means, type the following:
      - <escape key>
      - :
      - Tutor
      - <enter key>

    (If you already know the Neovim basics, you can skip this step.)

  Once you've completed that, you can continue working through **AND READING** the rest
  of the kickstart init.lua.

  Next, run AND READ `:help`.
    This will open up a help window with some basic information
    about reading, navigating and searching the builtin help documentation.

    This should be the first place you go to look when you're stuck or confused
    with something. It's one of my favorite Neovim features.

    MOST IMPORTANTLY, we provide a keymap "<space>sh" to [s]earch the [h]elp documentation,
    which is very useful when you're not exactly sure of what you're looking for.

  I have left several `:help X` comments throughout the init.lua
    These are hints about where to find more information about the relevant settings,
    plugins or Neovim features used in Kickstart.

   NOTE: Look for lines like this

    Throughout the file. These are for you, the reader, to help you understand what is happening.
    Feel free to delete them once you know what you're doing, but they should serve as a guide
    for when you are first encountering a few different constructs in your Neovim config.

If you experience any errors while trying to install kickstart, run `:checkhealth` for more info.

I hope you enjoy your Neovim journey,
- TJ

P.S. You can delete this when you're done too. It's your config now! :)
--]]

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

vim.g.nord_disable_background = true
-- [[ Setting options ]]
-- See `:help vim.opt`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Make line numbers default
vim.opt.number = true
vim.opt.relativenumber = false
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
-- vim.opt.relativenumber = true
vim.opt.statuscolumn = '%s%=%l ▏'

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

vim.g.python3_host_prog = vim.fn.exepath 'python' ~= '' and vim.fn.exepath 'python' or vim.fn.exepath 'python3'

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.opt.clipboard = 'unnamedplus'
  -- WezTerm doesn't respond to OSC 52 paste queries on Linux/Wayland (wezterm/wezterm#2050,
  -- PR #6239 unmerged as of 2026). Fall back to wl-paste when inside WezTerm on Linux.
  local osc52 = require 'vim.ui.clipboard.osc52'
  local wezterm_on_linux = vim.env.TERM_PROGRAM == 'WezTerm'
    and vim.uv.os_uname().sysname == 'Linux'
    and vim.fn.executable 'wl-paste' == 1
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = osc52.copy '+',
      ['*'] = osc52.copy '*',
    },
    paste = wezterm_on_linux and {
      ['+'] = { 'wl-paste', '--no-newline', '--type', 'text/plain' },
      ['*'] = { 'wl-paste', '--no-newline', '--primary', '--type', 'text/plain' },
    } or {
      ['+'] = osc52.paste '+',
      ['*'] = osc52.paste '*',
    },
  }
end)

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Keep signcolumn on by default
vim.opt.signcolumn = 'yes'

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
-- Displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

vim.keymap.set('x', '<leader>n', ':normal ', { noremap = true, silent = false })

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- ]d / [d (built in) jump between diagnostics but, since 0.11, do not show the
-- message, and virtual text is off. Open the float on arrival instead; it closes
-- when the cursor moves. Prose flags (Vale, prose.nvim) depend on this: they
-- are dim underlines with no other text on screen.
vim.diagnostic.config {
  jump = {
    on_jump = function(diagnostic, bufnr)
      if diagnostic then
        vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false }
      end
    end,
  },
}

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Navigate changelist (older/newer change position)
vim.keymap.set('n', 'H', 'g;', { desc = 'Go to older position in changelist' })
vim.keymap.set('n', 'L', 'g,', { desc = 'Go to newer position in changelist' })

-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.highlight.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- [[ Claude Code prompt buffers ]]
--  `ctrl+g` in Claude Code opens the prompt in $EDITOR on a temp file named
--  `claude-prompt-<hash>.md`, and submits it on write. The pattern is specific
--  enough that neither of these can touch an ordinary markdown file.
local claude_prompt_pattern = 'claude-prompt*.md'
local claude_group = vim.api.nvim_create_augroup('claude-prompt', { clear = true })

-- Claude discards the temp file after submitting, so a prompt that took real
-- effort to write leaves no trace. Keep a copy; behaviour is otherwise unchanged.
vim.api.nvim_create_autocmd('BufWritePost', {
  desc = 'Archive Claude prompts so they can be searched and reused',
  group = claude_group,
  pattern = claude_prompt_pattern,
  callback = function(args)
    local body = table.concat(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false), '\n')
    if vim.trim(body) == '' then
      return
    end
    local dir = vim.fn.expand '~/.claude/prompt-archive'
    vim.fn.mkdir(dir, 'p')
    local path = string.format('%s/%s.md', dir, os.date '%Y-%m')
    local entry = string.format('\n\n---\n\n## %s\n\n%s\n', os.date '%Y-%m-%d %H:%M', body)
    local fh = io.open(path, 'a')
    if fh then
      fh:write(entry)
      fh:close()
    end
  end,
})

-- Claude's answers, written by the `Stop` hook at ~/.claude/hooks/claude-answer.sh.
-- The hook keys the file by cwd, the same slug convention ~/.claude/projects/ uses,
-- and Claude launches $EDITOR with the project as cwd -- so the right answer
-- resolves here with nothing to pick.
local claude_answers_dir = vim.fn.expand '~/.claude/answers'

local function claude_answer_file()
  local direct = string.format('%s/%s.md', claude_answers_dir, (vim.fn.getcwd():gsub('/', '-')))
  if vim.uv.fs_stat(direct) then
    return direct
  end
  -- Editing from somewhere other than the project: fall back to whichever answer
  -- was written last, skipping the YYYY-MM archives (history, not a reading surface).
  local newest, newest_time = nil, -1
  for _, path in ipairs(vim.fn.glob(claude_answers_dir .. '/*.md', false, true)) do
    if not vim.fn.fnamemodify(path, ':t:r'):match '^%d%d%d%d%-%d%d$' then
      local stat = vim.uv.fs_stat(path)
      if stat and stat.mtime.sec > newest_time then
        newest, newest_time = path, stat.mtime.sec
      end
    end
  end
  return newest
end

-- Deliberately NOT opened, split, floated, or even added to the buffer list on
-- its own. Two reasons, the second learned the hard way:
--
--  1. A second *window* would keep Neovim alive after `:wq`, and Claude waits for
--     the editor process to exit before submitting -- the prompt would never send.
--  2. A second listed *buffer* present at `:wq` time was observed to stop Neovim
--     exiting while zen-mode is open. Headless results were inconsistent, so the
--     mechanism is unconfirmed -- but the compose path is not the place to carry an
--     unconfirmed risk.
--
-- So pressing `<leader>o` is what pulls the answer in. Until then this changes
-- nothing about `ctrl+g`. Once opened, it is a listed buffer like any other, so
-- `<leader><leader>` swaps between answer and compose in the same window.
-- Add the answer to the buffer list without showing it, so `<leader><leader>`
-- (Telescope buffers) lists it straight away. Deliberately not a split, tab or
-- float: a second *window* keeps Neovim alive after `:wq`, and Claude waits for the
-- editor process to exit before submitting. One window, two buffers.
vim.api.nvim_create_autocmd('BufWinEnter', {
  desc = "Offer Claude's last answer as a buffer while composing",
  group = claude_group,
  pattern = claude_prompt_pattern,
  callback = function()
    local answer = claude_answer_file()
    if answer then
      pcall(vim.cmd, 'badd ' .. vim.fn.fnameescape(answer))
    end
  end,
})

vim.keymap.set('n', '<leader>o', function()
  local answer = claude_answer_file()
  if answer then
    vim.cmd('edit ' .. vim.fn.fnameescape(answer))
  else
    vim.notify('No Claude answer recorded yet', vim.log.levels.INFO)
  end
end, { desc = "Claude's [O]utput" })

-- Read-only, so it can never be edited into the prompt archive, can never be
-- written by a stray `:wq`, and can never block `:q` with unsaved changes.
-- On BufWinEnter rather than BufRead: it must land after the markdown ftplugin,
-- which turns spell on -- Claude's prose is not yours to correct.
-- `nomodifiable` does not block `autoread`'s reload (verified), so the buffer
-- still refreshes in place as later turns land.
vim.api.nvim_create_autocmd('BufWinEnter', {
  desc = 'Claude answer buffers are for reading',
  group = claude_group,
  pattern = claude_answers_dir .. '/*.md',
  callback = function()
    vim.bo.modifiable = false
    vim.bo.readonly = true
    vim.opt_local.spell = false
    vim.cmd 'normal! G'
  end,
})

-- Pick up answers written while the buffer sat open.
vim.api.nvim_create_autocmd({ 'BufEnter', 'CursorHold', 'FocusGained' }, {
  desc = 'Refresh Claude answer buffers from disk',
  group = claude_group,
  pattern = claude_answers_dir .. '/*.md',
  callback = function()
    -- Scheduled: `checktime` is blocked by textlock inside an autocmd, and the
    -- failure is silent, so calling it directly here looks fine and never refreshes.
    vim.schedule(function()
      pcall(vim.cmd, 'checktime')
    end)
  end,
})

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  You can press `?` in this menu for help. Use `:q` to close the window
--
--  To update plugins you can run
--    :Lazy update
--
-- NOTE: Here is where you install your plugins.
require('lazy').setup({
  -- NOTE: Plugins can be added with a link (or for a github repo: 'owner/repo' link).
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically

  -- NOTE: Plugins can also be added by using a table,
  -- with the first argument being the link and the following
  -- keys can be used to configure plugin behavior/loading/etc.
  --
  -- Use `opts = {}` to force a plugin to be loaded.
  --

  -- Here is a more advanced example where we pass configuration
  -- options to `gitsigns.nvim`. This is equivalent to the following Lua:
  --    require('gitsigns').setup({ ... })
  --
  -- See `:help gitsigns` to understand what the configuration keys do
  { -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
    },
  },

  -- NOTE: Plugins can also be configured to run Lua code when they are loaded.
  --
  -- This is often very useful to both group configuration, as well as handle
  -- lazy loading plugins that don't need to be loaded immediately at startup.
  --
  -- For example, in the following configuration, we use:
  --  event = 'VimEnter'
  --
  -- which loads which-key before all the UI elements are loaded. Events can be
  -- normal autocommands events (`:help autocmd-events`).
  --
  -- Then, because we use the `config` key, the configuration only runs
  -- after the plugin has been loaded:
  --  config = function() ... end
  {
    'mfussenegger/nvim-dap-python',
  },
  ---@type LazySpec
  {
    'mikavilpas/yazi.nvim',
    tag = 'v10.3.0',
    event = 'VeryLazy',
    dependencies = {
      { 'nvim-lua/plenary.nvim', lazy = true },
    },
    keys = {
      -- 👇 in this section, choose your own keymappings!
      {
        '<leader>-',
        mode = { 'n', 'v' },
        function()
          -- When editing a temp file (e.g. from shell ctrl-x ctrl-e), open at cwd instead
          local bufpath = vim.api.nvim_buf_get_name(0)
          if bufpath:match '^/tmp/' or bufpath:match '^/private/tmp/' then
            vim.cmd 'Yazi cwd'
          else
            vim.cmd 'Yazi'
          end
        end,
        desc = 'Open yazi at the current file',
      },
      {
        -- Open in the current working directory
        '<leader>cw',
        '<cmd>Yazi cwd<cr>',
        desc = "Open the file manager in nvim's working directory",
      },
      {
        '<c-up>',
        '<cmd>Yazi toggle<cr>',
        desc = 'Resume the last yazi session',
      },
    },
    ---@type YaziConfig | {}
    opts = {
      -- if you want to open yazi instead of netrw, see below for more info
      open_for_directories = false,
      keymaps = {
        show_help = '<f1>',
      },
    },
    -- 👇 if you use `open_for_directories=true`, this is recommended
    init = function()
      -- mark netrw as loaded so it's not loaded at all.
      --
      -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
      vim.g.loaded_netrwPlugin = 1
    end,
  },
  {
    'fei6409/log-highlight.nvim',
    config = function()
      require('log-highlight').setup {}
    end,
  }, -- lazy.nvim
  {
    'folke/zen-mode.nvim',
    opts = {
      -- 72 columns keeps prose inside the 45-75 character measure that the
      -- typography research converges on (66 is the usual single-column ideal).
      -- The default of 120 is well outside it.
      window = {
        width = 82,
        options = {
          signcolumn = 'no',
          number = false,
          relativenumber = false,
        },
      },
    },
  },
  { -- Prose tools: Vale, spell lists, Claude review, synonyms, fill, highlighting.
    -- A local plugin kept in this repo, so it travels with `git clone`; see
    -- plugins/prose.nvim/README.md. Not lazy: the spell lists must be set up
    -- before the first buffer turns spell on.
    dir = vim.fn.stdpath 'config' .. '/plugins/prose.nvim',
    name = 'prose.nvim',
    main = 'prose',
    lazy = false,
    opts = {
      roles = true, -- subject/action/object colours in every markdown file; <leader>pg turns them off
    },
  },
  -- lua/plugins/pencil.lua
  {
    'preservim/vim-pencil',
    init = function()
      -- This runs during startup and sets defaults
      -- Example: Set a default mode for all markdown files
      vim.cmd [[autocmd FileType markdown PencilSoft]]
    end,
  },
  -- Lua
  {
    'folke/twilight.nvim',
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      dimming = {
        alpha = 0.25, -- Adjust the dimming amount as needed
        -- Twilight walks this list for the first entry that HAS a foreground and
        -- blends it towards `term_bg`. Normal no longer has one (see the nord
        -- spec below), so the fallback is what gets used -- and it must be a
        -- foreground colour. The old fallback was `#2E3440`, the *background*:
        -- blending it towards an identical `term_bg` yields `#2E3440` again, i.e.
        -- dimmed text the same colour as the background. nord4 keeps the muted
        -- grey this produced when Normal still had a foreground.
        color = { 'Normal', '#D8DEE9' },
        term_bg = '#2E3440', -- Ensure terminal background is also set
        inactive = false, -- or true, depending on preference
      },
    },
    dependencies = {},
  },
  {
    'rcarriga/nvim-notify',
    opts = {
      -- other stuff
      background_colour = '#2E3440',
      -- Only show WARN and ERROR level notifications
      level = vim.log.levels.WARN,
    },
  },
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
      -- if you lazy-load any plugin below, make sure to add proper `module="..."` entries
      'MunifTanjim/nui.nvim',
      -- OPTIONAL:
      --   `nvim-notify` is only needed, if you want to use the notification view.
      --   If not available, we use `mini` as the fallback
      'rcarriga/nvim-notify',
    },
    config = function()
      ---@type NoiceConfig
      require('noice').setup {
        lsp = {
          -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
          override = {
            ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
            ['vim.lsp.util.stylize_markdown'] = true,
            ['cmp.entry.get_documentation'] = true, -- requires hrsh7th/nvim-cmp
          },
        },
        routes = {
          -- Skip routing notifications to messages view - nvim-notify handles display
          -- nvim-notify is configured with level = WARN, so only WARN/ERROR show
          {
            filter = { event = 'lsp', kind = 'progress', find = 'pyright' },
            opts = { skip = true },
          },
        },
        -- you can enable a preset for easier configuration
        presets = {
          bottom_search = false, -- use a classic bottom cmdline for search
          command_palette = true, -- position the cmdline and popupmenu together
          long_message_to_split = true, -- long messages will be sent to a split
          inc_rename = false, -- enables an input dialog for inc-rename.nvim
          lsp_doc_border = false, -- add a border to hover docs and signature help
        },
        -- Configure notify - use nvim-notify view (which respects level filter)
        notify = {
          enabled = true,
          view = 'notify',
        },
        -- Add empty tables for other sections to satisfy LSP type checking
        cmdline = {},
        messages = {},
        views = {},
        popupmenu = {},
        commands = {},
      }
    end,
  },
  { -- Useful plugin to show you pending keybinds.
    'folke/which-key.nvim',
    event = 'VimEnter', -- Sets the loading event to 'VimEnter'
    opts = {
      icons = {
        -- set icon mappings to true if you have a Nerd Font
        mappings = vim.g.have_nerd_font,
        -- If you are using a Nerd Font: set icons.keys to an empty table which will use the
        -- default whick-key.nvim defined Nerd Font icons, otherwise define a string table
        keys = vim.g.have_nerd_font and {} or {
          Up = '<Up> ',
          Down = '<Down> ',
          Left = '<Left> ',
          Right = '<Right> ',
          C = '<C-…> ',
          M = '<M-…> ',
          D = '<D-…> ',
          S = '<S-…> ',
          CR = '<CR> ',
          Esc = '<Esc> ',
          ScrollWheelDown = '<ScrollWheelDown> ',
          ScrollWheelUp = '<ScrollWheelUp> ',
          NL = '<NL> ',
          BS = '<BS> ',
          Space = '<Space> ',
          Tab = '<Tab> ',
          F1 = '<F1>',
          F2 = '<F2>',
          F3 = '<F3>',
          F4 = '<F4>',
          F5 = '<F5>',
          F6 = '<F6>',
          F7 = '<F7>',
          F8 = '<F8>',
          F9 = '<F9>',
          F10 = '<F10>',
          F11 = '<F11>',
          F12 = '<F12>',
        },
      },

      -- Document existing key chains
      spec = {
        { '<leader>c', group = '[C]ode', mode = { 'n', 'x' } },
        { '<leader>d', group = '[D]ocument' },
        { '<leader>r', group = '[R]ename' },
        { '<leader>s', group = '[S]earch' },
        { '<leader>w', group = '[W]orkspace' },
        { '<leader>t', group = '[T]oggle' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
        { '<leader>p', group = '[P]rose' },
        { 'zg', group = 'Add word to spell list', mode = { 'n', 'x' } },
      },
    },
  },

  -- NOTE: Plugins can specify dependencies.
  --
  -- The dependencies are proper plugin specifications as well - anything
  -- you do for a plugin at the top level, you can do for a dependency.
  --
  -- Use the `dependencies` key to specify the dependencies of a particular plugin

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { -- If encountering errors, see telescope-fzf-native README for installation instructions
        'nvim-telescope/telescope-fzf-native.nvim',

        -- `build` is used to run some command when the plugin is installed/updated.
        -- This is only run then, not every time Neovim starts up.
        build = 'make',

        -- `cond` is a condition used to determine whether this plugin should be
        -- installed and loaded.
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      -- Data only: the emoji list behind prose.nvim's <leader>pe.
      { 'nvim-telescope/telescope-symbols.nvim' },

      -- Useful for getting pretty icons, but requires a Nerd Font.
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      -- Telescope is a fuzzy finder that comes with a lot of different things that
      -- it can fuzzy find! It's more than just a "file finder", it can search
      -- many different aspects of Neovim, your workspace, LSP, and more!
      --
      -- The easiest way to use Telescope, is to start by doing something like:
      --  :Telescope help_tags
      --
      -- After running this command, a window will open up and you're able to
      -- type in the prompt window. You'll see a list of `help_tags` options and
      -- a corresponding preview of the help.
      --
      -- Two important keymaps to use while in Telescope are:
      --  - Insert mode: <c-/>
      --  - Normal mode: ?
      --
      -- This opens a window that shows you all of the keymaps for the current
      -- Telescope picker. This is really useful to discover what Telescope can
      -- do as well as how to actually do it!

      -- [[ Configure Telescope ]]
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        -- You can put your default mappings / updates / etc. in here
        --  All the info you're looking for is in `:help telescope.setup()`
        --
        defaults = {
          mappings = {
            i = {
              ['<CR>'] = function(prompt_bufnr)
                local actions = require 'telescope.actions'
                local action_state = require 'telescope.actions.state'
                local picker = action_state.get_current_picker(prompt_bufnr)
                local multi = picker:get_multi_selection()
                if #multi > 0 then
                  actions.close(prompt_bufnr)
                  for _, entry in ipairs(multi) do
                    vim.cmd('edit ' .. vim.fn.fnameescape(entry.path or entry.filename or entry.value))
                  end
                else
                  actions.select_default(prompt_bufnr)
                end
              end,
            },
          },
        },
        pickers = {
          colorscheme = {
            enable_preview = true,
          },
        },
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
        },
      }

      -- Enable Telescope extensions if they are installed
      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')

      -- See `:help telescope.builtin`
      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

      -- Slightly advanced example of overriding default behavior and theme
      vim.keymap.set('n', '<leader>/', function()
        -- You can pass additional configuration to Telescope to change the theme, layout, etc.
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 0,
          previewer = false,
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      -- It's also possible to pass additional configuration options.
      --  See `:help telescope.builtin.live_grep()` for information about particular keys
      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
    end,
  },
  {
    'ThePrimeagen/vim-be-good',
  },
  -- LSP Plugins
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  { 'michaeljsmith/vim-indent-object' },
  { 'jeetsukumaran/vim-indentwise' },
  -- { 'neoclide/coc.nvim' },
  {
    -- Main LSP Configuration
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      { 'williamboman/mason.nvim', config = true }, -- NOTE: Must be loaded before dependants
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = { progress = { ignore = { 'pyright' } } } },

      -- Allows extra capabilities provided by nvim-cmp
      'hrsh7th/cmp-nvim-lsp',
    },
    opts = {
      inlay_hints = { enabled = false },
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Disable formatting for lua_ls since we use stylua
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.name == 'lua_ls' then
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
          end

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')

          -- Find references for the word under your cursor.
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      -- Change diagnostic symbols in the sign column (gutter)
      -- if vim.g.have_nerd_font then
      --   local signs = { Error = '', Warn = '', Hint = '', Info = '' }
      --   for type, icon in pairs(signs) do
      --     local hl = 'DiagnosticSign' .. type
      --     vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      --   end
      -- end

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      -- Enable the following language servers
      --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
      --
      --  Add any additional override configuration in the following tables. Available keys are:
      --  - cmd (table): Override the default command used to start the server
      --  - filetypes (table): Override the default list of associated filetypes for the server
      --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
      --  - settings (table): Override the default settings passed when initializing the server.
      --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
      local servers = {
        -- clangd = {},
        -- gopls = {},
        pyright = {},
        -- markdown LSP: powers <leader>ds (lsp_document_symbols) as a heading
        -- outline, plus [[wiki-link]] completion.
        marksman = {},
        -- rust_analyzer = {},
        -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
        --
        -- Some languages (like typescript) have entire language plugins that can be useful:
        --    https://github.com/pmizio/typescript-tools.nvim
        --
        -- But for many setups, the LSP (`ts_ls`) will work just fine
        -- ts_ls = {},
        --

        lua_ls = {
          -- cmd = {...},
          -- filetypes = { ...},
          -- capabilities = {},
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
              -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
              -- diagnostics = { disable = { 'missing-fields' } },
            },
          },
        },
      }

      -- Ensure the servers and tools above are installed
      --  To check the current status of installed tools and/or manually install
      --  other tools, you can run
      --    :Mason
      --
      --  You can press `g?` for help in this menu.
      require('mason').setup()

      -- You can add other tools here that you want Mason to install
      -- for you, so that they are available from within Neovim.
      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, {
        'stylua', -- Used to format Lua code
        'ruff', -- Python formatter with range support
        'vale-ls', -- Prose linter LSP; prose.nvim configures it (plugins/prose.nvim/vale/)
        'vale', -- The binary vale-ls runs. Mason's bin is on Neovim's PATH, so
        -- this is the only copy (vale-ls's own download is off, in prose.nvim).
      })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      -- mason-lspconfig v2 dropped the `handlers` option (it was silently ignored
      -- here) and instead calls vim.lsp.enable() on every installed server. So the
      -- overrides above go through the native config API, which merges them over
      -- nvim-lspconfig's defaults when each server starts.
      vim.lsp.config('*', { capabilities = capabilities })
      for server_name, server in pairs(servers) do
        vim.lsp.config(server_name, server)
      end

      -- vale_ls gets its config from prose.nvim (plugins/prose.nvim); this only
      -- enables it, like every other installed server.
      require('mason-lspconfig').setup {}
    end,
  },

  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = false,
      formatters_by_ft = {
        lua = { 'stylua' },
        python = { 'ruff_format' },
        -- Conform can also run multiple formatters sequentially
        -- python = { "isort", "black" },
        --
        -- You can use 'stop_after_first' to run the first available formatter from the list
        -- javascript = { "prettierd", "prettier", stop_after_first = true },
      },
      formatters = {
        stylua = {
          -- Use config file if found in project root
          prepend_args = function()
            local config_file = vim.fs.find({ '.stylua.toml', 'stylua.toml' }, { path = vim.fn.getcwd(), upward = true })[1]
            if config_file then
              return { '--config-path', config_file }
            end
            return {}
          end,
        },
      },
    },
  },

  { -- Autocompletion
    'hrsh7th/nvim-cmp',
    event = 'InsertEnter',
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      {
        'L3MON4D3/LuaSnip',
        build = (function()
          -- Build Step is needed for regex support in snippets.
          -- This step is not supported in many windows environments.
          -- Remove the below condition to re-enable on windows.
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          -- `friendly-snippets` contains a variety of premade snippets.
          --    See the README about individual language/framework/plugin snippets:
          --    https://github.com/rafamadriz/friendly-snippets
          -- {
          --   'rafamadriz/friendly-snippets',
          --   config = function()
          --     require('luasnip.loaders.from_vscode').lazy_load()
          --   end,
          -- },
        },
      },
      'saadparwaiz1/cmp_luasnip',

      -- Adds other completion capabilities.
      --  nvim-cmp does not ship with all sources by default. They are split
      --  into multiple repos for maintenance purposes.
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
    },
    config = function()
      -- See `:help cmp`
      local cmp = require 'cmp'
      local luasnip = require 'luasnip'
      luasnip.config.setup {}

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = 'menu,menuone,noinsert' },

        -- For an understanding of why these mappings were
        -- chosen, you will need to read `:help ins-completion`
        --
        -- No, but seriously. Please read `:help ins-completion`, it is really good!
        mapping = cmp.mapping.preset.insert {
          -- Select the [n]ext item
          ['<C-n>'] = cmp.mapping.select_next_item(),
          -- Select the [p]revious item
          ['<C-p>'] = cmp.mapping.select_prev_item(),

          -- Scroll the documentation window [b]ack / [f]orward
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),

          -- Accept ([y]es) the completion.
          --  This will auto-import if your LSP supports it.
          --  This will expand snippets if the LSP sent a snippet.
          ['<C-y>'] = cmp.mapping.confirm { select = true },

          -- If you prefer more traditional completion keymaps,
          -- you can uncomment the following lines
          ['<CR>'] = cmp.mapping.confirm { select = true },
          ['<Tab>'] = cmp.mapping.select_next_item(),
          ['<S-Tab>'] = cmp.mapping.select_prev_item(),

          -- Manually trigger a completion from nvim-cmp.
          --  Generally you don't need this, because nvim-cmp will display
          --  completions whenever it has completion options available.
          ['<C-Space>'] = cmp.mapping.complete {},

          -- Think of <c-l> as moving to the right of your snippet expansion.
          --  So if you have a snippet that's like:
          --  function $name($args)
          --    $body
          --  end
          --
          -- <c-l> will move you to the right of each of the expansion locations.
          -- <c-h> is similar, except moving you backwards.
          ['<C-l>'] = cmp.mapping(function()
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' }),
          ['<C-h>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),

          -- For more advanced Luasnip keymaps (e.g. selecting choice nodes, expansion) see:
          --    https://github.com/L3MON4D3/LuaSnip?tab=readme-ov-file#keymaps
        },
        sources = {
          {
            name = 'lazydev',
            -- set group index to 0 to skip loading LuaLS completions as lazydev recommends it
            group_index = 0,
          },
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'path' },
        },
      }

      -- Make cmp-path complete relative to cwd when editing temp files
      -- (e.g. shell commands via ctrl-x ctrl-e where the buffer is in /tmp).
      local cmp_path = require 'cmp_path'
      local orig_dirname = cmp_path._dirname
      cmp_path._dirname = function(self, params, option)
        local bufpath = vim.api.nvim_buf_get_name(params.context.bufnr)
        if bufpath:match '^/tmp/' or bufpath:match '^/private/tmp/' then
          option.get_cwd = function()
            return vim.fn.getcwd()
          end
        end
        return orig_dirname(self, params, option)
      end
    end,
  },

  { -- You can easily change to a different colorscheme.
    -- Change the name of the colorscheme plugin below, and then
    -- change the command in the config to whatever the name of that colorscheme is.
    --
    -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
    'shaunsingh/nord.nvim',

    -- 'tinted-theming/tinted-vim',
    priority = 1000, -- Make sure to load this before all the other start plugins.
    init = function()
      -- Every highlight override lives in one function, replayed on ColorScheme.
      -- Setting them once after `:colorscheme` looks like it works, but any later
      -- colorscheme command silently wipes them all.
      local function overrides()
        vim.cmd.hi 'Comment gui=none'
        vim.api.nvim_set_hl(0, 'LineNr', { fg = require('nord.colors').nord1_gui })

        -- Hand the foreground back to the terminal. `nord_disable_background` at
        -- the top of this file already gives up the background; this extends the
        -- same idea to the foreground, so text with no highlight of its own uses
        -- whatever the terminal's default is.
        --
        -- It has to be the *global* Normal. `winhighlight` can point a window at
        -- a different colour, but cannot express "no colour": redirecting Normal
        -- to a group with `guifg=NONE` falls back to Normal and changes nothing.
        -- So this cannot be scoped to markdown without inverting the exception
        -- onto every other window.
        vim.cmd 'highlight Normal guifg=NONE guibg=NONE'

        -- Markdown colours for both rendered and raw views; see that file.
        require('custom.markdown_theme').apply()
      end

      -- Load the colorscheme here.
      -- Like many other themes, this one has different styles, and you could load
      -- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
      vim.cmd.colorscheme 'nord'
      overrides()

      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('custom-highlight-overrides', { clear = true }),
        callback = overrides,
      })
    end,
  },

  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  { -- Collection of various small independent plugins/modules
    'echasnovski/mini.nvim',
    config = function()
      -- Better Around/Inside textobjects
      --
      -- Examples:
      --  - va)  - [V]isually select [A]round [)]paren
      --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
      --  - ci'  - [C]hange [I]nside [']quote
      local ai = require 'mini.ai'
      ai.setup {
        n_lines = 500,
        custom_textobjects = {
          -- Use treesitter for function and parameter textobjects
          f = ai.gen_spec.treesitter { a = '@function.outer', i = '@function.inner' },
          a = ai.gen_spec.treesitter { a = '@parameter.outer', i = '@parameter.inner' },
        },
      }

      -- Add/delete/replace surroundings (brackets, quotes, etc.), mapped
      -- vim-surround style rather than mini's own `sa`/`sd`/`sr`.
      --
      -- - ysiw) - [Y]ank [S]urround [I]nner [W]ord [)]Paren
      -- - ds'   - [D]elete [S]urround [']quotes
      -- - cs)'  - [C]hange [S]urround [)] to [']
      -- - SB    - bold the visual selection (see custom_surroundings)
      require('mini.surround').setup {
        mappings = {
          add = 'ys',
          delete = 'ds',
          replace = 'cs',
          -- find = 'sf',
          -- find_left = 'sF',
          -- highlight = 'sh',
          -- update_n_lines = 'sul',
        },
        -- Markdown emphasis. Without these, `**bold**` needs two passes of `ys*`
        -- and the natural "re-select and repeat" via `gv` corrupts the text --
        -- `gv` restores the byte range from *before* the first `*` was inserted,
        -- so `v2e ys* gv ys*` yields `**hello worl*d*`.
        --
        -- Identifiers are deliberate: `b` and `q` are already built-in aliases
        -- for brackets and quotes, so bold takes `B`. `B`, `i`, `c` and `s` are
        -- otherwise unused (they fall through to their literal character).
        custom_surroundings = {
          B = { input = { '%*%*().-()%*%*' }, output = { left = '**', right = '**' } }, -- bold
          i = { input = { '%*().-()%*' }, output = { left = '*', right = '*' } }, -- italic
          c = { input = { '`().-()`' }, output = { left = '`', right = '`' } }, -- inline code
          s = { input = { '~~().-()~~' }, output = { left = '~~', right = '~~' } }, -- strikethrough
        },
      }

      -- Use `S` for the visual-mode add, not `ys`.
      --
      -- `ys` was the only visual-mode mapping starting with `y`, which made plain
      -- `y` ambiguous: every yank from visual mode waited out `timeoutlen` before
      -- doing anything. Normal mode is unaffected -- `y`/`d`/`c` are always
      -- followed by a motion there, so the ambiguity resolves on the next key.
      -- This is the same trade vim-surround makes; it costs the built-in `S`
      -- (change selected lines linewise).
      vim.keymap.del('x', 'ys')
      vim.keymap.set('x', 'S', [[:<C-u>lua MiniSurround.add('visual')<CR>]], { silent = true, desc = 'Add surrounding to selection' })

      -- Pattern-based highlighting for things treesitter has no node for.
      --
      -- Markdown's grammar does not tokenise parentheses or quotes inside
      -- running text -- a plain paragraph carries no captures beyond `@spell` --
      -- so dimming `(an aside)` cannot be a treesitter query. This is the regex
      -- layer that can, with treesitter consulted only to decide whether a match
      -- is really prose. See plugins/prose.nvim/lua/prose/highlight.lua.
      require('mini.hipatterns').setup {
        highlighters = require('prose.highlight').highlighters(),
      }

      -- Simple and easy statusline.
      --  You could remove this setup call if you don't like it,
      --  and try some other statusline plugin
      local statusline = require 'mini.statusline'
      -- set use_icons to true if you have a Nerd Font
      statusline.setup { use_icons = vim.g.have_nerd_font }

      -- You can configure sections in the statusline by overriding their
      -- default behavior. For example, here we set the section for
      -- cursor location to LINE:COLUMN
      ---@diagnostic disable-next-line: duplicate-set-field
      statusline.section_location = function()
        return '%2l:%-2v'
      end

      -- ... and there is more!
      --  Check out: https://github.com/echasnovski/mini.nvim
    end,
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = {
      'nvim-treesitter/nvim-treesitter',
      'nvim-tree/nvim-web-devicons', -- optional but recommended
    },
    opts = {
      heading = {
        enabled = true,
        sign = false,
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
        backgrounds = {
          'RenderMarkdownH1Bg',
          'RenderMarkdownH2Bg',
          'RenderMarkdownH3Bg',
          'RenderMarkdownH4Bg',
          'RenderMarkdownH5Bg',
          'RenderMarkdownH6Bg',
        },
      },

      code = {
        enabled = true,
        sign = false,
        width = 'block',
        border = 'thin',
        left_pad = 2,
        right_pad = 2,
        -- A space of code background either side of inline `code`. This is
        -- inline virtual text, so it exists only while rendering: in insertish
        -- and visual modes the padding is gone and the backticks are back. That
        -- asymmetry is unavoidable -- padding is by definition inserted space.
        inline_pad = 1,
      },

      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
      },

      checkbox = {
        enabled = true,
        unchecked = { icon = '󰄱' },
        checked = { icon = '󰱒' },
        custom = {
          todo = { raw = '[~]', rendered = '󰥔' },
        },
      },

      quote = {
        enabled = true,
        icon = '▎',
      },

      pipe_table = {
        enabled = true,
      },

      callout = {
        note = { raw = '[!NOTE]', rendered = '󰋽 Note', highlight = 'RenderMarkdownInfo' },
        tip = { raw = '[!TIP]', rendered = '󰌶 Tip', highlight = 'RenderMarkdownSuccess' },
        warning = { raw = '[!WARNING]', rendered = '󰀪 Warning', highlight = 'RenderMarkdownWarn' },
        danger = { raw = '[!DANGER]', rendered = '󰳦 Danger', highlight = 'RenderMarkdownError' },
      },
      latex = { enabled = false },
    },
  },
  { -- Parser manager + queries for tree-sitter features built into Neovim
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').setup({
        ensure_installed = { 'bash', 'c', 'python', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc' },
      })

      -- The 'main' branch of nvim-treesitter no longer has a `highlight.enable`
      -- option: parsing/highlighting must be started explicitly per buffer.
      -- Without this, the syntax tree is never parsed for most filetypes, so
      -- treesitter-based textobjects (mini.ai's `aa`/`ia`, etc.) silently find
      -- nothing. Lua/Markdown/help appear to work regardless because Neovim's
      -- own bundled ftplugins already call `vim.treesitter.start()` for those.
      vim.api.nvim_create_autocmd('FileType', {
        callback = function(args)
          local ok = pcall(vim.treesitter.start, args.buf)
          if ok then vim.bo[args.buf].indentexpr = 'v:lua.vim.treesitter.indentexpr()' end
        end,
      })
    end,
  },
  { -- Syntax-aware text objects and movements
    'nvim-treesitter/nvim-treesitter-textobjects',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('nvim-treesitter-textobjects').setup {
        select = { lookahead = true },
        move = { set_jumps = true },
      }

      -- NOTE: af/if and aa/ia are handled by mini.ai with treesitter specs
      local select = require 'nvim-treesitter-textobjects.select'
      vim.keymap.set({ 'x', 'o' }, 'ac', function() select.select_textobject('@class.outer', 'textobjects') end, { desc = 'Select outer class' })
      vim.keymap.set({ 'x', 'o' }, 'ic', function() select.select_textobject('@class.inner', 'textobjects') end, { desc = 'Select inner class' })
      vim.keymap.set({ 'x', 'o' }, 'a=', function() select.select_textobject('@assignment.outer', 'textobjects') end, { desc = 'Select outer assignment' })
      vim.keymap.set({ 'x', 'o' }, 'i=', function() select.select_textobject('@assignment.inner', 'textobjects') end, { desc = 'Select inner assignment' })
      vim.keymap.set({ 'x', 'o' }, 'l=', function() select.select_textobject('@assignment.lhs', 'textobjects') end, { desc = 'Select lhs of assignment' })
      vim.keymap.set({ 'x', 'o' }, 'r=', function() select.select_textobject('@assignment.rhs', 'textobjects') end, { desc = 'Select rhs of assignment' })

      local move = require 'nvim-treesitter-textobjects.move'
      vim.keymap.set({ 'n', 'x', 'o' }, ']m', function() move.goto_next_start('@function.outer', 'textobjects') end, { desc = 'Next function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']]', function() move.goto_next_start('@class.outer', 'textobjects') end, { desc = 'Next class start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']M', function() move.goto_next_end('@function.outer', 'textobjects') end, { desc = 'Next function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '][', function() move.goto_next_end('@class.outer', 'textobjects') end, { desc = 'Next class end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[m', function() move.goto_previous_start('@function.outer', 'textobjects') end, { desc = 'Prev function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[[', function() move.goto_previous_start('@class.outer', 'textobjects') end, { desc = 'Prev class start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[M', function() move.goto_previous_end('@function.outer', 'textobjects') end, { desc = 'Prev function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[]', function() move.goto_previous_end('@class.outer', 'textobjects') end, { desc = 'Prev class end' })

      local swap = require 'nvim-treesitter-textobjects.swap'
      vim.keymap.set('n', '<leader>a', function() swap.swap_next('@parameter.inner') end, { desc = 'Swap with next parameter' })
      vim.keymap.set('n', '<leader>A', function() swap.swap_previous('@parameter.inner') end, { desc = 'Swap with previous parameter' })
    end,
  },
  -- {
  --   'numirias/semshi',
  --   build = ':UpdateRemotePlugins',
  -- },
  -- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
  -- init.lua. If you want these files, they are in the repository, so you can just download them and
  -- place them in the correct locations.

  -- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
  --
  --  Here are some example plugins that I've included in the Kickstart repository.
  --  Uncomment any of the lines below to enable them (you will need to restart nvim).
  --
  -- require 'kickstart.plugins.debug',
  -- require 'kickstart.plugins.indent_line',
  -- require 'kickstart.plugins.lint',
  -- require 'kickstart.plugins.autopairs',
  -- require 'kickstart.plugins.neo-tree',
  -- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    This is the easiest way to modularize your config.
  --
  --  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  -- { import = 'custom.plugins' },
  --
  -- For additional information with loading, sourcing and examples see `:help lazy.nvim-🔌-plugin-spec`
  -- Or use telescope!
  -- In normal mode type `<space>sh` then write `lazy.nvim-plugin`
  -- you can continue same window with `<space>sr` which resumes last telescope search
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})
local insert_start_row = nil

-- Record the line where insert mode begins
vim.api.nvim_create_autocmd('InsertEnter', {
  callback = function()
    insert_start_row = vim.api.nvim_win_get_cursor(0)[1]
  end,
})

-- On InsertLeave, clean all-whitespace lines from the insert region
vim.api.nvim_create_autocmd('InsertLeave', {
  callback = function()
    if not insert_start_row then
      return
    end
    local end_row = vim.api.nvim_win_get_cursor(0)[1]
    local buf = 0 -- current buffer

    -- Ensure start <= end
    local start_row = math.min(insert_start_row, end_row)
    end_row = math.max(insert_start_row, end_row)

    local lines = vim.api.nvim_buf_get_lines(buf, start_row - 1, end_row, false)
    for i, line in ipairs(lines) do
      if line:match '^%s+$' then
        vim.api.nvim_buf_set_lines(buf, start_row - 1 + i - 1, start_row - 1 + i, false, { '' })
      end
    end
  end,
})

-- Disable CoC inlay hints
vim.g.coc_user_config = vim.tbl_deep_extend('force', vim.g.coc_user_config or {}, {
  inlayHint = { enable = false },
})

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
--
--
--

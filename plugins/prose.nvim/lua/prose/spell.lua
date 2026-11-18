-- Two spell word lists: one private to this machine, one that travels with the repo.
--
--   zgl  add the word under the cursor (or the selection) to the LOCAL list
--   zgg  add it to the GLOBAL list, committed to the nvim config repo
--   z=   pick a suggestion in a centered Telescope picker (M.suggest)
--
-- The config repo is a PUBLIC GitHub fork, so the global list is public. It is
-- for vocabulary anyone could know (GenAI, LLM, PyTorch). Names of people,
-- clients and internal projects go in the local list.
--
-- Local is entry 1 of 'spellfile' on purpose. Plain `zg`, `zw` and `zug` act on
-- entry 1, so a bare `zg` (which-key normally turns it into a menu, but not
-- before VimEnter) can never publish a word. Undo a global add with `2zug`, or
-- edit the global list (by default spell/en.utf-8.add in the config) directly.
--
-- Neovim does not read a `.add` file without its compiled `.spl`, and does not
-- build the `.spl` itself -- a cloned or pulled list does nothing until
-- `:mkspell!` runs, and it must run before spell loads (verified headless). So
-- setup() rebuilds any stale `.spl`. prose.setup() calls it at startup, before
-- any buffer turns spell on, which is why the plugin is not lazy-loaded.
-- `zg` keeps the `.spl` current by itself.

local M = {}

-- Neovim's own default 'spellfile' location, so the list `zg` already wrote to
-- keeps working, and so does `zg` in a buffer that never sees this config.
M.local_list = vim.fn.stdpath 'data' .. '/site/spell/en.utf-8.add'
-- The word list is personal data, so it stays in the config, not this plugin.
M.global_list = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add'

---Is file `a` strictly newer than file `b`?
local function newer(a, b)
  if a.mtime.sec ~= b.mtime.sec then
    return a.mtime.sec > b.mtime.sec
  end
  return a.mtime.nsec > b.mtime.nsec
end

-- [[ z=: spelling suggestions in a centered picker ]]
--
-- which-key's own z= popup sits at the bottom of the screen, and the arrow
-- keys do not move through it. This picker opens in the middle. Its labels are
-- which-key's, so z=1 still picks the first suggestion with no Enter. Up to 18,
-- because which-key's i and j would clash with the picker's i (filter) and j
-- (down).
local LABELS = '1234567890abcdefgh'

---Vim's own z= list for the cursor, read from its prompt, which `:normal`
---then cancels. Not spellsuggest(): only z= capitalizes at the start of a
---sentence, so "teh" at the start of a line gets Tea, Tee, Te, The, while
---spellsuggest('teh') gives the, ten, tea. `{i}z=` picks from this list.
---@return string? word, {word: string, replaces: string?}[] list, string output
local function own_list()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ok, res = pcall(vim.api.nvim_exec2, 'silent normal! z=', { output = true })
  vim.api.nvim_win_set_cursor(0, cursor)
  if not ok then
    return nil, {}, tostring(res)
  end
  local list = {}
  for line in vim.gsplit(res.output, '\n', { plain = true }) do
    -- ` 1 "Tea"`, or ` 1 "Tea" < "teh cat"` when it replaces more than the word.
    local word = line:match '^%s*%d+ "(.-)"'
    if word then
      list[#list + 1] = { word = word, replaces = line:match ' < "(.*)"$' }
    end
  end
  return res.output:match 'Change "(.-)" to:', list, vim.trim(res.output)
end

---Spelling suggestions for the word under the cursor, in a Telescope dropdown.
---A label key or <CR> replaces the word through Vim's own `{i}z=`, which keeps
---its case and lets `:spellrepall` repeat the fix.
function M.suggest()
  local word, list, output = own_list()
  if #list == 0 then
    vim.notify(output ~= '' and output or 'No suggestions', vim.log.levels.INFO, { title = 'Prose' })
    return
  end

  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local entries = {}
  for i = 1, math.min(#list, #LABELS) do
    local s = list[i]
    entries[i] = { index = i, label = LABELS:sub(i, i), word = s.replaces and ('%s  < %s'):format(s.word, s.replaces) or s.word }
  end

  require('telescope.pickers')
    .new(require('telescope.themes').get_dropdown { winblend = 0, previewer = false, layout_config = { height = #entries + 4 } }, {
      prompt_title = word and ('Spelling: “%s”'):format(word) or 'Spelling',
      initial_mode = 'normal',
      default_selection_index = 1,
      finder = require('telescope.finders').new_table {
        results = entries,
        entry_maker = function(e)
          return { value = e.index, display = e.label .. '  ' .. e.word, ordinal = e.word }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        local function choose(i)
          actions.close(prompt_bufnr)
          if i then
            vim.cmd('normal! ' .. i .. 'z=')
          end
        end
        -- Our own <CR>: the Insert-mode one in init.lua's Telescope defaults
        -- would `:edit` the entry.
        local function choose_selected()
          local entry = action_state.get_selected_entry()
          choose(entry and entry.value)
        end
        map('i', '<CR>', choose_selected)
        map('n', '<CR>', choose_selected)
        -- nowait: `g` picks at once, without waiting to see if it is Telescope's `gg`.
        for _, e in ipairs(entries) do
          map('n', e.label, function()
            choose(e.index)
          end, { nowait = true })
        end
        return true
      end,
    })
    :find()
end

---@param opts? {local_list?: string, global_list?: string}
function M.setup(opts)
  opts = opts or {}
  M.local_list = opts.local_list or M.local_list
  M.global_list = opts.global_list or M.global_list

  -- `zg` fails with E482 when the directory is missing, as on a fresh machine.
  vim.fn.mkdir(vim.fs.dirname(M.local_list), 'p')

  -- Rebuild the two lists, and every other word list in the config's spell/
  -- directory, such as hy.utf-8.add. Those others are not 'spellfile' entries:
  -- Neovim loads LL.utf-8.add.spl from 'runtimepath' by itself whenever LL is
  -- in 'spelllang', but only once it is compiled. The config dir, not the
  -- global list's dir, because only a 'runtimepath' spell/ dir is loaded.
  local lists = { M.local_list, M.global_list }
  for _, add in ipairs(vim.fn.glob(vim.fn.stdpath 'config' .. '/spell/*.add', false, true)) do
    if not vim.tbl_contains(lists, add) then
      table.insert(lists, add)
    end
  end

  for _, add in ipairs(lists) do
    local add_stat = vim.uv.fs_stat(add)
    if add_stat then
      local spl_stat = vim.uv.fs_stat(add .. '.spl')
      if not spl_stat or newer(add_stat, spl_stat) then
        vim.cmd('silent mkspell! ' .. vim.fn.fnameescape(add))
      end
    end
  end

  vim.opt.spellfile = { M.local_list, M.global_list }

  -- `[count]zg` adds to entry [count] of 'spellfile'. noremap (the default) so
  -- the `zg` in the rhs is the built-in, not these mappings again.
  vim.keymap.set({ 'n', 'x' }, 'zgl', '1zg', { desc = 'Add word to [L]ocal spell list (private)' })
  vim.keymap.set({ 'n', 'x' }, 'zgg', '2zg', { desc = 'Add word to [G]lobal spell list (repo, public)' })

  -- z= opens the picker, except where Vim's own z= already does the right
  -- thing. A count picks with no list, and a returned z= keeps it: 3z= stays
  -- 3z=. A macro holds what was typed into Vim's own prompt (which-key steps
  -- aside in macros too), so z=1<CR> must replay there, not into a picker.
  vim.keymap.set('n', 'z=', function()
    local macro = vim.fn.reg_recording() ~= '' or vim.fn.reg_executing() ~= ''
    if vim.v.count > 0 or macro or not vim.wo.spell or not pcall(require, 'telescope') then
      return 'z='
    end
    return "<Cmd>lua require('prose.spell').suggest()<CR>"
  end, { expr = true, desc = 'Spelling suggestions (picker)' })
end

return M

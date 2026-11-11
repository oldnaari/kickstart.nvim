-- Two spell word lists: one private to this machine, one that travels with the repo.
--
--   zgl  add the word under the cursor (or the selection) to the LOCAL list
--   zgg  add it to the GLOBAL list, committed to this repo
--
-- The repo is a PUBLIC GitHub fork, so the global list is public. It is for
-- vocabulary anyone could know (GenAI, LLM, PyTorch). Names of people, clients
-- and internal projects go in the local list.
--
-- Local is entry 1 of 'spellfile' on purpose. Plain `zg`, `zw` and `zug` act on
-- entry 1, so a bare `zg` (which-key normally turns it into a menu, but not
-- before VimEnter) can never publish a word. Undo a global add with `2zug`, or
-- edit spell/en.utf-8.add directly.
--
-- Neovim does not read a `.add` file without its compiled `.spl`, and does not
-- build the `.spl` itself -- a cloned or pulled list does nothing until
-- `:mkspell!` runs, and it must run before spell loads (verified headless). So
-- setup() rebuilds any stale `.spl`. It has to be called from init.lua, before
-- any buffer turns spell on. `zg` keeps the `.spl` current by itself.

local M = {}

-- Neovim's own default 'spellfile' location, so the list `zg` already wrote to
-- keeps working, and so does `zg` in a buffer that never sees this config.
M.local_list = vim.fn.stdpath 'data' .. '/site/spell/en.utf-8.add'
M.global_list = vim.fn.stdpath 'config' .. '/spell/en.utf-8.add'

---Is file `a` strictly newer than file `b`?
local function newer(a, b)
  if a.mtime.sec ~= b.mtime.sec then
    return a.mtime.sec > b.mtime.sec
  end
  return a.mtime.nsec > b.mtime.nsec
end

function M.setup()
  -- `zg` fails with E482 when the directory is missing, as on a fresh machine.
  vim.fn.mkdir(vim.fs.dirname(M.local_list), 'p')

  for _, add in ipairs { M.local_list, M.global_list } do
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
end

return M

-- Search emoji by name and insert one after the cursor.
--
-- Telescope's own `symbols` picker does the work; the list comes from
-- telescope-symbols.nvim (data/telescope-sources/emoji.json), a data-only
-- plugin. Names are English ("grinning face", "red heart").

local M = {}

M.install_hint = "add 'nvim-telescope/telescope-symbols.nvim' to telescope's dependencies"

---Whether the emoji list is on the runtimepath. Telescope loads its
---dependencies when first required, so call this after `require 'telescope'`.
function M.available()
  return vim.api.nvim_get_runtime_file('data/telescope-sources/emoji.json', false)[1] ~= nil
end

function M.pick()
  if not pcall(require, 'telescope') then
    vim.notify('Emoji picker needs telescope.nvim', vim.log.levels.ERROR, { title = 'Prose' })
    return
  end
  if not M.available() then
    vim.notify('No emoji list found: ' .. M.install_hint, vim.log.levels.ERROR, { title = 'Prose' })
    return
  end
  require('telescope.builtin').symbols(require('telescope.themes').get_dropdown {
    prompt_title = 'Emoji',
    sources = { 'emoji' },
  })
end

return M

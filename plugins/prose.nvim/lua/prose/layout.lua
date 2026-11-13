-- Type in another language without switching the OS keyboard layout.
--
-- Uses Vim's 'keymap', which is buffer-local. The OS layout stays on English,
-- so Normal-mode commands keep working. Only typed text goes through the
-- keymap: Insert mode, `/` search, and the character after r, f or t. It also
-- works on a remote host over SSH, where the OS layout cannot be switched.
--
-- `<leader>pk` + a key picks a layout (see `layouts` in prose/init.lua). In
-- Insert mode, the built-in <C-^> toggles between the last picked layout and
-- English.
--
-- keymap/armenian-hmqwerty_utf-8.vim mirrors the macOS layout of the same name.
-- Russian uses Vim's bundled russian-jcukenmac, which already matches the
-- macOS "Russian" layout key for key.

local M = {}

---@class Prose.Layout
---@field key string     typed after the `<leader>pk` prefix
---@field name string
---@field keymap string  a 'keymap' name; '' means none (English)

---@param layout Prose.Layout
---@param buf? integer
function M.set(layout, buf)
  local bo = vim.bo[buf or 0]
  if layout.keymap == '' then
    -- Leave 'keymap' loaded, so <C-^> in Insert mode can switch straight back.
    bo.iminsert = 0
  else
    bo.keymap = layout.keymap
    bo.iminsert = 1
  end
  bo.imsearch = -1 -- `/` search follows Insert mode
  vim.notify('Keyboard: ' .. layout.name, vim.log.levels.INFO, { title = 'Prose' })
end

return M

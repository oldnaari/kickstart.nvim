-- Type in another language without switching the OS keyboard layout.
--
-- Uses Vim's 'keymap', which is buffer-local. The OS layout stays on English,
-- so Normal-mode commands keep working. Only typed text goes through the
-- keymap: Insert mode, `/` search, and the character after r, f or t. It also
-- works on a remote host over SSH, where the OS layout cannot be switched.
--
-- `<leader>pk` opens a picker (see `layouts` in prose/init.lua). In Insert
-- mode, the built-in <C-^> toggles between the last picked layout and English.
--
-- keymap/armenian-hmqwerty_utf-8.vim mirrors the macOS layout of the same name.
-- Russian uses Vim's bundled russian-jcukenmac, which already matches the
-- macOS "Russian" layout key for key.

local M = {}

---@class Prose.Layout
---@field key string     picks this layout straight from the picker
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

---The layout active in `buf`, if it is one of `layouts`.
---@param layouts Prose.Layout[]
---@param buf? integer
---@return Prose.Layout?, integer?
function M.current(layouts, buf)
  local bo = vim.bo[buf or 0]
  local active = bo.iminsert == 1 and bo.keymap or ''
  for i, layout in ipairs(layouts) do
    if layout.keymap == active then
      return layout, i
    end
  end
end

---Pick a layout for the current buffer: j/k or the arrows and <CR>, or a
---layout's own key to pick it at once. Opens in Normal mode so those keys pick
---rather than filter; `i` still gets you a prompt to type into.
---@param layouts Prose.Layout[]
function M.pick(layouts)
  local buf = vim.api.nvim_get_current_buf()
  local current, current_index = M.current(layouts, buf)
  local function label(layout)
    return ('%s  %s%s'):format(layout.key, layout.name, layout == current and '  ●' or '')
  end

  if not pcall(require, 'telescope') then
    vim.ui.select(layouts, { prompt = 'Keyboard layout', format_item = label }, function(layout)
      if layout then
        M.set(layout, buf)
      end
    end)
    return
  end

  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  require('telescope.pickers')
    .new(require('telescope.themes').get_dropdown { winblend = 0, previewer = false, layout_config = { height = #layouts + 4 } }, {
      prompt_title = 'Keyboard layout',
      initial_mode = 'normal',
      default_selection_index = current_index,
      finder = require('telescope.finders').new_table {
        results = layouts,
        entry_maker = function(layout)
          return { value = layout, display = label(layout), ordinal = layout.key .. ' ' .. layout.name }
        end,
      },
      sorter = require('telescope.config').values.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        local function choose(layout)
          actions.close(prompt_bufnr)
          if layout then
            M.set(layout, buf)
          end
        end
        -- Our own <CR>, not select_default, which would `:edit` the entry.
        local function choose_selected()
          local entry = action_state.get_selected_entry()
          choose(entry and entry.value)
        end
        map('i', '<CR>', choose_selected)
        map('n', '<CR>', choose_selected)
        -- Normal mode only: in Insert mode the letters filter, as usual.
        for _, layout in ipairs(layouts) do
          map('n', layout.key, function()
            choose(layout)
          end)
        end
        return true
      end,
    })
    :find()
end

return M

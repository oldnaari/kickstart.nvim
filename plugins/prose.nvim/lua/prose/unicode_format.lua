-- Unicode styled text: convert between 14 mathematical styles and plain ASCII.
-- Characters outside Latin letters and ASCII digits (Cyrillic, Armenian,
-- punctuation, spaces, newlines) pass through unchanged.

local M = {}

-- Build a map from plain ASCII to styled codepoints.
-- up / lo are the first codepoints of the uppercase / lowercase runs.
-- dig is the first codepoint of the digit run (nil = no digit mapping).
local function simple(up, lo, dig)
  local m = {}
  for i = 0, 25 do
    m[string.char(65 + i)] = vim.fn.nr2char(up + i)
    m[string.char(97 + i)] = vim.fn.nr2char(lo + i)
  end
  if dig then
    for i = 0, 9 do m[tostring(i)] = vim.fn.nr2char(dig + i) end
  end
  return m
end

-- Like simple(), but with per-character overrides for holes in the Math block
-- where a codepoint is unassigned and the standard uses a Letterlike symbol.
local function with_ex(up, lo, dig, up_ex, lo_ex)
  local m = simple(up, lo, dig)
  for k, v in pairs(up_ex or {}) do m[k] = v end
  for k, v in pairs(lo_ex or {}) do m[k] = v end
  return m
end

-- Small Caps uses IPA/Phonetic letters, not the Math block.
-- Q and X have no small-caps equivalents; they pass through as lowercase.
local sc = {
  'ᴀ','ʙ','ᴄ','ᴅ','ᴇ','ꜰ','ɢ','ʜ','ɪ','ᴊ','ᴋ','ʟ','ᴍ',
  'ɴ','ᴏ','ᴘ','q','ʀ','ꜱ','ᴛ','ᴜ','ᴠ','ᴡ','x','ʏ','ᴢ',
}
local function small_caps_map()
  local m = {}
  for i, c in ipairs(sc) do
    m[string.char(64 + i)] = c
    m[string.char(96 + i)] = c
  end
  return m
end

local function nr(n) return vim.fn.nr2char(n) end

local MAPS = {
  bold             = simple(0x1D400, 0x1D41A, 0x1D7CE),
  italic           = with_ex(0x1D434, 0x1D44E, nil, {}, { h = nr(0x210E) }),
  bold_italic      = simple(0x1D468, 0x1D482),
  script           = with_ex(0x1D49C, 0x1D4B6, nil,
    { B=nr(0x212C), E=nr(0x2130), F=nr(0x2131), H=nr(0x210B),
      I=nr(0x2110), L=nr(0x2112), M=nr(0x2133), R=nr(0x211B) },
    { e=nr(0x212F), g=nr(0x210A), o=nr(0x2134) }),
  bold_script      = simple(0x1D4D0, 0x1D4EA),
  fraktur          = with_ex(0x1D504, 0x1D51E, nil,
    { C=nr(0x212D), H=nr(0x210C), I=nr(0x2111), R=nr(0x211C), Z=nr(0x2128) }, {}),
  bold_fraktur     = simple(0x1D56C, 0x1D586),
  double_struck    = with_ex(0x1D538, 0x1D552, 0x1D7D8,
    { C=nr(0x2102), H=nr(0x210D), N=nr(0x2115), P=nr(0x2119),
      Q=nr(0x211A), R=nr(0x211D), Z=nr(0x2124) }, {}),
  sans             = simple(0x1D5A0, 0x1D5BA, 0x1D7E2),
  sans_bold        = simple(0x1D5D4, 0x1D5EE, 0x1D7EC),
  sans_italic      = simple(0x1D608, 0x1D622),
  sans_bold_italic = simple(0x1D63C, 0x1D656),
  monospace        = simple(0x1D670, 0x1D68A, 0x1D7F6),
  small_caps       = small_caps_map(),
}

-- Ordered list that drives the picker and M.apply dispatch.
M.STYLES = {
  { key = 'plain',            label = 'Plain'            },
  { key = 'bold',             label = 'Bold'             },
  { key = 'italic',           label = 'Italic'           },
  { key = 'bold_italic',      label = 'Bold Italic'      },
  { key = 'script',           label = 'Script'           },
  { key = 'bold_script',      label = 'Bold Script'      },
  { key = 'fraktur',          label = 'Fraktur'          },
  { key = 'bold_fraktur',     label = 'Bold Fraktur'     },
  { key = 'double_struck',    label = 'Double-struck'    },
  { key = 'sans',             label = 'Sans'             },
  { key = 'sans_bold',        label = 'Sans Bold'        },
  { key = 'sans_italic',      label = 'Sans Italic'      },
  { key = 'sans_bold_italic', label = 'Sans Bold Italic' },
  { key = 'monospace',        label = 'Monospace'        },
  { key = 'small_caps',       label = 'Small Caps'       },
}

-- Reverse lookup tables, built lazily on first use.
local reverse  = nil -- styled char → plain ASCII char
local style_of = nil -- styled char → style key

local function build_reverse()
  if reverse then return end
  reverse  = {}
  style_of = {}
  for key, m in pairs(MAPS) do
    for plain, styled in pairs(m) do
      if not reverse[styled] then
        reverse[styled]  = plain
        style_of[styled] = key
      end
    end
  end
end

-- Iterate over UTF-8 characters in `str`, yielding one char string per call.
local function each_char(str)
  local i, n = 1, #str
  return function()
    if i > n then return nil end
    local b   = str:byte(i)
    local len = b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
    local ch  = str:sub(i, i + len - 1)
    i = i + len
    return ch
  end
end

-- Return the last byte index (1-indexed) of the UTF-8 char that starts at `start`.
local function char_last_byte(str, start)
  local b = str:byte(start)
  if not b or b < 0x80 then return start end
  if b >= 0xF0 then return start + 3 end
  if b >= 0xE0 then return start + 2 end
  return start + 1
end

-- Apply `style_key` to `text`, stripping any existing style first.
function M.apply(style_key, text)
  build_reverse()
  local plain = {}
  for ch in each_char(text) do
    plain[#plain + 1] = reverse[ch] or ch
  end
  local plain_str = table.concat(plain)
  if style_key == 'plain' then return plain_str end
  local map = MAPS[style_key]
  if not map then return plain_str end
  local result = {}
  for i = 1, #plain_str do
    local ch = plain_str:sub(i, i)
    result[#result + 1] = map[ch] or ch
  end
  return table.concat(result)
end

-- Return the style key of the first styled alphabetic character in `text`,
-- or 'plain' when the text is plain ASCII or no alphabetic character is found.
function M.detect(text)
  build_reverse()
  for ch in each_char(text) do
    local b = ch:byte(1)
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
      return 'plain'
    end
    if b > 127 and style_of[ch] then
      return style_of[ch]
    end
  end
  return 'plain'
end

-- Open a Telescope picker (or vim.ui.select fallback) for `text`.
-- Calls on_select(styled_text) when the user confirms a style.
function M.pick(text, on_select)
  local detected = M.detect(text)
  local entries  = {}
  local initial  = 1
  for i, s in ipairs(M.STYLES) do
    entries[i] = { key = s.key, label = s.label, preview = M.apply(s.key, text) }
    if s.key == detected then initial = i end
  end

  if not pcall(require, 'telescope') then
    local items = {}
    for i, e in ipairs(entries) do
      items[i] = ('%-18s %s'):format(e.label, e.preview)
    end
    vim.ui.select(items, { prompt = 'Unicode style' }, function(_, idx)
      if idx then on_select(entries[idx].preview) end
    end)
    return
  end

  local actions      = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  require('telescope.pickers')
    .new(
      require('telescope.themes').get_dropdown {
        winblend      = 0,
        previewer     = false,
        layout_config = { height = #entries + 4 },
      },
      {
        prompt_title          = 'Unicode style',
        initial_mode          = 'normal',
        default_selection_index = initial,
        finder = require('telescope.finders').new_table {
          results     = entries,
          entry_maker = function(e)
            return {
              value   = e,
              display = ('%-18s %s'):format(e.label, e.preview),
              ordinal = e.label,
            }
          end,
        },
        sorter = require('telescope.config').values.generic_sorter {},
        attach_mappings = function(prompt_bufnr, map)
          local function choose()
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if entry then on_select(entry.value.preview) end
          end
          map('i', '<CR>', choose)
          map('n', '<CR>', choose)
          return true
        end,
      }
    )
    :find()
end

-- Capture the visual selection. Works in both normal mode (marks '< '> are set
-- after visual mode exits) and visual mode (some which-key configs call the
-- 'x' keymap callback before Neovim has updated the marks; use 'v'/'.' then).
local function get_visual()
  local sl, cs, el, ce
  local mode = vim.api.nvim_get_mode().mode
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local vs = vim.fn.getpos('v')
    local ve = vim.fn.getpos('.')
    sl, cs = vs[2], vs[3]
    el, ce = ve[2], ve[3]
    if sl > el or (sl == el and cs > ce) then
      sl, cs, el, ce = el, ce, sl, cs
    end
    if mode == 'V' then
      cs = 1
      local ll = vim.api.nvim_buf_get_lines(0, el - 1, el, false)[1] or ''
      ce = #ll
    end
  else
    sl = vim.fn.line("'<")
    cs = vim.fn.col("'<")
    el = vim.fn.line("'>")
    ce = vim.fn.col("'>")
    if sl == 0 then return nil end
  end
  local lines = vim.api.nvim_buf_get_lines(0, sl - 1, el, false)
  if #lines == 0 then return nil end
  local last    = lines[#lines]
  local ce_last = math.min(char_last_byte(last, ce), #last)
  local text
  if sl == el then
    text = lines[1]:sub(cs, ce_last)
  else
    local parts = { lines[1]:sub(cs) }
    for i = 2, #lines - 1 do parts[#parts + 1] = lines[i] end
    parts[#parts + 1] = last:sub(1, ce_last)
    text = table.concat(parts, '\n')
  end
  return text, sl - 1, cs - 1, el - 1, ce_last
end

-- Get the word under the cursor and its byte range on the current line.
-- Returns text, row, s_col, row, e_col (0-indexed, e_col exclusive), or nil.
local function get_cword()
  local word = vim.fn.expand('<cword>')
  if word == '' then return nil end
  local row     = vim.fn.line('.') - 1
  local line    = vim.api.nvim_get_current_line()
  local cur_col = vim.fn.col('.') - 1
  local wlen    = #word
  local pos     = 1
  while true do
    local s = line:find(word, pos, true)
    if not s then break end
    local s0 = s - 1
    if cur_col >= s0 and cur_col < s0 + wlen then
      return word, row, s0, row, s0 + wlen
    end
    pos = s + 1
  end
  local s = line:find(word, 1, true)
  if s then
    local s0 = s - 1
    return word, row, s0, row, s0 + wlen
  end
end

-- Entry point for the Normal-mode keymap: style the word under the cursor.
function M.format_normal()
  local text, row, sc, _, ec = get_cword()
  if not text then
    vim.notify('No word under cursor', vim.log.levels.WARN, { title = 'Prose' })
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  M.pick(text, function(styled)
    vim.api.nvim_buf_set_text(buf, row, sc, row, ec, { styled })
  end)
end

-- Entry point for the Visual-mode keymap: style the visual selection.
function M.format_visual()
  local text, sl, sc, el, ec = get_visual()
  if not text or text == '' then
    vim.notify('No selection', vim.log.levels.WARN, { title = 'Prose' })
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  M.pick(text, function(styled)
    vim.api.nvim_buf_set_text(buf, sl, sc, el, ec,
      vim.split(styled, '\n', { plain = true }))
  end)
end

return M

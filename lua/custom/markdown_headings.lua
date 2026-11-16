-- Centred markdown headings, drawn for render-markdown.nvim.
--
-- Registered as a `custom_handlers.markdown` entry in init.lua, with the plugin's
-- own heading renderer switched off (`heading = { enabled = false }`). The plugin
-- cannot draw this layout. Its `left_margin` / `left_pad` are either a fixed
-- column count or a fraction of the *whole* window, so they cannot centre on a
-- capped width. It has no way to fill padding with a character, and none to
-- change the case of the text.
--
-- Going through `custom_handlers` rather than plain extmarks keeps everything the
-- plugin does for its own marks: they exist only in `render_modes`, are redrawn on
-- `WinResized`, and the `conceal = true` ones hide on the cursor line.
--
-- Layout, in rendered mode only:
--
--   H1  ░░░░░░░░░░░░░░░░ GETTING STARTED ░░░░░░░░░░░░░░░░░░░░░░░░░  band to window edge
--   H2  ░░░░░░░░░░░░░░░░░░ Installation ░░░░░░░░░░░░░░░░░░░░░░░░░░
--   H3  ─────────────────── Section ──────────────────────────────  the `***` rule
--
-- The title is centred within `min(FRAME, window width)`, not the full window,
-- so it sits over the text column on a wide screen. A title too wide for that
-- frame falls back to left alignment. Colours come from markdown_theme.lua.

local M = {}

-- Width the title is centred within. Prose here is kept to 80 columns.
local FRAME = 80

-- Same shape as the TOC query in markdown_toc.lua. The marker carries the level
-- as the only digit in its node type.
local query = vim.treesitter.query.parse(
  'markdown',
  [[
  (atx_heading
    [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker)
     (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @marker
    heading_content: (_) @content)

  (setext_heading
    heading_content: (_) @content
    [(setext_h1_underline) (setext_h2_underline)] @marker)
]]
)

-- markdown_inline nodes whose bare text (the gaps between their children) is
-- prose and so gets uppercased in H1. Link wrappers are walked through to their
-- `link_text`, without taking gaps of their own. Everything else, notably
-- `code_span`, URLs and HTML, keeps its case.
local TEXT = { inline = true, emphasis = true, strong_emphasis = true, strikethrough = true, link_text = true, image_description = true }
local LINK = { inline_link = true, full_reference_link = true, collapsed_reference_link = true, shortcut_link = true, image = true }

---@param marks render.md.Mark[]
---@param conceal boolean true: hidden while the cursor is on this row
---@param row integer
---@param col integer
---@param opts table
local function add(marks, conceal, row, col, opts)
  marks[#marks + 1] = { conceal = conceal, start_row = row, start_col = col, opts = opts }
end

---render-markdown's per-render context. This is the one private API used here,
---so every use has a fallback.
---@param buf integer
---@return table?
local function request(buf)
  local ok, context = pcall(function()
    return require('render-markdown.request.context').get(buf)
  end)
  return ok and context or nil
end

---Display width of the title as rendered. render-markdown's context accounts for
---concealed `**`, backticks and link URLs, and for the cells it inserts (inline
---code padding, link icons). The markdown_inline handler has already run when
---this one does, so those are known.
---@param context table?
---@param body { text: string, start_row: integer, start_col: integer, end_row: integer, end_col: integer }
---@return integer
local function title_width(context, body)
  if context then
    local ok, width = pcall(context.width, context, body)
    if ok then
      return width
    end
  end
  return vim.fn.strdisplaywidth(body.text)
end

---Cells the line takes for 'wrap'. Neovim wraps on the raw text -- concealed
---`**` and link URLs still count -- plus inline virtual text, not on what is
---drawn. So padding that fits the rendered title can still push the line onto a
---second row.
---@param context table?
---@param row integer
---@param line string
---@return integer
local function wrap_cells(context, row, line)
  local cells = vim.fn.strdisplaywidth(line)
  if context then
    local ok, inserted = pcall(function()
      return context.offset:get({ text = line, start_row = row, start_col = 0, end_row = row, end_col = #line + 1 })
    end)
    if ok then
      cells = cells + inserted
    end
  end
  return cells
end

---Text area width of the window, without number and sign columns.
---@param win integer
---@return integer
local function text_width(win)
  local info = vim.fn.getwininfo(win)[1]
  return vim.api.nvim_win_get_width(win) - (info and info.textoff or 0)
end

---Collect `{ row, start_col, end_col }` for runs of plain text under `node`.
---Only single-row gaps are kept; `stop` clamps runs on `row` (closing `##`).
---@param node TSNode
---@param runs table[]
---@param stop_row integer
---@param stop_col integer
local function plain_runs(node, runs, stop_row, stop_col)
  local kind = node:type()
  if not (TEXT[kind] or LINK[kind]) then
    return
  end
  local function gap(row, col, end_row, end_col)
    if TEXT[kind] and row == end_row then
      if row == stop_row then
        end_col = math.min(end_col, stop_col)
      end
      if col < end_col then
        runs[#runs + 1] = { row, col, end_col }
      end
    end
  end
  local row, col = node:start()
  for child in node:iter_children() do
    local child_row, child_col = child:start()
    gap(row, col, child_row, child_col)
    plain_runs(child, runs, stop_row, stop_col)
    row, col = child:end_()
  end
  local end_row, end_col = node:end_()
  gap(row, col, end_row, end_col)
end

---ALL CAPS for H1: overlay the uppercased text on each plain run. Hidden on the
---cursor line, so the real case is what you see and edit there.
---@param marks render.md.Mark[]
---@param buf integer
---@param range integer[] the heading's inline content
---@param stop_col integer end of the title on its first row
---@param hl string
local function caps(marks, buf, range, stop_col, hl)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then
    return
  end
  local tree = parser:language_for_range(range)
  if tree:lang() ~= 'markdown_inline' then
    return
  end
  local root = tree:named_node_for_range(range)
  if not root then
    return
  end
  local runs = {}
  plain_runs(root, runs, range[1], stop_col)
  for _, run in ipairs(runs) do
    local row, col, end_col = run[1], run[2], run[3]
    local text = vim.api.nvim_buf_get_text(buf, row, col, row, end_col, {})[1]
    local upper = vim.fn.toupper(text)
    -- An overlay covers cells, not bytes: skip a run whose width would change.
    if upper ~= text and vim.fn.strdisplaywidth(upper) == vim.fn.strdisplaywidth(text) then
      add(marks, true, row, col, { virt_text = { { upper, hl } }, virt_text_pos = 'overlay' })
    end
  end
end

---@class custom.heading.Style
---@field band boolean H1/H2: background band; otherwise a rule
---@field fg string
---@field bg string
---@field icon string rule character, from render-markdown's `dash`
---@field rule string rule highlight, from render-markdown's `dash`

---The left fill, `cells` wide, split into the part drawn as inline virtual text
---and the last `k` cells, which are overlaid on the `#` marker. A rule ends in
---the space before the title.
---@param style custom.heading.Style
---@param cells integer
---@param k integer
---@return string inline, string overlay
local function left_fill(style, cells, k)
  if style.band then
    return (' '):rep(cells - k), (' '):rep(k)
  end
  if k == 0 then
    return style.icon:rep(cells - 1) .. ' ', ''
  end
  return style.icon:rep(cells - k), style.icon:rep(k - 1) .. ' '
end

---@param marks render.md.Mark[]
---@param buf integer
---@param context table?
---@param win_width integer
---@param wrap boolean the window's 'wrap'
---@param style custom.heading.Style
---@param marker TSNode
---@param content TSNode
---@param level integer
local function heading(marks, buf, context, win_width, wrap, style, marker, content, level)
  local setext = marker:type():find('setext', 1, true) ~= nil
  -- Setext content is a paragraph; the inline text is its child.
  local inline = content:type() == 'paragraph' and content:named_child(0) or content
  if not inline then
    return
  end
  local row, col, end_row, end_col = inline:range()
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  local single = row == end_row

  -- The grammar keeps an ATX closing sequence (`## Title ##`) inside the content.
  local title_end = single and end_col or #line
  if not setext and single then
    local kept = line:sub(col + 1, end_col):match '^(.-)%s+#+$'
    if kept and kept ~= '' then
      title_end = col + #kept
    end
  end

  -- Where the heading starts: the `#` marker, or the setext text. Anything
  -- before it other than spaces means a heading nested in a quote or list item.
  local first_col = setext and col or select(2, marker:start())
  local nested = line:sub(1, first_col):match '^ *$' == nil

  local w = title_width(context, {
    text = line:sub(col + 1, title_end),
    start_row = row,
    start_col = col,
    end_row = row,
    end_col = title_end,
  })
  local frame = math.min(FRAME, win_width)
  local trailing = single and title_end < #line

  if setext then
    local m_row, m_col, m_end_row, m_end_col = marker:range()
    add(marks, true, m_row, m_col, { end_row = m_end_row, end_col = m_end_col, conceal = '' })
    add(marks, true, m_row, m_col, { end_row = m_end_row, end_col = m_end_col, conceal_lines = '' })
  end
  if trailing then
    add(marks, true, row, title_end, { end_row = row, end_col = #line, conceal = '' })
  end

  -- Everything before the title -- the `#…# ` marker, or a setext title's
  -- indent -- is `m` cells. Rather than concealing it, the last `k` cells of the
  -- left fill are overlaid on it, and only the rest is inserted as inline text.
  -- On the cursor line the overlay hides and the raw `##` shows in the same
  -- cells, so nothing moves.
  local m = col
  local left = math.floor((frame - w) / 2)
  local wraps = false
  if wrap then
    -- Insert no more than the line has room for, or it wraps; see wrap_cells.
    -- A line that wraps even unpadded is left-aligned.
    local room = win_width - wrap_cells(context, row, line)
    wraps = room < 0
    left = wraps and 0 or math.min(left, m + room)
  end

  if not nested and single and w + 2 <= frame and left >= 1 then
    local k = math.min(left, m)
    local hl = style.band and style.bg or style.rule
    local before, over = left_fill(style, left, k)
    if before ~= '' then
      add(marks, false, row, 0, { virt_text = { { before, hl } }, virt_text_pos = 'inline' })
    end
    if over ~= '' then
      add(marks, true, row, 0, { virt_text = { { over, hl } }, virt_text_pos = 'overlay' })
    end
    if m > k then
      add(marks, true, row, k, { end_row = row, end_col = m, conceal = '' })
    end
    -- Revealing more marker than the overlay covers, or a closing `##`, shifts
    -- the title on the cursor line. Then the rule must hide there too, or it
    -- would draw over the end of the title.
    local shifts = m > k or trailing
    if style.band then
      add(marks, false, row, 0, { end_row = row + 1, end_col = 0, hl_group = style.bg, hl_eol = true })
    else
      -- A window column, not inline text: it clips at the edge instead of wrapping.
      add(marks, shifts, row, 0, {
        virt_text = { { ' ' .. style.icon:rep(vim.o.columns), style.rule } },
        virt_text_win_col = left + w,
      })
    end
  else
    -- Left-aligned: too wide for the frame or the window, nested, or a
    -- multi-line setext title. The title starts where the marker did.
    if not setext then
      add(marks, true, row, first_col, { end_row = row, end_col = col, conceal = '' })
    end
    if style.band then
      local last = nested and row or end_row
      for r = row, last do
        add(marks, false, r, r == row and first_col or 0, { end_row = r + 1, end_col = 0, hl_group = style.bg, hl_eol = true })
      end
    elseif not nested and single and not wraps and first_col + w + 2 < win_width then
      add(marks, true, row, 0, {
        virt_text = { { ' ' .. style.icon:rep(vim.o.columns), style.rule } },
        virt_text_win_col = first_col + w,
      })
    end
  end

  if level == 1 then
    caps(marks, buf, { row, col, end_row, end_col }, title_end, style.fg)
  end
end

---`custom_handlers.markdown.parse`, with `extends = true` so the builtin
---markdown handler still draws everything else.
---@param ctx render.md.handler.Context
---@return render.md.Mark[]
function M.parse(ctx)
  local marks = {} ---@type render.md.Mark[]
  local context = request(ctx.buf)
  local win = context and context.win or vim.fn.bufwinid(ctx.buf)
  if not win or win == -1 or not vim.api.nvim_win_is_valid(win) then
    return marks
  end
  local win_width = text_width(win)
  local wrap = vim.wo[win].wrap
  -- The rule is the `***` separator's own character and highlight.
  local dash = context and context.config.dash or {}

  for _, match in query:iter_matches(ctx.root, ctx.buf) do
    local marker, content
    for id, nodes in pairs(match) do
      -- Neovim 0.11+ hands back a list of nodes per capture, not a single node.
      local node = type(nodes) == 'table' and nodes[1] or nodes
      if query.captures[id] == 'marker' then
        marker = node
      else
        content = node
      end
    end
    local level = marker and tonumber(marker:type():match '%d')
    if level and content then
      heading(marks, ctx.buf, context, win_width, wrap, {
        band = level <= 2,
        fg = 'RenderMarkdownH' .. level,
        bg = 'RenderMarkdownH' .. level .. 'Bg',
        icon = dash.icon or '─',
        rule = dash.highlight or 'RenderMarkdownDash',
      }, marker, content, level)
    end
  end
  return marks
end

return M

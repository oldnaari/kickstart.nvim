-- Single source of truth for markdown colours.
--
-- READ THIS BEFORE CHANGING A COLOUR HERE.
--
-- Markdown is drawn two different ways depending on the mode:
--
--   normalish (normal, command)      render-markdown.nvim extmarks, which pick
--                                    their colours from `RenderMarkdown*` groups
--   insertish (insert, replace) and  plain treesitter highlighting, which picks
--   visual                           its colours from `@markup.*` groups
--
-- render-markdown only renders in `render_modes` (`{ 'n', 'c', 't' }`, left at
-- the default in init.lua on purpose -- visual counts as insertish here, so that
-- raw markers stay visible and column selection is predictable). The moment you
-- press `i` or `v` every extmark disappears and treesitter is all that is left.
--
-- The two are not independent. render-markdown links its own groups to the
-- treesitter namespace with `default = true` -- see `M.colors` in
-- render-markdown/core/colors.lua:
--
--     RenderMarkdownH1        -> @markup.heading.1.markdown
--     RenderMarkdownQuote     -> @markup.quote
--     RenderMarkdownUnchecked -> @markup.list.unchecked
--
-- so defining the treesitter group usually styles BOTH modes at once. That link
-- is why this file exists: nord.nvim predates Neovim's `@markup.*` namespace and
-- defines only the legacy `@text.*` groups, which left all six heading levels the
-- same colour and inline code indistinguishable from body text -- in the rendered
-- view as much as the raw one.
--
-- ===> Every row below applies to BOTH normalish and insertish modes. <===
-- ===> Change a row and you have changed both. That is the point.     <===
--
-- Where render-markdown has no such link, the second column names the group that
-- is set explicitly from the same palette entry, so the two modes cannot drift.

local M = {}

---Resolve the nord palette. Returns nil if nord is not the active theme.
---@return table?
local function palette()
  local ok, nord = pcall(require, 'nord.colors')
  if not ok then
    return nil
  end
  return {
    bg_soft = nord.nord1_gui, -- #3B4252
    muted = nord.nord3_gui_bright, -- #616E88
    cyan = nord.nord7_gui, -- #8FBCBB
    frost = nord.nord8_gui, -- #88C0D0
    blue = nord.nord9_gui, -- #81A1C1
    red = nord.nord11_gui, -- #BF616A
    yellow = nord.nord13_gui, -- #EBCB8B
    green = nord.nord14_gui, -- #A3BE8C
    purple = nord.nord15_gui, -- #B48EAD
  }
end

---The mapping table.
---
---  [1] treesitter group  -- authoritative, drives insertish + visual modes
---  [2] rendered consumer -- 'link' means render-markdown already links to [1]
---                           with `default = true`, so [1] covers both modes and
---                           there is nothing else to do. Any other value is a
---                           `RenderMarkdown*` group with no such link, set below
---                           from this same row.
---  [3] style
---  [4] optional style for [2] when the rendered side must differ from the raw
---      side. Used only for code, where the background is an extmark but the
---      foreground still comes from treesitter underneath it.
---@param p table
---@return table[]
local function rows(p)
  return {
    -- Headings. Six levels, six colours. Previously all six resolved to the same
    -- `Title`-derived green in both modes; only the icon told them apart.
    { '@markup.heading.1.markdown', 'link', { fg = p.frost, bold = true } },
    { '@markup.heading.2.markdown', 'link', { fg = p.blue, bold = true } },
    { '@markup.heading.3.markdown', 'link', { fg = p.green, bold = true } },
    { '@markup.heading.4.markdown', 'link', { fg = p.yellow, bold = true } },
    { '@markup.heading.5.markdown', 'link', { fg = p.purple, bold = true } },
    { '@markup.heading.6.markdown', 'link', { fg = p.red, bold = true } },

    -- Fenced code blocks. The background sits *under* the injected language's own
    -- syntax colours: a capture that only sets `fg` leaves `bg` alone, so python
    -- keywords keep their colour and gain the block background. In raw view the
    -- background stops at end-of-text rather than running to the window edge --
    -- that full-width fill is virtual text, so it is rendered-mode only.
    { '@markup.raw.block.markdown', 'RenderMarkdownCode', { bg = p.bg_soft } },

    -- Inline code. Rendered mode paints the background as an extmark over text
    -- that treesitter has already coloured, so the rendered group carries only
    -- the background -- hence the fourth column.
    { '@markup.raw.markdown_inline', 'RenderMarkdownCodeInline', { fg = p.cyan, bg = p.bg_soft }, { bg = p.bg_soft } },

    -- Lists. `RenderMarkdownBullet` links to `Normal`, not to `@markup.list`, so
    -- the rendered bullet icon needs setting from this row too.
    { '@markup.list', 'RenderMarkdownBullet', { fg = p.frost } },
    { '@markup.list.unchecked', 'link', { fg = p.muted } },
    { '@markup.list.checked', 'link', { fg = p.green } },

    -- Block quotes.
    { '@markup.quote', 'link', { fg = p.muted } },

    -- Callouts. The `@markup.callout.*` captures come from
    -- after/queries/markdown_inline/highlights.scm; without it treesitter sees
    -- `[!NOTE]` as an ordinary link label. The paired `RenderMarkdown*` groups are
    -- the ones the `callout` config in init.lua already names, so the raw
    -- `[!WARNING]` and the rendered `󰀪 Warning` share one colour.
    { '@markup.callout.note', 'RenderMarkdownInfo', { fg = p.frost, bold = true } },
    { '@markup.callout.tip', 'RenderMarkdownSuccess', { fg = p.green, bold = true } },
    { '@markup.callout.warning', 'RenderMarkdownWarn', { fg = p.yellow, bold = true } },
    { '@markup.callout.danger', 'RenderMarkdownError', { fg = p.red, bold = true } },
  }
end

---Groups that are neither treesitter nor render-markdown: plain extmarks added
---by prose.nvim (prose/highlight.lua) over text that has no node of its own.
---
---These are the one place in this file where the two-mode split does NOT apply.
---Extmarks are not gated by `render_modes`, so a single definition already
---covers normalish, insertish and visual alike -- there is no second consumer to
---keep in sync.
---@param p table
---@return table<string, table>
local function extmark_groups(p)
  return {
    -- Parentheticals in running prose. Nord's Polar Night proper (nord3,
    -- #4C566A) is too dark to read against the terminal background; this is its
    -- bright variant, the same grey used for quotes and unchecked boxes above.
    MarkdownProseParen = { fg = p.muted },
    -- "Quoted strings" in running prose.
    MarkdownProseString = { fg = p.green },
  }
end

---Define every group. Safe to call repeatedly; call it after `:colorscheme`.
function M.apply()
  local p = palette()
  if not p then
    return
  end

  for name, style in pairs(extmark_groups(p)) do
    vim.api.nvim_set_hl(0, name, style)
  end

  for _, row in ipairs(rows(p)) do
    local ts_group, rendered, style, rendered_style = row[1], row[2], row[3], row[4]
    vim.api.nvim_set_hl(0, ts_group, style)
    if rendered ~= 'link' then
      vim.api.nvim_set_hl(0, rendered, rendered_style or style)
    end
  end

  -- render-markdown caches colours combined from the groups above and refreshes
  -- that cache from its own ColorScheme autocmd. That autocmd is registered at
  -- startup, so it runs *before* ours and would cache the pre-change values for a
  -- whole colorscheme cycle. Force the refresh now that the groups are set.
  -- pcall: the plugin is `ft`-lazy and may not be loaded yet.
  pcall(function()
    require('render-markdown.core.colors').reload()
  end)
end

return M

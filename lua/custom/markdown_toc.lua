-- Table of contents picker for markdown buffers.
--
-- Bound to `<leader>dt` in `after/ftplugin/markdown.lua`. Lives here rather than in
-- the ftplugin so it is evaluated once instead of on every markdown buffer.
--
-- Built on treesitter rather than marksman's LSP document symbols (which `<leader>ds`
-- already gives you). Treesitter wins here on three counts: it does not depend on the
-- LSP having attached, the heading marker node carries the exact level so entries can
-- be indented by depth, and setext headings come back as bare text -- marksman returns
-- them with the underline glued on, as `"Setext Heading\n=============="`.
--
-- Headings inside fenced code blocks are excluded for free: they parse as
-- `code_fence_content`, not `atx_heading`.

local M = {}

-- The marker captures are what make the level available: `atx_h3_marker` and
-- `setext_h2_underline` both carry their level as the only digit in the node type.
-- Note the field order differs between the two -- setext underlines come *after* the
-- content, and the query has to match the grammar's order.
local query_src = [[
  (atx_heading
    [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker)
     (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @marker
    heading_content: (_) @content)

  (setext_heading
    heading_content: (_) @content
    [(setext_h1_underline) (setext_h2_underline)] @marker)
]]

--- Collect `{ level, text, lnum }` for every heading in `buf`, in document order.
local function headings(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then
    return nil, 'No markdown parser for this buffer'
  end

  local query = vim.treesitter.query.parse('markdown', query_src)
  local root = parser:parse()[1]:root()

  local results = {}
  for _, match in query:iter_matches(root, buf) do
    local level, text, lnum
    for id, nodes in pairs(match) do
      -- Neovim 0.11+ hands back a list of nodes per capture, not a single node.
      local node = type(nodes) == 'table' and nodes[1] or nodes
      if query.captures[id] == 'marker' then
        level = tonumber(node:type():match '%d')
      else
        text = vim.treesitter.get_node_text(node, buf)
        lnum = node:range() + 1
      end
    end
    if level and text and lnum then
      -- Trim, then drop an ATX closing sequence (`## Heading ##`), which the grammar
      -- keeps inside heading_content.
      text = vim.trim(text):gsub('%s*#+%s*$', '')
      results[#results + 1] = { level = level, text = text, lnum = lnum }
    end
  end

  -- Matches came back in document order in practice, but ordering across separate
  -- query patterns is not guaranteed, and a TOC out of order is worse than useless.
  table.sort(results, function(a, b)
    return a.lnum < b.lnum
  end)

  return results
end

--- Breadcrumb for the heading at `index`, e.g. `Ownership > Borrowing`.
--- Used as the fuzzy-match string so typing a parent's name narrows to its children,
--- and so the display indent never counts towards the match.
local function breadcrumb(items, index)
  local item = items[index]
  local path = { item.text }
  local level = item.level
  for i = index - 1, 1, -1 do
    if items[i].level < level then
      table.insert(path, 1, items[i].text)
      level = items[i].level
    end
  end
  return table.concat(path, ' > ')
end

function M.open()
  local buf = vim.api.nvim_get_current_buf()
  local items, err = headings(buf)
  if not items then
    return vim.notify(err, vim.log.levels.WARN)
  end
  if #items == 0 then
    return vim.notify('No headings in this buffer', vim.log.levels.INFO)
  end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  local entries = {}
  for i, item in ipairs(items) do
    entries[i] = {
      lnum = item.lnum,
      display = string.rep('  ', item.level - 1) .. item.text,
      ordinal = breadcrumb(items, i),
    }
  end

  pickers
    .new(require('telescope.themes').get_dropdown { winblend = 0, previewer = false }, {
      prompt_title = 'Table of Contents',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          entry.value = entry.lnum
          return entry
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        -- Deliberately not `actions.select_default`. Two reasons: the default action
        -- edits by filename, which an unnamed scratch buffer does not have; and the
        -- global `<CR>` override in init.lua falls back to `entry.value`, which would
        -- try to `:edit` a heading's text. Jumping in place is also just what a TOC
        -- should do -- same window, same buffer.
        local function jump()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not entry then
            return
          end
          vim.cmd "normal! m'" -- so <C-o> comes back
          vim.api.nvim_win_set_cursor(0, { entry.lnum, 0 })
          vim.cmd 'normal! zvzz' -- open any fold the heading sits in, then centre
        end

        map('i', '<CR>', jump)
        map('n', '<CR>', jump)
        return true
      end,
    })
    :find()
end

return M

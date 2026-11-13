-- Dim parentheticals and colour quoted strings -- but only where they are prose.
--
-- WHY THIS IS NOT A TREESITTER QUERY
--
-- It cannot be. Treesitter captures are node-granular, and the markdown grammar
-- does not tokenise parentheses or quotes inside running text: a plain paragraph
-- carries no captures at all beyond `@spell`. There is no node to capture, and
-- `#offset!` only shifts a range by a fixed amount, so it cannot follow a match.
--
-- So this is a regex layer (mini.hipatterns, already part of mini.nvim) that adds
-- extmarks, with treesitter used only to answer "is this position prose?".
--
-- Unlike render-markdown, extmarks are not tied to `render_modes`, so these
-- highlights apply in every mode -- normal, visual and insert alike.
--
-- The groups are MarkdownProseParen and MarkdownProseString. prose/init.lua
-- links them to Comment and String by default; a theme can define them itself.
--
-- mini.hipatterns has one global config, so this plugin does not call its
-- setup. Pass the highlighters in yourself:
--
--   require('mini.hipatterns').setup { highlighters = require('prose.highlight').highlighters() }

local M = {}

-- Anything parsed by an injected language (python in a fence, yaml in front
-- matter) is by definition not markdown prose.
local PROSE_LANGS = { markdown = true, markdown_inline = true }

-- Capture prefixes that disqualify a position.
local NOT_PROSE = {
  '^markup%.raw', -- inline code spans and fenced code blocks
  '^markup%.link', -- link labels, and the `(url)` that follows one
  '^markup%.heading', -- headings, and pipe-table header rows
  '^conceal$',
}

---Tables: the header row is captured as `@markup.heading`, but body cells carry
---no distinguishing capture, so their parentheses would slip through. Walk the
---markdown tree (not the injected inline tree, whose root stops inside the cell)
---looking for a `pipe_table` ancestor.
---@return boolean
local function in_table(buf, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or parser == nil then
    return false
  end
  local tree = parser:parse()[1]
  if tree == nil then
    return false
  end
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  while node ~= nil do
    if node:type() == 'pipe_table' then
      return true
    end
    node = node:parent()
  end
  return false
end

---Is the given position running prose, rather than code/link/heading/table?
---@return boolean
function M.is_prose(buf, row, col)
  for _, c in ipairs(vim.treesitter.get_captures_at_pos(buf, row, col)) do
    if not PROSE_LANGS[c.lang] then
      return false
    end
    for _, pat in ipairs(NOT_PROSE) do
      if c.capture:match(pat) then
        return false
      end
    end
  end
  -- Cheapest check last: it parses, so only reach it once the captures pass.
  return not in_table(buf, row, col)
end

-- hipatterns config is global, so both halves gate on filetype themselves. That
-- is deliberately not `vim.b.minihipatterns_config` in the ftplugin: the buffer
-- variable is read once when hipatterns enables the buffer, which it schedules,
-- so setting it from a ftplugin invites an ordering race for no benefit here.
local function markdown_only(pat)
  return function(buf)
    -- Returning a non-string is a documented no-op in hipatterns.
    return vim.bo[buf].filetype == 'markdown' and pat or nil
  end
end

local function in_prose_only(hl)
  return function(buf, _, data)
    -- data.line is 1-indexed, data.from_col is a 1-indexed byte column.
    if not M.is_prose(buf, data.line - 1, data.from_col - 1) then
      return nil -- documented: skips this match
    end
    return hl
  end
end

---Highlighters for `require('mini.hipatterns').setup`.
---@return table
function M.highlighters()
  return {
    -- `%b()` matches balanced parentheses, so `(outer (inner) outer)` is caught
    -- whole and a stray `(` is not caught at all.
    md_paren = { pattern = markdown_only '%b()', group = in_prose_only 'MarkdownProseParen' },
    -- Straight double quotes only. Add the curly pair here if you start using
    -- typographic quotes; apostrophes are deliberately untouched.
    md_string = { pattern = markdown_only '"[^"]*"', group = in_prose_only 'MarkdownProseString' },
  }
end

return M

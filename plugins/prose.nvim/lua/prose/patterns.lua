-- Bad-pattern flags: what in a draft can be improved, as quiet diagnostics.
--
-- The checks themselves run in the shared parser (bin/roles), in
-- patterns/prose_patterns.py: subject far from its verb, passive, light verbs,
-- nominalizations, hedges, канцелярит, genitive chains, dangling modifiers and
-- the rest, in English, Russian and Armenian. They ride on the same parse as
-- the role colours (prose/roles.lua), so turning both on costs one parse.
--
-- This module turns the parser's results into diagnostics in their own
-- namespace, plus the two checks that need the whole document, which the parser
-- never sees at once:
--
--   Parallel  the items of a markdown list should open the same way: all
--             imperatives, all gerunds or all noun phrases
--   Acronym   an all-caps word used before it is defined
--
-- Every flag is a Hint: advice that is often fine to ignore, never an error.
-- ]d and [d walk through them; the message says what was noticed and why it can
-- matter, never what to write instead. Each code is shown in the float, such
-- as [Prose.Passive]; list the names in M.off to hide a check.

local M = {}

-- Checks to hide, by name without "Prose.": { 'Repetition', 'Adverb' }.
M.off = {}
-- Files up to this many lines are checked whole, so ]d finds every flag.
-- Longer ones are checked in view (and a screen either side), as the colours
-- are: scanning a long file's paragraphs on every edit would be felt.
M.whole_file_lines = 2000

local ns = vim.api.nvim_create_namespace 'prose-patterns'

M.namespace = ns

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Prose patterns' })
end

local FORMS = {
  imperative = 'an imperative',
  gerund = 'a gerund',
  infinitive = 'an infinitive',
  past = 'a past-tense verb',
  finite = 'a verb',
  noun = 'a noun phrase',
}

---Diagnostics for `paras` from their cached parses.
---@param whole boolean the paragraphs are the whole file
function M.publish(buf, paras, cache, whole)
  local roles = require 'prose.roles'
  local off = {}
  for _, name in ipairs(M.off) do
    off[name] = true
  end
  local diags = {}
  local function add(p, s, e, code, message)
    if off[code] then
      return
    end
    local srow, scol = roles.position(p, s)
    local erow, ecol = roles.position(p, e)
    diags[#diags + 1] = {
      lnum = srow,
      col = scol,
      end_lnum = erow,
      end_col = ecol,
      severity = vim.diagnostic.severity.HINT,
      source = 'prose',
      code = 'Prose.' .. code,
      message = message,
    }
  end

  local lists = {} ---@type table<string, {p: table, lead: table}[]>
  local seen = {} ---@type table<string, true> acronyms met so far, in file order
  local complete = whole -- every paragraph so far is parsed
  for _, p in ipairs(paras) do
    local res = cache[p.text]
    if not res then
      complete = false
    else
      for _, f in ipairs(res.flags) do
        add(p, f[1], f[2], f[3], f[4])
      end
      if p.list and res.lead then
        lists[p.list] = lists[p.list] or {}
        table.insert(lists[p.list], { p = p, lead = res.lead })
      end
      -- First use, which only the whole file in order can tell.
      for _, a in ipairs(complete and res.acronyms or {}) do
        local word, defined = a[3], a[4]
        if not seen[word] then
          seen[word] = true
          if not defined then
            add(
              p,
              a[1],
              a[2],
              'Acronym',
              ("'%s' is used before it is defined: a reader who does not know it has to guess. (Pinker: the curse of knowledge)"):format(word)
            )
          end
        end
      end
    end
  end

  for _, items in pairs(lists) do
    local counts, known = {}, 0
    for _, it in ipairs(items) do
      local form = it.lead[3]
      if FORMS[form] then
        counts[form] = (counts[form] or 0) + 1
        known = known + 1
      end
    end
    local best, n, tie = nil, 0, false
    for form, c in pairs(counts) do
      if c > n then
        best, n, tie = form, c, false
      elseif c == n then
        tie = true
      end
    end
    if best and not tie and n >= 2 and known >= 3 then
      for _, it in ipairs(items) do
        local form = it.lead[3]
        if FORMS[form] and form ~= best then
          add(
            it.p,
            it.lead[1],
            it.lead[2],
            'Parallel',
            ('This item opens with %s, but %d of the %d items in this list open with %s: items that do the same job read more easily in the same form. (Strunk & White: parallel form)'):format(
              FORMS[form],
              n,
              known,
              FORMS[best]
            )
          )
        end
      end
    end
  end

  vim.diagnostic.set(ns, buf, diags)
end

function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.diagnostic.reset(ns, buf)
  end
end

function M.enabled(buf)
  return require('prose.roles').enabled(buf, 'flags')
end

---@param opts? {auto?: boolean} auto: turned on by setup { patterns = true }.
---Silent, and skips buffers where the flags were turned off by hand.
function M.enable(buf, opts)
  if require('prose.roles').attach(buf, 'flags', opts) and not (opts and opts.auto) then
    notify 'On'
  end
end

function M.disable(buf)
  require('prose.roles').detach(buf, 'flags')
end

function M.toggle(buf)
  notify(require('prose.roles').flip(buf, 'flags') and 'On' or 'Off')
end

return M

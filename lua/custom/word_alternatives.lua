-- Alternatives for the word under the cursor, from two offline tools that answer
-- different questions. Deliberately kept separate, never blended:
--
--   Synonyms (bin/syn, WordNet): what else MEANS this? A dictionary lookup,
--     blind to context. For cutting repetition or finding a closer word.
--   Fill (bin/fill, a masked language model): what else FITS HERE? It reads the
--     text around the word and ranks what could go in its place, whatever the
--     meaning, opposites included. For playing with prose.
--
-- Entry points: `<leader>ps` / `<leader>pf` in markdown, `<C-x><C-t>` in insert
-- mode (WordNet, via 'thesaurusfunc'), and the :Synonyms / :Fill commands.
--
-- A missing tool is never fatal: the action says what to install and stops,
-- and `:checkhealth custom` lists both (lua/custom/health.lua). Nothing here
-- installs system packages itself.

local M = {}

M.bin = vim.fn.stdpath 'config' .. '/bin'

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Word alternatives' })
end

---Install command for a missing tool, for this OS. Shared with the health check.
---@param exe 'wn'|'uv'
function M.install_hint(exe)
  local mac = vim.fn.has 'mac' == 1
  if exe == 'wn' then
    if mac then
      return 'brew install wordnet'
    end
    return 'sudo apt install wordnet (Debian/Ubuntu), or your distro’s wordnet package'
  end
  return mac and 'brew install uv' or 'curl -LsSf https://astral.sh/uv/install.sh | sh'
end

---@param exe 'wn'|'uv'
local function have(exe, purpose)
  if vim.fn.executable(exe) == 1 then
    return true
  end
  notify(('%s needs `%s`, which is not installed. Install it with: %s'):format(purpose, exe, M.install_hint(exe)), vim.log.levels.WARN)
  return false
end

---The keyword under the cursor and its byte range on the line.
---@return {word: string, row: integer, s: integer, e: integer}?
local function word_at_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  -- `\%Nc` anchors the match at the cursor column, so it is the word the
  -- cursor is on, not the first one on the line. `\k\+` after it requires the
  -- cursor to sit on a word character.
  local m = vim.fn.matchstrpos(line, [[\k*\%]] .. (col + 1) .. [[c\k\+]])
  if m[1] == '' then
    return nil
  end
  return { word = m[1], row = row - 1, s = m[2], e = m[3] }
end

---Replace the word, unless the text changed while a picker was open.
local function replace(target, new)
  local ok, cur = pcall(vim.api.nvim_buf_get_text, 0, target.row, target.s, target.row, target.e, {})
  if not ok or cur[1] ~= target.word then
    notify(('“%s” moved or changed; not replaced'):format(target.word), vim.log.levels.WARN)
    return
  end
  vim.api.nvim_buf_set_text(0, target.row, target.s, target.row, target.e, { new })
end

---Give a WordNet suggestion (always lowercase, unless a name) the case of the
---word it replaces: Happy -> Glad, HAPPY -> GLAD.
local function match_case(original, word)
  if #original > 1 and original == original:upper() then
    return word:upper()
  elseif original:sub(1, 1):match '%u' then
    return word:sub(1, 1):upper() .. word:sub(2)
  end
  return word
end

-- [[ Synonyms: WordNet via bin/syn ]]

---@class WordAlt.Synonym
---@field word string
---@field pos string     noun | verb | adj | adv
---@field sense string   WordNet sense number, most common first
---@field gloss string
---@field same boolean   true: same meaning; false: related (similar or broader)

---Parse bin/syn's output. The format is documented at the top of that script.
---@return WordAlt.Synonym[]?, string? err
function M.synonyms(word)
  local res = vim.system({ M.bin .. '/syn', word }, { text = true }):wait()
  if res.code ~= 0 then
    return nil, vim.trim(res.stderr or '')
  end
  local items, seen = {}, { [word:lower()] = true }
  local pos, sense
  for line in vim.gsplit(res.stdout, '\n', { plain = true, trimempty = true }) do
    local indent, body = line:match '^(%s*)(.*)$'
    if indent == '' then
      pos, sense, body = body:match '^(%a+) (%d+): (.*)$'
    end
    if body and pos then
      local words, gloss = body:match '^(.-) — (.*)$'
      words, gloss = words or body, gloss or ''
      for w in vim.gsplit(words, ', ', { plain = true, trimempty = true }) do
        if not seen[w:lower()] then
          seen[w:lower()] = true
          items[#items + 1] = { word = w, pos = pos, sense = sense, gloss = gloss, same = indent == '' }
        end
      end
    end
  end
  return items
end

---Pick a synonym. With no word given, for the word under the cursor, and the
---choice replaces it. With a word given, the choice is yanked into the unnamed
---register for `p`: the word is not in the buffer, so there is nothing to
---replace, and putting it at the cursor would glue it onto the word there.
---@param word string?
function M.pick_synonym(word)
  if not have('wn', 'Synonyms') then
    return
  end
  local target = not word and word_at_cursor() or nil
  word = word or (target and target.word)
  if not word then
    notify('No word under the cursor', vim.log.levels.WARN)
    return
  end

  local items, err = M.synonyms(word)
  if not items or #items == 0 then
    notify(err ~= '' and err or ('No synonyms for “%s”'):format(word), vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = ('Synonyms of “%s” (= same meaning, ~ related)'):format(word),
    format_item = function(it)
      return ('%-20s %s %-4s %s %s'):format(it.word, it.same and '=' or '~', it.pos, it.sense, it.gloss)
    end,
  }, function(choice)
    if not choice then
      return
    end
    if target then
      replace(target, match_case(target.word, choice.word))
    else
      vim.fn.setreg('"', choice.word)
      notify(('Yanked “%s”; put it with p'):format(choice.word))
    end
  end)
end

---'thesaurusfunc' for `<C-x><C-t>`: complete the word before the cursor with
---its WordNet synonyms.
function M.complete(findstart, base)
  if findstart == 1 then
    if vim.fn.executable 'wn' == 0 then
      vim.schedule(function()
        have('wn', 'Synonym completion')
      end)
      return -3 -- cancel completion quietly
    end
    local before = vim.api.nvim_get_current_line():sub(1, vim.fn.col '.' - 1)
    return vim.fn.match(before, [[\k*$]])
  end
  local items = M.synonyms(base) or {}
  return vim.tbl_map(function(it)
    return {
      word = match_case(base, it.word),
      menu = ('%s %s %s'):format(it.same and '=' or '~', it.pos, it.sense),
      info = it.gloss,
    }
  end, items)
end

-- [[ Fill: masked language model via bin/fill ]]

-- Marks the slot in the text sent to bin/fill. Not `*`, which markdown uses.
local MARKER = '⟦FILL⟧'

---Ask the model what could replace the word under the cursor, given the text
---around it (bin/fill keeps about 512 tokens centred on the word), and replace
---it with the choice. Async: the model takes a few seconds to load.
function M.pick_fill()
  if not have('uv', 'Fill') then
    return
  end
  local target = word_at_cursor()
  if not target then
    notify('No word under the cursor', vim.log.levels.WARN)
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local line = lines[target.row + 1]
  lines[target.row + 1] = line:sub(1, target.s) .. MARKER .. line:sub(target.e + 1)

  notify(('Fill: asking the model about “%s”…'):format(target.word))
  vim.system({ M.bin .. '/fill', '-m', MARKER, '-n', '30' }, { stdin = table.concat(lines, '\n'), text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        notify('Fill failed: ' .. vim.trim(res.stderr or ''), vim.log.levels.ERROR)
        return
      end
      if vim.api.nvim_get_current_buf() ~= buf then
        notify('Fill: switched buffers while the model was thinking; not shown', vim.log.levels.WARN)
        return
      end
      local items = {}
      for l in vim.gsplit(res.stdout, '\n', { plain = true, trimempty = true }) do
        local w, p = l:match '^(.-)\t(.*)$'
        if w then
          items[#items + 1] = { word = w, prob = p }
        end
      end
      vim.ui.select(items, {
        prompt = ('What fits instead of “%s”'):format(target.word),
        format_item = function(it)
          return ('%-20s %6s%s'):format(it.word, it.prob, it.word == target.word and '  ← current' or '')
        end,
      }, function(choice)
        if choice then
          replace(target, choice.word)
        end
      end)
    end)
  end)
end

return M

-- Who does what to whom: colour each sentence's subject, action (verb) and
-- object, and more faintly the other nouns, in English, Russian and Armenian.
--
-- WHY A PARSER, NOT A QUERY OR A REGEX
--
-- A subject is not a pattern. "Книгу читает мальчик" (the boy reads the book) puts
-- the object first, and only its case ending says so. Treesitter's markdown
-- grammar has no nodes inside a paragraph anyway (see prose/highlight.lua). So
-- bin/roles runs a dependency parser (Stanza) that labels each word, and this
-- module turns its labels into extmarks.
--
-- HOW IT FLOWS
--
--   toggle(buf) -> refresh(buf): treesitter finds the paragraphs; inline markup
--   is blanked to spaces of the same length, so byte offsets map straight back
--   -> paragraphs not in the cache go to bin/roles, nearest the cursor first
--   -> each result lands in the cache and triggers a repaint.
--
-- One bin/roles process serves every buffer. It starts on the first toggle and
-- stops when the last buffer turns roles off, freeing its memory (about 2 GB
-- with all three languages loaded). Edits re-send only the paragraphs whose
-- text changed, after M.debounce_ms of quiet.
--
-- Roles are grammatical: in "The bug was fixed by Ann" the subject is "bug".
-- Imperatives have no subject word, and neither do Armenian sentences whose
-- verb ending carries it ("Գնացի տուն"), so those show an action alone.

local M = {}

M.debounce_ms = 300
M.batch = 16 -- paragraphs per request; bin/roles parses a batch in bulk
-- Below hipatterns (200), so a role inside (a parenthetical) stays dimmed.
M.priority = 150

M.groups = {
  subject = 'ProseSubject',
  action = 'ProseAction',
  object = 'ProseObject',
  noun = 'ProseNoun',
}

local ns = vim.api.nvim_create_namespace 'prose-roles'
local group = vim.api.nvim_create_augroup('prose-roles', { clear = true })

---@class prose.roles.Buf
---@field cache table<string, table> paragraph text -> spans, for the paragraphs now in the buffer
---@field pending table<string, true> paragraph texts sent and not yet answered
---@field timer uv.uv_timer_t

local bufs = {} ---@type table<integer, prose.roles.Buf>
local proc ---@type vim.SystemObj?
local requests = {} ---@type table<integer, {buf: integer, key: string}>
local next_id = 0
local stderr_tail = {} ---@type string[]
local reported = {} ---@type table<string, true> errors already shown

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Prose roles' })
end

-- --- paragraphs --------------------------------------------------------------

-- Inline nodes whose text is not prose. Their bytes become 'x', so the parser
-- still sees a word there ("run `make test` first" keeps its object), but no
-- role is painted over them: a span that touches one is dropped.
local OPAQUE = { code_span = true, uri_autolink = true, email_autolink = true, latex_block = true }
-- Inline nodes that turn into spaces: markers, tags, images. A span may cover
-- them ("**The old** man" is still one subject).
local BLANK = { emphasis_delimiter = true, html_tag = true, image = true }
-- Links keep their visible text only: [text](url) reads as "text".
local LINKS = { inline_link = true, full_reference_link = true, collapsed_reference_link = true, shortcut_link = true }

---Prose paragraphs of `buf`, with inline markup masked.
---@return {row: integer, text: string, starts: integer[], nospan: table<integer, integer[][]>}[]
local function paragraphs(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then
    return {}
  end
  parser:parse(true)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nospan = {} ---@type table<integer, integer[][]> row -> {{s, e}}: never paint here

  ---Overwrite bytes [sc, ec) of each row in the range with `ch`, keeping lengths.
  local function fill(sr, sc, er, ec, ch, opaque)
    for r = sr, er do
      local l = lines[r + 1]
      if l then
        local s, e = r == sr and sc or 0, math.min(r == er and ec or #l, #l)
        if s < e then
          lines[r + 1] = l:sub(1, s) .. ch:rep(e - s) .. l:sub(e + 1)
          if opaque then
            nospan[r] = nospan[r] or {}
            table.insert(nospan[r], { s, e })
          end
        end
      end
    end
  end

  local function mask(node)
    for child in node:iter_children() do
      local t = child:type()
      if OPAQUE[t] then
        local sr, sc, er, ec = child:range()
        fill(sr, sc, er, ec, 'x', true)
        for d in child:iter_children() do
          if d:type() == 'code_span_delimiter' then
            local a, b, c, e = d:range()
            fill(a, b, c, e, ' ')
          end
        end
      elseif BLANK[t] or t == 'backslash_escape' then
        local sr, sc, er, ec = child:range()
        if t == 'backslash_escape' then
          er, ec = sr, sc + 1 -- just the backslash: "\*" reads as "*"
        end
        fill(sr, sc, er, ec, ' ')
      elseif LINKS[t] then
        for part in child:iter_children() do
          if part:type() == 'link_text' then
            mask(part)
          else
            local a, b, c, e = part:range()
            fill(a, b, c, e, ' ')
          end
        end
      else
        mask(child)
      end
    end
  end

  local inline = parser:children().markdown_inline
  for _, tree in ipairs(inline and inline:trees() or {}) do
    mask(tree:root())
  end

  local out = {}
  for _, tree in ipairs(parser:trees()) do
    for _, node in M.query():iter_captures(tree:root(), buf) do
      local sr, sc, er, ec = node:range()
      if ec == 0 and er > sr then -- ends at the start of the next line
        er = er - 1
        ec = #(lines[er + 1] or '')
      end
      -- "> " in a quote, the indent of a list item's later lines: children
      -- of the paragraph or of its `inline` node.
      local function continuations(n)
        for _, child in ipairs(n:named_children()) do
          if child:type() == 'block_continuation' then
            local a, b, c, d = child:range()
            fill(a, b, c, d, ' ')
          else
            continuations(child)
          end
        end
      end
      continuations(node)
      local parts, starts, pos = {}, {}, 0
      for r = sr, er do
        local l = lines[r + 1] or ''
        if r == er then
          l = l:sub(1, ec)
        end
        if r == sr then
          l = (' '):rep(sc) .. l:sub(sc + 1) -- the list marker or "> " before it
        end
        parts[#parts + 1] = l
        starts[#starts + 1] = pos
        pos = pos + #l + 1
      end
      local text = table.concat(parts, '\n')
      if text:find '%S' then
        out[#out + 1] = { row = sr, text = text, starts = starts, nospan = nospan }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.row < b.row
  end)
  return out
end

local query
function M.query()
  query = query or vim.treesitter.query.parse('markdown', '(paragraph) @p')
  return query
end

---Byte offset in a paragraph's text -> buffer (row, col).
local function position(p, offset)
  local k = #p.starts
  while k > 1 and p.starts[k] > offset do
    k = k - 1
  end
  return p.row + k - 1, offset - p.starts[k]
end

local function blocked(p, srow, scol, erow, ecol)
  for r = srow, erow do
    for _, range in ipairs(p.nospan[r] or {}) do
      local s, e = r == srow and scol or 0, r == erow and ecol or math.huge
      if range[1] < e and s < range[2] then
        return true
      end
    end
  end
  return false
end

-- --- the parser process ------------------------------------------------------

local refresh -- forward declaration

local function on_result(msg)
  local req = msg.id and requests[msg.id]
  if msg.error and not reported[msg.error] then
    reported[msg.error] = true
    notify('bin/roles: ' .. msg.error, vim.log.levels.WARN)
  end
  if not req then
    return
  end
  requests[msg.id] = nil
  local st = bufs[req.buf]
  if not st then
    return
  end
  st.pending[req.key] = nil
  -- An error caches as no spans, so the paragraph is not re-sent in a loop.
  st.cache[req.key] = msg.spans or {}
  refresh(req.buf, 30) -- results arrive in bursts; repaint once per burst
end

local function stop()
  local p = proc
  proc = nil
  requests = {}
  for _, st in pairs(bufs) do
    st.pending = {}
  end
  if p then
    pcall(p.kill, p, 15)
  end
end

local function start()
  if proc then
    return proc
  end
  local exe = require('prose').root .. '/bin/roles'
  if vim.fn.executable 'uv' == 0 then
    notify('needs `uv`, which is not installed. Install it with: ' .. require('prose.alternatives').install_hint 'uv', vim.log.levels.ERROR)
    return nil
  end
  local partial = ''
  stderr_tail = {}
  local job
  local ok, res = pcall(vim.system, { exe }, {
    stdin = true,
    text = true,
    stdout = function(_, data)
      if not data then
        return
      end
      partial = partial .. data
      for line in partial:gmatch '([^\n]*)\n' do
        vim.schedule(function()
          if proc == job then
            local okj, msg = pcall(vim.json.decode, line)
            if okj and type(msg) == 'table' then
              on_result(msg)
            end
          end
        end)
      end
      partial = partial:match '[^\n]*$'
    end,
    stderr = function(_, data)
      for line in (data or ''):gmatch '[^\n]+' do
        table.insert(stderr_tail, line)
        if #stderr_tail > 20 then
          table.remove(stderr_tail, 1)
        end
        if line:match '^roles: downloading' then
          vim.schedule(function()
            notify((line:gsub('^roles: ', '')))
          end)
        end
      end
    end,
  }, function(res)
    vim.schedule(function()
      if proc ~= job then
        return -- stopped on purpose, or replaced
      end
      proc = nil
      requests = {}
      for _, st in pairs(bufs) do
        st.pending = {}
      end
      notify(
        ('bin/roles exited (%s): %s'):format(res.signal ~= 0 and 'signal ' .. res.signal or 'code ' .. res.code, table.concat(stderr_tail, '\n')),
        vim.log.levels.ERROR
      )
    end)
  end)
  if not ok then
    notify('could not start bin/roles: ' .. tostring(res), vim.log.levels.ERROR)
    return nil
  end
  job = res
  proc = job
  return job
end

-- Claude Code waits for the editor to exit before it submits, so the parser
-- must never hold Neovim open. Both events, for the reason in prose/review.lua.
vim.api.nvim_create_autocmd({ 'ExitPre', 'VimLeavePre' }, { group = group, callback = stop })

---Send the paragraphs the cache lacks, nearest the cursor first.
local function request(buf, missing)
  if #missing == 0 then
    return
  end
  local job = start()
  if not job then
    return
  end
  local st = bufs[buf]
  local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] - 1 or 0
  table.sort(missing, function(a, b)
    return math.abs(a.row - cursor) < math.abs(b.row - cursor)
  end)
  for i = 1, #missing, M.batch do
    local items = {}
    for j = i, math.min(i + M.batch - 1, #missing) do
      next_id = next_id + 1
      requests[next_id] = { buf = buf, key = missing[j].text }
      st.pending[missing[j].text] = true
      items[#items + 1] = { id = next_id, text = missing[j].text }
    end
    local ok, line = pcall(vim.json.encode, items)
    if ok then
      pcall(job.write, job, line .. '\n') -- a dead process reports itself on exit
    end
  end
end

-- --- painting ----------------------------------------------------------------

local function paint(buf)
  local st = bufs[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local paras = paragraphs(buf)
  local cache, missing, seen = {}, {}, {}
  for _, p in ipairs(paras) do
    if st.cache[p.text] then
      cache[p.text] = st.cache[p.text]
    elseif not st.pending[p.text] and not seen[p.text] then
      seen[p.text] = true
      missing[#missing + 1] = p
    end
  end
  st.cache = cache -- drop paragraphs that no longer exist

  -- Clear everywhere except paragraphs still waiting on the parser: their old
  -- marks have moved with the text as it was edited, and are a better guess
  -- than nothing until the new parse arrives.
  local row = 0
  for _, p in ipairs(paras) do
    if not cache[p.text] then
      vim.api.nvim_buf_clear_namespace(buf, ns, row, p.row)
      row = p.row + #p.starts
    end
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, row, -1)

  for _, p in ipairs(paras) do
    for _, span in ipairs(cache[p.text] or {}) do
      local s, e, role = span[1], span[2], span[3]
      local srow, scol = position(p, s)
      local erow, ecol = position(p, e)
      if M.groups[role] and not blocked(p, srow, scol, erow, ecol) then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, srow, scol, {
          end_row = erow,
          end_col = ecol,
          hl_group = M.groups[role],
          priority = M.priority,
        })
      end
    end
  end
  request(buf, missing)
end

---Repaint `buf` after `delay` ms, restarting the wait on every call.
function refresh(buf, delay)
  local st = bufs[buf]
  if not st then
    return
  end
  st.timer:stop()
  st.timer:start(delay or M.debounce_ms, 0, function()
    vim.schedule(function()
      paint(buf)
    end)
  end)
end

-- --- on and off --------------------------------------------------------------

function M.enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  return bufs[buf] ~= nil
end

---How many paragraphs of `buf` are waiting on the parser: 0 once all are coloured.
function M.pending(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local n = 0
  for _ in pairs(bufs[buf] and bufs[buf].pending or {}) do
    n = n + 1
  end
  return n
end

function M.disable(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = bufs[buf]
  if not st then
    return
  end
  bufs[buf] = nil
  st.timer:stop()
  st.timer:close()
  pcall(vim.api.nvim_clear_autocmds, { group = group, buffer = buf })
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  if next(bufs) == nil then
    stop() -- nothing left to colour: give the memory back
  end
end

function M.enable(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if bufs[buf] then
    return
  end
  bufs[buf] = { cache = {}, pending = {}, timer = assert(vim.uv.new_timer()) }
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = group,
    buffer = buf,
    callback = function()
      refresh(buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      M.disable(buf)
    end,
  })
  if not proc then
    notify 'On. The parser takes 5-20 s to load each language; the first run also downloads about 2 GB of models.'
  end
  paint(buf)
end

function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if bufs[buf] then
    M.disable(buf)
    notify 'Off'
  else
    M.enable(buf)
  end
end

return M

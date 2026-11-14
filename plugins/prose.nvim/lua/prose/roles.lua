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
--   -> paragraphs in view (and a screen either side) that are not in the cache
--   go to bin/roles, nearest the cursor first -> each result lands in the cache
--   and triggers a repaint. Scrolling repaints, which sends what came into view.
--
-- Only what is shown, because a long file would otherwise queue all of itself:
-- a month of the prompt archive is 3,300 paragraphs.
-- With setup { roles = true } it turns on in every file of `filetypes`.
--
-- One shared parser serves every buffer of every Neovim: `bin/roles --daemon`,
-- on a socket in stdpath('state'). The first Neovim to need it starts it and
-- later ones connect, so three tabs cost one set of models, not three. It keeps
-- English loaded for good (about 0.9 GB) and drops Russian and Armenian after
-- M.keep_alive unused, so a new tab or a Claude Code prompt colours English at
-- once. It outlives every Neovim on purpose; `:ProseRoles stop` ends it. Edits
-- re-send only the paragraphs whose text changed, after M.debounce_ms of quiet.
--
-- Roles are grammatical: in "The bug was fixed by Ann" the subject is "bug".
-- Imperatives have no subject word, and neither do Armenian sentences whose
-- verb ending carries it ("Գնացի տուն"), so those show an action alone.
--
-- ONE PARSE, TWO FEATURES
--
-- The same parse also carries the bad-pattern flags (prose/patterns.lua), so a
-- buffer has two switches: `roles` (the colours) and `flags` (the diagnostics).
-- Either one keeps the buffer's parse alive. Colours are painted in view only;
-- flags want the whole file, so ]d finds them all, and with flags on the whole
-- file is parsed, the view first (see M.inflight).

local M = {}

M.debounce_ms = 300
M.batch = 16 -- paragraphs per request; bin/roles parses a batch in bulk
-- Batches in flight per buffer. A whole file is sent this many at a time, so
-- the paragraph you just edited never waits behind the rest of the file.
M.inflight = 4
-- Parse this many window heights above and below what is shown, so text
-- scrolled into view is usually coloured already.
M.margin = 1
-- Parsed paragraphs remembered beyond those in view, per buffer.
M.cache_size = 2000
-- How long each language stays loaded after its last use: 'forever', '0', or a
-- number with s, m or h. Read by the Neovim that starts the shared parser.
-- Loading again costs about 5 s for Russian and 12 s for Armenian.
M.keep_alive = { en = 'forever', ru = '30m', hy = '30m' }
-- Below hipatterns (200), so a role inside (a parenthetical) stays dimmed, and
-- below diagnostic underlines (150): a character shows one underline style, and
-- a prose flag's line must win over a noun's dots.
M.priority = 140

M.groups = {
  subject = 'ProseSubject',
  action = 'ProseAction',
  object = 'ProseObject',
  noun = 'ProseNoun',
}

local ns = vim.api.nvim_create_namespace 'prose-roles'
local group = vim.api.nvim_create_augroup('prose-roles', { clear = true })

---@class prose.roles.Result
---@field spans table[] {start, end, role} in bytes
---@field flags table[] {start, end, code, message} in bytes
---@field lead table? {start, end, form}: how the paragraph's first word reads
---@field acronyms table[] {start, end, word, defined}

---@class prose.roles.Buf
---@field cache table<string, prose.roles.Result> paragraph text -> its parse, for the paragraphs now in the buffer
---@field pending table<string, true> paragraph texts sent and not yet answered
---@field timer uv.uv_timer_t
---@field roles boolean colours on
---@field flags boolean pattern flags on

local bufs = {} ---@type table<integer, prose.roles.Buf>
local requests = {} ---@type table<integer, {buf: integer, key: string}>
local next_id = 0
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

---Prose paragraphs of `buf` that touch any of `ranges`, with inline markup
---masked. Only those, because a long file costs: all 3,300 paragraphs of a
---7,900-line file take 80 ms, which would be felt on every scroll and edit.
---`list` is set on the first paragraph of a list item: the id of its list, so
---the items of one list can be compared.
---@param ranges integer[][] 0-based {first, last} rows
---@return {row: integer, text: string, starts: integer[], nospan: table<integer, integer[][]>, list: string?}[]
local function paragraphs(buf, ranges)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser or #ranges == 0 then
    return {}
  end
  local first, last = math.huge, 0
  for _, r in ipairs(ranges) do
    first, last = math.min(first, r[1]), math.max(last, r[2])
  end
  first = math.max(first, 0)
  local function inside(node)
    local sr, _, er = node:range()
    for _, r in ipairs(ranges) do
      if sr <= r[2] and er >= r[1] then
        return true
      end
    end
    return false
  end
  parser:parse { first, last + 1 } -- the inline trees of this stretch only
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
      if not inside(child) then -- skip it
      elseif OPAQUE[t] then
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
    if inside(tree:root()) then
      mask(tree:root())
    end
  end

  local out = {}
  for _, tree in ipairs(parser:trees()) do
    for _, node in M.query():iter_captures(tree:root(), buf, first, last + 1) do
      if inside(node) then
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
        local list ---@type string?
        local item = node:parent()
        if item and item:type() == 'list_item' then
          for child in item:iter_children() do
            if child:type() == 'paragraph' then
              local owner = item:parent()
              list = child:id() == node:id() and owner and owner:id() or nil
              break
            end
          end
        end
        if text:find '%S' then
          out[#out + 1] = { row = sr, text = text, starts = starts, nospan = nospan, list = list }
        end
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
M.position = position

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

-- --- the shared parser -------------------------------------------------------
--
-- It must never keep Neovim from exiting: Claude Code waits for the editor to
-- exit before it takes the prompt back. So it starts detached, in its own
-- session (closing this terminal does not take it down either), with its
-- output going to a log file rather than to pipes this Neovim holds. Neovim
-- keeps only a socket to it, which closes when Neovim exits, however it exits.

local refresh -- forward declaration

local conn ---@type uv.uv_pipe_t? the connection, once made
local connecting = false
local failed = false -- gave up; cleared when roles are next turned on
local outbox = {} ---@type string[] requests made while connecting
local starting ---@type uv.uv_process_t? the parser this Neovim started, until it exits
local spawns = 0 -- parsers started during this connection attempt
local farewell ---@type string? the reason the parser gave for closing
local drops = {} ---@type integer[] when the parser went away without one

---@return string socket, string log, string dir
local function files()
  local dir = vim.fn.stdpath 'state' --[[@as string]]
  return dir .. '/prose-roles.sock', dir .. '/prose-roles.log', dir
end

local function log_tail()
  local ok, lines = pcall(vim.fn.readfile, select(2, files()), '', -12)
  return ok and table.concat(lines, '\n') or ''
end

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
  st.cache[req.key] = {
    spans = msg.spans or {},
    flags = msg.flags or {},
    lead = msg.lead,
    acronyms = msg.acronyms or {},
  }
  refresh(req.buf, 30) -- results arrive in bursts; repaint once per burst
end

---Drop the connection. Requests in flight are lost; the next paint re-sends them.
local function close()
  connecting = false
  local c = conn
  conn = nil
  if c and not c:is_closing() then
    c:close()
  end
  requests, outbox = {}, {}
  for _, st in pairs(bufs) do
    st.pending = {}
  end
end

local function fail(msg)
  close()
  failed = true
  notify(('%s\nLog %s:\n%s'):format(msg, select(2, files()), log_tail()), vim.log.levels.ERROR)
end

-- Claude Code waits for the editor to exit before it submits; let go of the
-- socket on the way out. Both events, for the reason in prose/review.lua.
vim.api.nvim_create_autocmd({ 'ExitPre', 'VimLeavePre' }, { group = group, callback = close })

local function on_eof()
  local bye = farewell
  close()
  if next(bufs) == nil then
    return
  end
  -- A goodbye means it stopped on purpose ("stop", or a new bin/roles taking
  -- over). Without one it crashed: start it again, but not in a loop.
  if not bye then
    local now = vim.uv.now()
    drops = vim.tbl_filter(function(t)
      return now - t < 60000
    end, drops)
    table.insert(drops, now)
    if #drops >= 3 then
      fail 'The shared parser keeps stopping. Roles and pattern flags stay off until you turn one on again.'
      return
    end
    notify('The shared parser stopped unexpectedly. It starts again with the next paragraph to parse.', vim.log.levels.WARN)
  end
  for buf in pairs(bufs) do
    refresh(buf, 100)
  end
end

---@param pipe uv.uv_pipe_t
local function listen(pipe)
  local partial = ''
  pipe:read_start(function(err, data)
    if err or not data then
      vim.schedule(function()
        if conn == pipe then
          on_eof()
        end
      end)
      return
    end
    partial = partial .. data
    local lines = {}
    for line in partial:gmatch '([^\n]*)\n' do
      lines[#lines + 1] = line
    end
    partial = partial:match '[^\n]*$'
    vim.schedule(function()
      for _, line in ipairs(lines) do
        -- luanil: a JSON null (no lead) is nil, not vim.NIL.
        local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
        if conn == pipe and ok and type(msg) == 'table' then
          if msg.notice then
            notify(msg.notice)
          elseif msg.bye then
            farewell = msg.bye
          else
            on_result(msg)
          end
        end
      end
    end)
  end)
end

local function spawn()
  local sock, log, dir = files()
  if vim.fn.executable 'uv' == 0 then
    fail('needs `uv`, which is not installed. Install it with: ' .. require('prose.alternatives').install_hint 'uv')
    return
  end
  spawns = spawns + 1
  vim.fn.mkdir(dir, 'p')
  local keep = {}
  for lang, v in pairs(M.keep_alive) do
    keep[#keep + 1] = lang .. '=' .. v
  end
  table.sort(keep)
  local null = assert(vim.uv.fs_open('/dev/null', 'r', 0))
  local out, open_err = vim.uv.fs_open(log, 'a', tonumber('600', 8))
  if not out then
    vim.uv.fs_close(null)
    fail('cannot write the log: ' .. tostring(open_err))
    return
  end
  local handle, err ---@type uv.uv_process_t?, string?
  handle, err = vim.uv.spawn(require('prose').root .. '/bin/roles', {
    args = { '--daemon', sock, '--keep-alive', table.concat(keep, ',') },
    stdio = { null, out, out }, -- no pipe back to this Neovim
    cwd = dir,
    detached = true, -- its own session: not this terminal's, not Claude Code's
  }, function(code, signal)
    vim.schedule(function()
      if starting == handle then
        starting = nil
      end
      if handle and not handle:is_closing() then
        handle:close()
      end
      -- Exit 0 without a socket: another Neovim's parser won the race.
      if (code ~= 0 or signal ~= 0) and connecting then
        fail(('The shared parser could not start (%s).'):format(signal ~= 0 and 'signal ' .. signal or 'exit ' .. code))
      end
    end)
  end)
  vim.uv.fs_close(null)
  vim.uv.fs_close(out)
  if not handle then
    fail('could not start bin/roles: ' .. tostring(err))
    return
  end
  handle:unref() -- never keeps Neovim's event loop alive
  starting = handle
  notify 'Starting the shared parser. English is ready in about 10 s; Russian and Armenian load the first time they appear (5-15 s).'
end

-- Until it listens: it binds the socket within a second or so of starting,
-- but uv's first run installs PyTorch first, which takes minutes.
local function attempt()
  if not connecting then
    return
  end
  local pipe = assert(vim.uv.new_pipe(false))
  pipe:connect(files(), function(err)
    vim.schedule(function()
      if err or not connecting then
        pipe:close()
        if not connecting then
          return
        end
        if not starting then
          if spawns >= 3 then
            fail 'The shared parser did not start.'
            return
          end
          spawn()
        end
        vim.defer_fn(attempt, 200)
        return
      end
      connecting, conn, farewell = false, pipe, nil
      listen(pipe)
      for _, line in ipairs(outbox) do
        pipe:write(line)
      end
      outbox = {}
    end)
  end)
end

local function send(line)
  if conn then
    conn:write(line) -- a broken connection reports itself as end of file
    return
  end
  outbox[#outbox + 1] = line
  if not connecting then
    connecting, spawns = true, 0
    attempt()
  end
end

---Send one command to the shared parser and wait for its answer. Never starts it.
---@return table? reply nil if it is not running
local function ask(cmd, timeout)
  local pipe = assert(vim.uv.new_pipe(false))
  local line = vim.json.encode { cmd = cmd } .. '\n'
  local data, done = '', false
  pipe:connect(files(), function(err)
    if err then
      done = true
      return
    end
    pipe:read_start(function(e, chunk)
      data = data .. (chunk or '')
      done = done or e ~= nil or chunk == nil or data:find '\n' ~= nil
    end)
    pipe:write(line)
  end)
  vim.wait(timeout or 2000, function()
    return done
  end, 10)
  if not pipe:is_closing() then
    pipe:close()
  end
  local ok, reply = pcall(vim.json.decode, data:match '^[^\n]*')
  return ok and type(reply) == 'table' and reply or nil
end

---Send the paragraphs the cache lacks, nearest the cursor first, at most
---M.inflight batches at a time: each answer repaints, which sends the next.
local function request(buf, missing)
  if #missing == 0 or failed then
    return
  end
  local st = bufs[buf]
  local waiting = 0
  for _ in pairs(st.pending) do
    waiting = waiting + 1
  end
  local room = M.inflight * M.batch - waiting
  if room <= 0 then
    return
  end
  local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] - 1 or 0
  table.sort(missing, function(a, b)
    return math.abs(a.row - cursor) < math.abs(b.row - cursor)
  end)
  local n = math.min(#missing, room)
  for i = 1, n, M.batch do
    local items = {}
    for j = i, math.min(i + M.batch - 1, n) do
      next_id = next_id + 1
      requests[next_id] = { buf = buf, key = missing[j].text }
      st.pending[missing[j].text] = true
      items[#items + 1] = { id = next_id, text = missing[j].text }
    end
    local ok, line = pcall(vim.json.encode, items)
    if ok then
      send(line .. '\n')
    end
  end
end

-- --- painting ----------------------------------------------------------------

---Rows of `buf` worth parsing now: each window's view, padded by M.margin
---window heights. Empty when no window shows it.
---@return integer[][] 0-based {first, last} pairs
local function shown(buf)
  local ranges = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then
      local pad = info.height * M.margin
      -- botline is only fresh after a redraw; topline + height covers a view
      -- that has just scrolled. Closed folds can show more, hence the max.
      local last = math.max(info.botline, info.topline + info.height)
      ranges[#ranges + 1] = { info.topline - 1 - pad, last - 1 + pad }
    end
  end
  return ranges
end

---Does any paragraph row of `p` fall in `ranges`?
local function visible(p, ranges)
  local last = p.row + #p.starts - 1
  for _, r in ipairs(ranges) do
    if p.row <= r[2] and last >= r[1] then
      return true
    end
  end
  return false
end

local function paint(buf)
  local st = bufs[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local view = shown(buf)
  local lines = vim.api.nvim_buf_line_count(buf)
  -- Flags cover the whole file, unless it is too long to scan on every edit.
  local whole = st.flags and lines <= require('prose.patterns').whole_file_lines
  local paras = paragraphs(buf, whole and { { 0, lines - 1 } } or view)
  local cache, missing, seen = {}, {}, {}
  for _, p in ipairs(paras) do
    if st.cache[p.text] then
      cache[p.text] = st.cache[p.text]
    elseif not st.pending[p.text] and not seen[p.text] then
      seen[p.text] = true
      missing[#missing + 1] = p
    end
  end
  -- Paragraphs out of view keep their results, so scrolling back costs
  -- nothing. Up to M.cache_size of them: edits leave old texts behind, and
  -- only a full scan could tell those apart.
  local kept = 0
  for text, spans in pairs(st.cache) do
    if kept >= M.cache_size then
      break
    end
    if not cache[text] then
      cache[text], kept = spans, kept + 1
    end
  end
  st.cache = cache

  if st.roles then
    M.paint_roles(buf, whole and vim.tbl_filter(function(p)
      return visible(p, view)
    end, paras) or paras, cache)
  end
  if st.flags then
    require('prose.patterns').publish(buf, paras, cache, whole)
  end
  request(buf, missing)
end

---Colour the roles of `paras`, the ones in view, and clear the rest.
function M.paint_roles(buf, paras, cache)
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
    for _, span in ipairs(cache[p.text] and cache[p.text].spans or {}) do
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

-- Scrolling or resizing a window brings new paragraphs into view.
vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized' }, {
  group = group,
  callback = function()
    local wins = vim.v.event.windows or vim.tbl_keys(vim.v.event) -- WinResized, WinScrolled
    for _, id in ipairs(wins) do
      local win = tonumber(id)
      if win and vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if bufs[buf] then
          refresh(buf, 100)
        end
      end
    end
  end,
})

-- --- on and off --------------------------------------------------------------
--
-- Two features share a buffer's parse: 'roles' (the colours) and 'flags' (the
-- pattern diagnostics, prose/patterns.lua). Each is turned on and off on its
-- own, and each remembers being turned off by hand in a buffer variable, so
-- setup's "on in every file" leaves that buffer alone when the file reloads.

local OFF_BY_HAND = { roles = 'prose_roles', flags = 'prose_patterns' }

local function resolve(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

---@param feature? 'roles'|'flags' default 'roles'
function M.enabled(buf, feature)
  local st = bufs[resolve(buf)]
  return st ~= nil and st[feature or 'roles'] == true
end

---How many paragraphs of `buf` are waiting on the parser: 0 once all are parsed.
function M.pending(buf)
  buf = resolve(buf)
  local n = 0
  for _ in pairs(bufs[buf] and bufs[buf].pending or {}) do
    n = n + 1
  end
  return n
end

---Forget `buf` entirely: both features off, its parse and timer gone.
local function drop(buf)
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
  if st.flags then
    require('prose.patterns').clear(buf)
  end
  if next(bufs) == nil then
    close() -- the shared parser stays, for the next buffer or Neovim
  end
end

---Turn `feature` off in `buf`. The parse goes once neither feature is on.
---@param feature 'roles'|'flags'
function M.detach(buf, feature)
  buf = resolve(buf)
  local st = bufs[buf]
  if not st or not st[feature] then
    return
  end
  if not (st.roles and st.flags) then
    drop(buf)
    return
  end
  st[feature] = false
  if feature == 'roles' and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  elseif feature == 'flags' then
    require('prose.patterns').clear(buf)
    paint(buf) -- back to parsing the view only
  end
end

---Turn `feature` on in `buf`.
---@param feature 'roles'|'flags'
---@param opts? {auto?: boolean} auto: turned on by setup, not by hand. Skips
---buffers where the feature was turned off by hand, and does not retry a
---parser that failed.
---@return boolean? on true if it was turned on now
function M.attach(buf, feature, opts)
  buf = resolve(buf)
  local auto = opts and opts.auto
  local st = bufs[buf]
  if (st and st[feature]) or (auto and vim.b[buf][OFF_BY_HAND[feature]] == false) then
    return
  end
  if not st then
    st = { cache = {}, pending = {}, timer = assert(vim.uv.new_timer()), roles = false, flags = false }
    bufs[buf] = st
    vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
      group = group,
      buffer = buf,
      callback = function()
        refresh(buf)
      end,
    })
    vim.api.nvim_create_autocmd('BufWinEnter', {
      group = group,
      buffer = buf,
      callback = function()
        refresh(buf, 0)
      end,
    })
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = group,
      buffer = buf,
      callback = function()
        drop(buf)
      end,
    })
  end
  st[feature] = true
  vim.b[buf][OFF_BY_HAND[feature]] = nil
  if not auto then
    failed, drops = false, {} -- turning a feature on is the way to try again
  end
  paint(buf)
  return true
end

---Turn `feature` on or off in `buf` by hand; off stays off when the file reloads.
---@return boolean on
function M.flip(buf, feature)
  buf = resolve(buf)
  if M.enabled(buf, feature) then
    M.detach(buf, feature)
    vim.b[buf][OFF_BY_HAND[feature]] = false
    return false
  end
  M.attach(buf, feature)
  return true
end

-- The colours, as before the flags existed.

function M.disable(buf)
  M.detach(buf, 'roles')
end

---@param opts? {auto?: boolean} see M.attach
function M.enable(buf, opts)
  if M.attach(buf, 'roles', opts) and not (opts and opts.auto) then
    notify 'On'
  end
end

function M.toggle(buf)
  notify(M.flip(buf, 'roles') and 'On' or 'Off')
end

local LANGS = { en = 'English', ru = 'Russian', hy = 'Armenian' }

local function ago(seconds)
  return seconds < 90 and ('%d s'):format(seconds) or ('%d min'):format(seconds / 60)
end

---One line about the shared parser, or nil if it is not running.
---@return string?
function M.describe()
  local s = (ask 'status' or {}).status
  if type(s) ~= 'table' then
    return nil
  end
  local langs = {}
  for lang, idle in pairs(s.loaded or {}) do
    local keep = (s.keep_alive or {})[lang]
    langs[#langs + 1] = keep == 'forever' and ('%s (kept)'):format(LANGS[lang] or lang)
      or ('%s (unused %s, unloads after %s)'):format(LANGS[lang] or lang, ago(idle), keep)
  end
  table.sort(langs)
  local kb = tonumber(vim.trim(vim.fn.system { 'ps', '-o', 'rss=', '-p', tostring(s.pid) }))
  return ('pid %d, %s. Loaded: %s. Neovims connected: %d. Log: %s'):format(
    s.pid,
    -- Resident only: macOS compresses idle pages, so this can sit well below
    -- what the models take once they are in use.
    kb and ('%d MB in RAM'):format(kb / 1024) or 'memory unknown',
    #langs > 0 and table.concat(langs, ', ') or 'nothing yet',
    s.clients or 0,
    select(2, files())
  )
end

function M.status()
  local d = M.describe()
  notify(d and 'Shared parser: ' .. d or 'The shared parser is not running. It starts when roles or pattern flags are turned on.')
end

---Stop the shared parser and free its memory. Roles and pattern flags go off in
---this Neovim's buffers and stay off there; another Neovim with either on, or a
---file opened later with setup { roles = true } or { patterns = true }, starts
---the parser again.
function M.stop()
  for _, buf in ipairs(vim.tbl_keys(bufs)) do
    local st = bufs[buf]
    for feature, var in pairs(OFF_BY_HAND) do
      if st[feature] then
        vim.b[buf][var] = false
      end
    end
    drop(buf)
  end
  if (ask 'stop' or {}).bye then
    notify 'Stopped the shared parser.'
  else
    notify 'The shared parser is not running.'
  end
end

return M

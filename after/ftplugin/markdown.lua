-- Prose settings for markdown.
-- Buffer-local on purpose: nothing here should leak into code buffers.
--
-- Deliberately NOT setting `conceallevel` here: render-markdown.nvim owns it as a
-- window option, using 3 while rendering and falling back to the global value for
-- the raw view. Setting it here looks like it works and is silently overridden.
-- (The old global `conceallevel = 2` came from the vim-markdown spec, now removed.)

vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_us'
-- Check CamelCase words part by part: GenAI is Gen + AI, TypeScript is Type +
-- Script, so neither needs a word list entry. A typo inside a part is still
-- caught. Word lists and `zgl`/`zgg` are in lua/custom/spell.lua.
vim.opt_local.spelloptions:append 'camel'
vim.opt_local.linebreak = true -- wrap at word boundaries, not mid-word
vim.opt_local.list = false -- listchars are noise in prose
vim.opt_local.textwidth = 0 -- soft wrap only; vim-pencil handles the rest

-- Wide tables lose their alignment under `wrap`, but prose needs it. Toggle
-- rather than choosing globally.
--
-- Note `wrap` is window-local, so this affects the current window, not the
-- buffer. In practice each markdown buffer still opens wrapped, because
-- vim-pencil's PencilSoft re-enables it on FileType -- verified, not assumed.
vim.keymap.set('n', '<leader>tw', function()
  vim.opt_local.wrap = not vim.opt_local.wrap:get()
  vim.notify('wrap ' .. (vim.opt_local.wrap:get() and 'on' or 'off'), vim.log.levels.INFO)
end, { buffer = true, desc = '[T]oggle [W]rap' })

-- With nowrap the cursor drives horizontal scrolling; keep some context visible.
vim.opt_local.sidescrolloff = 8

-- Jump by heading. `<leader>ds` (marksman document symbols) covers this too, but
-- flattens the tree; see lua/custom/markdown_toc.lua for why this one is treesitter.
-- `require`d lazily so the module stays off the startup path.
vim.keymap.set('n', '<leader>dt', function()
  require('custom.markdown_toc').open()
end, { buffer = true, desc = '[D]ocument [T]OC' })

-- Judgment-based review by `claude -p` (buried request, unclear referent, packed
-- instruction) into quickfix -- what Vale's patterns cannot catch. Only ever on
-- demand; see lua/custom/prose_review.lua.
vim.keymap.set('n', '<leader>pr', function()
  require('custom.prose_review').run(0)
end, { buffer = true, desc = '[P]rose [R]eview' })

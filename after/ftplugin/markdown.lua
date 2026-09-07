-- Prose settings for markdown.
-- Buffer-local on purpose: nothing here should leak into code buffers.
--
-- Deliberately NOT setting `conceallevel` here: render-markdown.nvim owns it as a
-- window option, using 3 while rendering and falling back to the global value for
-- the raw view. Setting it here looks like it works and is silently overridden.
-- (The old global `conceallevel = 2` came from the vim-markdown spec, now removed.)

vim.opt_local.spell = true
vim.opt_local.spelllang = 'en_us'
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

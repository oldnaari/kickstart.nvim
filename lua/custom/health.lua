-- `:checkhealth custom`: external tools this config's own features rely on.
-- Missing ones are warnings, not errors: each feature says what to install when
-- used, and everything else keeps working without it.

local M = {}

local function hf_cache()
  return vim.env.HF_HUB_CACHE or (vim.env.HF_HOME and vim.env.HF_HOME .. '/hub') or ((vim.env.XDG_CACHE_HOME or vim.fn.expand '~/.cache') .. '/huggingface/hub')
end

function M.check()
  local alt = require 'custom.word_alternatives'

  vim.health.start 'Word alternatives (lua/custom/word_alternatives.lua)'

  if vim.fn.executable 'wn' == 1 then
    vim.health.ok 'WordNet (`wn`) found: :Synonyms, <leader>ps and <C-x><C-t> work'
  else
    vim.health.warn('WordNet (`wn`) not found: :Synonyms, <leader>ps and <C-x><C-t> are unavailable', { 'Install it with: ' .. alt.install_hint 'wn' })
  end

  if vim.fn.executable 'uv' == 1 then
    vim.health.ok '`uv` found: :Fill and <leader>pf work'
    if vim.fn.isdirectory(hf_cache() .. '/models--distilbert--distilroberta-base') == 1 then
      vim.health.ok 'Fill model (distilroberta-base) is cached; :Fill runs offline'
    else
      vim.health.info 'Fill model not downloaded yet. The first :Fill fetches the Python packages and the model (about 1 GB in total), then runs offline.'
    end
  else
    vim.health.warn('`uv` not found: :Fill and <leader>pf are unavailable', { 'Install it with: ' .. alt.install_hint 'uv' })
  end
end

return M

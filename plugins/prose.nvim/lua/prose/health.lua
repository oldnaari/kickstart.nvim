-- `:checkhealth prose`: the external tools each feature relies on. Missing ones
-- are warnings, not errors: each feature says what to install when used, and
-- everything else keeps working without it.

local M = {}

local function hf_cache()
  return vim.env.HF_HUB_CACHE or (vim.env.HF_HOME and vim.env.HF_HOME .. '/hub') or ((vim.env.XDG_CACHE_HOME or vim.fn.expand '~/.cache') .. '/huggingface/hub')
end

function M.check()
  local alt = require 'prose.alternatives'

  vim.health.start 'Word alternatives (prose/alternatives.lua)'

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

  vim.health.start 'Prose review (prose/review.lua)'

  if vim.fn.executable 'claude' == 1 then
    vim.health.ok '`claude` found: :ProseReview and <leader>pr work'
  else
    vim.health.warn '`claude` (Claude Code) not found: :ProseReview and <leader>pr are unavailable'
  end

  vim.health.start 'Vale (vale/.vale.ini)'

  if not require('prose').config.vale then
    vim.health.info 'Disabled in setup() (`vale = false`)'
  else
    for _, exe in ipairs { 'vale-ls', 'vale' } do
      if vim.fn.executable(exe) == 1 then
        vim.health.ok(('`%s` found'):format(exe))
      else
        vim.health.warn(('`%s` not found: no Vale diagnostics'):format(exe), { 'Install it with :MasonInstall ' .. exe })
      end
    end
  end
end

return M

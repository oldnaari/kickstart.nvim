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

  vim.health.start 'Grammar roles (prose/roles.lua)'

  if vim.fn.executable 'uv' == 1 then
    vim.health.ok '`uv` found: :ProseRoles and <leader>pg work'
    -- Stanza keeps one folder per version and language under its cache.
    local cache = vim.env.STANZA_RESOURCES_DIR
      or (
        vim.fn.has 'mac' == 1 and vim.fn.expand '~/Library/Caches/stanza/*/resources'
        or (vim.env.XDG_CACHE_HOME or vim.fn.expand '~/.cache') .. '/stanza/*/resources'
      )
    local missing = {}
    for _, lang in ipairs { 'en', 'ru', 'hy' } do
      if vim.fn.glob(cache .. '/' .. lang, false, true)[1] == nil then
        table.insert(missing, lang)
      end
    end
    if #missing == 0 then
      vim.health.ok 'Stanza models for en, ru and hy are cached'
    else
      vim.health.info(
        ('No Stanza model yet for %s. The first paragraph in each language downloads it (300-600 MB, plus a 1 GB transformer for hy).'):format(
          table.concat(missing, ', ')
        )
      )
    end
    local shared = require('prose.roles').describe()
    if shared then
      vim.health.ok('Shared parser running: ' .. shared)
    else
      vim.health.info 'Shared parser not running. The first <leader>pg starts it, and it stays (`:ProseRoles stop` ends it).'
    end
  else
    vim.health.warn('`uv` not found: :ProseRoles and <leader>pg are unavailable', { 'Install it with: ' .. alt.install_hint 'uv' })
  end

  vim.health.start 'Emoji (prose/emoji.lua)'

  if not pcall(require, 'telescope') then
    vim.health.warn 'telescope.nvim not found: :Emoji and <leader>pe are unavailable'
  elseif require('prose.emoji').available() then
    vim.health.ok 'Emoji list found: :Emoji and <leader>pe work'
  else
    vim.health.warn('No emoji list: :Emoji and <leader>pe are unavailable', { require('prose.emoji').install_hint })
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

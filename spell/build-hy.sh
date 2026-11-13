#!/usr/bin/env bash
# Build spell/hy.utf-8.spl, Neovim's Eastern Armenian spell file. Takes about
# 30 minutes. The result is committed, so this only needs to run again to
# change the dictionary.
#
# Vim's spell server has no Armenian file, so it is compiled here with
# :mkspell from the Hunspell dictionary in wooorm/dictionaries. :mkspell is
# stricter than Hunspell and the dictionary needs fixes first; see below.
#
# Usage: spell/build-hy.sh
set -euo pipefail
export LC_ALL=C # grep, sed and awk below work on bytes; UTF-8 survives as-is

COMMIT=8cfea406b505e4d7df52d5a19bce525df98c54ab
BASE=https://raw.githubusercontent.com/wooorm/dictionaries/$COMMIT/dictionaries/hy
AFF_SHA256=aa8b49f32350a0136d112f62ee697c87cdc452256d12a70ef1fea2e7a13b32fb
DIC_SHA256=53530792b4937e4b8cd387e28ff45884e42742c8218d8ba4510804efcfb81084

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$BASE/index.aff" -o "$tmp/index.aff"
curl -fsSL "$BASE/index.dic" -o "$tmp/index.dic"
(cd "$tmp" && shasum -a 256 -c) <<EOF
$AFF_SHA256  index.aff
$DIC_SHA256  index.dic
EOF

# Affix file fixes:
# 1. Seven rules in the GX block have no condition field. :mkspell rejects them,
#    keeps waiting for them, and so silently drops every block after GX: the
#    instrumental, the locative -ում and every verb conjugation. "." is the
#    condition that matches any stem.
# 2. Some rule lines carry a trailing extra field, which :mkspell rejects
#    unless IGNOREEXTRA is set.
# 3. The VD header counts 171 rules; the block has 172.
awk 'BEGIN { OFS = "\t" }
  NR == 1 { print; print "IGNOREEXTRA"; next }
  ($1 == "SFX" || $1 == "PFX") && NF == 4 && $4 !~ /^[0-9]+$/ { print $1, $2, $3, $4, "."; next }
  $1 == "SFX" && $2 == "VD" && $3 == "Y" && $4 == "171" { print $1, $2, $3, "172"; next }
  { print }' "$tmp/index.aff" >"$tmp/hy.aff"

# The dictionary writes the ligature և as two letters, եւ (նաեւ, արեւ).
# Reformed spelling types և, so each entry with եւ gets a twin with և, and
# both spellings pass. The first line of a .dic is its entry count.
{
  tail -n +2 "$tmp/index.dic"
  grep 'եւ' "$tmp/index.dic" | sed 's/եւ/և/g'
} >"$tmp/body"
{
  wc -l <"$tmp/body" | tr -d ' '
  cat "$tmp/body"
} >"$tmp/hy.dic"

mkdir -p "$tmp/rtp/spell"
OUT="$tmp/rtp/spell/hy" IN="$tmp/hy" \
  nvim --clean --headless -c 'execute "mkspell!" fnameescape($OUT) fnameescape($IN)' -c 'qa!'
echo

# :mkspell reports problems but still exits 0, so check the result: words from
# the blocks the fixes rescue must pass, and a misspelling must not.
CHECK='
  local bad = {}
  for _, w in ipairs { "աշխատում", "քաղաքում", "լեզվով", "կարդացել", "նաեւ", "նաև" } do
    if vim.fn.spellbadword(w)[1] ~= "" then table.insert(bad, w .. " rejected") end
  end
  if vim.fn.spellbadword("աշխատըմ")[1] == "" then table.insert(bad, "misspelling աշխատըմ accepted") end
  if #bad > 0 then
    io.stderr:write(table.concat(bad, "\n") .. "\n")
    vim.cmd "cquit"
  end' \
RTP="$tmp/rtp" nvim --clean --headless --cmd 'let &rtp = $RTP . "," . &rtp' \
  -c 'setlocal spell spelllang=hy' -c 'lua assert(load(vim.env.CHECK))()' -c 'qa!'

mv "$tmp/rtp/spell/hy.utf-8.spl" "$here/hy.utf-8.spl"
echo "Wrote $here/hy.utf-8.spl"

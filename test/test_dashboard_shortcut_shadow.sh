#!/usr/bin/env bash
# Repro/regression test for: "after adding a bookmark dir, :Dashboard in an
# EXISTING nvim instance gets corrupted and e.g. [p] Jump Projects stops
# working".
#
# Drives a fully sandboxed headless nvim (HOME + XDG_* redirected into a
# mktemp dir under ${TMPDIR:-/tmp}/kilo; nothing outside the sandbox +
# $HOME_REAL/.local/share/nvim/lazy is touched). Real dashboard-nvim,
# nvim-web-devicons, telescope.nvim and plenary.nvim are put on the runtime
# path of the runner's real HOME.
#
# Two mechanisms are probed, both of which would kill the buffer-local [p]
# shortcut map on the dashboard buffer:
#   1. letter shadowing: with >= 12 project rows + mru rows, hyper.lua could
#      assign the letter 'p' (or 'l'/'q') to an entry and the restyle pass
#      would rebind it -> assert NO entry extmark letter is in {l,q,p}.
#   2. same-instance :Dashboard re-open: dashboard-nvim's cache_opts
#      string.dump()s function shortcut actions when the last dashboard
#      buffer closes; the next :Dashboard restores them from bytecode with
#      nil upvalues -> [p] errors instead of opening the picker. Assert
#      pressing [p] opens the telescope picker on BOTH the first render and
#      after a close + :Dashboard cycle in the same instance.
#
# Run: bash user/repos/nvim/test/test_dashboard_shortcut_shadow.sh
# Must FAIL on unfixed code, ALL PASS after the fix.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_LUA="$HERE/../lua/plugins/dashboard.lua"

FAILURES=0
PASS() { printf 'PASS: %s\n' "$1"; }
FAIL() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

command -v nvim >/dev/null 2>&1 || { printf 'FAIL: nvim not found on PATH\n'; exit 1; }
[ -f "$SPEC_LUA" ] || { printf 'FAIL: dashboard spec not found: %s\n' "$SPEC_LUA"; exit 1; }

# Runner's real home, resolved before HOME is redirected into the sandbox.
HOME_REAL="$HOME"
LAZY_DIR="$HOME_REAL/.local/share/nvim/lazy"
for d in dashboard-nvim nvim-web-devicons telescope.nvim plenary.nvim; do
  [ -d "$LAZY_DIR/$d" ] || { printf 'FAIL: real plugin dir missing: %s/%s\n' "$LAZY_DIR" "$d"; exit 1; }
done

SB_PARENT="${TMPDIR:-/tmp}/kilo"
mkdir -p "$SB_PARENT"
SB="$(mktemp -d "$SB_PARENT/dash-shortcut-test.XXXXXX")"
cleanup() { rm -rf "$SB"; }
trap cleanup EXIT

export HOME="$SB/home"
export XDG_CONFIG_HOME="$SB/xdg/config"
export XDG_CACHE_HOME="$SB/xdg/cache"
export XDG_DATA_HOME="$SB/xdg/data"
export XDG_STATE_HOME="$SB/xdg/state"
export HOME_REAL
export DASH_SPEC_PATH="$SPEC_LUA"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# Seed enough existing project dirs that the combined project list reaches
# the maximum of 12 displayed rows (6 ~/.bookmarks entries + 6 dashboard
# cache entries after dedup): 16 disjoint dirs, 8 per source.
for i in 1 2 3 4 5 6 7 8; do
  mkdir -p "$SB/projs/b$i" "$SB/projs/c$i"
done
: > "$HOME/.bookmarks"
for i in 1 2 3 4 5 6 7 8; do
  printf '%s|bm%d\n' "$SB/projs/b$i" "$i" >> "$HOME/.bookmarks"
done

CACHE_DIR="$XDG_CACHE_HOME/nvim/dashboard"
mkdir -p "$CACHE_DIR"
{
  printf 'return {\n'
  for i in 1 2 3 4 5 6 7 8; do
    printf '  "%s",\n' "$SB/projs/c$i"
  done
  printf '}\n'
} > "$CACHE_DIR/cache"

# Scratch file the "user" opens when leaving the dashboard in phase 2.
export DASH_SCRATCH_FILE="$SB/scratch.txt"
printf 'scratch\n' > "$DASH_SCRATCH_FILE"

mkdir -p "$SB/init"
cat > "$SB/init/init.lua" <<'LUA'
local home_real = os.getenv('HOME_REAL') or ''
for _, p in ipairs({ 'dashboard-nvim', 'nvim-web-devicons', 'telescope.nvim', 'plenary.nvim' }) do
  vim.opt.runtimepath:prepend(home_real .. '/.local/share/nvim/lazy/' .. p)
end
vim.opt.swapfile = false

local spec_path = os.getenv('DASH_SPEC_PATH')

local function res(ok, id, detail)
  detail = detail or ''
  if detail ~= '' then
    detail = ' | ' .. tostring(detail)
  end
  io.stdout:write(string.format('TRESULT %s %s%s\n', ok and 'PASS' or 'FAIL', id, detail))
end
local function trace(msg)
  io.stdout:write('TTRACE ' .. msg .. '\n')
end

local function cur_dashboard_bufs()
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].filetype == 'dashboard' then
      table.insert(bufs, b)
    end
  end
  return bufs
end

local function has_map(key)
  local m = vim.fn.maparg(key, 'n', false, true)
  if vim.tbl_isempty(m) then
    return nil
  end
  return m
end

-- Dashboard rendered AND the DashboardLoaded restyle pass has bound the
-- entry letters (e.g. [a]) on the current buffer.
local function wait_rendered(timeout)
  return vim.wait(timeout, function()
    local bufs = cur_dashboard_bufs()
    if #bufs == 0 then
      return false
    end
    local lines = vim.api.nvim_buf_get_lines(bufs[#bufs], 0, -1, false)
    local has_projects = false
    for _, l in ipairs(lines) do
      if l:find('Recent Projects:', 1, true) then
        has_projects = true
      end
    end
    if not has_projects then
      return false
    end
    local p = has_map('p')
    local a = has_map('a')
    return (p and (p.callback ~= nil or (p.rhs or '') ~= '') or false)
      and (a and a.callback ~= nil or false)
  end, 100)
end

-- Collect the per-entry letters hyper.lua attached as virt_text extmarks in
-- the 'dashboard' namespace.
local function collect_letters()
  local buf = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace('dashboard')
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4] or {}
    local virt = d.virt_text
    if type(virt) == 'table' and type(virt[1]) == 'table' then
      local k = tostring(virt[1][1] or '')
      if k:match('^%S+$') then
        local line = vim.api.nvim_buf_get_lines(buf, m[2], m[2] + 1, false)[1] or ''
        table.insert(out, { row = m[2], key = k, line = vim.fn.trim(line) })
      end
    end
  end
  return out
end

local function check_letters(phase)
  local bad = {}
  for _, e in ipairs(collect_letters()) do
    trace(string.format('%s row=%d letter=%s line=%s', phase, e.row, e.key, e.line))
    if e.key == 'l' or e.key == 'q' or e.key == 'p' then
      table.insert(bad, e.key .. '@row' .. e.row)
    end
  end
  res(#bad == 0, phase .. ': no dashboard entry letter in {l,q,p}', table.concat(bad, ' '))
end

local function picker_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local ok, bt = pcall(function()
      return vim.bo[b].buftype
    end)
    local name = vim.api.nvim_buf_get_name(b)
    if ok and (bt == 'prompt' or name:find('Telescope', 1, true)) then
      return b
    end
  end
  return nil
end

local function press_p(phase)
  local dash_buf = vim.api.nvim_get_current_buf()
  local named_before = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= '' then
      named_before[b] = name
    end
  end
  vim.api.nvim_feedkeys('p', 'x', false)
  local found = vim.wait(3000, function()
    return picker_buf() ~= nil
  end, 100)
  local pb = picker_buf()

  -- surface whatever error the keypress produced as evidence
  local okm, msgs = pcall(vim.fn.execute, 'messages')
  if okm then
    for line in msgs:gmatch('[^\r\n]+') do
      if line:find('Error executing', 1, true) or line:find('attempt to', 1, true) then
        trace(phase .. ' message: ' .. vim.fn.trim(line))
      end
    end
  end

  res(found, phase .. ': [p] opens the telescope jump picker',
    found and ('picker buf ' .. pb) or 'no prompt/telescope buffer appeared')

  local edited = nil
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if
      name ~= ''
      and named_before[b] == nil
      and vim.fn.isdirectory(name) ~= 1
      and not name:find('Telescope', 1, true)
    then
      edited = name
    end
  end
  res(edited == nil, phase .. ': [p] did not edit any file', edited or '')

  if pb then
    pcall(vim.api.nvim_buf_delete, pb, { force = true })
  end
  vim.cmd('sleep 100m')
  pcall(vim.api.nvim_set_current_buf, dash_buf)
end

-- The whole flow must run after startup: with -u init.lua the init chunk
-- executes BEFORE plugin/ files are sourced, so :Dashboard only exists once
-- VimEnter fires.
local function main()
  -- -------------------------------------------------------------------------
  -- Phase 1: first open in a fresh instance (must work before AND after fix).
  -- -------------------------------------------------------------------------
  local spec = dofile(spec_path)
  local okcfg, errcfg = pcall(function()
    spec.config()
  end)
  res(okcfg, 'phase1: dashboard spec config() ran', okcfg and '' or tostring(errcfg))

  vim.api.nvim_feedkeys([[<Esc>]], 'x', false)
  vim.cmd('Dashboard')
  res(wait_rendered(5000), 'phase1: :Dashboard renders (first open)')

  check_letters('phase1')
  press_p('phase1')

  -- -------------------------------------------------------------------------
  -- Phase 2: leave the dashboard the way the user does (open a file), which
  -- wipes the dashboard buffer and runs dashboard-nvim's BufEnter cleanup:
  -- cache_opts persists the config (function actions -> string.dump
  -- bytecode) and clears the in-memory opts. NOTE: headless nvim does not
  -- fire BufEnter on buffer switches (a real UI does), so BufEnter is fired
  -- explicitly on the file buffer to run the plugin's own autocmd.
  -- -------------------------------------------------------------------------
  local scratch = os.getenv('DASH_SCRATCH_FILE') or (vim.fn.tempname())
  vim.cmd('edit ' .. vim.fn.fnameescape(scratch))
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = vim.api.nvim_get_current_buf(), modeline = false })

  local conf = vim.fn.stdpath('cache') .. '/dashboard/conf'
  local conf_written = vim.wait(3000, function()
    return vim.fn.getfsize(conf) > 10
  end, 50)
  res(conf_written, 'phase2: dashboard conf cache written (cache_opts ran)')

  -- Re-open :Dashboard in the SAME instance: dashboard-nvim now restores its
  -- config from the conf cache (get_opts) -- the "existing nvim instance"
  -- path from the bug report.
  vim.api.nvim_feedkeys([[<Esc>]], 'x', false)
  vim.cmd('Dashboard')
  res(wait_rendered(5000), 'phase2: :Dashboard re-renders in same instance')

  local mp = has_map('p')
  res(mp ~= nil and mp.desc == 'dashboard-shortcut-p', 'phase2: [p] map is the custom rebind (desc)',
    tostring(mp and mp.desc))

  press_p('phase2')
  check_letters('phase2')

-- Regression: restyle entry maps keep working (first entry letter is [a]).
  local ma = has_map('a')
  res(ma ~= nil and ma.callback ~= nil, 'phase2: entry letter [a] still mapped by restyle')
  res(ma ~= nil and ma.desc == 'dashboard custom entry open', 'phase2: entry letter [a] has custom desc',
    tostring(ma and ma.desc))

  print('TRESULT DONE')
  io.stdout:flush()
end

vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    local ok, err = pcall(main)
    if not ok then
      print('TRESULT FAIL harness: main() errored | ' .. tostring(err))
    end
    vim.cmd('qa!')
  end,
})
LUA

OUT="$(cd "$SB" && timeout 120 nvim --headless -u "$SB/init/init.lua" 2>&1)"
RC=$?

printf '%s\n' "$OUT" | sed 's/^/  | /'

PARSED_ANY=0
while IFS= read -r line; do
  case "$line" in
    'TRESULT PASS '*) PASS "${line#'TRESULT PASS '}" ; PARSED_ANY=1 ;;
    'TRESULT FAIL '*) FAIL "${line#'TRESULT FAIL '}" ; PARSED_ANY=1 ;;
    TTRACE*) printf 'TRACE: %s\n' "${line#'TTRACE '}" ;;
  esac
done <<< "$OUT"

if [ "$RC" -ne 0 ]; then
  FAIL "nvim exited rc=$RC"
fi
if [ "$PARSED_ANY" -eq 0 ]; then
  FAIL "no TRESULT lines parsed (nvim output above)"
fi

if [ "$FAILURES" -ne 0 ]; then
  printf 'FAILED: %d assertion(s)\n' "$FAILURES"
  printf 'Sandbox kept for inspection: %s\n' "$SB"
  trap - EXIT
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0

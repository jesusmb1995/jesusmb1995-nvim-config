#!/usr/bin/env bash
# Headless nvim tests for window fraction mappings (lua/mappings/windows.lua)
# and the undotree lazy `keys` spec (lua/plugins/undotree.lua).
# Exits non-zero if any case fails.
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v nvim >/dev/null 2>&1; then
  echo "FAIL: nvim not found on PATH" >&2
  exit 1
fi

HARNESS="$WORK/harness.lua"
cat > "$HARNESS" <<'LUA'
local arg0 = select(1, ...) -- nvim -l passes script args as varargs
local root = arg0 or os.getenv("NVIM_TEST_ROOT") or "."

local failures = 0
local function check(name, ok, detail)
  if not ok then failures = failures + 1 end
  print((ok and "PASS" or "FAIL") .. ": " .. name .. (detail and (" | " .. detail) or ""))
end

vim.o.columns = 100 -- advisory in headless; all expectations use measured sizes

local M = dofile(root .. "/lua/mappings/windows.lua")
local api = vim.api

local function layout(split_cmd, n)
  vim.cmd("silent! only")
  for _ = 1, n do
    vim.cmd(split_cmd)
  end
  vim.cmd("wincmd t") -- top-left-most window
end

-- a. two vsplits (3 windows): leftmost is current, no left neighbor -> right fallback
layout("vsplit", 2)
local cur = api.nvim_get_current_win()
local cur_w = api.nvim_win_get_width(cur)
vim.cmd("wincmd l")
local nb = api.nvim_get_current_win()
local nb_w = api.nvim_win_get_width(nb)
vim.cmd("wincmd t")
M._set_fraction_with_neighbor("width", 0.25)
local got_a = api.nvim_win_get_width(cur)
local want_a = math.floor((cur_w + nb_w) * 0.25)
check("a. width 0.25 of combined (leftmost win, right neighbor)", got_a == want_a,
  ("cur=%d nb=%d want=%d got=%d"):format(cur_w, nb_w, want_a, got_a))

-- b. helper("width", 0.5) restores equal split on the same layout
local cur_b = api.nvim_win_get_width(cur)
local nb_b = api.nvim_win_get_width(nb)
M._set_fraction_with_neighbor("width", 0.5)
local got_b = api.nvim_win_get_width(cur)
local nb_after = api.nvim_win_get_width(nb)
check("b. width 0.5 restores equal split",
  got_b == math.floor((cur_b + nb_b) * 0.5) and got_b + nb_after == cur_b + nb_b,
  ("cur=%d nb=%d want=%d got=%d nb_after=%d"):format(
    cur_b, nb_b, math.floor((cur_b + nb_b) * 0.5), got_b, nb_after))

-- c. two splits (3 stacked windows): top window, no up neighbor -> down fallback
layout("split", 2)
local top = api.nvim_get_current_win()
local top_h = api.nvim_win_get_height(top)
vim.cmd("wincmd j")
local below = api.nvim_get_current_win()
local below_h = api.nvim_win_get_height(below)
vim.cmd("wincmd t")
M._set_fraction_with_neighbor("height", 0.25)
local got_c = api.nvim_win_get_height(top)
local want_c = math.floor((top_h + below_h) * 0.25)
check("c. height 0.25 of combined (top win, down neighbor)", got_c == want_c,
  ("top=%d below=%d want=%d got=%d"):format(top_h, below_h, want_c, got_c))

-- d. single window: no neighbor at all -> no-op
vim.cmd("silent! only")
local solo_w = api.nvim_win_get_width(api.nvim_get_current_win())
M._set_fraction_with_neighbor("width", 0.25)
local solo_after = api.nvim_win_get_width(api.nvim_get_current_win())
check("d. single window no-op", solo_after == solo_w,
  ("before=%d after=%d"):format(solo_w, solo_after))

-- keymaps registered (non-empty + desc readable)
for _, lhs in ipairs({ "<leader>wq", "<leader>wa", "<leader>wd", "<leader>we", "<leader>wE" }) do
  local ma = vim.fn.maparg(lhs, "n", false, true)
  check("maparg(" .. lhs .. ", n) non-empty", type(ma) == "table" and next(ma) ~= nil)
end
for _, lhs in ipairs({ "<leader>wq", "<leader>wa", "<leader>wd" }) do
  local ma = vim.fn.maparg(lhs, "n", false, true)
  check("desc readable for " .. lhs, type(ma) == "table" and (ma.desc or "") ~= "",
    "desc=" .. (type(ma) == "table" and (ma.desc or "") or "?"))
end

-- undotree lazy spec contains a keys entry for <leader>u
local spec = dofile(root .. "/lua/plugins/undotree.lua")
local u_hit = false
if type(spec) == "table" and type(spec.keys) == "table" then
  for _, k in ipairs(spec.keys) do
    if k[1] == "<leader>u" then
      u_hit = k[2] == "<cmd>UndotreeToggle<cr>" and k.desc == "Toggle undotree"
    end
  end
end
check("undotree spec keys has <leader>u -> UndotreeToggle", u_hit)

print(("summary: %d failure(s)"):format(failures))
os.exit(failures)
LUA

export NVIM_TEST_ROOT="$ROOT"
cd "$ROOT"
if nvim --headless -u NONE -l "$HARNESS" "$ROOT"; then
  echo "test_window_fractions: ALL PASS"
  exit 0
else
  echo "test_window_fractions: FAILURES DETECTED"
  exit 1
fi

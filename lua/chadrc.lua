-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "gruvchad",

  hl_override = {
    Cursor = { fg = "#1e2122", bg = "#ff6000" },
  },
}

-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
--}

-- Cached `jj log/diff` lookup for the statusline: statusline modules run
-- on every redraw, so refresh at most every 2s per directory.
local _jj_cache = { at = 0, dir = nil, text = "" }
local function _jj_status_text(dir)
  local pre = "cd " .. vim.fn.shellescape(dir) .. " && "
  local rev = vim.trim(vim.fn.system(pre .. "jj log --no-graph -r @ -T 'change_id.shortest(8)' 2>/dev/null") or "")
  if rev == "" or vim.v.shell_error ~= 0 then return "" end
  local stat = vim.fn.system(pre .. "jj diff --stat -r @ 2>/dev/null") or ""
  local added, removed, files = 0, 0, 0
  for line in stat:gmatch("[^\n]+") do
    local a = line:match("(%d+) insertions?%(%+%)")
    local d = line:match("(%d+) deletions?%(%-%)")
    if a or d then
      added, removed = tonumber(a) or 0, tonumber(d) or 0
    elseif line:match("%|") then
      files = files + 1
    end
  end
  local nfiles = stat:match("(%d+) files? changed")
  if nfiles then files = tonumber(nfiles) or 0 end
  local text = " @" .. rev
  if added ~= 0 then text = text .. "  " .. added end
  if files ~= 0 then text = text .. "  " .. files end
  if removed ~= 0 then text = text .. "  " .. removed end
  return "%#St_cwd_text#" .. text .. " "
end

M.ui = {
  statusline = {
    -- "jj" must be listed here or NvChad never renders the module below
    -- (default order has no jj entry).
    order = { "mode", "file", "git", "jj", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "cwd", "cursor" },
    modules = {
      -- NvChad's default cwd module reads vim.uv.cwd(): the PROCESS-global
      -- cwd, which :tcd (per-tab) never touches — so every tab showed the
      -- same, last-set project. Read the EVALUATED window's effective cwd
      -- instead (tcd/lcd-aware, like mappings/terminal.lua and nvim-tree),
      -- with the module's exact styling/width gate.
      cwd = function()
        local ok, dir = pcall(function()
          local winid = vim.g.statusline_winid or vim.api.nvim_get_current_win()
          return vim.fn.getcwd(vim.api.nvim_win_get_number(winid))
        end)
        if not ok or not dir or dir == "" then
          dir = vim.fn.getcwd()
        end
        local name = dir:match("([^/\\]+)[/\\]*$") or dir
        local config = require("nvconfig").ui.statusline
        local sep_style = config.separator_style
        local sep_icons = require("nvchad.stl.utils").separators
        local separators = (type(sep_style) == "table" and sep_style) or sep_icons[sep_style]
        local icon = "%#St_cwd_icon#" .. "󰉋 "
        local text = "%#St_cwd_text#" .. " " .. name .. " "
        return (vim.o.columns > 85 and ("%#St_cwd_sep#" .. separators.left .. icon .. text)) or ""
      end,
      -- Git-style JJ indicator: @<change> plus per-patch +added ~files -removed.
      -- Runs jj in the EVALUATED window's cwd (tcd/lcd-aware); empty outside
      -- jj repos. Single-quoted -T templates: container sh is dash, which
      -- chokes on unquoted jj template parens (see mappings/jj.lua _jj_capture).
      jj = function()
        local ok, dir = pcall(function()
          local winid = vim.g.statusline_winid or vim.api.nvim_get_current_win()
          return vim.fn.getcwd(vim.api.nvim_win_get_number(winid))
        end)
        if not ok or not dir or dir == "" then return "" end
        local now = vim.uv.now()
        if _jj_cache.dir ~= dir or now - _jj_cache.at > 2000 then
          _jj_cache.dir = dir
          _jj_cache.at = now
          _jj_cache.text = _jj_status_text(dir)
        end
        return _jj_cache.text
      end,
    },
  },
}

-- nvim-tree setup moved to lua/plugins/ui.lua to allow lazy loading

return M

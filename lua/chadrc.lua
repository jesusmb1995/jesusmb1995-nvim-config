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

M.ui = {
  statusline = {
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
    },
  },
}

-- nvim-tree setup moved to lua/plugins/ui.lua to allow lazy loading

return M

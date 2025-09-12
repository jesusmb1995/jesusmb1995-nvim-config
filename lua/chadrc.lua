-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "gruvchad",

  -- hl_override = {
  -- 	Comment = { italic = true },
  -- 	["@comment"] = { italic = true },
  -- },
}

-- M.nvdash = { load_on_startup = true }
-- M.ui = {
--       tabufline = {
--          lazyload = false
--      }
--}

-- TODO override config
if vim.env.NVIM_MINIMAL == nil then
  -- Relative line numbers on file tree by default
  require('nvim-tree').setup({
    view = {relativenumber = true},
    update_focused_file = {
      enable = true,
    }
  })
end

return M

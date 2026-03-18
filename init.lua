-- Share vim config with neovim
vim.cmd("set runtimepath^=~/.vim runtimepath+=~/.vim/after")
vim.cmd("let &packpath=&runtimepath")

local function source_if_exists(file)
  if vim.fn.filereadable(vim.fn.expand(file)) == 1 then
    vim.cmd("source " .. file)
  end
end

source_if_exists("~/.vimrc")
source_if_exists("~/.vimrc_prog_mapping")

vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "nvchad.autocmds"

vim.schedule(function()
  require "mappings"
end)

vim.wo.relativenumber=true

-- Register workspace in tmux warm daemon if .was_agent marker exists
function _G.register_warm_workspace()
  local root = vim.fn.getcwd()
  if vim.fn.filereadable(root .. "/.was_agent") == 0 then return end

  local ws_file = "/tmp/tmux_warm_agent_workspaces.json"
  local workspaces = {}

  local f = io.open(ws_file, "r")
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(decoded) == "table" then
      workspaces = decoded
    end
  end

  for _, path in ipairs(workspaces) do
    if path == root then return end
  end

  table.insert(workspaces, root)
  f = io.open(ws_file, "w")
  if f then
    f:write(vim.json.encode(workspaces))
    f:close()
  end

  local pid = io.open("/tmp/tmux_warm_daemon.pid", "r")
  if pid then
    local daemon_pid = pid:read("*l")
    pid:close()
    if daemon_pid then
      os.execute("kill -USR1 " .. daemon_pid .. " 2>/dev/null")
    end
  end
end

vim.api.nvim_create_autocmd({"VimEnter", "DirChanged"}, {
  callback = register_warm_workspace,
})

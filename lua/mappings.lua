require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- conform
if vim.env.NVIM_MINIMAL == nil then
  local _conform = require "conform"
  map({ "n", "v" }, "<leader>F", function()
    _conform.format {
      lsp_fallback = true,
      async = false,
      timeout_ms = 500,
    }
  end, { desc = "Format file or range (in visual mode)" })

  -- The other mappings are as default
  -- <C-n> next
  -- <C-p> prev
  -- <C-Space> complete
  -- <C-e> abort
  map({ "i" }, "<C-A-Space>", function()
    vim.b.x = not vim.b.x
    local cmp = require "cmp"
    local _enabled = not vim.b.x
    cmp.setup.buffer { enabled = _enabled }
  end, { desc = "Toggle Automatic Autocompletion Dropdown CMP" })
end

map("n", "<leader>X", ":tabclose | bdelete<CR>", { desc = "Close current tab and its buffers" })

map("n", "<leader>B", ":tabnew %<CR>", { desc = "Open current window in new tab" })

-- cursor
if vim.env.NVIM_MINIMAL == nil then
  map("n", "<C-S-l>", function()
    -- Get current directory and file
    local cwd = vim.fn.getcwd()
    local current_file = vim.fn.expand "%:p"
    -- Open folder and file in VS Code, then trigger new chat
    local system_command = "cursor " .. cwd .. " " .. current_file .. " --command workbench.action.chat.newChat"
    -- print(system_command)
    vim.fn.system(system_command)
  end, { desc = "Open folder and file in VS Code, start new chat" })
end

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

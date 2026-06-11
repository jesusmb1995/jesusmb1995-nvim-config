local map = vim.keymap.set

local _conform = require "conform"
local _linter = require "lint"
local current_formatter = {}
local current_linter = {}

local function cycle_formatter(use)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local formatters = _conform.formatters_by_ft[filetype] or {}

  if #formatters == 0 then
    vim.notify("No formatters configured for " .. filetype, vim.log.levels.WARN)
    return
  end

  -- Initialize or increment the current formatter index
  if use then
    current_formatter[filetype] = (current_formatter[filetype] or 0) % #formatters
  else
    current_formatter[filetype] = (current_formatter[filetype] or 0) % #formatters + 1
  end
  local formatter = formatters[current_formatter[filetype]]

  if use then
    if formatter == "standardjs" then
      local filename = vim.api.nvim_buf_get_name(bufnr)
      vim.notify("Fixing " .. filename, vim.log.levels.INFO)
      vim.fn.system("standard --fix " .. vim.fn.shellescape(filename))
      vim.cmd("e " .. filename)
      return
    end
    _conform.format {
      lsp_fallback = true,
      async = false,
      timeout_ms = 5000,
      formatters = { formatter },
      { bufnr = bufnr },
    }
  else
    vim.notify("Set formatter to " .. formatter, vim.log.levels.INFO)
  end
end

local function cycle_linter(use)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local linters = _linter.linters_by_ft[filetype] or {}

  if #linters == 0 then
    vim.notify("No linters configured for " .. filetype, vim.log.levels.WARN)
    return
  end

  -- Initialize or increment the current linter index
  if use then
    current_linter[filetype] = (current_linter[filetype] or 0) % #linters
  else
    current_linter[filetype] = (current_linter[filetype] or 0) % #linters + 1
  end
  local linter = linters[current_linter[filetype]]

  if use then
    _linter.try_lint(linter)
  else
    vim.notify("Set linter to " .. linter, vim.log.levels.INFO)
  end
end

-- Create a user command
vim.api.nvim_create_user_command("CycleFormatter", function()
  cycle_formatter(false)
end, {})
vim.api.nvim_create_user_command("CycleLinter", function()
  cycle_linter(false)
end, {})

map({ "n", "v" }, "<leader>F", function()
  cycle_formatter(true)
end, { desc = "Format file or range (in visual mode)" })

vim.keymap.set("n", "<leader>l", function()
  cycle_linter(true)
end, { desc = "Trigger linting for current file" })

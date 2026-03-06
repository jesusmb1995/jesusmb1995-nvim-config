local branch_changed_lines = {}

local function update_branch_changed_lines()
  for k in pairs(branch_changed_lines) do
    branch_changed_lines[k] = nil
  end
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if not git_root then
    return
  end
  local diff = vim.fn.systemlist("git diff upstream/main..HEAD --unified=0")
  local current_file = nil
  for _, line in ipairs(diff) do
    local file = line:match("^%+%+%+ b/(.+)$")
    if file then
      current_file = git_root .. "/" .. file
      branch_changed_lines[current_file] = branch_changed_lines[current_file] or {}
    elseif current_file then
      local s, c = line:match("^@@.-%+(%d+),?(%d*)%s")
      if s then
        s = tonumber(s)
        c = tonumber(c) or 1
        for l = s, s + math.max(c, 1) - 1 do
          branch_changed_lines[current_file][l] = true
        end
      end
    end
  end
end

return {
  "folke/trouble.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  opts = {
    modes = {
      branch_diagnostics = {
        mode = "diagnostics",
        filter = {
          function(item)
            local file_lines = branch_changed_lines[item.filename]
            return file_lines ~= nil and item.pos ~= nil and file_lines[item.pos[1]] == true
          end,
        },
      },
    },
  },
  cmd = "Trouble",
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Diagnostics (Trouble)",
    },
    {
      "<leader>xX",
      function()
        update_branch_changed_lines()
        require("trouble").toggle("branch_diagnostics")
      end,
      desc = "Branch Diagnostics (Trouble)",
    },
    {
      "<leader>cs",
      "<cmd>Trouble symbols toggle focus=false<cr>",
      desc = "Symbols (Trouble)",
    },
    {
      "<leader>cl",
      "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
      desc = "LSP Definitions / references / ... (Trouble)",
    },
    {
      "<leader>xL",
      "<cmd>Trouble loclist toggle<cr>",
      desc = "Location List (Trouble)",
    },
    {
      "<leader>xQ",
      "<cmd>Trouble qflist toggle<cr>",
      desc = "Quickfix List (Trouble)",
    },
  },
}


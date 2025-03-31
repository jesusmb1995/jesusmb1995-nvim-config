return {
  -- https://www.youtube.com/watch?v=y1WWOaLCNyI
  "mfussenegger/nvim-lint",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require "lint"
    lint.linters_by_ft = {
      cpp = { "cpplint" },
      c = { "cpplint" },
      python = { "pylint" },
      yaml = { "yamllint" },
      javascript = { "biomejs" },
      bash = { "shellcheck" },
      zsh = { "shellcheck" },
    }

    vim.keymap.set("n", "<leader>l", function()
      lint.try_lint()
    end, { desc = "Trigger linting for current file" })
  end,
}

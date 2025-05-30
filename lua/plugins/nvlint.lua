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
      javascript = { "biomejs", "standardjs" },
      bash = { "shellcheck" },
      zsh = { "shellcheck" },
      -- TODO automatically generate .vale.ini or root project and vale sync styles
      markdown = { "vale" },
      dockerfile = { "hadolint" },
    }
  end,
}

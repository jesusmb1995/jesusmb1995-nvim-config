return {
  "folke/snacks.nvim",
  lazy = true,
  cmd = { "SnacksProfilerToggle", "SnacksProfilerShow" },
  opts = {
    defaults = { enabled = false },
    profiler = { enabled = true },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    vim.api.nvim_create_user_command("SnacksProfilerToggle", function()
      Snacks.profiler.toggle()
    end, { desc = "Toggle Snacks Profiler" })
    vim.api.nvim_create_user_command("SnacksProfilerShow", function()
      Snacks.profiler.scratch()
    end, { desc = "Show Snacks Profiler results" })
  end,
}

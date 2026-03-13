return {
  "folke/snacks.nvim",
  lazy = true,
  cmd = { "SnacksProfilerToggle", "SnacksProfilerShow", "SnacksProfilerScratch" },
  opts = {
    defaults = { enabled = false },
    profiler = { enabled = true },
    picker = { enabled = true },
    scratch = { enabled = true },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    vim.api.nvim_create_user_command("SnacksProfilerToggle", function()
      Snacks.profiler.toggle()
    end, { desc = "Toggle Snacks Profiler" })
    vim.api.nvim_create_user_command("SnacksProfilerShow", function()
      Snacks.profiler.pick({
        group = "name",
        min_time = 1,
        sort = "time",
        structure = true,
      })
    end, { desc = "Show Snacks Profiler results" })
    vim.api.nvim_create_user_command("SnacksProfilerScratch", function()
      Snacks.profiler.scratch()
    end, { desc = "Snacks Profiler scratch buffer" })
  end,
}

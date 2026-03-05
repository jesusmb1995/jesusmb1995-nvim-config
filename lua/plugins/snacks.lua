return {
  "folke/snacks.nvim",
  lazy = true,
  cmd = { "SnacksProfilerToggle" },
  opts = {
    defaults = { enabled = false },
    profiler = { enabled = true },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    vim.api.nvim_create_user_command("SnacksProfilerToggle", function()
      Snacks.profiler.toggle()
    end, { desc = "Toggle Snacks Profiler" })
  end,
}

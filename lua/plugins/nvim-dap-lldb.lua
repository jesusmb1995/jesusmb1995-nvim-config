return {
  "julianolf/nvim-dap-lldb",
  lazy = true,
  dependencies = {
    "mfussenegger/nvim-dap",
  },
  keys = {
    { '<leader>Vc', function() require("dap-lldb").setup() end, "Setup DAP LLDB" }
  },
}

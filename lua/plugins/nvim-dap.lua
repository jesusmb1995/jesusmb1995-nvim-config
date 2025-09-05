return {
  "mfussenegger/nvim-dap.nvim",
  url = "https://github.com/mfussenegger/nvim-dap",
  dependencies = { 'rcarriaga/nvim-dap-ui' },
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  keys = {
    {
      "<leader>dh",
      function()
        require("dap.ui.widgets").hover()
      end,
      desc = "Hover variable",
    },
    {
      "<leader>db",
      function()
        require("dap").toggle_breakpoint()
      end,
      desc = "Toggle breakpoint",
    },
    {
      "<leader>dB", 
      function()
        vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
          require("dap").toggle_breakpoint(condition)
        end)
      end,
      desc = "Toggle conditional breakpoint",
    },
    {
      "<leader>ds",
      function()
        require("dap").terminate()
      end,
      desc = "Stop debugging",
    },
    {
      "<F8>",
      function()
        require("dap").step_over()
      end,
      desc = "Step over",
    },
    {
      "<leader>do",
      function()
        require("dap").step_over()
      end,
      desc = "Step over",
    },
    {
      "<leader>dc",
      function()
        require("dap").continue()
      end,
      desc = "Start/Continue",
    },
    {
      "<leader>dr",
      function()
        require("dap").restart()
      end,
      desc = "Restart",
    },
    {
      "<leader>dC",
      function()
        require("dap").run_to_cursor()
      end,
      desc = "Run to cursor",
    },
    {
      "<F9>",
      function()
        require("dap").step_out()
      end,
      desc = "Step out",
    },
    {
      "<leader>du",
      function()
        require("dap").step_out()
      end,
      desc = "Step out",
    },
    {
      "<F7>",
      function()
        require("dap").step_into()
      end,
      desc = "Step into",
    },
    {
      "<leader>di",
      function()
        require("dap").step_into()
      end,
      desc = "Step into",
    },
    {
      "<leader>dd",
      function()
        require("dapui").toggle()
      end,
      desc = "Toggle DAP UI",
    },
  },
  config = function()
    require("dapui").setup()
  end
}

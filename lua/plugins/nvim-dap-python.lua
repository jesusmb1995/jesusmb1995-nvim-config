return {
  "mfussenegger/nvim-dap-python",
  lazy = true,
  config = function()
    local python = vim.fn.getcwd() .. "/venv/bin/python"
    require("dap-python").setup(python)
  end,
  dependencies = {
    "mfussenegger/nvim-dap",
  }
}

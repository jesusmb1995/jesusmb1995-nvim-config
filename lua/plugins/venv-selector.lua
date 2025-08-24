return {
  'linux-cultist/venv-selector.nvim',
  dependencies = { 'neovim/nvim-lspconfig', 'nvim-telescope/telescope.nvim', 'mfussenegger/nvim-dap-python' },
  branch = "regexp",
  cmd = "VenvSelect",
  keys = {
    { '<leader>Vs', '<cmd>VenvSelect<cr>', "Select Python Venv and enable DAP Python" }
  },
  config = function()
    require('venv-selector').setup {}
  end
}

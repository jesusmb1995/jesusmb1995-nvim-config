return {
  "sudormrfbin/cheatsheet.nvim",
  dependencies = { 'nvim-telescope/telescope.nvim' },
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  cmd = { "Cheatsheet" },
  keys = {
    { "<leader>?", "<cmd>Cheatsheet<CR>", desc = "Cheatsheet (searchable)" },
  },
}

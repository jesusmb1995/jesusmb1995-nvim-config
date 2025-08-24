return {
  "sudormrfbin/cheatsheet.nvim",
  dependencies = { 'nvim-telescope/telescope.nvim' },
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end;
  cmd = { "Cheatsheet" },
  vim.keymap.set("n", "<leader>?", function()
     vim.cmd("Cheatsheet")
  end, { desc = "Cheatsheet (searchable)" })
}

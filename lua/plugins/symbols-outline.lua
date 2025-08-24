return {
  "simrat39/symbols-outline.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  cmd = { "SymbolsOutline" },
  keys = {
    {
      "<leader>s",
      "<cmd>SymbolsOutline<cr>",
      desc = "Symbols outline",
    }
  },
  config = function()
    require("symbols-outline").setup()
  end
}

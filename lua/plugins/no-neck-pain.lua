return {
  "shortcuts/no-neck-pain.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  cmd = "NoNeckPain",
}

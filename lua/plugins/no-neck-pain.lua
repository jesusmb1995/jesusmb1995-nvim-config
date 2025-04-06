return {
  "shortcuts/no-neck-pain.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  cmd = "NoNeckPain",
  config = function()
    require("no-neck-pain").setup {
      width = 120,
      minSideBufferWidth = 12,
      autocmds = {
        skipEnteringNoNeckPainBuffer = true,
      },
      integrations = { NvimTree = {
        reopen = true,
      } },
    }
  end,
}

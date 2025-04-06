return {
  "sindrets/diffview.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  cmd = { "DiffviewOpen", "DiffviewOpen HEAD^" },
}

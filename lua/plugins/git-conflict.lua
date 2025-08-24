return {
  'akinsho/git-conflict.nvim',
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  config = true,
  cmd = { "GitConflictListQf", "GitConflictRefresh" }
}

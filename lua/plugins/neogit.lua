return {
  "NeogitOrg/neogit",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required
    --"sindrets/diffview.nvim",        -- optional - Diff integration

    ---- Only one of these is needed.
    --"nvim-telescope/telescope.nvim", -- optional
    --"ibhagwan/fzf-lua",              -- optional
    --"echasnovski/mini.pick",         -- optional
  },
  config = true
}


return {
  {
    url = "https://github.com/jesusmb1995/stg-nvim",
    -- dir = "/luksmap/Code/stg-nvim",
    lazy = true,
    cmd = { "StgNew", "StgSeries", "StgGoto", "StgRefresh", "StgStagedApplyTo", "StgApplyTo", "StgSpill", "StgResolve", "StgBranchClone", "StgEdit", "StgRebase" },
    keys = {
      { "<leader>gkn", "<cmd>StgNew<cr>", desc = "Create new patch" },
      { "<leader>gks", "<cmd>StgSeries<cr>", desc = "Show patches" },
      { "<leader>gkg", "<cmd>StgGoto<cr>", desc = "Go to patch" },
      { "<leader>gkr", "<cmd>StgRefresh<cr>", desc = "Refresh current patch" },
      { "<leader>gka", "<cmd>StgStagedApplyTo<cr>", desc = "Apply current staged changes to another patch but stay on current patch" },
      { "<leader>gkA", "<cmd>StgApplyTo<cr>", desc = "Apply current changes to another patch but stay on current patch" },
      { "<leader>gku", "<cmd>StgSpill<cr>", desc = "Empty current patch but keep changes locally" },
      { "<leader>gkc", "<cmd>StgBranchClone<cr>", desc = "Clone current branch" },
      { "<leader>gkC", "<cmd>StgResolve<cr>", desc = "Resolve conflicts" },
      { "<leader>gke", "<cmd>StgEdit<cr>", desc = "Edit current patch" },
      { "<leader>gkR", "<cmd>StgRebase<cr>", desc = "Interactive rebase" },
    },
    config = function()
      require('stg-nvim').setup({
        -- Optional: specify stg path
        stg_path = "/home/linuxbrew/.linuxbrew/bin/stg"
      })
    end
  }
}

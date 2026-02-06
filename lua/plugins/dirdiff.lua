return {
  "will133/vim-dirdiff",
  cmd = { "DirDiff" },
  config = function()
    -- Optional: customize DirDiff settings
    vim.g.DirDiffExcludes = "*.bare,*.node,*.so,*.dylib,.git,node_modules"
  end,
}


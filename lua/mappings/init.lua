require "nvchad.mappings"

-- add yours here

require "mappings.mode-switching"

if vim.env.NVIM_MINIMAL == nil then
  require "mappings.telescope"
  require "mappings.nvim-tree"
  require "mappings.cmp"
  require "mappings.neogit"
  require "mappings.gitsigns"
  require "mappings.git-worktrees"
  require "mappings.testing"
  require "mappings.tabs-buffers"
  require "mappings.disabled-keys"
  require "mappings.external-editors"
  require "mappings.agent-term"
  require "mappings.diffview"
  require "mappings.git-conflict"
  require "mappings.terminal"
  require "mappings.windows"
end

require "mappings.format-lint"

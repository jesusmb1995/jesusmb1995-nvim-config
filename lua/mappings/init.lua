require "nvchad.mappings"

-- add yours here

require "mappings.mode-switching"

if vim.env.NVIM_MINIMAL == nil then
  -- pcall: mapping files gated off by config (e.g. neogit/git-conflict in jj
  -- mode) render empty and are pruned by the nvim post-render hook, so a plain
  -- require would fail at launch. Guard the optional ones.
  local opt = function(m) pcall(require, m) end
  require "mappings.telescope"
  require "mappings.nvim-tree"
  require "mappings.cmp"
  opt "mappings.neogit"
  opt "mappings.jj"
  opt "mappings.gitsigns"
  opt "mappings.git-worktrees"
  require "mappings.testing"
  require "mappings.tabs-buffers"
  require "mappings.disabled-keys"
  opt "mappings.external-editors"
  require "mappings.agent-term"
  require "mappings.diffview"
  opt "mappings.git-conflict"
  require "mappings.terminal"
  require "mappings.windows"
end

require "mappings.format-lint"

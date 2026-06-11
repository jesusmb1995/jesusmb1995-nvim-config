local map = vim.keymap.set

-- The other mappings are as default
-- <C-n> next
-- <C-p> prev
-- <C-Space> complete
-- <C-e> abort
map({ "i" }, "<C-A-Space>", function()
  vim.b.x = not vim.b.x
  local cmp = require "cmp"
  local _enabled = not vim.b.x
  cmp.setup.buffer { enabled = _enabled }
end, { desc = "Toggle Automatic Autocompletion Dropdown CMP" })

require "nvchad.options"

-- add yours here!
require "configs.gitsigns"

-- Auto-choose "E" (edit anyway) when swap files already exist.
vim.api.nvim_create_autocmd("SwapExists", {
  callback = function()
    vim.v.swapchoice = "e"
  end,
  desc = "Use Edit anyway on swap prompt",
})

-- Reduce noisy swap-related command-line prompts.
vim.opt.shortmess:append("A")

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

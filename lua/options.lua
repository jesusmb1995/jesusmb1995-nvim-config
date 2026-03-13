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

-- Signal pre-warmed tmux shells that this terminal was opened from Neovim,
-- so zsh can hide redundant cwd/git info from the prompt.
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    if vim.fn.exists("$TMUX") == 1 then
      vim.fn.system("tmux set-environment -g NVIM_TERM_DIR " .. vim.fn.shellescape(vim.fn.getcwd()))
    end
  end,
  desc = "Set NVIM_TERM_DIR in tmux env for prompt suppression",
})

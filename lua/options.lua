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
    -- Unset NVIM and TMUX so oh-my-zsh tmux plugin auto-starts tmux inside :terminal
    local buf = vim.api.nvim_get_current_buf()
    local chan = vim.b[buf].terminal_job_id
    if chan then
      vim.fn.chansend(chan, "unset NVIM TMUX; exec zsh\n")
    end
  end,
  desc = "Set NVIM_TERM_DIR in tmux env and enable tmux autostart in :terminal",
})

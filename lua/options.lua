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

-- TODO is there a way to do this at one go? instead of opening a terminal then executing additional command
-- Signal pre-warmed tmux shells that this terminal was opened from Neovim,
-- so zsh can hide redundant cwd/git info from the prompt.
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    if vim.fn.exists("$TMUX") == 1 then
      vim.fn.system("tmux set-environment -g NVIM_TERM_DIR " .. vim.fn.shellescape(vim.fn.expand(vim.fn.getcwd())))
    end
    -- Unset NVIM and TMUX so the oh-my-zsh tmux plugin auto-starts tmux inside
    -- :terminal, and cd to Neovim's cwd first. The :terminal shell can inherit a
    -- different directory (e.g. /), and the warm session it attaches to is born
    -- in the daemon's cwd (/tmp); the plugin then sends `cd "$(pwd)"` to that
    -- session. Without this cd, $(pwd) is the wrong dir and the warm shell lands
    -- in / instead of the project root.
    local buf = vim.api.nvim_get_current_buf()
    local chan = vim.b[buf].terminal_job_id
    if chan then
      local dir = vim.fn.shellescape(vim.fn.expand(vim.fn.getcwd()))
      vim.fn.chansend(chan, "unset NVIM TMUX; cd " .. dir .. " 2>/dev/null; exec zsh\n")
    end
  end,
  desc = "Set NVIM_TERM_DIR in tmux env and enable tmux autostart in :terminal",
})

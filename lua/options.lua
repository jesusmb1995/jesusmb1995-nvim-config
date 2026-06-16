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

-- Record Neovim's cwd in the tmux env so the pre-warmed shell can hide
-- redundant cwd/git info from its prompt. Joining the warm tmux session is
-- handled by launching the terminal shell already clean (see
-- lua/mappings/terminal.lua), so no post-open `unset NVIM TMUX; exec zsh`
-- re-source is needed here. See doc/tmux.md.
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    if vim.fn.exists("$TMUX") == 1 then
      vim.fn.system("tmux set-environment -g NVIM_TERM_DIR " .. vim.fn.shellescape(vim.fn.expand(vim.fn.getcwd())))
    end
  end,
  desc = "Record Neovim cwd in NVIM_TERM_DIR for the warm tmux shell's prompt",
})

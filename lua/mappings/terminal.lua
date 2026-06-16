-- Open generic terminals with NVIM and TMUX stripped from the environment so
-- the oh-my-zsh tmux plugin attaches to a pre-warmed session on the first
-- ~/.zshrc source. Neovim injects $NVIM (and inherits $TMUX) into terminal
-- children, which makes the plugin's autostart guard skip; launching clean
-- avoids the old `unset NVIM TMUX; exec zsh` re-source dance.
--
-- The terminal cwd is pinned explicitly: the inherited terminal cwd is
-- unreliable and the warm session is born in the daemon's /tmp, so the plugin's
-- `cd "$(pwd)"` only lands in the project when $(pwd) of this shell is right.
-- getcwd is preferred, but it is itself unreliable (nvim is often launched from
-- a shell already sitting at /, e.g. a warm session that landed at /), so when
-- getcwd is / or empty we fall back to the current file's git root / directory.
-- See doc/tmux.md.
local warm_shell = "env -u NVIM -u TMUX zsh"
local map = vim.keymap.set

local function warm_cwd()
  local cwd = vim.fn.getcwd()
  if cwd ~= "" and cwd ~= "/" then
    return cwd
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return cwd
  end
  local dir = vim.fs.dirname(file)
  return vim.fs.root(dir, { ".git" }) or dir
end

local warm_terms = {
  { "<A-v>", { "n", "t" }, "toggle", { pos = "vsp", id = "vtoggleTerm" }, "toggleable vertical" },
  { "<A-h>", { "n", "t" }, "toggle", { pos = "sp", id = "htoggleTerm" }, "toggleable horizontal" },
  { "<A-i>", { "n", "t" }, "toggle", { pos = "float", id = "floatTerm" }, "floating" },
  { "<leader>h", "n", "new", { pos = "sp" }, "new horizontal" },
  { "<leader>v", "n", "new", { pos = "vsp" }, "new vertical" },
}

for _, t in ipairs(warm_terms) do
  local lhs, modes, fn, opts, label = t[1], t[2], t[3], t[4], t[5]
  map(modes, lhs, function()
    require("nvchad.term")[fn](vim.tbl_extend("force", opts, {
      cmd = warm_shell,
      termopen_opts = { cwd = warm_cwd() },
    }))
  end, { desc = "terminal " .. label .. " (warm tmux)" })
end

local terminal_file_ref_pattern = [[\v(\f+\/\f+|\f+\.\f+)(:\d+(:\d+)?)?]]

local function jump_terminal_file_ref(forward)
  local flags = forward and "W" or "bW"
  local found = vim.fn.search(terminal_file_ref_pattern, flags)
  if found == 0 then
    vim.notify("No more file references found", vim.log.levels.INFO)
  end
end

local function open_terminal_cfile_in_tab()
  local raw = vim.fn.expand "<cfile>"
  if raw == nil or raw == "" then
    vim.notify("No file reference under cursor", vim.log.levels.WARN)
    return
  end

  local path, lnum, col = raw:match("^(.-):(%d+):(%d+)$")
  if not path then
    path, lnum = raw:match("^(.-):(%d+)$")
  end
  path = path or raw

  path = vim.fs.normalize(vim.fn.expand(path))
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("File not found: " .. path, vim.log.levels.WARN)
    return
  end

  vim.cmd("tabedit " .. vim.fn.fnameescape(path))
  if lnum then
    local row = tonumber(lnum) or 1
    local c = math.max((tonumber(col) or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(0, { row, c })
  end
end

-- Dont resize terminals vertically.
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value("winfixwidth", true, {})
    vim.api.nvim_set_option_value("winfixheight", true, {})
    vim.keymap.set("n", "]f", function() jump_terminal_file_ref(true) end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Next file reference in terminal",
    })
    vim.keymap.set("n", "[f", function() jump_terminal_file_ref(false) end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Previous file reference in terminal",
    })
    vim.keymap.set("n", "gf", open_terminal_cfile_in_tab, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Open terminal file reference in new tab",
    })
    vim.keymap.set("t", "gf", function()
      vim.cmd "stopinsert"
      open_terminal_cfile_in_tab()
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Open terminal file reference in new tab",
    })
    vim.keymap.set("t", " ", " ", {
      buffer = buf,
      nowait = true,
      desc = "Bypass leader timeout so space is sent immediately",
    })
  end,
})
-- Neither when toggle hide. Force reapply option.
vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*",
  callback = function()
    if vim.bo.buftype == "terminal" then
      vim.api.nvim_set_option_value("winfixwidth", true, {})
      vim.api.nvim_set_option_value("winfixheight", true, {})
    end
  end,
})

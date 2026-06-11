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

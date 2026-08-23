local M = {}

local map = vim.keymap.set

-- Resize panel width with Ctrl+Alt+Shift+Arrows
map("n", "<C-A-S-Right>", ":vertical resize +5<CR>", { desc = "Increase window width", silent = true })
map("n", "<C-A-S-Left>", ":vertical resize -5<CR>", { desc = "Decrease window width", silent = true })

-- Set the current window's size to `fraction` of the combined size of the
-- current window and one neighbor along `axis` ("width": left/right windows,
-- "height": up/down windows). Neighbor discovery: an explicit `direction`
-- ("left"/"right" or "up"/"down") uses only that side; otherwise prefer
-- left/up and fall back to right/down. No neighbor at all: no-op.
local function set_fraction_with_neighbor(axis, fraction, direction)
  local cur_win = vim.api.nvim_get_current_win()
  local is_width = axis == "width"
  local get_size = is_width and vim.api.nvim_win_get_width or vim.api.nvim_win_get_height
  local set_size = is_width and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height
  local back_cmd, forth_cmd = "wincmd h", "wincmd l"
  if not is_width then
    back_cmd, forth_cmd = "wincmd k", "wincmd j"
  end
  if direction == "right" or direction == "down" then
    back_cmd, forth_cmd = forth_cmd, nil
  elseif direction == "left" or direction == "up" then
    forth_cmd = nil
  end

  local function win_after(cmd)
    vim.cmd(cmd)
    local win = vim.api.nvim_get_current_win()
    if win == cur_win then return nil end
    return win
  end

  local neighbor_win = win_after(back_cmd) or (forth_cmd and win_after(forth_cmd) or nil)
  if not neighbor_win then return end

  local combined = get_size(cur_win) + get_size(neighbor_win)
  vim.api.nvim_set_current_win(cur_win)
  set_size(cur_win, math.max(1, math.floor(combined * fraction)))
end

map("n", "<leader>we", function() set_fraction_with_neighbor("width", 0.5, "left") end, { desc = "Equalize width with left window", silent = true })
map("n", "<leader>wE", function() set_fraction_with_neighbor("width", 0.5, "right") end, { desc = "Equalize width with right window", silent = true })

map("n", "<leader>wq", function() set_fraction_with_neighbor("width", 0.25) end, { desc = "Set current window width to quarter of split", silent = true })
map("n", "<leader>wa", function() set_fraction_with_neighbor("height", 0.25) end, { desc = "Set current window height to quarter of split", silent = true })
map("n", "<leader>wd", function() set_fraction_with_neighbor("height", 0.5) end, { desc = "Set current window height to half of split", silent = true })

M._set_fraction_with_neighbor = set_fraction_with_neighbor

map("n", "<leader>np", ":NoNeckPain<CR>", { noremap = true, silent = true, desc = "No neck pain toggle" })

-- Automatically resize window on display change
vim.api.nvim_create_autocmd("VimResized", {
  pattern = "*",
  callback = function()
    -- Close nvim tree and vertical terminals to avoid weird effects.
    local nvim_tree = package.loaded["nvim-tree.api"]
    if nvim_tree and nvim_tree.tree.is_visible() then
      vim.defer_fn(function()
        nvim_tree.tree.close()
      end, 70)
    end

    -- Close vertical toggleable terminals if window is too smaller
    vim.defer_fn(function()
      local current_columns = vim.o.columns
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)

        if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
          -- Check if the terminal is vertical (height larger than width)
          -- Somehow width is not accurate wrp of how it appears on the screen, adjust by 30.
          local win_width = vim.api.nvim_win_get_width(win)
          local win_height = vim.api.nvim_win_get_height(win)
          local is_vertical = win_height >= win_width - 30
          -- vim.notify(
          --   string.format(
          --     "Win: %d, Width: %d, Height: %d, Vertical: %s, Columns: %d",
          --     win,
          --     win_width,
          --     win_height,
          --     tostring(is_vertical),
          --     current_columns
          --   ),
          --   vim.log.levels.INFO
          -- )

          if is_vertical and win_width > (current_columns / 2) then
            vim.api.nvim_win_close(win, true)
          end
        end
      end
    end, 110)

    -- Equal resize windows
    vim.cmd "wincmd ="
  end,
})

-- TODO automatically toggle back no-neck-pain if closed...
-- TODO .. and fix resizing twice to 80 then 120
-- TODO keep nvimtree resized to expanded size on no-neck-pain when new buffer is opened

-- Automatically trigger resize of windows when nvimtree is opened
-- Deferred: subscribe only after nvim-tree is actually loaded
local function subscribe_tree_open_resize()
  local nvim_tree_events = require "nvim-tree.events"
  nvim_tree_events.subscribe(nvim_tree_events.Event.TreeOpen, function()
    local vertical_count = 0
    local defered = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if
        vim.api.nvim_get_option_value("buftype", { buf = buf }) == ""
        or vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal"
      then
        local win_width = vim.api.nvim_win_get_width(win)
        local win_height = vim.api.nvim_win_get_height(win)
        local is_vertical = win_height >= win_width - 30
        if is_vertical then
          vertical_count = vertical_count + 1
        end
        if vertical_count > 2 then
          defered = true
          vim.defer_fn(function()
            require("no-neck-pain").toggle(false)
            vim.cmd.NvimTreeResize(30)
            vim.cmd "wincmd ="
          end, 30)
          break
        end
      end
    end
    if not defered then
      vim.cmd "wincmd ="
    end
  end)
end

if package.loaded["nvim-tree"] then
  subscribe_tree_open_resize()
else
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    once = true,
    callback = function(args)
      if args.data == "nvim-tree.lua" then
        subscribe_tree_open_resize()
      end
    end,
  })
end

return M

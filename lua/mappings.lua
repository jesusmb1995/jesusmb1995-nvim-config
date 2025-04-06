require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- conform
if vim.env.NVIM_MINIMAL == nil then
  local _conform = require "conform"
  map({ "n", "v" }, "<leader>F", function()
    _conform.format {
      lsp_fallback = true,
      async = false,
      timeout_ms = 500,
    }
  end, { desc = "Format file or range (in visual mode)" })

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
end

map("n", "<leader>X", ":tabclose | bdelete<CR>", { desc = "Close current tab and its buffers" })

map("n", "<leader>B", ":tabnew %<CR>", { desc = "Open current window in new tab" })

-- cursor
if vim.env.NVIM_MINIMAL == nil then
  map("n", "<C-S-l>", function()
    -- Get current directory and file
    local cwd = vim.fn.getcwd()
    local current_file = vim.fn.expand "%:p"
    -- Open folder and file in VS Code, then trigger new chat
    local system_command = "cursor "
      .. cwd
      .. " --goto "
      .. current_file
      .. ":"
      .. vim.fn.line "."
      .. " --command workbench.action.chat.newChat 2> /dev/null & disown || true"
    -- print(system_command)
    vim.fn.system(system_command)
  end, { desc = "Open folder and file in VS Code, start new chat" })

  map("n", "<F4>", ":%bd|e#<CR>", { desc = "Close all buffers except current" })

  -- TODO shorcut close all windows except :only the editor ones
  -- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

  -- Create a command to open current file in CLion in normal mode
  vim.api.nvim_create_user_command("Intellij", function()
    -- Get current file path, line number, and column
    local file_path = vim.fn.expand "%:p"
    local line_number = vim.fn.line "."
    local column_number = vim.fn.col "."

    -- Find the git root or use the current directory as the project root
    local project_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
    if vim.v.shell_error ~= 0 then
      project_root = vim.fn.getcwd()
    end

    -- Construct the CLion command with parameters
    -- Using --line and --column but also explicitly specify the project directory
    -- TODO: Detect other file types and open them in other IDEs
    local command = string.format(
      "clion --project %s --line %d --column %d %s",
      vim.fn.shellescape(project_root),
      line_number,
      column_number,
      vim.fn.shellescape(file_path)
    )

    -- Execute the command
    vim.fn.jobstart(command, {
      detach = true,
      on_stderr = function(_, data)
        if data and #data > 1 then
          vim.notify("Error opening CLion: " .. vim.inspect(data), vim.log.levels.ERROR)
        end
      end,
    })

    vim.notify("Opening file in CLion...", vim.log.levels.INFO)
  end, {})

  vim.keymap.set("n", "<A-S-c>", ":DiffviewOpen HEAD^<CR>", { desc = "Open diffview against previous commit" })

  -- Optionally, create a keybinding for the command
  vim.keymap.set("n", "<leader>ic", ":Intellij<CR>", { noremap = true, silent = true, desc = "Open in CLion" })

  vim.keymap.set("n", "<leader>np", ":NoNeckPain<CR>", { noremap = true, silent = true, desc = "No neck pain toggle" })

  -- Dont resize terminals vertically.
  vim.api.nvim_create_autocmd("TermOpen", {
    pattern = "*",
    callback = function()
      vim.api.nvim_set_option_value("winfixwidth", true, {})
      vim.api.nvim_set_option_value("winfixheight", true, {})
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

  -- Automatically resize window on display change
  vim.api.nvim_create_autocmd("VimResized", {
    pattern = "*",
    callback = function()
      -- Close nvim tree and vertical terminals to avoid weird effects.
      local ok, nvim_tree = pcall(require, "nvim-tree.api")
      if ok and nvim_tree.tree.is_visible() then
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
            local is_vertical = win_height >= win_width-30
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

  -- Automatically trigger reisze of windows when nvimtree is opened
  local nvim_tree_events = require "nvim-tree.events"
  nvim_tree_events.subscribe(nvim_tree_events.Event.TreeOpen, function()

    -- Toggle NoNeckPain off if there are more than 2 vertical buffers and terminal in total
    -- TODO
    
    vim.cmd "wincmd ="
  end)
end

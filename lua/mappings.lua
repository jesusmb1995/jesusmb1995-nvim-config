require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- conform
if vim.env.NVIM_MINIMAL == nil then
  -- Symbol lookup telescope
  map(
    { "n" },
    "<leader>ts",
    "<cmd> Telescope lsp_dynamic_workspace_symbols <CR>",
    { desc = "Telescope workspace symbols" }
  )
  map(
    { "n" },
    "<leader>fF",
    "<cmd> Telescope find_files hidden=true<CR>",
    { desc = "Find files including hidden" }
  )
  map({ "n" }, "<leader>tS", "<cmd> Telescope lsp_workspace_symbols <CR>", { desc = "Telescope workspace symbols" })

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

  -- Git shortcuts
  map("n", "<leader>gg", ":Neogit<CR>", { desc = "Git Tab" })
  map("n", "<leader>gb", ":Neogit branch<CR>", { desc = "Git Branch" })
  map("n", "<leader>gB", ":Gitsigns blame<CR>", { desc = "Git Blame" })
  map("n", "<leader>gl", ":Neogit log<CR>", { desc = "Git Log" })
  map("n", "<leader>gz", ":Neogit stash<CR>", { desc = "Git Stash" })
  map("n", "<leader>gp", ":Neogit pull<CR>", { desc = "Git pull" })
  map("n", "<leader>gP", ":Neogit push<CR>", { desc = "Git Push" })
  map("n", "<leader>gr", ":Neogit rebase<CR>", { desc = "Git Rebase" })
  map("n", "<leader>gf", ":Neogit fetch<CR>", { desc = "Git Fetch" })
  map("n", "<leader>gwg", function()
    local git = require("neogit.lib.git")
    local worktrees = git.worktree.list()
    if not worktrees or #worktrees == 0 then
      vim.notify("No git worktrees found", vim.log.levels.WARN)
      return
    end

    local entries = {}
    for _, wt in ipairs(worktrees) do
      table.insert(entries, wt.path)
    end

    vim.ui.select(entries, { prompt = "Select git worktree to cd:" }, function(choice)
      if choice then
        vim.cmd("cd " .. vim.fn.fnameescape(choice))
        vim.notify("Changed directory to: " .. choice, vim.log.levels.INFO)
      end
    end)
  end, { desc = "Select and cd to Git Worktree" })

  map("n", "<leader>X", ":tabclose | bdelete<CR>", { desc = "Close current tab and its buffers" })

  map("n", "<leader>B", ":tabnew %<CR>", { desc = "Open current buffer window in new tab" })
  map("n", "<leader>T", ":tabnew<CR>", { desc = "Open new tab" })

  -- cursor
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

  vim.keymap.set("n", "<leader>gd", ":DiffviewOpen HEAD^<CR>", { desc = "Open diffview against previous commit" })

  vim.keymap.set("n", "<leader>gcr", ":GitConflictRefresh<CR>",  { desc = "Activate git conflict plugin" } )
  vim.keymap.set("n", "<leader>gcl", ":GitConflictListQf<CR>",  { desc = "Show git conflict list" } )
  vim.keymap.set("n", "<leader>gcl", ":GitConflictListQf<CR>",  { desc = "Show git conflict list" } )
  vim.keymap.set("n", "<leader>gco", ":GitConflictChooseOurs<CR>",  { desc = "Resolve conflict choosing current/ours" } )
  vim.keymap.set("n", "<leader>gcb", ":GitConflictChooseBoth<CR>",  { desc = "Resolve conflict choosing both" } )
  vim.keymap.set("n", "<leader>gcn", ":GitConflictChooseNone<CR>",  { desc = "Resolve conflict choosing none" } )
  vim.keymap.set("n", "<leader>gct", ":GitConflictChooseTheirs<CR>",  { desc = "Resolve conflict choosing  incoming/theirs" } )

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

  -- Automatically trigger reisze of windows when nvimtree is opened
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

local _conform = require "conform"
local _linter = require "lint"
local current_formatter = {}
local current_linter = {}

local function cycle_formatter(use)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local formatters = _conform.formatters_by_ft[filetype] or {}

  if #formatters == 0 then
    vim.notify("No formatters configured for " .. filetype, vim.log.levels.WARN)
    return
  end

  -- Initialize or increment the current formatter index
  if use then
    current_formatter[filetype] = (current_formatter[filetype] or 0) % #formatters
  else
    current_formatter[filetype] = (current_formatter[filetype] or 0) % #formatters + 1
  end
  local formatter = formatters[current_formatter[filetype]]

  if use then
    if formatter == "standardjs" then
      local filename = vim.api.nvim_buf_get_name(bufnr)
      vim.notify("Fixing " .. filename, vim.log.levels.INFO)
      vim.fn.system("standard --fix " .. vim.fn.shellescape(filename))
      vim.cmd("e " .. filename)
      return
    end
    _conform.format {
      lsp_fallback = true,
      async = false,
      timeout_ms = 5000,
      formatters = { formatter },
      { bufnr = bufnr },
    }
  else
    vim.notify("Set formatter to " .. formatter, vim.log.levels.INFO)
  end
end

local function cycle_linter(use)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local linters = _linter.linters_by_ft[filetype] or {}

  if #linters == 0 then
    vim.notify("No linters configured for " .. filetype, vim.log.levels.WARN)
    return
  end

  -- Initialize or increment the current linter index
  if use then
    current_linter[filetype] = (current_linter[filetype] or 0) % #linters
  else
    current_linter[filetype] = (current_linter[filetype] or 0) % #linters + 1
  end
  local linter = linters[current_linter[filetype]]

  if use then
    _linter.try_lint(linter)
  else
    vim.notify("Set linter to " .. linter, vim.log.levels.INFO)
  end
end

-- Create a user command
vim.api.nvim_create_user_command("CycleFormatter", function()
  cycle_formatter(false)
end, {})
vim.api.nvim_create_user_command("CycleLinter", function()
  cycle_linter(false)
end, {})

map({ "n", "v" }, "<leader>F", function()
  cycle_formatter(true)
end, { desc = "Format file or range (in visual mode)" })

vim.keymap.set("n", "<leader>l", function()
  cycle_linter(true)
end, { desc = "Trigger linting for current file" })

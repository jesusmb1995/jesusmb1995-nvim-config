local map = vim.keymap.set

-- cursor
map("n", "<leader><C-S-l>", function()
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

-- Optionally, create a keybinding for the command
vim.keymap.set("n", "<leader>ic", ":Intellij<CR>", { noremap = true, silent = true, desc = "Open in CLion" })

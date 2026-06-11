local map = vim.keymap.set

-- Symbol lookup telescope
map(
  { "n" },
  "<leader>ts",
  "<cmd> Telescope lsp_dynamic_workspace_symbols <CR>",
  { desc = "Telescope workspace symbols" }
)
local function is_hidden_path(path)
  for part in (path or ""):gmatch("[^/]+") do
    if part:sub(1, 1) == "." then
      return true
    end
  end
  return false
end

local function recent_files_picker(include_hidden)
  local ok_pickers, pickers = pcall(require, "telescope.pickers")
  local ok_finders, finders = pcall(require, "telescope.finders")
  local ok_config, telescope_config = pcall(require, "telescope.config")
  local ok_sorts, sorters = pcall(require, "telescope.sorters")
  local ok_actions, actions = pcall(require, "telescope.actions")
  local ok_state, action_state = pcall(require, "telescope.actions.state")
  if not (ok_pickers and ok_finders and ok_config and ok_sorts and ok_actions and ok_state) then
    vim.notify("Telescope is not available", vim.log.levels.WARN)
    return
  end

  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local function list_project_files()
    local cmd
    if include_hidden then
      cmd = "fd --type f --hidden --no-ignore --exclude .git . " .. vim.fn.shellescape(cwd) .. " 2>/dev/null"
    else
      cmd = "fd --type f --exclude .git . " .. vim.fn.shellescape(cwd) .. " 2>/dev/null"
    end
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 then
      local rg_cmd
      if include_hidden then
        rg_cmd = "rg --files --hidden --no-ignore --glob '!.git' " .. vim.fn.shellescape(cwd) .. " 2>/dev/null"
      else
        rg_cmd = "rg --files --glob '!.git' " .. vim.fn.shellescape(cwd) .. " 2>/dev/null"
      end
      out = vim.fn.systemlist(rg_cmd)
    end
    local paths = {}
    for _, item in ipairs(out or {}) do
      local full = item
      if type(item) == "string" and item ~= "" and item:sub(1, 1) ~= "/" then
        full = cwd .. "/" .. item
      end
      full = vim.fs.normalize(vim.fn.expand(full))
      if vim.fn.filereadable(full) == 1 then
        table.insert(paths, full)
      end
    end
    return paths
  end

  local seen = {}
  local files = {}
  for _, file in ipairs(vim.v.oldfiles or {}) do
    if type(file) == "string" and file ~= "" then
      local path = vim.fs.normalize(vim.fn.expand(file))
      local in_cwd = path == cwd or path:sub(1, #cwd + 1) == (cwd .. "/")
      if vim.fn.filereadable(path) == 1 and in_cwd and not seen[path] then
        local rel = vim.fn.fnamemodify(path, ":.")
        if include_hidden or not is_hidden_path(rel) then
          seen[path] = true
          table.insert(files, path)
        end
      end
    end
  end

  for _, file in ipairs(list_project_files()) do
    if not seen[file] then
      local rel = vim.fn.fnamemodify(file, ":.")
      if include_hidden or not is_hidden_path(rel) then
        seen[file] = true
        table.insert(files, file)
      end
    end
  end

  if #files == 0 then
    vim.notify("No files found in current workspace", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = include_hidden
        and "Files (MRU first + all project files, hidden included)"
      or "Files (MRU first + all project files)",
    finder = finders.new_table({
      results = files,
      entry_maker = function(path)
        return {
          value = path,
          ordinal = path,
          display = vim.fn.fnamemodify(path, ":~:."),
        }
      end,
    }),
    sorter = telescope_config.values.generic_sorter({}),
    previewer = telescope_config.values.file_previewer({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          vim.cmd("edit " .. vim.fn.fnameescape(selection.value))
        end
      end)
      return true
    end,
  }):find()
end

map({ "n" }, "<leader>ff", function() recent_files_picker(false) end, { desc = "Recent files (MRU first)" })
map({ "n" }, "<leader>fF", function() recent_files_picker(true) end, { desc = "Recent files (MRU + hidden)" })
map({ "n" }, "<leader>tS", "<cmd> Telescope lsp_workspace_symbols <CR>", { desc = "Telescope workspace symbols" })

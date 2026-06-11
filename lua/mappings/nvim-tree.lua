local map = vim.keymap.set

map({ "n" }, "<leader>tm", function()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    vim.notify("nvim-tree API not available", vim.log.levels.WARN)
    return
  end
  if api.tree and api.tree.toggle_git_clean_filter then
    api.tree.toggle_git_clean_filter()
    return
  end
  vim.notify("toggle_git_clean_filter is not supported by your nvim-tree version", vim.log.levels.WARN)
end, { desc = "NvimTree toggle modified-files filter" })
do
  local upstream_filter = nil -- holds { files = {}, dirs = {} } when active

  local function apply_upstream_filter()
    if not upstream_filter then return end
    local explorer = require("nvim-tree.core").get_explorer()
    if not explorer then return end
    explorer.filters.custom_function = function(absolute_path)
      if upstream_filter.dirs[absolute_path] then return false end
      if upstream_filter.files[absolute_path] then return false end
      return true
    end
    if not explorer.filters.state.custom then
      explorer.filters.state.custom = true
    end
    explorer:reload_explorer()
  end

  map({ "n" }, "<leader>tM", function()
    local api = require("nvim-tree.api")

    if upstream_filter then
      upstream_filter = nil
      api.tree.close()
      api.tree.open()
      vim.notify("upstream/main filter OFF", vim.log.levels.INFO)
      return
    end

    local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
    if vim.v.shell_error ~= 0 or not git_root then
      vim.notify("Not inside a git repository", vim.log.levels.WARN)
      return
    end
    git_root = git_root:gsub("/$", "")

    local diff_output = vim.fn.systemlist("git diff --name-only upstream/main..HEAD")
    if vim.v.shell_error ~= 0 or #diff_output == 0 then
      vim.notify("No files modified since upstream/main..HEAD", vim.log.levels.INFO)
      return
    end

    local allowed_files = {}
    local allowed_dirs = {}
    for _, rel in ipairs(diff_output) do
      local abs = git_root .. "/" .. rel
      allowed_files[abs] = true
      local dir = vim.fn.fnamemodify(abs, ":h")
      while #dir >= #git_root do
        if allowed_dirs[dir] then break end
        allowed_dirs[dir] = true
        dir = vim.fn.fnamemodify(dir, ":h")
      end
    end

    upstream_filter = { files = allowed_files, dirs = allowed_dirs }
    api.tree.close()
    api.tree.open()
    vim.defer_fn(apply_upstream_filter, 50)
    vim.notify("upstream/main filter ON (" .. #diff_output .. " files)", vim.log.levels.INFO)
  end, { desc = "NvimTree toggle upstream/main modified filter" })
end

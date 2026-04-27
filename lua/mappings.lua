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
  map("n", "<leader>gP", function()
    local root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if vim.v.shell_error ~= 0 or not root or root == "" then
      vim.notify("Not inside a git repository", vim.log.levels.ERROR)
      return
    end

    local git = "git -C " .. vim.fn.shellescape(root) .. " "
    local branch = vim.fn.systemlist(git .. "branch --show-current 2>/dev/null")[1]
    if vim.v.shell_error ~= 0 or not branch or branch == "" then
      vim.cmd "Neogit push"
      return
    end

    local upstream = vim.fn.systemlist(git .. "rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null")[1]
    if vim.v.shell_error ~= 0 or not upstream or upstream == "" then
      vim.cmd "Neogit push"
      return
    end

    local upstream_branch = upstream:match("^[^/]+/(.+)$") or upstream
    if upstream_branch == branch then
      vim.cmd "Neogit push"
      return
    end

    vim.ui.select({
      "Unset upstream, then push",
      "Push without changing upstream",
      "Cancel",
    }, {
      prompt = ("Upstream is %s, current branch is %s"):format(upstream, branch),
    }, function(choice)
      if choice == "Unset upstream, then push" then
        vim.fn.system(git .. "branch --unset-upstream 2>/dev/null")
        if vim.v.shell_error ~= 0 then
          vim.notify("Failed to unset upstream", vim.log.levels.ERROR)
          return
        end

        vim.notify("Unset upstream for " .. branch, vim.log.levels.INFO)
        vim.cmd "Neogit push"
      elseif choice == "Push without changing upstream" then
        vim.cmd "Neogit push"
      end
    end)
  end, { desc = "Git Push" })
  map("n", "<leader>gr", ":Neogit rebase<CR>", { desc = "Git Rebase" })
  map("n", "<leader>grb", function()
    local root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
    if vim.v.shell_error ~= 0 or not root then
      vim.notify("Not inside a git repository", vim.log.levels.ERROR)
      return
    end

    vim.fn.system("git rev-parse --verify upstream/main 2>/dev/null")
    if vim.v.shell_error ~= 0 then
      vim.notify("upstream/main does not exist", vim.log.levels.ERROR)
      return
    end

    local stg_path = "/home/linuxbrew/.linuxbrew/bin/stg"
    local patch_count = tonumber(vim.fn.trim(vim.fn.system(stg_path .. " series --count 2>/dev/null"))) or 0
    local is_stg = patch_count > 0

    if is_stg then
      local cmd = stg_path .. " rebase upstream/main"
      vim.notify("Running: stg rebase upstream/main", vim.log.levels.INFO)
      require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
    else
      local cmd = "git rebase upstream/main"
      vim.notify("Running: git rebase upstream/main", vim.log.levels.INFO)
      require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
    end
  end, { desc = "Rebase upstream/main (stg if stg branch, else git)" })
  map("n", "<leader>gf", ":Neogit fetch<CR>", { desc = "Git Fetch" })
  map("n", "<A-l>", function()
    local gitsigns = require("gitsigns")

    local function project_root()
      local result = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")
      if vim.v.shell_error ~= 0 or not result or #result == 0 then return nil end
      return vim.trim(result[1])
    end

    local function changed_files(root)
      local unstaged = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " diff --name-only 2>/dev/null")
      local staged = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " diff --cached --name-only 2>/dev/null")
      local seen, files = {}, {}
      for _, list in ipairs({ unstaged, staged }) do
        for _, f in ipairs(list) do
          f = vim.trim(f)
          if f ~= "" and not seen[f] then
            seen[f] = true
            table.insert(files, f)
          end
        end
      end
      table.sort(files)
      return files
    end

    local function goto_next_file_hunk()
      local root = project_root()
      if not root then return end
      local files = changed_files(root)
      if #files == 0 then return end

      local cur_file = vim.fn.expand("%:p")
      local cur_rel = ""
      if cur_file:sub(1, #root) == root then
        cur_rel = cur_file:sub(#root + 2)
      end

      local next_file = nil
      local found = false
      for _, f in ipairs(files) do
        if found then
          next_file = f
          break
        end
        if f == cur_rel then
          found = true
        end
      end
      if not next_file then
        next_file = files[1]
        if next_file == cur_rel then return end
      end

      vim.cmd("edit " .. vim.fn.fnameescape(root .. "/" .. next_file))
      vim.defer_fn(function()
        pcall(gitsigns.nav_hunk, "first")
        vim.defer_fn(function()
          vim.cmd("normal! zz")
          pcall(gitsigns.preview_hunk_inline)
        end, 100)
      end, 200)
    end

    local before = vim.api.nvim_win_get_cursor(0)
    local ok = pcall(gitsigns.nav_hunk, "next", { wrap = false })

    if not ok then
      goto_next_file_hunk()
      return
    end

    vim.defer_fn(function()
      local after = vim.api.nvim_win_get_cursor(0)
      if after[1] ~= before[1] then
        vim.cmd("normal! zz")
        pcall(gitsigns.preview_hunk_inline)
      else
        goto_next_file_hunk()
      end
    end, 50)
  end, { desc = "Next git hunk (project-wide)" })
   -- Helper: get git root (uses git CLI, no neogit internal API)
  local function git_root()
    local result = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")
    if vim.v.shell_error ~= 0 or not result or #result == 0 then
      return nil
    end
    return vim.trim(result[1])
  end

  -- Helper: list git worktree paths (uses git CLI)
  local function git_worktree_list()
    local Job = require("plenary.job")
    local cwd = git_root() or vim.fn.getcwd()
    local job = Job:new({
      command = "git",
      args = { "worktree", "list", "--porcelain" },
      cwd = cwd,
    })
    job:sync()
    local paths = {}
    for _, line in ipairs(job:result()) do
      local path = line:match("^worktree%s+(.+)$")
      if path and #path > 0 then
        table.insert(paths, vim.trim(path))
      end
    end
    return paths
  end

  -- Helper: relative path from git root to cwd (e.g. "src/components"), or "" if at root
  local function worktree_relative_subpath()
    local root = git_root()
    if not root then return "" end
    local root_norm = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
    local cwd_norm = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("/$", "")
    if cwd_norm == root_norm then
      return ""
    end
    if cwd_norm:sub(1, #root_norm + 1) == root_norm .. "/" then
      return cwd_norm:sub(#root_norm + 2)
    end
    return ""
  end

  -- Helper: choose target dir (worktree root or same relative subfolder if it exists)
  local function worktree_cd_target(worktree_dir)
    local target = worktree_dir
    local rel = worktree_relative_subpath()
    if #rel > 0 then
      local subpath = vim.fn.fnamemodify(worktree_dir, ":p"):gsub("/$", "") .. "/" .. rel
      if vim.fn.isdirectory(subpath) == 1 then
        target = subpath
      end
    end
    return target
  end

  -- Helper function: select and cd to git worktree (used by gwg and after gwc).
  -- Jumps to the same relative subfolder in the selected worktree if it exists.
  local function select_and_cd_worktree()
    local worktrees = git_worktree_list()
    if not worktrees or #worktrees == 0 then
      vim.notify("No git worktrees found", vim.log.levels.WARN)
      return
    end

    vim.ui.select(worktrees, { prompt = "Select git worktree to cd:" }, function(choice)
      if not choice then return end
      local target = worktree_cd_target(choice)
      vim.cmd("cd " .. vim.fn.fnameescape(target))
      vim.notify("Changed directory to: " .. target, vim.log.levels.INFO)
    end)
  end

  -- Opens a new nvim instance at the given directory (tmux > alacritty > error)
  -- Optional file_arg: e.g. "+42 src/foo.lua" to open a file at a specific line
  local function open_nvim_in_new_instance(dir, file_arg)
    local nvim_bin = vim.v.progpath
    local cmd = { nvim_bin }
    if file_arg then
      for _, a in ipairs(file_arg) do
        table.insert(cmd, a)
      end
    end

    local tmux_env = vim.fn.getenv("TMUX")
    if tmux_env ~= vim.NIL and tmux_env ~= "" then
      vim.fn.jobstart(vim.list_extend({ "tmux", "new-window", "-c", dir }, cmd), { detach = true })
    elseif vim.fn.executable("alacritty") == 1 then
      vim.fn.jobstart(vim.list_extend({ "alacritty", "--working-directory", dir, "-e" }, cmd), { detach = true })
    else
      vim.notify("No supported terminal found (tmux/alacritty)", vim.log.levels.ERROR)
      return
    end
    vim.notify("Opened new nvim in: " .. dir, vim.log.levels.INFO)
  end

  -- <leader>gwg: Select and cd to Git worktree
  map("n", "<leader>gwg", select_and_cd_worktree, { desc = "Select and cd to Git Worktree" })

  -- <leader>gwG: Select git worktree and open in a new nvim instance (with current file)
  map("n", "<leader>gwG", function()
    local worktrees = git_worktree_list()
    if not worktrees or #worktrees == 0 then
      vim.notify("No git worktrees found", vim.log.levels.WARN)
      return
    end

    local cur_line = vim.fn.line(".")
    local cur_file = vim.fn.expand("%:p")
    local cur_root = git_root()

    vim.ui.select(worktrees, { prompt = "Select git worktree (new nvim):" }, function(choice)
      if not choice then return end
      local target = worktree_cd_target(choice)
      local file_arg = nil
      if cur_root and cur_file ~= "" then
        local root_norm = vim.fn.fnamemodify(cur_root, ":p"):gsub("/$", "")
        local file_norm = vim.fn.fnamemodify(cur_file, ":p"):gsub("/$", "")
        if file_norm:sub(1, #root_norm + 1) == root_norm .. "/" then
          local rel = file_norm:sub(#root_norm + 2)
          local wt_root = vim.fn.fnamemodify(choice, ":p"):gsub("/$", "")
          local candidate = wt_root .. "/" .. rel
          if vim.fn.filereadable(candidate) == 1 then
            file_arg = { "+" .. cur_line, rel }
          end
        end
      end
      open_nvim_in_new_instance(target, file_arg)
    end)
  end, { desc = "Select Git Worktree → new nvim instance" })

  -- <leader>gwx: Remove all clean git worktrees (no staged/unstaged/untracked changes)
  map("n", "<leader>gwx", function()
    local worktrees = git_worktree_list()
    if not worktrees or #worktrees == 0 then
      vim.notify("No git worktrees found", vim.log.levels.WARN)
      return
    end

    local main_root = git_root()
    if main_root then
      main_root = vim.fn.fnamemodify(main_root, ":p"):gsub("/$", "")
    end

    local Job = require("plenary.job")
    local clean = {}
    local dirty = {}

    for _, wt in ipairs(worktrees) do
      local wt_norm = vim.fn.fnamemodify(wt, ":p"):gsub("/$", "")
      if wt_norm ~= main_root then
        local job = Job:new({ command = "git", args = { "-C", wt, "status", "--porcelain", "-uno" } })
        job:sync()
        if job.code == 0 and #job:result() == 0 then
          table.insert(clean, wt)
        else
          table.insert(dirty, wt)
        end
      end
    end

    if #clean == 0 then
      local msg = "No clean worktrees to remove."
      if #dirty > 0 then
        msg = msg .. " " .. #dirty .. " worktree(s) have uncommitted changes."
      end
      vim.notify(msg, vim.log.levels.INFO)
      return
    end

    local prompt = "Remove " .. #clean .. " clean worktree(s)?\n"
    for _, wt in ipairs(clean) do
      prompt = prompt .. "  - " .. wt .. "\n"
    end
    prompt = prompt .. "Confirm? [y/N]: "

    vim.ui.input({ prompt = prompt }, function(input)
      if not input or input:lower() ~= "y" then
        vim.notify("Aborted", vim.log.levels.INFO)
        return
      end
      local removed = 0
      for _, wt in ipairs(clean) do
        local job = Job:new({
          command = "git",
          args = { "worktree", "remove", wt },
          cwd = main_root,
        })
        job:sync()
        if job.code == 0 then
          removed = removed + 1
        else
          vim.notify("Failed to remove: " .. wt .. "\n" .. table.concat(job:stderr_result(), "\n"), vim.log.levels.ERROR)
        end
      end
      vim.notify("Removed " .. removed .. " clean worktree(s)", vim.log.levels.INFO)
    end)
  end, { desc = "Remove clean Git Worktrees" })

  -- <leader>gbs: Git branch spin-off with default name when under packages/<package>
  map("n", "<leader>gs", function()
    local root = git_root()
    if not root then
      vim.notify("Not inside a Git repository", vim.log.levels.ERROR)
      return
    end
    local root_norm = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
    local rel = worktree_relative_subpath()
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path and buf_path ~= "" then
      local full = vim.fn.fnamemodify(buf_path, ":p"):gsub("/$", "")
      if full:sub(1, #root_norm + 1) == root_norm .. "/" then
        rel = full:sub(#root_norm + 2)
      end
    end
    local pkg = rel and rel:match("^packages/([^/]+)") or nil
    local default = "feature-qvac-lib-inference-" .. (pkg or "")
    vim.ui.input({
      prompt = "Branch name (spin-off): ",
      default = default,
    }, function(name)
      if not name or name == "" then return end
      local Job = require("plenary.job")
      local job = Job:new({
        command = "git",
        args = { "checkout", "-b", name },
        cwd = root,
      })
      job:sync()
      if job.code == 0 then
        vim.notify("Created and checked out branch " .. name, vim.log.levels.INFO)
      else
        vim.notify("Git: " .. table.concat(job:stderr_result(), " "), vim.log.levels.ERROR)
      end
    end)
  end, { desc = "Git branch spin-off (default name from packages/<package>)" })

  -- <leader>gwc: Create worktree for <branch> in ../<repo-name>-<branch> if not exist, then cd to it
  map("n", "<leader>gwc", function()
    local Job = require("plenary.job")
    local notify = vim.notify

    local root = git_root()
    if not root then
      notify("Not inside a Git repository", vim.log.levels.ERROR)
      return
    end
    local repo_name = vim.fn.fnamemodify(root, ":t")

    local branches = {}
    Job:new({
      command = "git",
      args = {"branch", "--format=%(refname:short)"},
      cwd = root,
      on_exit = function(j)
        vim.schedule(function()
          local results = j:result()
          for _, branch in ipairs(results) do
            local b = vim.trim(branch)
            if #b > 0 then
              table.insert(branches, b)
            end
          end

          vim.ui.select(branches, { prompt = "Select branch to create worktree:" }, function(branch_name)
            if not branch_name then return end

            local parent_dir = vim.fn.fnamemodify(root, ":h")
            local worktree_dir = parent_dir .. "/" .. repo_name .. "-" .. branch_name

            local all_wts = git_worktree_list()
            for _, wt_path in ipairs(all_wts or {}) do
              if vim.fn.fnamemodify(wt_path, ":p") == vim.fn.fnamemodify(worktree_dir, ":p") then
                notify("Worktree already exists for branch at: " .. worktree_dir, vim.log.levels.INFO)
                local target = worktree_cd_target(worktree_dir)
                vim.cmd("cd " .. vim.fn.fnameescape(target))
                notify("Changed directory to: " .. target, vim.log.levels.INFO)
                return
              end
            end

            Job:new({
              command = "git",
              args = {"worktree", "add", worktree_dir, branch_name},
              cwd = root,
              on_exit = function(j2, return_val)
                vim.schedule(function()
                  if return_val == 0 then
                    notify("Worktree created: " .. worktree_dir, vim.log.levels.INFO)
                    local target = worktree_cd_target(worktree_dir)
                    vim.cmd("cd " .. vim.fn.fnameescape(target))
                    notify("Changed directory to: " .. target, vim.log.levels.INFO)
                  else
                    notify("Error creating worktree: " .. table.concat(j2:stderr_result(), " "), vim.log.levels.ERROR)
                  end
                end)
              end,
            }):start()
          end)
        end)
      end,
    }):start()
  end, { desc = "Create worktree for selected branch in ../<repo-name>-<branchname> and cd to it" })

  -- <leader>gwC: Create worktree for <branch> and open in a new nvim instance
  map("n", "<leader>gwC", function()
    local Job = require("plenary.job")
    local notify = vim.notify

    local root = git_root()
    if not root then
      notify("Not inside a Git repository", vim.log.levels.ERROR)
      return
    end
    local repo_name = vim.fn.fnamemodify(root, ":t")

    local branches = {}
    Job:new({
      command = "git",
      args = { "branch", "--format=%(refname:short)" },
      cwd = root,
      on_exit = function(j)
        vim.schedule(function()
          local results = j:result()
          for _, branch in ipairs(results) do
            local b = vim.trim(branch)
            if #b > 0 then
              table.insert(branches, b)
            end
          end

          vim.ui.select(branches, { prompt = "Select branch to create worktree (new nvim):" }, function(branch_name)
            if not branch_name then return end

            local parent_dir = vim.fn.fnamemodify(root, ":h")
            local worktree_dir = parent_dir .. "/" .. repo_name .. "-" .. branch_name

            local all_wts = git_worktree_list()
            for _, wt_path in ipairs(all_wts or {}) do
              if vim.fn.fnamemodify(wt_path, ":p") == vim.fn.fnamemodify(worktree_dir, ":p") then
                notify("Worktree already exists at: " .. worktree_dir, vim.log.levels.INFO)
                local target = worktree_cd_target(worktree_dir)
                open_nvim_in_new_instance(target)
                return
              end
            end

            Job:new({
              command = "git",
              args = { "worktree", "add", worktree_dir, branch_name },
              cwd = root,
              on_exit = function(j2, return_val)
                vim.schedule(function()
                  if return_val == 0 then
                    notify("Worktree created: " .. worktree_dir, vim.log.levels.INFO)
                    local target = worktree_cd_target(worktree_dir)
                    open_nvim_in_new_instance(target)
                  else
                    notify("Error creating worktree: " .. table.concat(j2:stderr_result(), " "), vim.log.levels.ERROR)
                  end
                end)
              end,
            }):start()
          end)
        end)
      end,
    }):start()
  end, { desc = "Create worktree for branch → new nvim instance" })

  -- CTest / GTest picker: find build dir, list ctest tests + gtest suites/cases,
  -- show in Telescope, save selected command to .local_cmd_bookmarks and run it.
  -- <C-f> in prompt: use typed text as *text* gtest wildcard on highlighted item's binary.
  -- TODO: Make it a plugin, even integrate well into telescope (e.g. for tests only on current file)
  local function ctest_gtest_picker(term_pos, term_id)
    -- Search upward from cwd for a directory containing CTestTestfile.cmake.
    local function find_build_dir()
      local cwd = vim.fn.getcwd()
      local build_names = { "build", "Build", "_build", "cmake-build-debug", "cmake-build-release" }

      local function has_ctest(dir)
        return vim.fn.filereadable(dir .. "/CTestTestfile.cmake") == 1
      end

      -- Check cwd and common subdirs first
      if has_ctest(cwd) then return cwd end
      for _, bd in ipairs(build_names) do
        if has_ctest(cwd .. "/" .. bd) then return cwd .. "/" .. bd end
      end

      -- Walk up to git root and repeat
      local git_root_lines = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")
      if vim.v.shell_error == 0 and git_root_lines and #git_root_lines > 0 then
        local root = vim.trim(git_root_lines[1])
        if root ~= cwd then
          if has_ctest(root) then return root end
          for _, bd in ipairs(build_names) do
            if has_ctest(root .. "/" .. bd) then return root .. "/" .. bd end
          end
        end
      end
      return nil
    end

    -- Parse `binary --gtest_list_tests` output.
    -- Returns { [suite_name] = { "TestA", "TestB", ... }, ... }
    local function parse_gtest_list(binary)
      if vim.fn.executable(binary) ~= 1 then return nil end
      local out = vim.fn.systemlist(vim.fn.shellescape(binary) .. " --gtest_list_tests 2>/dev/null")
      if vim.v.shell_error ~= 0 or not out then return nil end
      local suites = {}
      local cur = nil
      for _, line in ipairs(out) do
        -- Suite header: "SuiteName." or "Inst/SuiteName." (parameterised/typed tests)
        local suite = line:match("^(%w[%w_:/]*%.)")
        if suite and not line:match("^%s") then
          cur = suite:sub(1, -2) -- strip trailing dot
          suites[cur] = suites[cur] or {}
        elseif cur and line:match("^%s+%S") then
          local t = line:match("^%s+(%S+)")
          if t then
            t = t:gsub("/%d+$", "") -- strip parameterised suffix /0 /1 ...
            -- deduplicate
            local dup = false
            for _, existing in ipairs(suites[cur]) do
              if existing == t then dup = true; break end
            end
            if not dup then table.insert(suites[cur], t) end
          end
        end
      end
      return suites
    end

    -- Collect picker items synchronously (gtest_list_tests is instant).
    local build_dir = find_build_dir()
    if not build_dir then
      vim.notify("CTest: no build directory found (CTestTestfile.cmake missing)", vim.log.levels.WARN)
      return
    end

    local raw = vim.fn.system("ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --show-only=json-v1 2>/dev/null")
    local ok, info = pcall(vim.fn.json_decode, raw)
    if not ok or not info or not info.tests or #info.tests == 0 then
      vim.notify("CTest: no tests found in " .. build_dir, vim.log.levels.WARN)
      return
    end

    local items = {}

    -- item: { display, name, command, binary?, working_dir? }
    -- binary + working_dir are stored so <C-f> can build ad-hoc filter commands.
    local function add(display, name, cmd, binary, working_dir)
      table.insert(items, { display = display, name = name, command = cmd,
                             binary = binary, working_dir = working_dir })
    end

    -- Build a direct binary command: "cd <wdir> && <binary> [--gtest_filter=<f>]"
    local function make_bin_cmd(binary, working_dir, filter)
      local prefix = working_dir and ("cd " .. vim.fn.shellescape(working_dir) .. " && ") or ""
      local suffix = filter and (" --gtest_filter=" .. vim.fn.shellescape(filter)) or ""
      return prefix .. binary .. suffix
    end

    -- [ALL]: must use ctest since there may be multiple binaries
    add("[ALL] Run all ctest tests", "ctest: all",
      "ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --output-on-failure")

    for _, test in ipairs(info.tests) do
      local cname  = test.name
      local binary = test.command and test.command[1]

      local wdir = nil
      for _, prop in ipairs(test.properties or {}) do
        if prop.name == "WORKING_DIRECTORY" then wdir = prop.value; break end
      end

      local suites = binary and parse_gtest_list(binary)
      if suites then
        -- Run all gtest tests in this binary (no filter)
        add("[CTEST] " .. cname, "ctest: " .. cname,
          make_bin_cmd(binary, wdir, nil), binary, wdir)

        local suite_names = vim.tbl_keys(suites)
        table.sort(suite_names)
        for _, suite in ipairs(suite_names) do
          add("  [SUITE] " .. suite,
            "ctest: " .. cname .. " / suite: " .. suite,
            make_bin_cmd(binary, wdir, suite .. ".*"), binary, wdir)

          local tests = suites[suite]
          table.sort(tests)
          for _, tname in ipairs(tests) do
            add("    [TEST] " .. suite .. "." .. tname,
              "ctest: " .. cname .. " / " .. suite .. "." .. tname,
              make_bin_cmd(binary, wdir, suite .. "." .. tname), binary, wdir)
          end
        end
      else
        -- No gtest binary — fall back to plain ctest
        local ctest_r = " -R " .. vim.fn.shellescape("^" .. cname .. "$")
        add("[CTEST] " .. cname, "ctest: " .. cname,
          "ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --output-on-failure" .. ctest_r)
      end
    end

    -- ── save & run ─────────────────────────────────────────────────────────────
    local function save_and_run(item)
      local cwd   = vim.fn.getcwd()
      local bfile = cwd .. "/.local_cmd_bookmarks"
      local lines = vim.fn.filereadable(bfile) == 1 and vim.fn.readfile(bfile) or {}
      local exists = false
      for _, l in ipairs(lines) do
        if l:match("^([^|]+)|") == item.name then exists = true; break end
      end
      if not exists then
        table.insert(lines, item.name .. "|" .. item.command)
        if vim.fn.writefile(lines, bfile) ~= 0 then
          vim.notify("CTest picker: failed to write " .. bfile, vim.log.levels.ERROR)
        end
      end
      require("nvchad.term").runner { pos = term_pos, cmd = item.command, id = term_id, clear_cmd = false }
      vim.notify("Running: " .. item.command, vim.log.levels.INFO)
    end

    -- ── telescope picker ───────────────────────────────────────────────────────
    local tel_ok = pcall(require, "telescope")
    if tel_ok then
      require("telescope.pickers").new({}, {
        prompt_title = "CTest / GTest  [" .. build_dir .. "]  (<C-f> = custom filter)",
        finder = require("telescope.finders").new_table({
          results = items,
          entry_maker = function(e)
            return { value = e, display = e.display, ordinal = e.display }
          end,
        }),
        sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
        previewer = require("telescope.previewers").new_buffer_previewer({
          title = "Command",
          define_preview = function(self, entry)
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
              "Name:", "  " .. entry.value.name, "",
              "Command:", "  " .. entry.value.command,
            })
          end,
        }),
        attach_mappings = function(prompt_bufnr, tmap)
          local actions = require("telescope.actions")
          local state   = require("telescope.actions.state")

          -- Enter: get selection BEFORE close (close destroys picker state)
          actions.select_default:replace(function()
            local sel = state.get_selected_entry()
            actions.close(prompt_bufnr)
            if sel then save_and_run(sel.value) end
          end)

          -- <C-f>: treat prompt text as *text* gtest wildcard on highlighted binary
          tmap("i", "<C-f>", function()
            local prompt_text = state.get_current_line()
            local sel         = state.get_selected_entry()
            actions.close(prompt_bufnr)
            if not prompt_text or prompt_text == "" then
              vim.notify("CTest picker: type a filter pattern before pressing <C-f>", vim.log.levels.WARN)
              return
            end
            local binary = sel and sel.value and sel.value.binary
            if not binary then
              vim.notify("CTest picker: highlighted entry has no gtest binary", vim.log.levels.WARN)
              return
            end
            local filter = "*" .. prompt_text .. "*"
            save_and_run({
              name    = "gtest filter: " .. filter,
              command = make_bin_cmd(binary, sel.value.working_dir, filter),
              binary  = binary, working_dir = sel.value.working_dir,
            })
          end)

          return true
        end,
      }):find()
    else
      vim.ui.select(items, {
        prompt = "Select CTest / GTest test to run:",
        format_item = function(i) return i.display end,
      }, function(choice)
        if choice then save_and_run(choice) end
      end)
    end
  end

  map("n", "<leader><A-H>", function()
    ctest_gtest_picker("sp", "htoggleTerm")
  end, { desc = "CTest / GTest picker — horizontal terminal" })

  map("n", "<leader><A-V>", function()
    ctest_gtest_picker("vsp", "vtoggleTerm")
  end, { desc = "CTest / GTest picker — vertical right terminal" })

  map("n", "<leader>X", ":tabclose | bdelete<CR>", { desc = "Close current tab and its buffers" })

  map("n", "<leader>B", ":tabnew %<CR>", { desc = "Open current buffer window in new tab" })
  map("n", "<leader>T", ":tabnew<CR>", { desc = "Open new tab" })

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

  local function find_agent_term()
    for _, opts in pairs(vim.g.nvchad_terms or {}) do
      if opts and opts.id == "agentTerm" then
        return opts
      end
    end
    return nil
  end

  local function in_agent_term()
    local term = find_agent_term()
    return term ~= nil and term.buf == vim.api.nvim_get_current_buf()
  end

  local function ensure_is_agent_marker()
    local marker = vim.fn.getcwd() .. "/.was_agent"
    if vim.fn.filereadable(marker) == 0 then
      local f = io.open(marker, "w")
      if f then f:close() end
      _G.register_warm_workspace()
    end
  end

  local function open_or_focus_agent_term()
    ensure_is_agent_marker()
    local term = find_agent_term()
    if term and vim.api.nvim_buf_is_valid(term.buf) then
      local win_id = vim.fn.bufwinid(term.buf)
      if win_id ~= -1 then
        vim.api.nvim_set_current_win(win_id)
        vim.cmd "startinsert"
      else
        require("nvchad.term").toggle { pos = "vsp", id = "agentTerm" }
      end
    else
      local root = vim.fn.shellescape(vim.fn.getcwd())
      local hash = vim.fn.system("printf '%s' " .. root .. " | md5sum | cut -c1-8"):gsub("%s+", "")
      local session = "agent@" .. hash
      vim.fn.system("tmux has-session -t " .. session .. " 2>/dev/null")
      local cmd
      if vim.v.shell_error == 0 then
        cmd = "env -u TMUX tmux attach -t " .. session
      else
        cmd = "agent"
      end
      require("nvchad.term").toggle { pos = "vsp", cmd = cmd, id = "agentTerm" }
    end
  end

  local function send_to_agent(text)
    open_or_focus_agent_term()
    vim.schedule(function()
      local term = find_agent_term()
      if term and term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        local job_id = vim.b[term.buf].terminal_job_id
        if job_id then
          vim.api.nvim_chan_send(job_id, text)
        end
      end
    end)
  end

  map("n", "<leader><C-l>", open_or_focus_agent_term, { desc = "Open/focus agent terminal" })

  -- NOTE: <leader><C-l> removed from terminal mode because leader=<Space>
  -- caused input delay. Use <C-x> to exit terminal mode, then <leader><C-l>.

  map("t", "<C-l>", function()
    if in_agent_term() then
      require("nvchad.term").toggle { pos = "vsp", cmd = "agent", id = "agentTerm" }
    end
  end, { desc = "Close agent terminal from inside" })

  map("v", "<C-l>", function()
    local start_line = vim.fn.line "v"
    local end_line = vim.fn.line "."
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    local file = vim.fn.expand "%:."
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    send_to_agent("@" .. file .. ":" .. start_line .. "-" .. end_line .. " ")
  end, { desc = "Send file section reference to agent terminal" })

  map("n", "<C-S-l>", function()
    local file = vim.fn.expand "%:."
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    send_to_agent("@" .. file .. " ")
  end, { desc = "Send file reference to agent terminal" })

  map("t", "<C-n>", function()
    if not in_agent_term() then
      return vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "n", false)
    end
    local chan = vim.b.terminal_job_id
    if chan then
      vim.fn.chansend(chan, "/clear")
    end
  end, { desc = "Clear agent conversation (new chat)" })

  map("n", "<C-x>", "<Nop>")
  map("n", "<C-a>", "<Nop>")

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

  -- Diffview: resolve rev from current buffer's worktree so worktrees show the right diff
  local function git_root_for_buffer()
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path == "" or buf_path == nil then return nil end
    local buf_dir = vim.fn.fnamemodify(buf_path, ":h")
    if buf_dir == "" or vim.fn.isdirectory(buf_dir) ~= 1 then return nil end
    local out = vim.fn.systemlist("git -C " .. vim.fn.shellescape(buf_dir) .. " rev-parse --show-toplevel 2>/dev/null")
    if vim.v.shell_error ~= 0 or not out or #out == 0 then return nil end
    return vim.trim(out[1])
  end
  vim.keymap.set("n", "<leader>gd", function()
    local root = git_root_for_buffer()
    if root and #root > 0 then
      local rev = vim.fn.trim(vim.fn.system("git -C " .. vim.fn.shellescape(root) .. " rev-parse HEAD^ 2>/dev/null"))
      if vim.v.shell_error == 0 and #rev > 0 then
        vim.cmd("DiffviewOpen " .. vim.fn.escape(rev, " "))
        return
      end
    end
    vim.cmd("DiffviewOpen HEAD^")
  end, { desc = "Open diffview against previous commit" })
  vim.keymap.set("n", "<leader>gD", function()
    local root = git_root_for_buffer()
    local prev_cwd = vim.fn.getcwd()
    if root and #root > 0 then vim.cmd("cd " .. vim.fn.fnameescape(root)) end
    vim.cmd("DiffviewOpen upstream/main")
    if root and #root > 0 then vim.cmd("cd " .. vim.fn.fnameescape(prev_cwd)) end
  end, { desc = "Open diffview against main branch" })

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

-- Resize panel width with Ctrl+Alt+Shift+Arrows
map("n", "<C-A-S-Right>", ":vertical resize +5<CR>", { desc = "Increase window width", silent = true })
map("n", "<C-A-S-Left>", ":vertical resize -5<CR>", { desc = "Decrease window width", silent = true })

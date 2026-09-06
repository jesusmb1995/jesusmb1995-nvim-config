local map = vim.keymap.set

-- jj root for the CURRENT BUFFER's repo (not global cwd: async select/input
-- callbacks fire after cwd may have moved, and global cwd may never have been
-- the repo — same "not a repo" class of bug as jj.lua mappings).
local function gw_jj_root()
  local buf_dir = vim.fn.expand("%:p:h")
  if buf_dir ~= "" then
    local out = vim.fn.system({ "sh", "-c", "cd " .. vim.fn.shellescape(buf_dir) .. " && jj root 2>/dev/null" })
    if vim.v.shell_error == 0 and vim.trim(out) ~= "" then return vim.trim(out) end
  end
  return vim.fn.getcwd()
end

local function is_jj_repo()
  local buf_dir = vim.fn.expand("%:p:h")
  if buf_dir ~= "" then
    local out = vim.fn.system({ "sh", "-c", "cd " .. vim.fn.shellescape(buf_dir) .. " && jj root 2>/dev/null" })
    if vim.v.shell_error == 0 and vim.trim(out) ~= "" then return true end
  end
  local out2 = vim.fn.system({ "sh", "-c", "jj root 2>/dev/null" })
  return vim.v.shell_error == 0 and vim.trim(out2) ~= ""
end

-- Pin cwd to root for fn, then restore. Wrap every vim.ui callback body in jj
-- branches: pickers return after cwd moved on.
local function gw_in_root(root, fn)
  local prev = vim.fn.getcwd()
  vim.fn.chdir(root)
  local ok, err = pcall(fn)
  vim.fn.chdir(prev)
  if not ok then vim.notify("workspace action failed: " .. tostring(err), vim.log.levels.ERROR) end
end

local function norm_dir(p)
  local ok, r = pcall(vim.fn.resolve, p)
  if ok and r and r ~= "" then return (r:gsub("/$", "")) end
  return (vim.fn.fnamemodify(p, ":p"):gsub("/$", ""))
end

-- `jj workspace list` scoped to the current tab: entries carry name, path
-- (first token after "name:" — the rest is change/desc junk), a name-first
-- label, and a `current` flag for the workspace matching the tab cwd.
-- Status lines without "name:" are skipped. The list itself is already scoped
-- to the current repo (jj), so other repos' workspaces never show up.
local function jj_workspace_list_scoped(root)
  local tab_cwd = vim.fn.getcwd()
  local jj_root = root or gw_jj_root()
  local prev = vim.fn.getcwd()
  vim.fn.chdir(jj_root)
  local out = vim.fn.system({ "sh", "-c", "jj workspace list 2>/dev/null" })
  local ok = vim.v.shell_error == 0
  vim.fn.chdir(prev)
  if not ok then return {}, jj_root end
  local list = {}
  local cur_norm = norm_dir(tab_cwd)
  for _, line in ipairs(vim.split(vim.trim(out), "\n")) do
    line = vim.trim(line)
    if line ~= "" then
      local name, rest = line:match("^(%S+):%s*(.+)$")
      if name and rest then
        local p = rest:match("^(%S+)")
        if p then
          local abs = p:sub(1, 1) == "/" and p or (jj_root .. "/" .. p)
          local is_cur = norm_dir(abs) == cur_norm
          table.insert(list, {
            name = name,
            path = p,
            current = is_cur,
            label = (is_cur and "* " or "  ") .. name .. " → " .. p,
          })
        end
      end
    end
  end
  return list, jj_root
end

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

-- <leader>gwg: Select and cd to Git worktree (JJ workspace when jj repo)
map("n", "<leader>gwg", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local list = jj_workspace_list_scoped()
    if #list > 0 then
      vim.ui.select(list, { prompt = "Select jj workspace (new tab, * = current):", format_item = function(i) return i.label end }, function(c)
        if not c then return end
        gw_in_root(gw_root, function()
          local dir = c.path:sub(1, 1) == "/" and c.path or (gw_root .. "/" .. c.path)
          vim.cmd("tabnew")
          vim.cmd("tcd " .. vim.fn.fnameescape(dir))
          vim.notify("Tab → [" .. c.name .. "] " .. dir, vim.log.levels.INFO)
        end)
      end)
      return
    end
    vim.notify("No jj workspaces", vim.log.levels.WARN)
    return
  end
  -- git path: new tab as well (was cd-in-place)
  local worktrees = git_worktree_list()
  if not worktrees or #worktrees == 0 then
    vim.notify("No git worktrees found", vim.log.levels.WARN)
    return
  end
  vim.ui.select(worktrees, { prompt = "Select git worktree (new tab):" }, function(choice)
    if not choice then return end
    vim.cmd("tabnew")
    vim.cmd("tcd " .. vim.fn.fnameescape(worktree_cd_target(choice)))
    vim.notify("Tab → " .. choice, vim.log.levels.INFO)
  end)
end, { desc = "Select Git Worktree / JJ workspace (new tab)" })

-- <leader>gwG: Select git worktree and open in new tab (JJ workspace when jj)
map("n", "<leader>gwG", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local list = jj_workspace_list_scoped()
    if #list > 0 then
      vim.ui.select(list, { prompt = "Select jj workspace (new tab, * = current):", format_item = function(i) return i.label end }, function(c)
        if not c then return end
        gw_in_root(gw_root, function()
          local dir = c.path:sub(1, 1) == "/" and c.path or (gw_root .. "/" .. c.path)
          vim.cmd("tabnew")
          vim.cmd("tcd " .. vim.fn.fnameescape(dir))
          vim.notify("Tab → [" .. c.name .. "] " .. dir, vim.log.levels.INFO)
        end)
      end)
      return
    end
    vim.notify("No jj workspaces", vim.log.levels.WARN)
    return
  end
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

-- <leader>gwK: Create worktree for <branch> and open in new nvim instance (JJ workspace when jj)
map("n", "<leader>gwK", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    vim.ui.input({ prompt = "New jj workspace name (bookmark) for new nvim: " }, function(name)
      if not name or vim.trim(name) == "" then return end
      name = vim.trim(name)
      local parent = vim.fn.fnamemodify(gw_root, ":h")
      local worktree_dir = parent .. "/" .. vim.fn.fnamemodify(gw_root, ":t") .. "-" .. name
      vim.fn.jobstart({ "jj", "workspace", "add", "--name", name, worktree_dir }, {
      cwd = gw_root,
        cwd = gw_root,
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              local nvim_bin = vim.v.progpath
              local tmux_env = vim.fn.getenv("TMUX")
              if tmux_env ~= vim.NIL and tmux_env ~= "" then vim.fn.jobstart({ "tmux", "new-window", "-c", worktree_dir, nvim_bin }, { detach = true })
              elseif vim.fn.executable("alacritty") == 1 then vim.fn.jobstart({ "alacritty", "--working-directory", worktree_dir, "-e", nvim_bin }, { detach = true })
              else vim.notify("No supported terminal", vim.log.levels.ERROR) return end
              vim.notify("JJ workspace created and nvim opened: " .. worktree_dir, vim.log.levels.INFO)
            else vim.notify("JJ workspace add failed", vim.log.levels.ERROR) end
          end)
        end,
      })
    end)
    return
  end
  -- git fallback: same as gwC but for new nvim
  local Job = require("plenary.job")
  local notify = vim.notify
  local root = git_root()
  if not root then notify("Not inside a Git repository", vim.log.levels.ERROR) return end
  local repo_name = vim.fn.fnamemodify(root, ":t")
  local branches = {}
  Job:new({
    command = "git",
    args = { "branch", "--format=%(refname:short)" },
    cwd = root,
    on_exit = function(j)
      vim.schedule(function()
        for _, branch in ipairs(j:result()) do local b = vim.trim(branch); if #b > 0 then table.insert(branches, b) end end
        vim.ui.select(branches, { prompt = "Select branch to create worktree (new nvim):" }, function(branch_name)
          if not branch_name then return end
          local parent_dir = vim.fn.fnamemodify(root, ":h")
          local worktree_dir = parent_dir .. "/" .. repo_name .. "-" .. branch_name
          local all_wts = git_worktree_list()
          for _, wt_path in ipairs(all_wts or {}) do if vim.fn.fnamemodify(wt_path, ":p") == vim.fn.fnamemodify(worktree_dir, ":p") then notify("Worktree already exists at: " .. worktree_dir, vim.log.levels.INFO); open_nvim_in_new_instance(worktree_cd_target(worktree_dir)); return end end
          Job:new({ command = "git", args = { "worktree", "add", worktree_dir, branch_name }, cwd = root, on_exit = function(j2, return_val) vim.schedule(function() if return_val == 0 then notify("Worktree created: " .. worktree_dir, vim.log.levels.INFO); open_nvim_in_new_instance(worktree_cd_target(worktree_dir)) else notify("Error creating worktree: " .. table.concat(j2:stderr_result(), " "), vim.log.levels.ERROR) end end) end }):start()
        end)
      end)
    end,
  }):start()
end, { desc = "Create worktree for branch → new nvim instance (JJ: workspace)" })

-- <leader>gwH: Select git worktree and open in new nvim instance (JJ workspace when jj)
map("n", "<leader>gwH", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local out = vim.fn.system({ "sh", "-c", "jj workspace list 2>/dev/null" })
    if vim.v.shell_error == 0 and vim.trim(out) ~= "" then
      local list = {}
      for _, line in ipairs(vim.split(out, "\n")) do line = vim.trim(line); if line ~= "" then
        local name, rest = line:match("^(%S+):%s*(.+)$"); if name and rest then local path = rest:match("^(%S+)"); if path then table.insert(list, { label = line, path = path }) end end
      end end
      if #list > 0 then
        vim.ui.select(list, { prompt = "Select jj workspace (new nvim):", format_item = function(i) return i.label end }, function(c)
          if not c then return end
          local nvim_bin = vim.v.progpath
          local dir = c.path
          local tmux_env = vim.fn.getenv("TMUX")
          if tmux_env ~= vim.NIL and tmux_env ~= "" then vim.fn.jobstart({ "tmux", "new-window", "-c", dir, nvim_bin }, { detach = true })
          elseif vim.fn.executable("alacritty") == 1 then vim.fn.jobstart({ "alacritty", "--working-directory", dir, "-e", nvim_bin }, { detach = true })
          else vim.notify("No supported terminal", vim.log.levels.ERROR) return end
          vim.notify("Opened new nvim in: " .. dir, vim.log.levels.INFO)
        end)
        return
      end
    end
    vim.notify("No jj workspaces", vim.log.levels.WARN)
    return
  end
  local worktrees = git_worktree_list()
  if not worktrees or #worktrees == 0 then vim.notify("No git worktrees found", vim.log.levels.WARN) return end
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
        if vim.fn.filereadable(candidate) == 1 then file_arg = { "+" .. cur_line, rel } end
      end
    end
    open_nvim_in_new_instance(target, file_arg)
  end)
end, { desc = "Select Git Worktree → new nvim instance (JJ: workspace)" })

-- <leader>gwx: Remove all clean git worktrees (JJ workspace forget when jj)
map("n", "<leader>gwx", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local wslist = jj_workspace_list_scoped(gw_root)
    if #wslist == 0 then vim.notify("No jj workspaces", vim.log.levels.WARN) return end
    if #wslist <= 1 then vim.notify("No extra jj workspaces to forget (only main)", vim.log.levels.INFO) return end
    -- current workspace cannot be forgotten; mark it so it is distinguishable
    vim.ui.select(wslist, { prompt = "Forget jj workspace (clean, * = current, cannot forget):", format_item = function(i) return i.label end }, function(c)
      if not c then return end
      if c.current then vim.notify("Cannot forget current workspace [" .. c.name .. "]", vim.log.levels.WARN) return end
      vim.fn.jobstart({ "jj", "workspace", "forget", c.name }, { cwd = gw_root, on_exit = function(_, code) vim.schedule(function() if code==0 then vim.notify("Forgot jj workspace "..c.name, vim.log.levels.INFO) else vim.notify("Failed to forget "..c.name, vim.log.levels.ERROR) end end) end })
    end)
    return
  end
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

-- <leader>gbs: Git branch spin-off (JJ: bookmark create + new)
map("n", "<leader>gs", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local default = "feature-" .. (vim.fn.fnamemodify(vim.fn.expand("%:p"), ":t:r") or "")
    vim.ui.input({ prompt = "JJ bookmark name (spin-off): ", default = default }, function(name)
      if not name or name == "" then return end
      vim.fn.jobstart({ "jj", "new", "-m", "spin-off " .. name }, { cwd = gw_root, on_exit = function(_, code) vim.schedule(function() if code==0 then vim.fn.jobstart({ "jj", "bookmark", "create", name, "-r", "@" }, { cwd = gw_root, on_exit = function(_, c2) vim.schedule(function() if c2==0 then vim.notify("Created jj bookmark " .. name .. " at @", vim.log.levels.INFO) else vim.notify("jj bookmark create failed", vim.log.levels.ERROR) end end) end }) else vim.notify("jj new failed", vim.log.levels.ERROR) end end) end })
    end)
    return
  end
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
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    -- JJ mode: delegate to jj workspace add (branch → bookmark + workspace)
    vim.ui.input({ prompt = "New jj workspace name (bookmark): " }, function(name)
      if not name or vim.trim(name) == "" then return end
      name = vim.trim(name)
      local parent = vim.fn.fnamemodify(gw_root, ":h")
      local worktree_dir = parent .. "/" .. vim.fn.fnamemodify(gw_root, ":t") .. "-" .. name
      vim.fn.jobstart({ "jj", "workspace", "add", "--name", name, worktree_dir }, {
      cwd = gw_root,
        cwd = gw_root,
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              vim.notify("JJ workspace created: " .. worktree_dir, vim.log.levels.INFO)
              vim.cmd("tabnew")
              vim.cmd("tcd " .. vim.fn.fnameescape(worktree_dir))
            else
              vim.notify("JJ workspace add failed", vim.log.levels.ERROR)
            end
          end)
        end,
      })
    end)
    return
  end
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
              vim.cmd("tabnew")
              vim.cmd("tcd " .. vim.fn.fnameescape(target))
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
                  vim.cmd("tabnew")
                  vim.cmd("tcd " .. vim.fn.fnameescape(target))
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

-- <leader>gwC: Create worktree for <branch> in new tab (JJ workspace when jj)
map("n", "<leader>gwC", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    vim.ui.input({ prompt = "New jj workspace name (bookmark) for new tab: " }, function(name)
      if not name or vim.trim(name) == "" then return end
      name = vim.trim(name)
      local parent = vim.fn.fnamemodify(gw_root, ":h")
      local worktree_dir = parent .. "/" .. vim.fn.fnamemodify(gw_root, ":t") .. "-" .. name
      vim.fn.jobstart({ "jj", "workspace", "add", "--name", name, worktree_dir }, {
      cwd = gw_root,
        cwd = gw_root,
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              vim.cmd("tabnew")
              vim.cmd("tcd " .. vim.fn.fnameescape(worktree_dir))
              vim.notify("JJ workspace tab: " .. worktree_dir, vim.log.levels.INFO)
            else vim.notify("JJ workspace add failed", vim.log.levels.ERROR) end
          end)
        end,
      })
    end)
    return
  end
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

-- <leader>gwp: pick an open PR from upstream/origin and create a worktree from it.
-- Fetches refs/pull/<num>/head into local branch pr-<num>, then worktrees to
-- ../<repo-name>-pr-<num> and cds into it.
map("n", "<leader>gwp", function()
  if is_jj_repo() then
    local gw_root = gw_jj_root()
    local out = vim.fn.system({ "sh", "-c", "jj bookmark list -T 'name ++ \"\\n\"' 2>/dev/null" })
    local bms = {}
    for _, line in ipairs(vim.split(out, "\n")) do line = vim.trim(line); if line ~= "" then table.insert(bms, line) end end
    if #bms == 0 then vim.notify("No jj bookmarks for workspace", vim.log.levels.WARN) return end
    vim.ui.select(bms, { prompt = "Select jj bookmark for new workspace:" }, function(choice)
      if not choice then return end
      local parent = vim.fn.fnamemodify(gw_root, ":h")
      local dir = parent .. "/" .. vim.fn.fnamemodify(gw_root, ":t") .. "-" .. choice
      vim.fn.jobstart({ "jj", "workspace", "add", "--name", choice .. "-wt", dir }, { cwd = gw_root, on_exit = function(_, code) vim.schedule(function() if code==0 then vim.cmd("cd " .. vim.fn.fnameescape(dir)); vim.notify("JJ workspace for " .. choice .. " at " .. dir, vim.log.levels.INFO) else vim.notify("JJ workspace add failed", vim.log.levels.ERROR) end end) end })
    end)
    return
  end
  local Job = require("plenary.job")
  local notify = vim.notify

  if vim.fn.executable("gh") ~= 1 then
    notify("`gh` CLI not found in PATH", vim.log.levels.ERROR)
    return
  end

  local root = git_root()
  if not root then
    notify("Not inside a Git repository", vim.log.levels.ERROR)
    return
  end
  local repo_name = vim.fn.fnamemodify(root, ":t")

  -- pick remote: prefer upstream, fallback origin
  local remotes = vim.fn.systemlist({ "git", "-C", root, "remote" })
  local remote = nil
  for _, r in ipairs(remotes or {}) do
    if vim.trim(r) == "upstream" then remote = "upstream"; break end
  end
  if not remote then
    for _, r in ipairs(remotes or {}) do
      if vim.trim(r) == "origin" then remote = "origin"; break end
    end
  end
  if not remote then
    notify("No `upstream` or `origin` remote configured", vim.log.levels.ERROR)
    return
  end

  notify("Listing open PRs from " .. remote .. "…", vim.log.levels.INFO)

  Job:new({
    command = "gh",
    args = { "pr", "list", "--limit", "200", "--state", "open",
             "--json", "number,title,author,headRefName,isCrossRepository,headRepositoryOwner" },
    cwd = root,
    on_exit = function(j, code)
      vim.schedule(function()
        if code ~= 0 then
          notify("gh pr list failed: " .. table.concat(j:stderr_result(), " "), vim.log.levels.ERROR)
          return
        end
        local raw = table.concat(j:result(), "\n")
        local ok, prs = pcall(vim.json.decode, raw)
        if not ok or type(prs) ~= "table" or #prs == 0 then
          notify("No open PRs found", vim.log.levels.INFO)
          return
        end

        local items = {}
        for _, pr in ipairs(prs) do
          local login = (pr.author and pr.author.login) or "?"
          local cross = pr.isCrossRepository
              and (" [" .. ((pr.headRepositoryOwner and pr.headRepositoryOwner.login) or "fork") .. "]")
              or ""
          local display = string.format("#%-5d %s  (@%s)%s", pr.number, pr.title or "", login, cross)
          table.insert(items, { number = pr.number, title = pr.title or "", display = display })
        end

        local function do_checkout(item)
          local num = item.number
          local local_branch = "pr-" .. num
          local parent_dir = vim.fn.fnamemodify(root, ":h")
          local worktree_dir = parent_dir .. "/" .. repo_name .. "-pr-" .. num

          local all_wts = git_worktree_list()
          for _, wt_path in ipairs(all_wts or {}) do
            if vim.fn.fnamemodify(wt_path, ":p") == vim.fn.fnamemodify(worktree_dir, ":p") then
              notify("Worktree already exists at: " .. worktree_dir, vim.log.levels.INFO)
              local target = worktree_cd_target(worktree_dir)
              vim.cmd("cd " .. vim.fn.fnameescape(target))
              notify("Changed directory to: " .. target, vim.log.levels.INFO)
              return
            end
          end

          notify("Fetching PR #" .. num .. " from " .. remote .. "…", vim.log.levels.INFO)
          Job:new({
            command = "git",
            args = { "fetch", remote,
                     "+refs/pull/" .. num .. "/head:refs/heads/" .. local_branch },
            cwd = root,
            on_exit = function(jf, fcode)
              vim.schedule(function()
                if fcode ~= 0 then
                  notify("Fetch failed: " .. table.concat(jf:stderr_result(), " "), vim.log.levels.ERROR)
                  return
                end
                Job:new({
                  command = "git",
                  args = { "worktree", "add", worktree_dir, local_branch },
                  cwd = root,
                  on_exit = function(jw, wcode)
                    vim.schedule(function()
                      if wcode ~= 0 then
                        notify("worktree add failed: " .. table.concat(jw:stderr_result(), " "), vim.log.levels.ERROR)
                        return
                      end
                      notify("Worktree created: " .. worktree_dir, vim.log.levels.INFO)
                      local target = worktree_cd_target(worktree_dir)
                      vim.cmd("cd " .. vim.fn.fnameescape(target))
                      notify("Changed directory to: " .. target, vim.log.levels.INFO)
                    end)
                  end,
                }):start()
              end)
            end,
          }):start()
        end

        local tel_ok = pcall(require, "telescope")
        if tel_ok then
          require("telescope.pickers").new({}, {
            prompt_title = "Open PRs (" .. remote .. ") — Enter to checkout as worktree",
            finder = require("telescope.finders").new_table({
              results = items,
              entry_maker = function(e)
                return { value = e, display = e.display, ordinal = e.display }
              end,
            }),
            sorter = require("telescope.config").values.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
              local actions = require("telescope.actions")
              local state = require("telescope.actions.state")
              actions.select_default:replace(function()
                local sel = state.get_selected_entry()
                actions.close(prompt_bufnr)
                if sel then do_checkout(sel.value) end
              end)
              return true
            end,
          }):find()
        else
          vim.ui.select(items, {
            prompt = "Select PR to create worktree:",
            format_item = function(i) return i.display end,
          }, function(choice)
            if choice then do_checkout(choice) end
          end)
        end
      end)
    end,
  }):start()
end, { desc = "Create worktree from selected open PR (gh)" })

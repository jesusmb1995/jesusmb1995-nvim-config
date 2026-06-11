local map = vim.keymap.set

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

-- <leader>gwp: pick an open PR from upstream/origin and create a worktree from it.
-- Fetches refs/pull/<num>/head into local branch pr-<num>, then worktrees to
-- ../<repo-name>-pr-<num> and cds into it.
map("n", "<leader>gwp", function()
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

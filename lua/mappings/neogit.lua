local map = vim.keymap.set

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
local function is_stg_branch()
  local stg_path = "/home/linuxbrew/.linuxbrew/bin/stg"
  local patch_count = tonumber(vim.fn.trim(vim.fn.system(stg_path .. " series --count 2>/dev/null"))) or 0
  return patch_count > 0
end

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

  if is_stg_branch() then
    local stg_path = "/home/linuxbrew/.linuxbrew/bin/stg"
    local cmd = stg_path .. " rebase upstream/main"
    vim.notify("Running: stg rebase upstream/main", vim.log.levels.INFO)
    require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
  else
    local cmd = "git rebase upstream/main"
    vim.notify("Running: git rebase upstream/main", vim.log.levels.INFO)
    require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
  end
end, { desc = "Rebase upstream/main (stg if stg branch, else git)" })

map("n", "<leader>gri", function()
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

  if is_stg_branch() then
    local stg_path = "/home/linuxbrew/.linuxbrew/bin/stg"
    local cmd = stg_path .. " rebase -i upstream/main"
    vim.notify("Running: stg rebase -i upstream/main", vim.log.levels.INFO)
    require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
  else
    local cmd = "git rebase -i upstream/main"
    vim.notify("Running: git rebase -i upstream/main", vim.log.levels.INFO)
    require("nvchad.term").runner { pos = "sp", cmd = cmd, id = "htoggleTerm", clear_cmd = false }
  end
end, { desc = "Interactive rebase upstream/main (stg if stg branch, else git)" })
map("n", "<leader>gf", ":Neogit fetch<CR>", { desc = "Git Fetch" })

local map = vim.keymap.set

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

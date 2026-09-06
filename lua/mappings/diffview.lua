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
  -- JJ repo: same diff view as pressing D on the @ line in <leader>gl log
  -- (jj.diff.show_revision, diffview backend → new tab). jj has no HEAD.
  local buf_path = vim.api.nvim_buf_get_name(0)
  local buf_dir = (buf_path ~= "" and buf_path ~= nil) and vim.fn.fnamemodify(buf_path, ":h") or vim.fn.getcwd()
  local jj_out = vim.fn.system({ "sh", "-c", "cd " .. vim.fn.shellescape(buf_dir) .. " && jj root 2>/dev/null" })
  if vim.v.shell_error == 0 and vim.trim(jj_out) ~= "" then
    require("lazy").load({ plugins = { "jj.nvim" } })
    require("jj.diff").show_revision({ rev = "@" })
    return
  end
  local root = git_root_for_buffer()
  if root and #root > 0 then
    local rev = vim.fn.trim(vim.fn.system("git -C " .. vim.fn.shellescape(root) .. " rev-parse HEAD^ 2>/dev/null"))
    if vim.v.shell_error == 0 and #rev > 0 then
      vim.cmd("DiffviewOpen " .. vim.fn.escape(rev, " "))
      return
    end
  end
  vim.cmd("DiffviewOpen HEAD^")
end, { desc = "Open diffview against previous commit (jj: current patch)" })
vim.keymap.set("n", "<leader>gD", function()
  local root = git_root_for_buffer()
  local prev_cwd = vim.fn.getcwd()
  if root and #root > 0 then vim.cmd("cd " .. vim.fn.fnameescape(root)) end
  vim.cmd("DiffviewOpen upstream/main")
  if root and #root > 0 then vim.cmd("cd " .. vim.fn.fnameescape(prev_cwd)) end
end, { desc = "Open diffview against main branch" })

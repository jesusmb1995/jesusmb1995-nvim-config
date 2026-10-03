local branch_changed_lines = {}
local diffview_changed_lines = {}

-- Shared unified=0 hunk parser: fills target[file][line] = true for the
-- new-side (+) ranges of every file in the diff output.
local function parse_unified0(diff, root, target)
  local current_file = nil
  for _, line in ipairs(diff) do
    local file = line:match("^%+%+%+ b/(.+)$")
    if file then
      current_file = root .. "/" .. file
      target[current_file] = target[current_file] or {}
    elseif current_file then
      local s, c = line:match("^@@.-%+(%d+),?(%d*)%s")
      if s then
        s = tonumber(s)
        c = tonumber(c) or 1
        for l = s, s + math.max(c, 1) - 1 do
          target[current_file][l] = true
        end
      end
    end
  end
end

local function update_branch_changed_lines()
  for k in pairs(branch_changed_lines) do
    branch_changed_lines[k] = nil
  end
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if not git_root then
    return
  end
  parse_unified0(
    vim.fn.systemlist("git diff upstream/main..HEAD --unified=0"),
    git_root,
    branch_changed_lines
  )
end

-- Diffview endpoints for the current tab: repo toplevel plus the view's two
-- commit SHAs (same shape for git and jj-backed views — jj.nvim opens plain
-- DiffviewOpen <sha>..<sha>). Nil when not on a 2-commit diff view.
local function diffview_endpoints()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return nil
  end
  local view = lib.get_current_view()
  if not view then
    return nil
  end
  local toplevel = view.adapter and view.adapter.ctx and view.adapter.ctx.toplevel
  if not toplevel or toplevel == "" then
    return nil
  end
  local pairs = {}
  if view.cur_entry and view.cur_entry.revs then
    table.insert(pairs, { view.cur_entry.revs.a, view.cur_entry.revs.b })
  end
  local layout = view.cur_layout
  if layout then
    local fa = layout.a and layout.a.file and layout.a.file.rev
    local fb = layout.b and layout.b.file and layout.b.file.rev
    -- Layout windows show the two sides of the same entry.
    table.insert(pairs, { fa, fb })
  end
  for _, pair in ipairs(pairs) do
    local a, b = pair[1], pair[2]
    -- RevType.COMMIT == 2; stage/local/custom views have no diffable SHAs.
    if a and b and a.type == 2 and b.type == 2 and a.commit and b.commit then
      return toplevel, a.commit, b.commit
    end
  end
  return nil
end

local function update_diffview_changed_lines()
  for k in pairs(diffview_changed_lines) do
    diffview_changed_lines[k] = nil
  end
  local toplevel, left, right = diffview_endpoints()
  if not toplevel then
    return false
  end
  parse_unified0(
    vim.fn.systemlist("git -C " .. vim.fn.shellescape(toplevel) .. " diff " .. left .. " " .. right .. " --unified=0"),
    toplevel,
    diffview_changed_lines
  )
  return true
end

return {
  "folke/trouble.nvim",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  opts = {
    modes = {
      branch_diagnostics = {
        mode = "diagnostics",
        filter = {
          function(item)
            local file_lines = branch_changed_lines[item.filename]
            return file_lines ~= nil and item.pos ~= nil and file_lines[item.pos[1]] == true
          end,
        },
      },
      diffview_diagnostics = {
        mode = "diagnostics",
        filter = {
          function(item)
            local file_lines = diffview_changed_lines[item.filename]
            return file_lines ~= nil and item.pos ~= nil and file_lines[item.pos[1]] == true
          end,
        },
      },
    },
  },
  cmd = "Trouble",
  keys = {
    {
      "<leader>xx",
      function()
        -- On a diffview tab, xx shows only diagnostics on the diff's
        -- changed lines; everywhere else it toggles plain diagnostics.
        if update_diffview_changed_lines() then
          require("trouble").toggle("diffview_diagnostics")
        else
          require("trouble").toggle("diagnostics")
        end
      end,
      desc = "Diagnostics (Trouble, changed lines on diffview)",
    },
    {
      "<leader>xX",
      function()
        update_branch_changed_lines()
        require("trouble").toggle("branch_diagnostics")
      end,
      desc = "Branch Diagnostics (Trouble)",
    },
    {
      "<leader>cs",
      "<cmd>Trouble symbols toggle focus=false<cr>",
      desc = "Symbols (Trouble)",
    },
    {
      "<leader>cl",
      "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
      desc = "LSP Definitions / references / ... (Trouble)",
    },
    {
      "<leader>xL",
      "<cmd>Trouble loclist toggle<cr>",
      desc = "Location List (Trouble)",
    },
    {
      "<leader>xQ",
      "<cmd>Trouble qflist toggle<cr>",
      desc = "Quickfix List (Trouble)",
    },
  },
}


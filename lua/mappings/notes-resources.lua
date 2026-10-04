local map = vim.keymap.set

-- Journal + project resources. Both derive identity from the workspace root,
-- not from a pretty name, so agents and nvim land on the same files:
--   root = jj root (current workspace), else git toplevel, else cwd
--   journal hash = sha256(realpath -m(root))[:8], file ~/Documents/journal/*-<hash>.md
--   resources  = ~/projtmp/<original workspace name>
local function workspace_root()
  local bufname = vim.api.nvim_buf_get_name(0)
  local start = bufname ~= "" and vim.fn.fnamemodify(bufname, ":h") or vim.fn.getcwd()
  start = vim.fs.normalize(start)
  local dir = start
  while dir and dir ~= "" do
    if vim.fn.isdirectory(dir .. "/.jj") == 1 then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  local git_root = vim.fn.systemlist({ "git", "-C", start, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and git_root[1] and git_root[1] ~= "" then
    return vim.fs.normalize(git_root[1])
  end
  return vim.fs.normalize(vim.fn.getcwd())
end

local function canonical_dir(dir)
  local out = vim.fn.systemlist({ "realpath", "-m", "--", dir })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    dir = out[1]
  else
    dir = vim.fn.fnamemodify(dir, ":p")
  end
  dir = vim.fs.normalize(dir)
  if dir ~= "/" then
    dir = dir:gsub("/$", "")
  end
  return dir
end

local function slugify(text)
  local slug = (text or ""):lower():gsub("%s+", "-"):gsub("[^a-z0-9%-]", "")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")
  return slug
end

local function journal_candidates(hash)
  local root = vim.fn.expand("~/Documents/journal")
  local files = vim.fn.glob(root .. "/*-" .. hash .. ".md", true, true) or {}
  table.sort(files, function(a, b)
    local ta, tb = vim.fn.getftime(a), vim.fn.getftime(b)
    if ta == tb then
      return a < b
    end
    return ta > tb
  end)
  return files
end

local function journal_template(title, canon, hash)
  return {
    "# " .. title .. " — `" .. canon .. "`",
    "Hash: `" .. hash .. "`  Path: `" .. canon .. "`",
    "",
    "## Summary",
    "",
    "## Details",
    "",
    "## Log",
    "- " .. os.date("%Y-%m-%d %H:%M") .. " — opened from nvim",
  }
end

-- Ensure (creating if needed) the per-directory journal for `dir` without
-- opening it. Same formula as /journal-dir-update + /journal-dir-read.
local function ensure_journal(dir_arg, title_arg)
  local dir = canonical_dir(dir_arg and dir_arg ~= "" and dir_arg or workspace_root())
  local hash = vim.fn.sha256(dir):sub(1, 8):lower()
  if not hash:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") then
    return nil, "cannot hash " .. dir
  end
  vim.fn.mkdir(vim.fn.expand("~/Documents/journal"), "p")
  local existing = journal_candidates(hash)
  if #existing > 1 then
    vim.notify(
      "Journal: " .. #existing .. " files share hash " .. hash .. " — using newest; run /journal-dir-update to deduplicate",
      vim.log.levels.WARN
    )
  end
  if existing[1] then
    return existing[1], nil
  end
  local pretty = (title_arg and title_arg ~= "") and title_arg or vim.fn.fnamemodify(dir, ":t")
  local slug = slugify(pretty)
  local name = ((slug ~= "") and (slug .. "-") or "") .. hash .. ".md"
  local target = vim.fn.expand("~/Documents/journal") .. "/" .. name
  vim.fn.writefile(journal_template(pretty, dir, hash), target)
  return target, "created"
end

local function open_journal(dir_arg, title_arg)
  local target, status = ensure_journal(dir_arg, title_arg)
  if not target then
    vim.notify("Journal: " .. (status or "unknown error"), vim.log.levels.ERROR)
    return
  end
  if status == "created" then
    vim.notify("Journal: created " .. target, vim.log.levels.INFO)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end

vim.api.nvim_create_user_command("Journal", function(opts)
  open_journal(opts.args ~= "" and opts.args or nil, nil)
end, { nargs = "?", complete = "dir", desc = "Open per-directory journal (same file as /journal-dir-*)" })
map("n", "<leader>qj", function()
  open_journal(nil, nil)
end, { desc = "Journal: open project journal (same file as /journal-dir-*)" })

-- Sibling workspaces of the same jj repo, authoritatively: `jj workspace
-- list` knows every workspace regardless of naming. Returns a list of
-- {name, path} with absolute paths, or nil when jj is unavailable/fails.
local function jj_workspaces(root)
  if vim.fn.executable("jj") == 0 then
    return nil
  end
  local out = vim.fn.systemlist("cd " .. vim.fn.shellescape(root) .. " && jj workspace list")
  if vim.v.shell_error ~= 0 or not out then
    return nil
  end
  local ws = {}
  for _, line in ipairs(out) do
    local name, path = line:match("^(%S+):%s+(%S+)")
    if name and path then
      -- paths print relative to cwd: anchor them at the repo root.
      -- (parens: gsub returns 2 values, normalize takes 1.)
      local abs = vim.fs.normalize((vim.fn.fnamemodify(root .. "/" .. path, ":p"):gsub("/$", "")))
      ws[#ws + 1] = { name = name, path = abs }
    end
  end
  if #ws == 0 then
    return nil
  end
  return ws
end

local function original_workspace(root)
  local base = vim.fn.fnamemodify(root, ":t")
  local orig = base:gsub("%-secondary%d*$", "")
  if orig == "" then
    orig = base
  end
  return orig, orig ~= base, vim.fn.fnamemodify(root, ":h")
end

local function link_to(target, link)
  if target == "" or vim.fn.filereadable(target) == 0 and vim.fn.isdirectory(target) == 0 then
    return false
  end
  vim.fn.mkdir(vim.fn.fnamemodify(link, ":h"), "p")
  if vim.fn.resolve(link) ~= target then
    vim.fn.delete(link)
    vim.fn.system({ "ln", "-sfn", "--", target, link })
    if vim.v.shell_error ~= 0 then
      return false
    end
  end
  return true
end

local function cmd_bookmarks_store(root)
  local central = vim.fn.expand("~/.local/share/cmd_bookmarks")
  if vim.fn.filereadable(central .. "/savecmd.zsh") == 1 then
    return central .. "/" .. root:gsub("/", "_")
  end
  return root
end

-- Build ~/projtmp/<original workspace> and open it in a new tab with the
-- filetree rooted there (<C-n> follows the tab cwd, so it just works).
local function open_proj_resources()
  local root = workspace_root()
  local orig, is_secondary, parent = original_workspace(root)
  local res = vim.fn.expand("~/projtmp") .. "/" .. orig
  vim.fn.mkdir(res .. "/workspaces", "p")

  -- project notes: this workspace's projnote store (outside the repo)
  local notes = vim.fn.expand("~/.local/share/projnote") .. "/" .. vim.fn.sha256(root):sub(1, 16)
  vim.fn.mkdir(notes, "p")
  link_to(notes, res .. "/notes")

  -- project journal: same file :Journal opens
  local canon = canonical_dir(root)
  local hash = vim.fn.sha256(canon):sub(1, 8):lower()
  local journals = journal_candidates(hash)
  if journals[1] then
    link_to(journals[1], res .. "/journal.md")
  else
    local fresh, err = ensure_journal(root, nil)
    if fresh then
      link_to(fresh, res .. "/journal.md")
    else
      vim.notify("proj resources: journal unavailable (" .. (err or "unknown") .. ")", vim.log.levels.WARN)
    end
  end

  -- command bookmarks: central store when deployed, else the workspace file
  local store = cmd_bookmarks_store(root)
  link_to(store .. "/.local_cmd_bookmarks", res .. "/cmd-bookmarks")
  link_to(store .. "/.local_cmd_bookmarks_stats", res .. "/cmd-bookmarks-stats")

  -- sibling workspaces: authoritative via `jj workspace list` (any naming),
  -- with the *-secondary name glob as fallback outside jj repos. Rebuilt on
  -- every open, so new/removed workspaces show up immediately: stale links
  -- are pruned first, then the current set is linked. A main workspace links
  -- every sibling; a secondary links only the main one. Links point at each
  -- sibling's NOTE STORE (not the checkout): this tab aggregates notes.
  -- Siblings with no notes yet are skipped — their store appears on next
  -- open once they take their first note.
  local notes_base = vim.fn.expand("~/.local/share/projnote")
  local function sibling_notes_link(ws_path, link_name)
    local store = notes_base .. "/" .. vim.fn.sha256(ws_path):sub(1, 16)
    if vim.fn.isdirectory(store) == 1 then
      link_to(store, res .. "/workspaces/" .. link_name)
      return true
    end
    return false
  end
  for _, stale in ipairs(vim.fn.glob(res .. "/workspaces/*", true, true)) do
    vim.fn.delete(stale)
  end
  local linked = false
  local siblings = jj_workspaces(root)
  if siblings then
    local main_path = nil
    for _, w in ipairs(siblings) do
      if w.name == "default" then
        main_path = w.path
      end
    end
    for _, w in ipairs(siblings) do
      if vim.fs.normalize(w.path) ~= vim.fs.normalize(root) and vim.fn.isdirectory(w.path) == 1 then
        local want = false
        if not is_secondary then
          want = true -- main: link every sibling workspace
        elseif main_path and vim.fs.normalize(w.path) == vim.fs.normalize(main_path) then
          want = true -- secondary: only the default (main) workspace
        elseif not main_path and vim.fn.fnamemodify(w.path, ":t") == orig then
          want = true -- secondary, no default: the orig-named parent
        end
        if want and sibling_notes_link(w.path, w.name) then
          linked = true
        end
      end
    end
  end
  if not linked then
    if is_secondary then
      if vim.fn.isdirectory(parent .. "/" .. orig) == 1
        and sibling_notes_link(parent .. "/" .. orig, orig) then
      end
    else
      for _, sib in ipairs(vim.fn.glob(parent .. "/" .. orig .. "-secondary*", true, true) or {}) do
        if vim.fn.isdirectory(sib) == 1 then
          sibling_notes_link(sib, vim.fn.fnamemodify(sib, ":t"))
        end
      end
    end
  end
  link_to(root, res .. "/workspace-current")

  vim.cmd("tabnew")
  vim.cmd("tcd " .. vim.fn.fnameescape(res))
  local ok, api = pcall(require, "nvim-tree.api")
  if ok then
    if api.tree.is_visible() then
      api.tree.close()
    end
    api.tree.open({ path = res })
  else
    vim.notify("proj resources ready at " .. res .. " (nvim-tree unavailable)", vim.log.levels.WARN)
  end
end

vim.api.nvim_create_user_command("ProjResources", open_proj_resources, { desc = "Open ~/projtmp/<project> resources in a new tab" })
map("n", "<leader>qr", open_proj_resources, { desc = "Resources: open ~/projtmp/<project> in a new tab" })

-- Dashboard project intelligence: usage tracking, jj workspace grouping,
-- and archive tiering for the dashboard panel and the project pickers.
--
-- Archive tiers for unpinned projects, by last use:
--   age <= 14 days : main panel + [p] picker
--   age <= 60 days : [p] picker only (off the main panel)
--   older          : [P] picker only (fully archived)
-- Pinned (zsh-bookmark-jumper) projects are exempt from archiving.
-- Workspace groups: the panel entry shows min(all workspaces); the variants
-- open through a selector (Shift+letter on the dashboard row).

local M = {}

M.PANEL_MAX_AGE = 14 * 86400
M.PICKER_MAX_AGE = 60 * 86400
M.PROBE_POOL = 24
M.PANEL_LIMIT = 12

function M.now()
  return os.time()
end

local function normalize_existing_dir(path)
  local expanded = vim.fn.expand(path or '')
  if expanded == '' then
    return nil
  end
  local normalized = vim.fs.normalize(expanded)
  if vim.fn.isdirectory(normalized) == 1 then
    return normalized
  end
  return nil
end

-- Usage store: flat { [normalized_path] = epoch } written as `return {...}`.
function M.read_usage(usage_path)
  if vim.fn.filereadable(usage_path) ~= 1 then
    return {}
  end
  local ok, chunk = pcall(loadfile, usage_path)
  if not ok or type(chunk) ~= 'function' then
    return {}
  end
  local ok2, data = pcall(chunk)
  if not ok2 or type(data) ~= 'table' then
    return {}
  end
  local clean = {}
  for k, v in pairs(data) do
    if type(k) == 'string' and type(v) == 'number' then
      clean[k] = v
    end
  end
  return clean
end

function M.write_usage(usage_path, tbl)
  local dir = vim.fn.fnamemodify(usage_path, ':h')
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile(vim.split('return ' .. vim.inspect(tbl or {}), '\n'), usage_path)
end

function M.rel_age(epoch, now)
  if not epoch or epoch == 0 then
    return 'never'
  end
  local d = math.max(0, (now or os.time()) - epoch)
  if d < 3600 then
    return 'just now'
  end
  if d < 86400 then
    return math.floor(d / 3600) .. 'h ago'
  end
  if d < 30 * 86400 then
    return math.floor(d / 86400) .. 'd ago'
  end
  return math.floor(d / (30 * 86400)) .. 'mo ago'
end

-- 'main' | 'picker' | 'archived'
function M.tier(usage, pinned, now)
  if pinned then
    return 'main'
  end
  local age = math.max(0, (now or os.time()) - (usage or 0))
  if age <= M.PANEL_MAX_AGE then
    return 'main'
  end
  if age <= M.PICKER_MAX_AGE then
    return 'picker'
  end
  return 'archived'
end

-- Jumper bookmarks: { { name, path, last_used } }, usage-sorted desc.
function M.load_bookmarks(bookmarks_file, stats_path)
  if vim.fn.filereadable(bookmarks_file) ~= 1 then
    return {}
  end
  local lines = vim.fn.readfile(bookmarks_file)
  local usage_stats = {}
  if stats_path and vim.fn.filereadable(stats_path) == 1 then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(stats_path), '\n'))
    if ok and type(decoded) == 'table' then
      usage_stats = decoded
    end
  end
  local bookmarks = {}
  for _, line in ipairs(lines) do
    local path, name = line:match('^(.+)|(.+)$')
    if name and path then
      path = path:gsub('%$HOME', vim.env.HOME)
      local normalized_path = normalize_existing_dir(path)
      if normalized_path then
        table.insert(bookmarks, {
          name = name,
          path = normalized_path,
          last_used = usage_stats[name] or 0,
        })
      end
    end
  end
  table.sort(bookmarks, function(a, b)
    return (a.last_used or 0) > (b.last_used or 0)
  end)
  return bookmarks
end

-- Dashboard cache: list of path strings, older->newer. Tolerates
-- { path = ... } table entries for forward compatibility.
function M.read_project_list(cache_path)
  if vim.fn.filereadable(cache_path) ~= 1 then
    return {}
  end
  local file = io.open(cache_path, 'rb')
  if not file then
    return {}
  end
  local raw = file:read('*a')
  file:close()
  if raw == '' then
    return {}
  end
  local ok, loader = pcall(loadstring, raw)
  if not ok or type(loader) ~= 'function' then
    return {}
  end
  local ok_list, list = pcall(loader)
  if not ok_list or type(list) ~= 'table' then
    return {}
  end
  return list
end

-- Merged candidates: { { path, usage, pinned, idx } }. Unknown recents seed
-- as fresh so the archive clock starts on deploy instead of mass-archiving
-- the inherited cache on day one.
function M.collect(bookmarks, recents, usage, now)
  now = now or os.time()
  usage = usage or {}
  local by_path = {}
  local ordered = {}
  local function add(raw, pinned, explicit)
    local n = normalize_existing_dir(raw)
    if not n then
      return
    end
    local use = explicit
    if use == nil then
      use = usage[n]
    end
    if use == nil and not pinned then
      use = now
    end
    if use == nil then
      use = 0
    end
    local cur = by_path[n]
    if cur then
      cur.usage = math.max(cur.usage, use)
      cur.pinned = cur.pinned or pinned
      return
    end
    local entry = { path = n, usage = use, pinned = pinned or false, idx = #ordered + 1 }
    by_path[n] = entry
    table.insert(ordered, entry)
  end
  for _, b in ipairs(bookmarks or {}) do
    local explicit = (b.last_used and b.last_used > 0) and b.last_used or nil
    add(b.path, true, explicit)
  end
  for _, p in ipairs(recents or {}) do
    add(type(p) == 'string' and p or p.path, false, nil)
  end
  return ordered
end

-- Sorted workspace paths of path's repo, or nil when not a multi-workspace
-- jj repo. `jj workspace list` prints `name: path ...` lines with paths
-- relative to the repo cwd — absolutize before comparing.
function M.probe_workspaces(path)
  local lines = vim.fn.systemlist('cd ' .. vim.fn.shellescape(path) .. ' && jj workspace list 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local set, seen = {}, {}
  for _, l in ipairs(lines) do
    local ws_path = l:match('^.-:%s+(%S+)')
    if ws_path then
      -- Extra parens: :gsub returns (string, count) and both would leak
      -- into normalize's (path, opts) signature otherwise.
      local abs = vim.fs.normalize((vim.fn.fnamemodify(path .. '/' .. ws_path, ':p'):gsub('/$', '')))
      if not seen[abs] and vim.fn.isdirectory(abs) == 1 then
        seen[abs] = true
        table.insert(set, abs)
      end
    end
  end
  if #set < 2 then
    return nil
  end
  table.sort(set)
  return set
end

-- Group candidates by repo (min workspace path wins as the main entry).
-- Returns list of { main, members = { [path] = { usage, pinned } },
-- usage = max, pinned = any, idx = min }.
function M.group(candidates, usage, probe_limit)
  usage = usage or {}
  probe_limit = probe_limit or M.PROBE_POOL
  local sorted = {}
  for _, c in ipairs(candidates or {}) do
    table.insert(sorted, c)
  end
  table.sort(sorted, function(a, b)
    if a.usage ~= b.usage then
      return a.usage > b.usage
    end
    return a.idx < b.idx
  end)
  local groups, member_key = {}, {}
  local probed = 0
  for _, c in ipairs(sorted) do
    local key = member_key[c.path]
    if not key and probed < probe_limit then
      probed = probed + 1
      local set = M.probe_workspaces(c.path)
      if set then
        key = set[1]
        for _, m in ipairs(set) do
          member_key[m] = key
        end
      end
    end
    key = key or c.path
    local g = groups[key]
    if not g then
      g = { main = key, members = {}, usage = 0, pinned = false, idx = c.idx }
      groups[key] = g
    end
    g.members[c.path] = { usage = c.usage, pinned = c.pinned }
    if c.usage > g.usage then
      g.usage = c.usage
    end
    g.pinned = g.pinned or c.pinned
    if c.idx < g.idx then
      g.idx = c.idx
    end
  end
  -- Unknown siblings (probed set members with no candidate record).
  for key, g in pairs(groups) do
    for m in pairs(member_key) do
      if member_key[m] == key and not g.members[m] and vim.fn.isdirectory(m) == 1 then
        g.members[m] = { usage = usage[m] or 0, pinned = false }
      end
    end
  end
  local out = {}
  for _, g in pairs(groups) do
    table.insert(out, g)
  end
  return out
end

function M.sorted_members(group)
  local list = {}
  for path, info in pairs(group.members or {}) do
    table.insert(list, { path = path, usage = info.usage or 0 })
  end
  table.sort(list, function(a, b)
    if a.usage ~= b.usage then
      return a.usage > b.usage
    end
    return a.path < b.path
  end)
  return list
end

-- Panel mains (usage desc) + variants table { [main] = sorted members }
-- for multi-workspace groups. now/limit injectable for tests.
function M.panel_mains(groups, now, limit)
  now = now or os.time()
  limit = limit or M.PANEL_LIMIT
  local sorted = {}
  for _, g in ipairs(groups or {}) do
    table.insert(sorted, g)
  end
  table.sort(sorted, function(a, b)
    if a.usage ~= b.usage then
      return a.usage > b.usage
    end
    return a.idx < b.idx
  end)
  local mains, variants = {}, {}
  for _, g in ipairs(sorted) do
    if #mains >= limit then
      break
    end
    if M.tier(g.usage, g.pinned, now) == 'main' then
      table.insert(mains, g.main)
      local members = M.sorted_members(g)
      if #members > 1 then
        variants[g.main] = members
      end
    end
  end
  return mains, variants
end

-- Flat picker entries, usage desc: { { path, mark } }. Archived excluded
-- unless include_archived. now injectable for tests.
function M.picker_entries(candidates, include_archived, now)
  now = now or os.time()
  local sorted = {}
  for _, c in ipairs(candidates or {}) do
    table.insert(sorted, c)
  end
  table.sort(sorted, function(a, b)
    if a.usage ~= b.usage then
      return a.usage > b.usage
    end
    return a.idx < b.idx
  end)
  local entries = {}
  for _, c in ipairs(sorted) do
    local t = M.tier(c.usage, c.pinned, now)
    if t ~= 'archived' or include_archived then
      local mark = ''
      if t == 'archived' then
        mark = ' (archived)'
      elseif (now - c.usage) > M.PANEL_MAX_AGE then
        mark = ' (' .. M.rel_age(c.usage, now) .. ')'
      end
      table.insert(entries, { path = c.path, mark = mark })
    end
  end
  return entries
end

return M

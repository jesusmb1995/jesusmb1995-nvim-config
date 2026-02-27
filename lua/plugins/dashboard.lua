return {
  'nvimdev/dashboard-nvim',
  event = 'VimEnter',
  config = function()
    math.randomseed(vim.loop.hrtime())

    local function cd_and_open_recent_file(project_path)
      if vim.fn.isdirectory(project_path) ~= 1 then
        vim.notify('Invalid project path: ' .. project_path, vim.log.levels.WARN)
        return
      end

      local normalized_root = vim.fs.normalize(project_path)
      vim.cmd('cd ' .. vim.fn.fnameescape(normalized_root))

      for _, file in ipairs(vim.v.oldfiles) do
        if type(file) == 'string' and file ~= '' and vim.fn.filereadable(file) == 1 then
          local normalized_path = vim.fs.normalize(file)
          local in_project = normalized_path == normalized_root
            or normalized_path:sub(1, #normalized_root + 1) == (normalized_root .. '/')
          if in_project then
            vim.cmd('edit ' .. vim.fn.fnameescape(file))
            return
          end
        end
      end

      vim.notify('No recent file found for ' .. normalized_root, vim.log.levels.INFO)
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

    local function load_j_bookmarks()
      local lines = vim.fn.systemlist("zsh -c 'source ~/.zshrc; showmarks' 2>/dev/null")
      if vim.v.shell_error ~= 0 then
        return {}
      end

      local stats_path = vim.fn.stdpath('data') .. '/zsh-bookmark-jumper.json'
      local usage_stats = {}
      if vim.fn.filereadable(stats_path) == 1 then
        local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(stats_path), '\n'))
        if ok and type(decoded) == 'table' then
          usage_stats = decoded
        end
      end

      local bookmarks = {}
      for _, line in ipairs(lines) do
        local name, path = line:match('^(%S+)%s+(.+)$')
        local normalized_path = normalize_existing_dir(path)
        if name and normalized_path then
          table.insert(bookmarks, {
            name = name,
            path = normalized_path,
            last_used = usage_stats[name] or 0,
          })
        end
      end

      table.sort(bookmarks, function(a, b)
        return (a.last_used or 0) > (b.last_used or 0)
      end)

      return bookmarks
    end

    local function read_dashboard_projects(cache_path)
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

    local function combine_projects_for_display(existing, jump_top, jump_limit, default_limit)
      local seen = {}
      local ordered = {}
      local function add(path)
        local normalized = normalize_existing_dir(path)
        if normalized and not seen[normalized] then
          seen[normalized] = true
          table.insert(ordered, normalized)
          return true
        end
        return false
      end

      local jump_added = 0
      for _, item in ipairs(jump_top) do
        if jump_added >= jump_limit then
          break
        end
        if add(item.path) then
          jump_added = jump_added + 1
        end
      end

      -- dashboard cache stores older->newer, walk backwards for most recent first
      local default_added = 0
      for idx = #existing, 1, -1 do
        if default_added >= default_limit then
          break
        end
        if add(existing[idx]) then
          default_added = default_added + 1
        end
      end

      return ordered
    end

    local function reverse_copy(list)
      local reversed = {}
      for idx = #list, 1, -1 do
        table.insert(reversed, list[idx])
      end
      return reversed
    end

    local function split_leaf_and_parent(path)
      local normalized = vim.fs.normalize(path)
      local leaf = vim.fn.fnamemodify(normalized, ':t')
      local parent = vim.fn.fnamemodify(normalized, ':h')
      if parent == '.' or parent == '' then
        parent = normalized
      end
      parent = vim.fn.fnamemodify(parent, ':~')
      return leaf, parent
    end

    local function compact_path_middle(path, max_len)
      if #path <= max_len then
        return path
      end
      local keep_left = math.max(8, math.floor((max_len - 3) * 0.6))
      local keep_right = math.max(8, max_len - 3 - keep_left)
      return path:sub(1, keep_left) .. '...' .. path:sub(-keep_right)
    end

    local function restyle_dashboard_entries(bufnr)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local extmarks = {}
      local row_targets = {}
      local section = nil

      for idx, line in ipairs(lines) do
        if line:find('Recent Projects:') then
          section = 'project'
        elseif line:find('Recent Files:') then
          section = 'mru'
        elseif line:match('^%s*$') then
          section = nil
        elseif section and (line:find('~[/\\]') or line:find('%s/')) then
          local path_start = line:find('[~/]')
          if path_start then
            local raw_path = line:sub(path_start):gsub('%s+$', '')
            raw_path = raw_path:gsub('%s+$', '')
            local expanded = vim.fn.expand(raw_path)
            local leaf, parent = split_leaf_and_parent(raw_path)
            local left_prefix = line:sub(1, path_start - 1)
            local left_width = vim.api.nvim_strwidth(left_prefix)
            table.insert(extmarks, {
              row = idx - 1,
              parent = parent,
              leaf = leaf,
              left_width = left_width,
              path_col = path_start - 1,
            })
            row_targets[idx - 1] = {
              path = expanded,
              is_project = section == 'project',
            }
          end
        end
      end

      local path_ns = vim.api.nvim_create_namespace('dashboard-custom-paths')
      local leaf_ns = vim.api.nvim_create_namespace('dashboard-custom-leaf')
      vim.api.nvim_buf_clear_namespace(bufnr, path_ns, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, leaf_ns, 0, -1)

      local function open_target(target)
        if not target or not target.path or target.path == '' then
          return
        end
        if target.is_project and vim.fn.isdirectory(target.path) == 1 then
          cd_and_open_recent_file(target.path)
          return
        end
        if vim.fn.filereadable(target.path) == 1 then
          vim.cmd('edit ' .. vim.fn.fnameescape(target.path))
        end
      end

      local dashboard_ns = vim.api.nvim_create_namespace('dashboard')
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, dashboard_ns, 0, -1, { details = true })
      for _, mark in ipairs(marks) do
        local row = mark[2]
        local details = mark[4] or {}
        local virt = details.virt_text
        local target = row_targets[row]
        if target and type(virt) == 'table' and type(virt[1]) == 'table' then
          local key = tostring(virt[1][1] or '')
          if key:match('^%S+$') then
            vim.keymap.set('n', key, function()
              open_target(target)
            end, { buffer = bufnr, silent = true, nowait = true })
          end
        end
      end

      local winid = vim.fn.bufwinid(bufnr)
      if winid == -1 then
        winid = vim.api.nvim_get_current_win()
      end
      local win_width = vim.api.nvim_win_get_width(winid)
      local base_path_col = math.max(38, math.floor(win_width * 0.56))
      for _, item in ipairs(extmarks) do
        local path_col = math.max(base_path_col, item.left_width + 20)
        local max_path_len = math.max(12, win_width - path_col - 2)
        local text = compact_path_middle(item.parent, max_path_len)

        local clear_cells = math.max(8, path_col - item.left_width)
        local leaf_pad = math.max(2, clear_cells - vim.api.nvim_strwidth(item.leaf))
        vim.api.nvim_buf_set_extmark(bufnr, leaf_ns, item.row, item.path_col, {
          virt_text = { { item.leaf .. (' '):rep(leaf_pad), 'DashboardFiles' } },
          virt_text_pos = 'overlay',
        })

        vim.api.nvim_buf_set_extmark(bufnr, path_ns, item.row, 0, {
          virt_text = { { text, 'Comment' } },
          virt_text_pos = 'overlay',
          virt_text_win_col = path_col,
        })
      end

      vim.keymap.set('n', '<CR>', function()
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        open_target(row_targets[row])
      end, { buffer = bufnr, silent = true, nowait = true })
    end

    local function write_dashboard_projects(cache_path, projects)
      local source = 'return ' .. vim.inspect(projects)
      local dir = vim.fn.fnamemodify(cache_path, ':h')
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile(vim.split(source, '\n'), cache_path)
    end

    local jump_limit = 6
    local default_recent_limit = 6
    local j_bookmarks = load_j_bookmarks()
    local dashboard_cache = vim.fn.stdpath('cache') .. '/dashboard/cache'
    local dashboard_projects = read_dashboard_projects(dashboard_cache)
    local display_projects = combine_projects_for_display(dashboard_projects, j_bookmarks, jump_limit, default_recent_limit)
    if #display_projects > 0 then
      write_dashboard_projects(dashboard_cache, reverse_copy(display_projects))
    end

    local shortcuts = {
      {
        icon = '󰒲 ',
        desc = ' Lazy',
        group = 'DiagnosticHint',
        action = 'Lazy',
        key = 'l',
      },
      {
        icon = ' ',
        desc = ' Quit',
        group = 'DiagnosticError',
        action = 'qa',
        key = 'q',
      },
    }

    local fire_headers = {
      {
        '',
        '            (  .      )',
        '        )           (              )',
        '              .  "   .   "  .  "  .',
        '       (    , )       (.   )  (   \',',
        '        ." ) ( . )    ,  ( ,     )   (',
        '     ). , ( .   (  ) ( , \')  .  (  ,',
        '    (_,) . ), ) _) _,\')  (, ) \'. )  ,',
        '    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^',
        '',
        '             n e o v i m',
        '',
      },
    }

    require('dashboard').setup {
      theme = 'hyper',
      config = {
        shortcuts_left_side = true,
        header = fire_headers[math.random(#fire_headers)],
        week_header = {
          enable = false,
        },
        shortcut = shortcuts,
        project = {
          enable = true,
          limit = jump_limit + default_recent_limit,
          icon = ' ',
          label = ' Recent Projects:',
          action = cd_and_open_recent_file,
        },
        mru = {
          enable = true,
          limit = 10,
          icon = ' ',
          label = ' Recent Files:',
          cwd_only = false,
        },
        footer = {
          '',
          'Keep shipping.',
        },
      },
    }

    vim.api.nvim_create_autocmd('User', {
      pattern = 'DashboardLoaded',
      group = vim.api.nvim_create_augroup('dashboard-custom-restyle', { clear = true }),
      callback = function(args)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            restyle_dashboard_entries(args.buf)
          end
        end)
      end,
    })

    vim.api.nvim_create_autocmd('VimResized', {
      group = 'dashboard-custom-restyle',
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].filetype == 'dashboard' then
          restyle_dashboard_entries(buf)
        end
      end,
    })
  end,
  dependencies = { { 'nvim-tree/nvim-web-devicons' } },
}

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
  end,
  dependencies = { { 'nvim-tree/nvim-web-devicons' } },
}

return {
  'nvimdev/dashboard-nvim',
  event = 'VimEnter',
  config = function()
    math.randomseed(vim.loop.hrtime())

    local dp = require('dashboard-projects')

    local usage_path = vim.fn.stdpath('cache') .. '/dashboard/usage'
    local project_usage = dp.read_usage(usage_path)

    local function stamp_project_open(project_path)
      project_usage[project_path] = os.time()
      dp.write_usage(usage_path, project_usage)
    end

    local function cd_and_open_recent_file(project_path)
      if vim.fn.isdirectory(project_path) ~= 1 then
        vim.notify('Invalid project path: ' .. project_path, vim.log.levels.WARN)
        return
      end

      local normalized_root = vim.fs.normalize(project_path)
      stamp_project_open(normalized_root)
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

      local readme = normalized_root .. '/README.md'
      if vim.fn.filereadable(readme) == 1 then
        vim.cmd('edit ' .. vim.fn.fnameescape(readme))
        return
      end

      vim.notify('No recent file found for ' .. normalized_root, vim.log.levels.INFO)
    end

    local function reverse_copy(list)
      local reversed = {}
      for idx = #list, 1, -1 do
        table.insert(reversed, list[idx])
      end
      return reversed
    end

    local dashboard_cache = vim.fn.stdpath('cache') .. '/dashboard/cache'

    -- Workspace variants by panel main path, rebuilt with every panel list
    -- computation. Consumed by restyle_dashboard_entries for the Shift+letter
    -- variant selector bindings.
    local panel_variants = {}

    local function collect_candidates()
      local j_bookmarks = dp.load_bookmarks(
        vim.fn.expand('~/.bookmarks'),
        vim.fn.stdpath('data') .. '/zsh-bookmark-jumper.json'
      )
      local dashboard_projects = dp.read_project_list(dashboard_cache)
      return dp.collect(j_bookmarks, dashboard_projects, project_usage)
    end

    -- Panel mains (min workspace path per group, usage-sorted,
    -- archive-filtered). Same list is written to the plugin's cache file.
    local function get_display_projects()
      local groups = dp.group(collect_candidates(), project_usage)
      local mains, variants = dp.panel_mains(groups)
      panel_variants = variants
      return mains
    end

    local function get_picker_entries(include_archived)
      return dp.picker_entries(collect_candidates(), include_archived)
    end

    local function open_project_picker(entries, title, empty_msg)
      local ok_pickers, pickers = pcall(require, 'telescope.pickers')
      local ok_finders, finders = pcall(require, 'telescope.finders')
      local ok_conf, conf = pcall(require, 'telescope.config')
      local ok_actions, actions = pcall(require, 'telescope.actions')
      local ok_state, action_state = pcall(require, 'telescope.actions.state')
      if not (ok_pickers and ok_finders and ok_conf and ok_actions and ok_state) then
        vim.notify('Telescope is not available', vim.log.levels.WARN)
        return
      end

      if #entries == 0 then
        vim.notify(empty_msg, vim.log.levels.INFO)
        return
      end

      pickers.new({}, {
        prompt_title = title,
        finder = finders.new_table {
          results = entries,
          entry_maker = function(entry)
            local display = vim.fn.fnamemodify(entry.path, ':~') .. entry.mark
            return {
              value = entry.path,
              display = display,
              ordinal = display,
            }
          end,
        },
        sorter = conf.values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if selection and selection.value then
              cd_and_open_recent_file(selection.value)
            end
          end)
          return true
        end,
      }):find()
    end

    local function open_project_jump_picker()
      open_project_picker(
        get_picker_entries(false),
        'Jump + Recent Projects',
        'No jump/recent projects found'
      )
    end

    local function open_project_archived_picker()
      open_project_picker(
        get_picker_entries(true),
        'All Projects (incl. archived)',
        'No projects found'
      )
    end

    local function open_workspace_selector(target)
      local members = (target and target.variants) or {}
      if #members == 0 then
        return
      end
      local items = {}
      for _, m in ipairs(members) do
        table.insert(items, {
          path = m.path,
          label = vim.fn.fnamemodify(m.path, ':~') .. ' (' .. dp.rel_age(m.usage) .. ')',
        })
      end
      vim.ui.select(items, {
        prompt = 'Workspace:',
        format_item = function(item)
          return item.label
        end,
      }, function(choice)
        if choice then
          cd_and_open_recent_file(choice.path)
        end
      end)
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

    -- Shortcut keys ([l] Lazy, [q] Quit, [p] Jump Projects, [P] All incl.
    -- archived) are reserved. Populated below where the shortcuts table is
    -- defined; entry-letter maps must never use these keys or they silently
    -- override the buffer-local shortcut maps bound while the dashboard
    -- renders.
    local reserved_shortcut_keys = {}

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
            local variants = nil
            if section == 'project' then
              variants = panel_variants[vim.fs.normalize(expanded)]
              if variants and #variants < 2 then
                variants = nil
              end
            end
            row_targets[idx - 1] = {
              path = expanded,
              is_project = section == 'project',
              variants = variants,
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
          -- Shadowing guard: restyle must never rebind a multi-char token
          -- or a reserved shortcut key ([l]/[q]/[p]/[P]) — dashboard-nvim
          -- binds those on the same buffer, and a later keymap.set for the
          -- same key would silently kill the shortcut.
          if key:match('^%S+$') and #key == 1 and not reserved_shortcut_keys[key] then
            vim.keymap.set('n', key, function()
              open_target(target)
            end, {
              buffer = bufnr,
              silent = true,
              nowait = true,
              desc = 'dashboard custom entry open',
            })
            -- Workspace groups: Shift+letter opens the variant selector.
            -- Entry letters come from the lowercase-only pool, so the
            -- uppercase form is free (guarded anyway for future-proofing).
            local upper = key:upper()
            if target.variants and upper ~= key and not reserved_shortcut_keys[upper] then
              vim.keymap.set('n', upper, function()
                open_workspace_selector(target)
              end, {
                buffer = bufnr,
                silent = true,
                nowait = true,
                desc = 'dashboard workspace variants',
              })
            end
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

    local display_projects = get_display_projects()
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
      {
        icon = ' ',
        desc = ' Jump Projects',
        group = 'DiagnosticInfo',
        action = open_project_jump_picker,
        key = 'p',
      },
      {
        icon = '󰈞 ',
        desc = ' All incl. archived',
        group = 'DiagnosticInfo',
        action = open_project_archived_picker,
        key = 'P',
      },
    }

    -- Mark the shortcut keys as reserved for restyle_dashboard_entries and
    -- for the entry-letter pool (letter_list below omits them too).
    for _, item in ipairs(shortcuts) do
      reserved_shortcut_keys[item.key] = true
    end

    -- dashboard-nvim persists its config when the last dashboard buffer
    -- closes (cache_opts): function shortcut actions are string.dump-ed to
    -- the cache, and the next :Dashboard in the same instance restores them
    -- from bytecode (get_opts). Restored closures lose their upvalues, so
    -- the [p] Jump Projects action dies with "attempt to call a nil value
    -- (upvalue ...)". Snapshot the live actions here and re-bind them on
    -- every render so the shortcuts survive the cache round-trip.
    local shortcut_actions = {}
    for _, item in ipairs(shortcuts) do
      shortcut_actions[item.key] = item.action
    end

    local function rebind_shortcut_keys(bufnr)
      for key, action in pairs(shortcut_actions) do
        vim.keymap.set('n', key, function()
          if type(action) == 'function' then
            action()
          else
            vim.cmd(action)
          end
        end, {
          buffer = bufnr,
          silent = true,
          nowait = true,
          desc = 'dashboard-shortcut-' .. key,
        })
      end
    end

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
      shortcut_type = 'letter',
      shuffle_letter = false,
      -- 'l', 'q' and 'p' removed: they belong to the shortcuts above, and
      -- keeping them out of the entry-letter pool guarantees entry rows can
      -- never shadow the [l]/[q]/[p]/[P] maps ('P' is uppercase so it never
      -- collides with the lowercase-only pool anyway).
      letter_list = 'asdfqwertyuiozxcvbnmghjk',
      config = {
        shortcuts_left_side = true,
        header = fire_headers[math.random(#fire_headers)],
        week_header = {
          enable = false,
        },
        shortcut = shortcuts,
        project = {
          enable = true,
          limit = dp.PANEL_LIMIT,
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
          'S-<letter> workspace variants · [P] all projects incl. archived',
          'Keep shipping.',
        },
      },
    }

    vim.api.nvim_create_autocmd('User', {
      pattern = 'DashboardLoaded',
      group = vim.api.nvim_create_augroup('dashboard-custom-restyle', { clear = true }),
      callback = function(args)
        -- Refresh the panel list for the NEXT open (usage/archive state may
        -- have changed this session); the current render already read the
        -- file, so this render keeps showing it until the next :Dashboard.
        local refreshed = get_display_projects()
        if #refreshed > 0 then
          write_dashboard_projects(dashboard_cache, reverse_copy(refreshed))
        end
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            -- Re-bind the shortcut keys with the live actions first: on a
            -- re-opened :Dashboard the plugin has restored the shortcut
            -- actions from string.dump bytecode with nil upvalues, so its
            -- own [p]/[P] bindings are broken until we override them here.
            rebind_shortcut_keys(args.buf)
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

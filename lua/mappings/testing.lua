local map = vim.keymap.set

-- CTest / GTest picker: find build dir, list ctest tests + gtest suites/cases,
-- show in Telescope, save selected command to .local_cmd_bookmarks and run it.
-- <C-f> in prompt: use typed text as *text* gtest wildcard on highlighted item's binary.
-- TODO: Make it a plugin, even integrate well into telescope (e.g. for tests only on current file)
local function ctest_gtest_picker(term_pos, term_id)
  -- Search upward from cwd for a directory containing CTestTestfile.cmake.
  local function find_build_dir()
    local cwd = vim.fn.getcwd()
    local build_names = { "build", "Build", "_build", "cmake-build-debug", "cmake-build-release" }

    local function has_ctest(dir)
      return vim.fn.filereadable(dir .. "/CTestTestfile.cmake") == 1
    end

    -- Check cwd and common subdirs first
    if has_ctest(cwd) then return cwd end
    for _, bd in ipairs(build_names) do
      if has_ctest(cwd .. "/" .. bd) then return cwd .. "/" .. bd end
    end

    -- Walk up to git root and repeat
    local git_root_lines = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")
    if vim.v.shell_error == 0 and git_root_lines and #git_root_lines > 0 then
      local root = vim.trim(git_root_lines[1])
      if root ~= cwd then
        if has_ctest(root) then return root end
        for _, bd in ipairs(build_names) do
          if has_ctest(root .. "/" .. bd) then return root .. "/" .. bd end
        end
      end
    end
    return nil
  end

  -- Parse `binary --gtest_list_tests` output.
  -- Returns { [suite_name] = { "TestA", "TestB", ... }, ... }
  local function parse_gtest_list(binary)
    if vim.fn.executable(binary) ~= 1 then return nil end
    local out = vim.fn.systemlist(vim.fn.shellescape(binary) .. " --gtest_list_tests 2>/dev/null")
    if vim.v.shell_error ~= 0 or not out then return nil end
    local suites = {}
    local cur = nil
    for _, line in ipairs(out) do
      -- Suite header: "SuiteName." or "Inst/SuiteName." (parameterised/typed tests)
      local suite = line:match("^(%w[%w_:/]*%.)")
      if suite and not line:match("^%s") then
        cur = suite:sub(1, -2) -- strip trailing dot
        suites[cur] = suites[cur] or {}
      elseif cur and line:match("^%s+%S") then
        local t = line:match("^%s+(%S+)")
        if t then
          t = t:gsub("/%d+$", "") -- strip parameterised suffix /0 /1 ...
          -- deduplicate
          local dup = false
          for _, existing in ipairs(suites[cur]) do
            if existing == t then dup = true; break end
          end
          if not dup then table.insert(suites[cur], t) end
        end
      end
    end
    return suites
  end

  -- Collect picker items synchronously (gtest_list_tests is instant).
  local build_dir = find_build_dir()
  if not build_dir then
    vim.notify("CTest: no build directory found (CTestTestfile.cmake missing)", vim.log.levels.WARN)
    return
  end

  local raw = vim.fn.system("ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --show-only=json-v1 2>/dev/null")
  local ok, info = pcall(vim.fn.json_decode, raw)
  if not ok or not info or not info.tests or #info.tests == 0 then
    vim.notify("CTest: no tests found in " .. build_dir, vim.log.levels.WARN)
    return
  end

  local items = {}

  -- item: { display, name, command, binary?, working_dir? }
  -- binary + working_dir are stored so <C-f> can build ad-hoc filter commands.
  local function add(display, name, cmd, binary, working_dir)
    table.insert(items, { display = display, name = name, command = cmd,
                           binary = binary, working_dir = working_dir })
  end

  -- Build a direct binary command: "cd <wdir> && <binary> [--gtest_filter=<f>]"
  local function make_bin_cmd(binary, working_dir, filter)
    local prefix = working_dir and ("cd " .. vim.fn.shellescape(working_dir) .. " && ") or ""
    local suffix = filter and (" --gtest_filter=" .. vim.fn.shellescape(filter)) or ""
    return prefix .. binary .. suffix
  end

  -- [ALL]: must use ctest since there may be multiple binaries
  add("[ALL] Run all ctest tests", "ctest: all",
    "ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --output-on-failure")

  for _, test in ipairs(info.tests) do
    local cname  = test.name
    local binary = test.command and test.command[1]

    local wdir = nil
    for _, prop in ipairs(test.properties or {}) do
      if prop.name == "WORKING_DIRECTORY" then wdir = prop.value; break end
    end

    local suites = binary and parse_gtest_list(binary)
    if suites then
      -- Run all gtest tests in this binary (no filter)
      add("[CTEST] " .. cname, "ctest: " .. cname,
        make_bin_cmd(binary, wdir, nil), binary, wdir)

      local suite_names = vim.tbl_keys(suites)
      table.sort(suite_names)
      for _, suite in ipairs(suite_names) do
        add("  [SUITE] " .. suite,
          "ctest: " .. cname .. " / suite: " .. suite,
          make_bin_cmd(binary, wdir, suite .. ".*"), binary, wdir)

        local tests = suites[suite]
        table.sort(tests)
        for _, tname in ipairs(tests) do
          add("    [TEST] " .. suite .. "." .. tname,
            "ctest: " .. cname .. " / " .. suite .. "." .. tname,
            make_bin_cmd(binary, wdir, suite .. "." .. tname), binary, wdir)
        end
      end
    else
      -- No gtest binary — fall back to plain ctest
      local ctest_r = " -R " .. vim.fn.shellescape("^" .. cname .. "$")
      add("[CTEST] " .. cname, "ctest: " .. cname,
        "ctest --test-dir " .. vim.fn.shellescape(build_dir) .. " --output-on-failure" .. ctest_r)
    end
  end

  -- ── save & run ─────────────────────────────────────────────────────────────
  local function save_and_run(item)
    local cwd   = vim.fn.getcwd()
    local bfile = cwd .. "/.local_cmd_bookmarks"
    local lines = vim.fn.filereadable(bfile) == 1 and vim.fn.readfile(bfile) or {}
    local exists = false
    for _, l in ipairs(lines) do
      if l:match("^([^|]+)|") == item.name then exists = true; break end
    end
    if not exists then
      table.insert(lines, item.name .. "|" .. item.command)
      if vim.fn.writefile(lines, bfile) ~= 0 then
        vim.notify("CTest picker: failed to write " .. bfile, vim.log.levels.ERROR)
      end
    end
    require("nvchad.term").runner { pos = term_pos, cmd = item.command, id = term_id, clear_cmd = false }
    vim.notify("Running: " .. item.command, vim.log.levels.INFO)
  end

  -- ── telescope picker ───────────────────────────────────────────────────────
  local tel_ok = pcall(require, "telescope")
  if tel_ok then
    require("telescope.pickers").new({}, {
      prompt_title = "CTest / GTest  [" .. build_dir .. "]  (<C-f> = custom filter)",
      finder = require("telescope.finders").new_table({
        results = items,
        entry_maker = function(e)
          return { value = e, display = e.display, ordinal = e.display }
        end,
      }),
      sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
      previewer = require("telescope.previewers").new_buffer_previewer({
        title = "Command",
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
            "Name:", "  " .. entry.value.name, "",
            "Command:", "  " .. entry.value.command,
          })
        end,
      }),
      attach_mappings = function(prompt_bufnr, tmap)
        local actions = require("telescope.actions")
        local state   = require("telescope.actions.state")

        -- Enter: get selection BEFORE close (close destroys picker state)
        actions.select_default:replace(function()
          local sel = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if sel then save_and_run(sel.value) end
        end)

        -- <C-f>: treat prompt text as *text* gtest wildcard on highlighted binary
        tmap("i", "<C-f>", function()
          local prompt_text = state.get_current_line()
          local sel         = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not prompt_text or prompt_text == "" then
            vim.notify("CTest picker: type a filter pattern before pressing <C-f>", vim.log.levels.WARN)
            return
          end
          local binary = sel and sel.value and sel.value.binary
          if not binary then
            vim.notify("CTest picker: highlighted entry has no gtest binary", vim.log.levels.WARN)
            return
          end
          local filter = "*" .. prompt_text .. "*"
          save_and_run({
            name    = "gtest filter: " .. filter,
            command = make_bin_cmd(binary, sel.value.working_dir, filter),
            binary  = binary, working_dir = sel.value.working_dir,
          })
        end)

        return true
      end,
    }):find()
  else
    vim.ui.select(items, {
      prompt = "Select CTest / GTest test to run:",
      format_item = function(i) return i.display end,
    }, function(choice)
      if choice then save_and_run(choice) end
    end)
  end
end

-- Combined function: execute shell script if applicable, else run ctest picker
local function exec_shell_or_ctest(pos, term_id)
  local filepath = vim.fn.expand("%:p")
  local ext = vim.fn.expand("%:e")
  local shell_extensions = { sh = true, bash = true, zsh = true, fish = true, ksh = true }

  if shell_extensions[ext] then
    -- Execute shell script from git worktree root
    local filedir = vim.fn.fnamemodify(filepath, ":h")
    local git_root_lines = vim.fn.systemlist("git -C " .. vim.fn.shellescape(filedir) .. " rev-parse --show-toplevel 2>/dev/null")
    if vim.v.shell_error ~= 0 or not git_root_lines or #git_root_lines == 0 then
      vim.notify("Not in a git repository", vim.log.levels.ERROR)
      return
    end
    local git_root = vim.trim(git_root_lines[1])

    -- Make script executable if needed
    local stat = vim.loop.fs_stat(filepath)
    if stat and bit.band(stat.mode, 0x40) == 0 then
      vim.fn.system("chmod +x " .. vim.fn.shellescape(filepath))
    end

    -- Run script from git root in the terminal (same mechanism as ctest picker)
    local script_rel = filepath:sub(#git_root + 2)
    local cmd = "cd " .. vim.fn.shellescape(git_root) .. " && ./" .. vim.fn.shellescape(script_rel)
    require("nvchad.term").runner { pos = pos, cmd = cmd, id = term_id, clear_cmd = false }
    vim.notify("Running: " .. cmd, vim.log.levels.INFO)
  else
    -- Fall back to ctest picker
    ctest_gtest_picker(pos, term_id)
  end
end

map("n", "<leader><A-H>", function()
  exec_shell_or_ctest("sp", "htoggleTerm")
end, { desc = "Execute shell script or CTest picker — horizontal" })

map("n", "<leader><A-V>", function()
  ctest_gtest_picker("vsp", "vtoggleTerm")
end, { desc = "CTest / GTest picker — vertical right terminal" })

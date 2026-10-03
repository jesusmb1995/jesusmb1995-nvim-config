-- quicknote.nvim — in-place notes, scoped per project.
--
-- Scopes:
--   <leader>qn  note at current line  -> keyed by (project, file path, line)
--   <leader>qN  the project note      -> keyed by (project) only, no line
--   <leader>ql  all notes in project  -> bottom panel, jump or open
--   <leader>qL  notes in this file    -> bottom panel, jump or open
--
-- Storage: the plugin has NO data-path option (only mode = portable |
-- resident), so we override its path resolver to keep notes in $HOME
-- instead of polluting the repo with a .quicknote/ folder:
--   ~/.local/share/quicknote/<hash of project root>/<hash of note scope>/
--
-- Why mode = "portable" even though we redirect the data path: portable is
-- the only mode whose hash input is the *relative* file path. Resident mode
-- hashes the file BASENAME, so every main.cpp in every project would share
-- one note dir.
--
-- jj notes:
--  * Scoping is by project root, which does not change between patches, so
--    notes follow you across `jj new`, `jj squash`, rebase and rewrites.
--  * Line-keyed notes are keyed by LINE NUMBER, so they drift when a patch
--    adds or removes lines above them. The project note (<leader>qN) is
--    patch-independent — use it for anything that must stay put.
--  * git_branch_recognizable is forced off: jj has no branch, and in a git
--    colocated repo the value would churn on every export, scattering notes
--    into a new dir each time.

local function project_root()
  for _, cmd in ipairs({ { "jj", "root" }, { "git", "rev-parse", "--show-toplevel" } }) do
    local out = vim.fn.systemlist(cmd)
    if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
      return vim.fs.normalize(out[1])
    end
  end
  return vim.fs.normalize(vim.fn.getcwd())
end

-- Open (creating if needed) the single project-wide note. The plugin's own
-- NewNoteAtCWD/OpenNoteAtCWD both prompt with vim.fn.input for a name, which is
-- noise for a "just take me there" binding — so drive the path helpers directly.
local function project_note()
  local path = require("quicknote.utils.path")
  local utils = require("quicknote.utils")
  local dir = path.getNoteDirPathForCWD()
  local file = dir .. "/project." .. utils.config.GetFileType()
  vim.fn.mkdir(dir, "p")
  if vim.fn.filereadable(file) == 0 then
    vim.fn.writefile({ "# " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"), "" }, file)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(file))
end

-- Reverse the plugin's hash so a note dir can be traced back to its source
-- file. The plugin hashes the path RELATIVE to cwd (plenary make_relative),
-- so the scan must use the same base or nothing will match.
local function source_index()
  local sha = require("quicknote.utils.sha")
  local ppath = require("plenary.path")
  local root = project_root()
  local index = {}
  for _, f in ipairs(vim.fn.glob(root .. "/**/*", true, true)) do
    if vim.fn.isdirectory(f) == 0 and not f:match("/%.") then
      index[sha.sha1(ppath:new(f):make_relative())] = f
    end
  end
  return index, root
end

-- Bottom panel listing notes. <CR> jumps to the noted line, <C-e> opens the
-- note itself for editing.
local function note_picker(scope)
  local path = require("quicknote.utils.path")
  local utils = require("quicknote.utils")
  local ft = utils.config.GetFileType()
  local files
  if scope == "file" then
    files = vim.fn.glob(path.getNoteDirPathForCurrentBuffer() .. "/*." .. ft, true, true)
  else
    files = vim.fn.glob(path.GetDataPath() .. "/**/*." .. ft, true, true)
  end
  if not files or #files == 0 then
    vim.notify("No notes yet — <leader>qn for this line, <leader>qN for the project", vim.log.levels.WARN)
    return
  end
  -- numeric line order for line notes, then plain name order for named ones
  table.sort(files, function(a, b)
    local la = tonumber(a:match("(%d+)%." .. ft .. "$"))
    local lb = tonumber(b:match("(%d+)%." .. ft .. "$"))
    if la and lb then
      return la < lb
    end
    if la then
      return true
    end
    if lb then
      return false
    end
    return a < b
  end)

  local index = scope == "file" and nil or source_index()
  local this_file = vim.api.nvim_buf_get_name(0)
  local items = {}
  for _, f in ipairs(files) do
    local note_name = vim.fn.fnamemodify(f, ":t:r")
    local line = tonumber(note_name)
    local src = nil
    if scope == "file" then
      src = this_file
    else
      -- note dir name is the hash of the source file's relative path
      src = index and index[vim.fn.fnamemodify(f, ":h"):match("([^/]+)$") or ""]
    end
    local body = table.concat(vim.fn.readfile(f), "\n")
    local first = vim.split(body, "\n")[1] or ""
    table.insert(items, {
      file = f,
      line = line,
      src = src,
      text = (line and ("line " .. line) or "project")
        .. (src and ("  " .. vim.fn.fnamemodify(src, ":~:.")) or "")
        .. (first ~= "" and ("  — " .. first) or ""),
      body = body,
    })
  end

  local ok_snacks, Snacks = pcall(require, "snacks")
  if not (ok_snacks and Snacks and Snacks.picker) then
    for _, it in ipairs(items) do
      print(it.text)
    end
    return
  end
  Snacks.picker.pick({
    title = scope == "file" and "Notes in this file  ·  <CR> jump  ·  <C-e> open" or "Notes in project  ·  <CR> jump  ·  <C-e> open",
    layout = { preset = "ivy", position = "bottom" },
    items = items,
    format = "text",
    win = { input = { keys = { ["<c-e>"] = { "note_open", mode = { "n", "i" } } } } },
    preview = function(ctx)
      if not ctx.item then return false end
      local lines = vim.split(ctx.item.body or "", "\n")
      if #lines > 60 then
        vim.list_extend(lines, { "-- (" .. (#lines - 60) .. " more lines)" })
        lines = vim.list_slice(lines, 1, 60)
      end
      ctx.preview:set_lines(#lines > 0 and lines or { "(empty note)" })
      ctx.preview:highlight({ ft = "markdown" })
      return true
    end,
    actions = {
      note_open = function(picker, item)
        if not item then return end
        picker:close()
        vim.cmd("split " .. vim.fn.fnameescape(item.file))
      end,
    },
    confirm = function(picker, item)
      if not item then return end
      picker:close()
      if item.src and vim.fn.filereadable(item.src) == 1 then
        vim.cmd("edit " .. vim.fn.fnameescape(item.src))
        if item.line and item.line > 0 then
          pcall(vim.api.nvim_win_set_cursor, 0, { item.line, 0 })
          vim.cmd("normal! zz")
        end
      elseif item.file then
        vim.cmd("split " .. vim.fn.fnameescape(item.file))
      end
    end,
  })
end

return {
  "RutaTang/quicknote.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
cmd = { "QuickNote" },
  -- eager: the sign marks must be there the moment a file is opened, and a
  -- lazy plugin only installs its autocmds after the first <leader>q* keypress
  -- — by which point BufReadPost has passed and the file stays unmarked.
  lazy = false,
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  keys = {
    { "<leader>qn", function() require("quicknote").NewNoteAtCurrentLine() end, mode = "n", desc = "Note: new at current line (project+file+line)" },
    { "<leader>qN", project_note, mode = "n", desc = "Note: go to project note (create if missing)" },
    { "<leader>qo", function() require("quicknote").OpenNoteAtCurrentLine() end, mode = "n", desc = "Note: open at current line" },
    { "<leader>qd", function() require("quicknote").DeleteNoteAtCurrentLine() end, mode = "n", desc = "Note: delete at current line" },
    { "<leader>ql", function() note_picker("project") end, mode = "n", desc = "Note: list project notes (jump/open)" },
    { "<leader>qL", function() note_picker("file") end, mode = "n", desc = "Note: list this file's notes (jump/open)" },
    { "<leader>q]", function() require("quicknote").JumpToNextNote() end, mode = "n", desc = "Note: jump to next note in file" },
    { "<leader>q[", function() require("quicknote").JumpToPreviousNote() end, mode = "n", desc = "Note: jump to previous note in file" },
    { "<leader>qt", function() require("quicknote").ToggleNoteSigns() end, mode = "n", desc = "Note: toggle note signs (on by default)" },
  },
  config = function()
    -- Redirect storage OUT OF THE REPO BEFORE calling setup().
    -- getNoteDirPathForCurrentBuffer/CWD call a LOCAL getHashedNoteDirPath,
    -- which calls M.GetDataPath() — so overriding M.GetDataPath is the one
    -- hook that actually redirects storage. It must be in place first because
    -- setup() eagerly does MKDirAsync(GetDataPath()), which would otherwise
    -- create <project>/.quicknote.
    local base = vim.fs.normalize(vim.fn.expand("~/.local/share/quicknote"))
    require("quicknote.utils.path").GetDataPath = function()
      -- First level keys the project, so two repos never share notes even
      -- when a relative path happens to be identical.
      return base .. "/" .. vim.fn.sha256(project_root()):sub(1, 16)
    end

    require("quicknote").setup({
      mode = "portable",
      -- Same private-use glyph as vim-bookmarks' BookmarkSign (U+F0AE), so
      -- note marks and bookmarks look alike in the sign column. Neovim appends
      -- its own trailing space, hence the stored text is 4 bytes.
      sign = vim.fn.nr2char(0xf0ae),
      filetype = "md",
      -- jj has no branch; branch-keyed dirs would scatter notes (see header).
      git_branch_recognizable = false,
    })

    -- The plugin's sign has texthl="QuickNote" but never defines it.
    vim.api.nvim_set_hl(0, "QuickNote", { default = true, link = "Special" })

    -- Signs ON by default: the plugin only ever shows them after an explicit
    -- ShowNoteSigns(), so without this a note is invisible until <leader>qt.
    -- First sight of a buffer turns them on; afterwards respect the user's
    -- toggle (ReShow only acts when the state is SHOW).
    local function refresh_signs(buf)
      -- The plugin's Show/ReShow act on the CURRENT buffer, so only ever mark
      -- the one in front. (Routing marks for other buffers via nvim_buf_call
      -- puts them on the wrong buffer.) BufEnter covers switching later.
      -- buf == 0 means "wherever we are", used by the load-time pass below.
      local cur = vim.api.nvim_get_current_buf()
      if buf ~= 0 and buf ~= cur then
        return
      end
      buf = cur
      if vim.bo[buf].buftype ~= "" then
        return
      end
      pcall(function()
        local sign = require("quicknote.core.sign")
        if sign.GetSignDisplayState(buf) == nil then
          sign.ShowNoteSigns()
        else
          sign.ReShowSignsForCurrentBuffer()
        end
      end)
    end

    local group = vim.api.nvim_create_augroup("QuickNoteSigns", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter" }, {
      group = group,
      callback = function(ev)
        refresh_signs(ev.buf)
      end,
    })
    -- config() runs during startup, which can be BEFORE the file named on the
    -- command line is read, so BufReadPost for it may already have gone by.
    -- VimEnter is the first event guaranteed to be after both.
    vim.api.nvim_create_autocmd({ "VimEnter", "BufWinEnter" }, {
      group = group,
      callback = function()
        refresh_signs(0)
      end,
    })
    refresh_signs(0)
    vim.schedule(function()
      refresh_signs(0)
    end)

    -- Optional telescope integration; guard so a missing/renamed extension
    -- cannot break startup.
    pcall(function()
      require("telescope").load_extension("quicknote")
    end)
  end,
}
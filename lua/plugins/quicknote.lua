-- quicknote.nvim — in-place notes, scoped per project.
--
-- Two scoping levels, matching how notes are actually used:
--   <leader>qn  note at current line  -> keyed by (project, file path, line)
--   <leader>qN  note for the project  -> keyed by (project) only, no line
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
--    adds or removes lines above them. Project-keyed notes (<leader>qN) are
--    patch-independent — use those for anything that must stay put.
--  * git_branch_recognizable is forced off: jj has no branch, and in a git
--    colocated repo the value would churn on every export, scattering notes
--    into a new dir each time.
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

return {
  "RutaTang/quicknote.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "QuickNote" },
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  keys = {
    { "<leader>qn", function() require("quicknote").NewNoteAtCurrentLine() end, mode = "n", desc = "Note: new at current line (project+file+line)" },
    { "<leader>qN", project_note, mode = "n", desc = "Note: go to project note (create if missing)" },
    { "<leader>qo", function() require("quicknote").OpenNoteAtCurrentLine() end, mode = "n", desc = "Note: open at current line" },
    { "<leader>qd", function() require("quicknote").DeleteNoteAtCurrentLine() end, mode = "n", desc = "Note: delete at current line" },
    { "<leader>ql", function() require("quicknote").ListNotesForCWD() end, mode = "n", desc = "Note: list for current project" },
    { "<leader>qL", function() require("quicknote").ListNotesForCurrentBuffer() end, mode = "n", desc = "Note: list for current file" },
    { "<leader>q]", function() require("quicknote").JumpToNextNote() end, mode = "n", desc = "Note: jump to next note in file" },
    { "<leader>q[", function() require("quicknote").JumpToPreviousNote() end, mode = "n", desc = "Note: jump to previous note in file" },
    { "<leader>qt", function() require("quicknote").ToggleNoteSigns() end, mode = "n", desc = "Note: toggle note signs" },
  },
  config = function()
    require("quicknote").setup({
      mode = "portable",
      sign = "󰆑",
      filetype = "md",
      -- jj has no branch; branch-keyed dirs would scatter notes (see header).
      git_branch_recognizable = false,
    })

    -- Keep notes in $HOME instead of <project>/.quicknote.
    -- getNoteDirPathForCurrentBuffer/CWD call a LOCAL getHashedNoteDirPath,
    -- which calls M.GetDataPath() — so overriding M.GetDataPath is the one
    -- hook that actually redirects storage.
    local base = vim.fs.normalize(vim.fn.expand("~/.local/share/quicknote"))
    local function project_root()
      for _, cmd in ipairs({ { "jj", "root" }, { "git", "rev-parse", "--show-toplevel" } }) do
        local out = vim.fn.systemlist(cmd)
        if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
          return vim.fs.normalize(out[1])
        end
      end
      return vim.fs.normalize(vim.fn.getcwd())
    end
    require("quicknote.utils.path").GetDataPath = function()
      -- First level keys the project, so two repos never share notes even
      -- when a relative path happens to be identical.
      return base .. "/" .. vim.fn.sha256(project_root()):sub(1, 16)
    end

    -- Optional telescope integration; guard so a missing/renamed extension
    -- cannot break startup.
    pcall(function()
      require("telescope").load_extension("quicknote")
    end)
  end,
}
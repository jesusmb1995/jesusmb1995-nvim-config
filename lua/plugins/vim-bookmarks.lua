
return {
  "MattesGroeger/vim-bookmarks",
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
-- Add/remove bookmark at current line	mm	:BookmarkToggle
-- Add/edit/remove annotation at current line	mi	:BookmarkAnnotate <TEXT>
-- Jump to next bookmark in buffer	mn	:BookmarkNext
-- Jump to previous bookmark in buffer	mp	:BookmarkPrev
-- Show all bookmarks (toggle)	ma	:BookmarkShowAll
-- Clear bookmarks in current buffer only	mc	:BookmarkClear
-- Clear bookmarks in all buffers	mx	:BookmarkClearAll
-- Move up bookmark at current line	[count]mkk	:BookmarkMoveUp [<COUNT>]
-- Move down bookmark at current line	[count]mjj	:BookmarkMoveDown [<COUNT>]
-- Move bookmark at current line to another line	[count]mg	:BookmarkMoveToLine <LINE>
-- Save all bookmarks to a file		:BookmarkSave <FILE_PATH>
-- Load bookmarks from a file		:BookmarkLoad <FILE_PATH>
  cmd={"BookmarkToggle", "BookmarkShowAll", "BookmarkAnnotate", "BookmarkNext", "BookmarkPrev", "BookmarkClear", "BookmarkClearAll", "BookmarkSave", "BookmarkLoad"},
  keys = {
    { "mm", mode = { "n" } },
    { "ma", mode = { "n" } },
    { "mM", mode = { "n" } },
    { "mA", mode = { "n" } },
    { "mn", mode = { "n" } },
    { "mp", mode = { "n" } },
    { "<leader>mm", mode = { "n" }, desc = "BookmarkToggle (leader)" },
    { "<leader>mM", mode = { "n" }, desc = "BookmarkToggle + save per-workspace (sqlite)" },
    { "<leader>ma", mode = { "n" }, desc = "BookmarkShowAll (leader)" },
    { "<leader>mA", mode = { "n" }, desc = "Show permanent bookmarks (leader)" },
  },
  init = function()
    vim.g.bookmark_sign = ""
    vim.g.bookmark_annotation_sign = ""
    vim.g.bookmark_save_per_working_dir = 1
    vim.g.bookmark_auto_save = 1
    vim.g.bookmark_auto_save_file = vim.fn.expand("~/.cache/nvim/bookmarks")
    vim.g.bookmark_highlight_lines = 1
    -- per-workspace sqlite: same dir as Dashboard's j_bookmarks
    vim.g.bookmark_manage_per_buffer = 1
    vim.g.bookmark_auto_save_file = vim.fn.expand("~/.cache/nvim/bookmarks/auto")
  end,
  config = function()
    -- mM / mA : permanent sqlite-backed bookmarks (per workspace, same as Dashboard)
    local map = vim.keymap.set
    local function workspace_key()
      local cwd = vim.fn.getcwd()
      local hash = vim.fn.sha256(cwd):sub(1,8)
      return hash, cwd
    end
    local function sqlite_path()
      local hash = workspace_key()
      local dir = vim.fn.expand("~/.cache/nvim/bookmarks")
      vim.fn.mkdir(dir, "p")
      return dir .. "/" .. hash .. ".bookmarks"
    end
    local function define_bookmark_maps()
      -- mM: toggle and immediately save to sqlite/per-workspace file
      map("n", "mM", function()
        vim.cmd("BookmarkToggle")
        vim.defer_fn(function()
          local path = sqlite_path()
          vim.cmd("silent! BookmarkSave " .. vim.fn.fnameescape(path))
          vim.notify("Bookmark toggled (permanent, workspace " .. workspace_key() .. ") → " .. path, vim.log.levels.INFO)
        end, 100)
      end, { desc = "BookmarkToggle + save per-workspace (sqlite)" })
      -- mA: show all permanent bookmarks for this workspace
      -- NOTE: call BookmarkLoad(file, 0, 1) with silent=1: the :BookmarkLoad
      -- command hardcodes silent=0 and prompts "Do you want to override your
      -- N bookmarks?" whenever any exist — pointless for mA which by definition
      -- wants the workspace file shown.
      local function load_workspace_silent(path)
        vim.fn["BookmarkLoad"](path, 0, 1)
      end
      map("n", "mA", function()
        local path = sqlite_path()
        if vim.fn.filereadable(path) == 1 then
          load_workspace_silent(path)
          vim.cmd("BookmarkShowAll")
          vim.notify("Loaded permanent bookmarks from " .. path, vim.log.levels.INFO)
        else
          vim.notify("No permanent bookmarks for this workspace yet (mM to create)", vim.log.levels.WARN)
          vim.cmd("BookmarkShowAll")
        end
      end, { desc = "Show permanent bookmarks (sqlite, per workspace)" })
      -- <leader> variants (user suspected <leader> blocked, provide both)
      map("n", "<leader>mm", function() vim.cmd("BookmarkToggle") end, { desc = "BookmarkToggle (leader)" })
      map("n", "<leader>mM", function()
        vim.cmd("BookmarkToggle")
        vim.defer_fn(function()
          local path = sqlite_path()
          vim.cmd("silent! BookmarkSave " .. vim.fn.fnameescape(path))
          vim.notify("Bookmark toggled (leader, permanent) → " .. path, vim.log.levels.INFO)
        end, 100)
      end, { desc = "BookmarkToggle + save (leader)" })
      map("n", "<leader>ma", function() vim.cmd("BookmarkShowAll") end, { desc = "BookmarkShowAll (leader)" })
      map("n", "<leader>mA", function()
        local path = sqlite_path()
        if vim.fn.filereadable(path) == 1 then
          load_workspace_silent(path)
          vim.cmd("BookmarkShowAll")
        else vim.cmd("BookmarkShowAll") end
      end, { desc = "Show permanent (leader)" })
      -- cleanup: :BookmarkClear for current buffer
      map("n", "<leader>mc", function() vim.cmd("BookmarkClear") end, { desc = "Clear bookmarks in current buffer" })
    end
    define_bookmark_maps()
    -- icon for current buffer: ensure signs are defined and highlight + cleanup helper
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
      callback = function()
        vim.fn.sign_define("BookmarkSign", { text = vim.g.bookmark_sign, texthl = "BookmarkSign" })
        vim.fn.sign_define("BookmarkAnnotationSign", { text = vim.g.bookmark_annotation_sign, texthl = "BookmarkAnnotationSign" })
      end,
    })
    -- expose cleanup: :BookmarkClearAll and removing sqlite file
    vim.api.nvim_create_user_command("BookmarkPurgeWorkspace", function()
      local path = sqlite_path()
      if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
        vim.notify("Purged workspace bookmarks: " .. path, vim.log.levels.INFO)
      end
      vim.cmd("BookmarkClearAll")
    end, { desc = "Purge sqlite bookmarks for this workspace" })
  end,
}

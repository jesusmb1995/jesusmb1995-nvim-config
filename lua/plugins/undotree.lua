return {
  "mbbill/undotree",
  lazy = true,
  cmd = {
    "UndotreeToggle",
    "UndotreeShow",
    "UndotreeHide",
    "UndotreeFocus",
  },
  init = function()
    local undodir = vim.fn.stdpath("state") .. "/undo"
    local max_undo_files = 1200
    local max_age_days = 2 

    local function cleanup_undo_files()
      local files = vim.fn.globpath(undodir, "*", false, true)
      local now = os.time()
      local max_age_seconds = max_age_days * 24 * 60 * 60
      local kept = {}

      for _, file in ipairs(files) do
        if vim.fn.filereadable(file) == 1 then
          local mtime = vim.fn.getftime(file)
          if mtime > 0 and (now - mtime) > max_age_seconds then
            pcall(vim.fn.delete, file)
          else
            table.insert(kept, { path = file, mtime = mtime })
          end
        end
      end

      table.sort(kept, function(a, b)
        return (a.mtime or 0) > (b.mtime or 0)
      end)

      for idx = max_undo_files + 1, #kept do
        pcall(vim.fn.delete, kept[idx].path)
      end
    end

    vim.fn.mkdir(undodir, "p")
    vim.opt.undofile = true
    vim.opt.undodir = undodir

    vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      callback = cleanup_undo_files,
      desc = "Trim persistent undo files by age and count",
    })
  end,
}

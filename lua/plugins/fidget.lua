-- Progress/notification UI (used by clang_tidy_analysis and LSP)
return {
  "j-hui/fidget.nvim",
  tag = "v1.2.0",
  opts = {
    notification = {
      override_vim_notify = true,
    },
    progress = {
      display = {
        done_icon = "✓",
        progress_icon = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        progress_icon_done = nil,
      },
    },
  },
}

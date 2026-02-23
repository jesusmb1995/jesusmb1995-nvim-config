-- Clang-tidy log parser: ClangTidyShowLog, ClangTidyDiff (from GitHub)
return {
  url = "https://github.com/jesusmb1995/nvim-clang-tidy-analysis",
  lazy = true,
  cmd = {
    "ClangTidyShowLog",
    "ClangTidyDiff",
    "ClangTidyGenerateOld",
    "ClangTidyGenerateNew",
    "ClangTidyGenerateNewDiff",
    "ClangTidyGenerateDiff",
  },
}

-- Own which-key spec on top of NvChad's (it lazy-loads on <leader> with a
-- dynamic default delay that raced timeoutlen=400, so the leader helper
-- panel sometimes never appeared). Pin delay=200: panel always shows on
-- pause, fast chords unaffected. Triggers left on auto.
return {
  "folke/which-key.nvim",
  opts = {
    delay = 200,
  },
}

return {
  {
    -- url = "https://github.com/jesusmb1995/savecmd",
    dir = "/luksmap/Code/savecmd",
    lazy = true,
    cmd = { "LaunchVert", "LaunchHoriz", "LaunchFloat" },
    keys = {
      { "<leader><A-v>", "<cmd>LaunchVert<cr>", desc = "Launch command in vertical terminal" },
      { "<leader><A-h>", "<cmd>LaunchHoriz<cr>", desc = "Launch command in horizontal terminal" },
      { "<leader><A-i>", "<cmd>LaunchFloat<cr>", desc = "Launch command in horizontal terminal" },
    },
    config = function()
      require('savecmd-nvim').setup()
    end
  }
}

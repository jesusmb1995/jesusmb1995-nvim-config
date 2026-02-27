return {
  {
    "rcarriga/nvim-notify",
    opts = {
      render = "compact",
      timeout = 2500,
      max_width = function()
        return math.floor(vim.o.columns * 0.4)
      end,
      max_height = function()
        return math.max(4, math.floor(vim.o.lines * 0.2))
      end,
    },
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    opts = {
      lsp = {
        progress = { enabled = false },
        hover = { enabled = true },
        signature = { enabled = true },
      },
      messages = { enabled = true, view = "mini" },
      notify = { enabled = true, view = "notify" },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
      routes = {
        {
          filter = { event = "msg_show", find = "written" },
          opts = { skip = true },
        },
      },
    },
  },
}

return {
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      exclude = {
        filetypes = { "noice", "notify", "NvimTree", "dashboard" },
      },
    },
  },
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
    "nvim-tree/nvim-tree.lua",
    opts = function(_, opts)
      local image_exts = { png = true, jpg = true, jpeg = true, gif = true, bmp = true, svg = true, webp = true }

      local function on_attach(bufnr)
        local api = require "nvim-tree.api"
        api.config.mappings.default_on_attach(bufnr)

        vim.keymap.set("n", "<CR>", function()
          local node = api.tree.get_node_under_cursor()
          if node and node.type == "file" then
            local ext = (node.name:match "%.(%w+)$" or ""):lower()
            if image_exts[ext] then
              vim.fn.jobstart({ "xdg-open", node.absolute_path }, { detach = true })
              return
            end
          end
          api.node.open.edit()
        end, { buffer = bufnr, noremap = true, silent = true, desc = "Open file / xdg-open images" })
      end

      return vim.tbl_deep_extend("force", opts, {
        view = { relativenumber = true, width = 40 },
        renderer = { full_name = true },
        update_focused_file = { enable = true },
        update_cwd = true,
        on_attach = on_attach,
      })
    end,
  },
  {
    "stevearc/dressing.nvim",
    event = "VeryLazy",
    opts = {
      input = { enabled = true },
      select = { enabled = true },
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
      throttle = 1000 / 30,
      cmdline = {
        view = "cmdline",
      },
      lsp = {
        progress = { enabled = false },
        hover = { enabled = false },
        signature = { enabled = false },
      },
      messages = { enabled = true, view = "mini" },
      notify = { enabled = true, view = "notify" },
      presets = {
        bottom_search = true,
        command_palette = false,
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

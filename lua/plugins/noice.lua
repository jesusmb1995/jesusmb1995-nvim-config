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
      background_colour = "#000000",
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

        -- Hover: show full path as virtual text to the right of the cursor line
        -- (not a floating box). User found the box-over-box ugly; this renders
        -- `  <full-path>` at eol, like `full_name` but always visible on hover.
        local hover_ns = vim.api.nvim_create_namespace("nvimtree-hover-" .. bufnr)
        local function clear_hover()
          vim.api.nvim_buf_clear_namespace(bufnr, hover_ns, 0, -1)
        end
        local function show_hover(explicit)
          clear_hover()
          local node = api.tree.get_node_under_cursor()
          if not node or not node.absolute_path then return end
          local win_width = vim.api.nvim_win_get_width(0)
          local is_truncated = #node.name > (win_width - 10) or #node.absolute_path > win_width
          if not explicit and not is_truncated and #node.absolute_path <= win_width then return end
          local text = node.absolute_path
          if node.type == "directory" then text = text .. "/" end
          local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
          -- render to the right (eol) with subtle highlight, no box
          vim.api.nvim_buf_set_extmark(bufnr, hover_ns, lnum, 0, {
            virt_text = { { "  " .. text, "Comment" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
          })
          if not explicit then vim.defer_fn(clear_hover, 2500) end
        end
        vim.keymap.set("n", "K", function() show_hover(true) end, { buffer = bufnr, noremap = true, silent = true, desc = "Show full path to the right (hover)" })
        vim.api.nvim_create_autocmd("CursorHold", {
          buffer = bufnr,
          callback = function() show_hover(false) end,
        })
        vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "WinLeave" }, {
          buffer = bufnr,
          callback = clear_hover,
        })
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

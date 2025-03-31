function GET_INIT_CONFIG()
  if vim.env.NVIM_MINIMAL == nil then
    return {
      {
        "stevearc/conform.nvim",
        -- event = 'BufWritePre', -- uncomment for format on save
        opts = require "configs.conform",
      },

      -- These are some examples, uncomment them if you want to see them work!
      {
        "neovim/nvim-lspconfig",
        config = function()
          require "configs.lspconfig"
        end,
      },

      {
        "nvim-treesitter/nvim-treesitter",
        opts = {
          ensure_installed = {
            -- NvChad originals (where commented out anyway)
            "vim",
            "lua",
            "vimdoc",
            "html",
            "css",

            -- Additions
            "cpp",
            "rust",
            "javascript",
            "typescript",
            "yaml",
            "json",
            "toml",
            "cmake",
          },
        },
      },
    }
  else
    return {
      {
        "stevearc/conform.nvim",
        enabled = false,
      },

      -- These are some examples, uncomment them if you want to see them work!
      {
        "neovim/nvim-lspconfig",
        enabled = false,
      },

      {
        "nvim-treesitter/nvim-treesitter",
        enabled = false,
      },
    }
  end
end

return GET_INIT_CONFIG()

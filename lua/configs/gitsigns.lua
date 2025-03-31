if vim.env.NVIM_MINIMAL == nil then
  require("gitsigns").setup {
    on_attach = function(bufnr)
      local gitsigns = require "gitsigns"

      local function map(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end

      -- Navigation
      map("n", "]c", function()
        if vim.wo.diff then
          vim.cmd.normal { "]c", bang = true }
        else
          gitsigns.nav_hunk "next"
        end
      end)

      map("n", "[c", function()
        if vim.wo.diff then
          vim.cmd.normal { "[c", bang = true }
        else
          gitsigns.nav_hunk "prev"
        end
      end)

      -- Actions
      map("n", "<leader>Hs", gitsigns.stage_hunk, { desc = "Stage hunk" })
      map("n", "<leader>Hr", gitsigns.reset_hunk, { desc = "Reset hunk" })

      map("v", "<leader>Hs", function()
        gitsigns.stage_hunk { vim.fn.line ".", vim.fn.line "v" }
      end, { desc = "Stage hunk" })

      map("v", "<leader>Hr", function()
        gitsigns.reset_hunk { vim.fn.line ".", vim.fn.line "v" }
      end, { desc = "Reset hunk" })

      map("n", "<leader>HS", gitsigns.stage_buffer, { desc = "Stage buffer" })
      map("n", "<leader>HR", gitsigns.reset_buffer, { desc = "Reset buffer" })
      map("n", "<leader>Hp", gitsigns.preview_hunk, { desc = "Preview hunk" })
      map("n", "<leader>Hi", gitsigns.preview_hunk_inline, { desc = "Preview hunk (inline)" })

      map("n", "<leader>Hb", function()
        gitsigns.blame_line { full = true }
      end, { desc = "Git blame" })
    end,
  }
end

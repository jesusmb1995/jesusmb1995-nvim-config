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

      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        lazy = false,
        config = function()
          require("telescope").load_extension("fzf")

          local Picker = require("telescope.pickers")
          local api = vim.api

          -- (1) Cap scoring: once entry_manager has max_results entries,
          --     skip sorter:score() + add_entry for all remaining results.
          --     The finder still runs to completion (so process_complete is
          --     called normally) but we avoid 10k+ unnecessary score calls.
          local orig_grp = Picker.get_result_processor
          function Picker:get_result_processor(find_id, prompt, status_updater)
            local process_result = orig_grp(self, find_id, prompt, status_updater)
            local picker = self
            return function(entry)
              if picker.manager and picker.manager:num_results() >= picker.max_results then
                return
              end
              return process_result(entry)
            end
          end

          -- (2) Throttle display: batch buffer writes + highlighting on a
          --     timer instead of per-entry. Only refreshes visible rows.
          local orig_entry_adder = Picker.entry_adder
          local REFRESH_MS = 100

          function Picker:entry_adder(index, entry, score, insert)
            if not self._ea_throttle then
              local picker = self
              local timer = vim.uv.new_timer()
              self._ea_throttle = { dirty = false, timer = timer }

              timer:start(REFRESH_MS, REFRESH_MS, vim.schedule_wrap(function()
                local t = picker._ea_throttle
                if not t or not t.dirty then
                  return
                end
                t.dirty = false

                if
                  picker.closed
                  or not picker.manager
                  or not picker.results_bufnr
                  or not api.nvim_buf_is_valid(picker.results_bufnr)
                  or not picker.results_win
                  or not api.nvim_win_is_valid(picker.results_win)
                then
                  timer:stop()
                  if not timer:is_closing() then
                    timer:close()
                  end
                  picker._ea_throttle = nil
                  return
                end

                local ok, h = pcall(api.nvim_win_get_height, picker.results_win)
                if not ok then
                  return
                end

                local idx = 0
                for e in picker.manager:iter() do
                  idx = idx + 1
                  if idx > h then
                    break
                  end
                  orig_entry_adder(picker, idx, e, nil, false)
                end

                pcall(function()
                  picker:_do_selection(picker:_get_prompt())
                end)
              end))
            end

            self._ea_throttle.dirty = true
          end
        end,
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

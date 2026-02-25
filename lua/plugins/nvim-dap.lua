local last_dap_config = nil

return {
  "mfussenegger/nvim-dap.nvim",
  url = "https://github.com/mfussenegger/nvim-dap",
  dependencies = { 'rcarriaga/nvim-dap-ui' },
  enabled = function()
    return vim.env.NVIM_MINIMAL == nil
  end,
  version = "*",
  keys = {
    {
      "<leader>dh",
      function()
        require("dap.ui.widgets").hover()
      end,
      desc = "Hover variable",
    },
    {
      "<leader>db",
      function()
        require("dap").toggle_breakpoint()
      end,
      desc = "Toggle breakpoint",
    },
    {
      "<leader>dB", 
      function()
        vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
          require("dap").toggle_breakpoint(condition)
        end)
      end,
      desc = "Toggle conditional breakpoint",
    },
    {
      "<leader>ds",
      function()
        require("dap").terminate()
      end,
      desc = "Stop debugging",
    },
    {
      "<F8>",
      function()
        require("dap").step_over()
      end,
      desc = "Step over",
    },
    {
      "<leader>do",
      function()
        require("dap").step_over()
      end,
      desc = "Step over",
    },
    {
      "<leader>dc",
      function()
        local dap = require("dap")
        -- If a session is already running, just continue
        if dap.session() then
          dap.continue()
          return
        end
        -- Offer "Reuse last config" in dropdown when we have one
        if last_dap_config and next(last_dap_config) then
          local name = last_dap_config.name or "unnamed"
          vim.ui.select(
            { "Reuse last config (" .. name .. ")", "Choose configuration..." },
            { prompt = "Debug: " },
            function(choice)
              if not choice then return end
              if choice:match("^Reuse last") then
                dap.run(vim.deepcopy(last_dap_config))
              else
                dap.continue({ new = true })
              end
            end
          )
        else
          dap.continue()
        end
      end,
      desc = "Start/Continue",
    },
    {
      "<leader>dr",
      function()
        require("dap").restart()
      end,
      desc = "Restart",
    },
    {
      "<leader>dC",
      function()
        require("dap").run_to_cursor()
      end,
      desc = "Run to cursor",
    },
    {
      "<F9>",
      function()
        require("dap").step_out()
      end,
      desc = "Step out",
    },
    {
      "<leader>du",
      function()
        require("dap").step_out()
      end,
      desc = "Step out",
    },
    {
      "<F7>",
      function()
        require("dap").step_into()
      end,
      desc = "Step into",
    },
    {
      "<leader>di",
      function()
        require("dap").step_into()
      end,
      desc = "Step into",
    },
    {
      "<leader>dd",
      function()
        require("dapui").toggle()
      end,
      desc = "Toggle DAP UI",
    },
  },
  config = function()
    require("dapui").setup()
    local dap = require("dap")
    dap.listeners.after.event_initialized["dap_save_last_config"] = function(session)
      if session and session.config then
        last_dap_config = vim.deepcopy(session.config)
      end
    end
  end,
}

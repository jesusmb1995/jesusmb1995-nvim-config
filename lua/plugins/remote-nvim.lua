return {
  "amitds1997/remote-nvim.nvim",
  version = "*",
  lazy = true,
  init = function()
    -- Prevent vim.loader filename-length failures for this plugin on systems
    -- where .cache/nvim/luac path segments can exceed filesystem limits.
    if vim.loader and vim.loader.disable then
      vim.loader.disable()
    end
  end,
  cmd = {
    "RemoteStart",
    "RemoteStop",
    "RemoteInfo",
    "RemoteCleanup",
    "RemoteConfigDel",
    "RemoteLog",
    "RemoteAddSshConfig",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    local ok_remote, remote_nvim = pcall(require, "remote-nvim")
    if ok_remote and remote_nvim.setup then
      remote_nvim.setup({
        remote = {
          app_name = "nvim-remote-jberlanga",
        },
        client_callback = function(port, _)
          local nvim_bin = vim.v.progpath or "nvim"
          require("remote-nvim.ui").float_term(
            ("%s --server localhost:%s --remote-ui"):format(nvim_bin, port),
            function(exit_code)
              if exit_code ~= 0 then
                vim.notify(("Local client failed with exit code %s"):format(exit_code), vim.log.levels.ERROR)
              end
            end
          )
        end,
      })

      -- The plugin hardcodes a 20s timeout and starts probing immediately.
      -- SSH tunnel + remote nvim startup need time, especially on first run.
      -- Initial delay 8s, probe every 3s, total timeout 120s.
      -- Uses the same coroutine+defer pattern as the original but with longer timings.
      -- Patch: replace _wait_for_server_to_be_ready AND _launch_local_neovim_client
      -- to use a non-blocking async approach that doesn't depend on coroutines.
      local Provider = require("remote-nvim.providers.provider")
      local function patched_launch_local_client(self)
        if not self:_get_local_client_start_preference() then
          self:show_progress_view_window()
          self.progress_viewer:switch_to_pane("session_info", true)
          return
        end

        local nvim_bin = vim.v.progpath or "nvim"
        local cmd = ("%s --server localhost:%s --remote-send ':lua vim.g.remote_neovim_host=true<CR>'"):format(
          nvim_bin, self._local_free_port
        )
        local timeout = 120000
        local probe_interval = 3000
        local initial_delay = 8000
        local port = self._local_free_port
        local config_provider = self._config_provider
        local unique_host_id = self.unique_host_id

        vim.notify(("Waiting for remote server on localhost:%s (up to 120s)... cmd: %s"):format(port, cmd), vim.log.levels.INFO)

        local elapsed = 0
        local deadline_timer = vim.uv.new_timer()

        local function do_probe()
          local res = vim.fn.system(cmd)
          vim.notify(("Probe result: len=%d v_shell_error=%d repr=%s"):format(#res, vim.v.shell_error, vim.inspect(res)), vim.log.levels.INFO)
          if vim.v.shell_error == 0 and vim.trim(res) == "" then
            if deadline_timer and not deadline_timer:is_closing() then
              deadline_timer:stop()
              deadline_timer:close()
            end
            vim.notify("Remote server ready! Launching client...", vim.log.levels.INFO)
            remote_nvim.config.client_callback(
              port,
              config_provider:get_workspace_config(unique_host_id)
            )
            return
          end

          elapsed = elapsed + probe_interval
          if elapsed < timeout then
            vim.defer_fn(do_probe, probe_interval)
          end
        end

        deadline_timer:start(timeout, 0, vim.schedule_wrap(function()
          vim.notify(("Server did not come up on localhost:%s in %ss"):format(port, timeout / 1000), vim.log.levels.ERROR)
          deadline_timer:stop()
          if not deadline_timer:is_closing() then deadline_timer:close() end
        end))

        vim.defer_fn(do_probe, initial_delay)
      end
      Provider._launch_local_neovim_client = patched_launch_local_client
      if Provider.__instanceDict then
        Provider.__instanceDict._launch_local_neovim_client = patched_launch_local_client
      end

      -- Passthrough terminal keys to remote TUI instead of local NvChad mappings.
      -- Uses buffer-local keymaps set when the remote-nvim float opens,
      -- so NvChad's global terminal mappings remain untouched for local terminals.
      local orig_float_term = require("remote-nvim.ui").float_term
      require("remote-nvim.ui").float_term = function(cmd, exit_cb, popup_options)
        orig_float_term(cmd, exit_cb, popup_options)
        vim.schedule(function()
          local buf = vim.api.nvim_get_current_buf()
          if vim.bo[buf].buftype ~= "terminal" then return end

          local passthrough_keys = { "<A-h>", "<A-v>", "<A-i>", "<C-n>" }
          for _, key in ipairs(passthrough_keys) do
            vim.keymap.set("t", key, function()
              local raw = vim.api.nvim_replace_termcodes(key, true, false, true)
              local chan = vim.b[buf].terminal_job_id
              if chan then
                vim.fn.chansend(chan, raw)
              end
            end, { buffer = buf, desc = "Passthrough " .. key .. " to remote nvim" })
          end
        end)
      end
    end

    local function parse_ssh_command(cmd)
      local split_ok, tokens = pcall(vim.fn.shellsplit, cmd)
      if not split_ok or type(tokens) ~= "table" then
        tokens = vim.split(cmd, "%s+", { trimempty = true })
      end

      local parsed = {
        identity_file = nil,
        host = nil,
        user = nil,
        port = "22",
        alias = nil,
      }

      local start_idx = 1
      if tokens[1] == "ssh" then
        start_idx = 2
      end

      local i = start_idx
      while i <= #tokens do
        local token = tokens[i]

        if token == "-i" then
          if i + 1 > #tokens then
            return nil, "Missing argument for -i"
          end
          parsed.identity_file = tokens[i + 1]
          i = i + 2
        elseif token:match("^%-i(.+)") and #token > 2 then
          parsed.identity_file = token:sub(3)
          i = i + 1
        elseif token:match("^%-%-identity%-file=(.+)") then
          parsed.identity_file = token:match("^%-%-identity%-file=(.+)")
          i = i + 1
        elseif token == "--identity-file" then
          if i + 1 > #tokens then
            return nil, "Missing argument for --identity-file"
          end
          parsed.identity_file = tokens[i + 1]
          i = i + 2
        elseif token == "-p" then
          if i + 1 > #tokens then
            return nil, "Missing argument for -p"
          end
          parsed.port = tokens[i + 1]
          i = i + 2
        elseif token:match("^%-p(%d+)$") then
          parsed.port = token:sub(3)
          i = i + 1
        elseif token:match("^%-%-port=(%d+)$") then
          parsed.port = token:match("^%-%-port=(%d+)$")
          i = i + 1
        elseif token == "--port" then
          if i + 1 > #tokens then
            return nil, "Missing argument for --port"
          end
          parsed.port = tokens[i + 1]
          i = i + 2
        elseif token == "--alias" then
          if i + 1 > #tokens then
            return nil, "Missing argument for --alias"
          end
          parsed.alias = tokens[i + 1]
          i = i + 2
        elseif not parsed.user and not parsed.host and not token:match("^%-") and token:find("@") then
          local user, host = token:match("^([^@]+)@(.+)$")
          if user and host then
            parsed.user = user
            parsed.host = host
            local bracket_host, bracket_port = host:match("^%[(.+)%]:(%d+)$")
            if bracket_host and bracket_port then
              parsed.host = bracket_host
              if parsed.port == "22" then
                parsed.port = bracket_port
              end
            else
              local host_only, host_port = host:match("^(.*):(%d+)$")
              if host_only and host_port then
                parsed.host = host_only
                if parsed.port == "22" then
                  parsed.port = host_port
                end
              end
            end
          end
          i = i + 1
        else
          i = i + 1
        end
      end

      if not parsed.identity_file then
        return nil, "Could not parse identity file. Example required: ssh -i <identity_file> user@host"
      end
      if not parsed.user or not parsed.host then
        return nil, "Could not parse destination (user@host). Example required: ssh -i <identity_file> user@host"
      end

      parsed.identity_file = vim.fn.expand(parsed.identity_file)
      parsed.alias = parsed.alias
        or (parsed.user .. "@" .. parsed.host):gsub("[^A-Za-z0-9._-]", "-")

      if vim.fn.filereadable(parsed.identity_file) == 0 then
        return nil, "Identity file not readable: " .. parsed.identity_file
      end

      return parsed
    end

    local function has_alias(entries, alias)
      local escaped_alias = vim.pesc(alias)
      for _, line in ipairs(entries) do
        if line:match("^%s*Host%s+" .. escaped_alias .. "%s*$") then
          return true
        end
      end
      return false
    end

    local function ensure_ssh_config()
      local config_dir = vim.fn.expand("$HOME") .. "/.ssh"
      local config_path = config_dir .. "/config"
      if vim.fn.isdirectory(config_dir) == 0 then
        vim.fn.mkdir(config_dir, "p")
      end
      if vim.fn.filereadable(config_path) == 0 then
        vim.fn.writefile({}, config_path)
      end
      return config_path
    end

    local function append_ssh_entry(parsed)
      local config_path = ensure_ssh_config()
      local lines = vim.fn.readfile(config_path)

      if has_alias(lines, parsed.alias) then
        vim.notify("Host alias already exists: " .. parsed.alias, vim.log.levels.WARN)
        return
      end

      local preview = {
        "Host " .. parsed.alias,
        "  HostName " .. parsed.host,
        "  User " .. parsed.user,
        "  IdentityFile " .. parsed.identity_file,
      }
      if parsed.port and parsed.port ~= "22" then
        table.insert(preview, "  Port " .. parsed.port)
      end

      local prompt = "Append the following to " .. config_path .. "?\n" .. table.concat(preview, "\n")
      local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
      if choice ~= 1 then
        vim.notify("Aborted: " .. parsed.alias, vim.log.levels.INFO)
        return
      end

      local f = io.open(config_path, "a")
      if not f then
        vim.notify("Failed to open " .. config_path, vim.log.levels.ERROR)
        return
      end
      f:write("\n")
      for _, line in ipairs(preview) do
        f:write(line .. "\n")
      end
      f:close()

      vim.notify("Added SSH config entry: " .. parsed.alias .. " -> " .. parsed.user .. "@" .. parsed.host, vim.log.levels.INFO)
    end

    vim.api.nvim_create_user_command("RemoteAddSshConfig", function(opts)
      local input = vim.trim(opts.args or "")
      if input == "" then
        vim.notify("Usage: :RemoteAddSshConfig ssh -i <identity> <user>@<host>", vim.log.levels.ERROR)
        return
      end

      local parsed, err = parse_ssh_command(input)
      if not parsed then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end

      append_ssh_entry(parsed)
    end, {
      nargs = "+",
      desc = "Parse an ssh command and add it to ~/.ssh/config",
    })
  end,
}

-- Open generic terminals with NVIM and TMUX stripped from the environment so
-- the oh-my-zsh tmux plugin attaches to a pre-warmed session on the first
-- ~/.zshrc source. Neovim injects $NVIM (and inherits $TMUX) into terminal
-- children, which makes the plugin's autostart guard skip; launching clean
-- avoids the old `unset NVIM TMUX; exec zsh` re-source dance.
--
-- The terminal cwd is pinned explicitly: the inherited terminal cwd is
-- unreliable and the warm session is born in the daemon's /tmp, so the plugin's
-- `cd "$(pwd)"` only lands in the project when $(pwd) of this shell is right.
-- getcwd is preferred, but it is itself unreliable (nvim is often launched from
-- a shell already sitting at /, e.g. a warm session that landed at /), so when
-- getcwd is / or empty we fall back to the current file's git root / directory.
-- See doc/tmux.md.
local map = vim.keymap.set

-- Required after mappings.agent-term (see init.lua order): exposes
-- send_to_agent used by the warm-terminal <C-l> hint mappings below.
local agent_term = require "mappings.agent-term"

local function file_root(file)
  if file == nil or file == "" then
    return nil
  end
  local dir = vim.fs.dirname(file)
  if dir == nil or vim.fn.isdirectory(dir) == 0 then
    return nil
  end
  return vim.fs.root(dir, { ".git" }) or dir
end

local function warm_cwd()
  local cwd = vim.fn.getcwd()
  if cwd ~= "" and cwd ~= "/" then
    return cwd
  end
  -- getcwd is useless (nvim was launched from a shell at /). Anchor to an open
  -- file's git root instead: current buffer, then alternate, then any loaded
  -- buffer. Last resort is $HOME — never /.
  local seen = { file_root(vim.api.nvim_buf_get_name(0)) }
  local alt = vim.fn.bufname("#")
  seen[#seen + 1] = file_root(alt ~= "" and vim.fn.fnamemodify(alt, ":p") or nil)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      seen[#seen + 1] = file_root(vim.api.nvim_buf_get_name(b))
    end
  end
  for _, root in ipairs(seen) do
    if root then
      return root
    end
  end
  return vim.env.HOME or cwd
end

local warm_terms = {
  { "<leader>v", { "n", "t" }, "toggle", { pos = "vsp", id = "vtoggleTerm" }, "toggleable vertical" },
  { "<C-g>", { "n", "t" }, "toggle", { pos = "sp", id = "htoggleTerm" }, "toggleable horizontal" },
  { "<A-i>", { "n", "t" }, "toggle", { pos = "float", id = "floatTerm" }, "floating" },
  { "<leader>h", "n", "new", { pos = "sp" }, "new horizontal" },
}

-- Build the shell command for a warm terminal: attach to (or create) a tmux
-- session on the warm-daemon DEFAULT socket. `env -u TMUX` detaches from the
-- outer WM (-L wm) so this inner tmux is Ctrl+B-controlled and never nests into
-- the WM. Replaces the old `env -u NVIM -u TMUX zsh` + oh-my-zsh autostart
-- approach, which was unreliable in the nested two-tmux setup (autostart probes
-- for warm-* sessions the daemon never creates). Each toggle reattaches to a
-- persistent per-id session via -A.
local function warm_cmd(opts, dir)
  -- opts.id is nil for `new` (<leader>h): each call must spawn its OWN warm
  -- session instead of reattaching a shared one, so derive a one-shot name.
  local id = opts.id or ("adhoc" .. vim.loop.hrtime())
  return "exec env -u TMUX tmux new-session -A -s nvim-" .. id .. " -c " .. vim.fn.shellescape(dir)
end

-- Turn a path into a key safe for buffer keys AND tmux session names
-- (tmux forbids "." and ":").
local function dir_key(dir)
  return (dir:gsub("[^%w%-]", "_"))
end

for _, t in ipairs(warm_terms) do
  local lhs, modes, fn, opts, label = t[1], t[2], t[3], t[4], t[5]
  map(modes, lhs, function()
    -- Workspace terminals keyed by WORKING DIRECTORY, not tab: warm_cwd is
    -- the effective cwd (:lcd/:tcd-aware), so every tab sitting at the same
    -- pwd reattaches the SAME terminal buffer and warm tmux session, while
    -- tabs at different pwds each get their own. The session is born in that
    -- pwd via -c/termopen cwd.
    local dir = warm_cwd()
    local dir_opts = opts.id and vim.tbl_extend("force", opts, {
      id = opts.id .. "-" .. dir_key(dir),
    }) or opts
    require("nvchad.term")[fn](vim.tbl_extend("force", dir_opts, {
      cmd = warm_cmd(dir_opts, dir),
      termopen_opts = { cwd = dir },
    }))
  end, { desc = "terminal " .. label .. " (warm tmux, per pwd)" })
end

local terminal_file_ref_pattern = [[\v(\f+\/\f+|\f+\.\f+)(:\d+(:\d+)?)?]]

local function jump_terminal_file_ref(forward)
  local flags = forward and "W" or "bW"
  local found = vim.fn.search(terminal_file_ref_pattern, flags)
  if found == 0 then
    vim.notify("No more file references found", vim.log.levels.INFO)
  end
end

local function open_terminal_cfile_in_tab()
  local raw = vim.fn.expand "<cfile>"
  if raw == nil or raw == "" then
    vim.notify("No file reference under cursor", vim.log.levels.WARN)
    return
  end

  local path, lnum, col = raw:match("^(.-):(%d+):(%d+)$")
  if not path then
    path, lnum = raw:match("^(.-):(%d+)$")
  end
  path = path or raw

  path = vim.fs.normalize(vim.fn.expand(path))
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("File not found: " .. path, vim.log.levels.WARN)
    return
  end

  vim.cmd("tabedit " .. vim.fn.fnameescape(path))
  if lnum then
    local row = tonumber(lnum) or 1
    local c = math.max((tonumber(col) or 1) - 1, 0)
    vim.api.nvim_win_set_cursor(0, { row, c })
  end
end

-- <C-l> in a warm tmux terminal: send the AGENT terminal a hint telling it how
-- to reach THIS terminal's tmux session (attach / capture-pane), instead of the
-- session contents themselves. With a selection the hint carries a
-- tail-relative line range recipe (e.g. lines -22:-20) the agent can run.
--
-- Two realities drive the design (verified end-to-end against the real
-- .tmux.conf, see doc/console_agent_pass.md):
--   * The tmux client repaints rows in place, so nvim's terminal buffer only
--     holds the CURRENT screen — buffer line numbers say nothing about tmux
--     history offsets.
--   * The Ctrl+B copy-mode selection itself is invisible to nvim (state lives
--     inside tmux, no format exposes it), so the "highlight" is nvim-native:
--     <C-x> then V selects lines on the (possibly frozen) screen.
--
-- Range resolution, in layers:
--   1. FROZEN pane (copy-mode): tmux renders "[N/M]" (scrolled/history) on the
--      top row of the frozen viewport into the pty stream, so nvim CAN read it.
--      Viewport bottom sits N+1 lines above the live tail (capture-stream
--      counting); a row R above the bottom adds (bottom-R) more. Exact.
--      #{pane_in_mode} confirms the freeze; #{pane_height} bounds the viewport.
--   2. LIVE pane: screen bottom IS the tail, so selected text is located in
--      `capture-pane` output counting from the tail (content-anchored; only
--      ambiguity is repeated identical lines, resolved toward the tail).
--   3. No resolution: plain attach + capture hint.
-- The only residual error (both layers) is output arriving between send and
-- the agent running the recipe — inherent to shipping a lookup, not content.
local function warm_session_from_cmd(cmd)
  if type(cmd) ~= "string" then
    return nil
  end
  -- dir_key output is [a-zA-Z0-9_-] (leading path "/" becomes "_"), so the
  -- class MUST include "_" — %w alone truncates at the first underscore.
  return cmd:match("tmux new%-session %-A %-s (nvim%-[%w_%-]+)")
end

-- Fallback when the stored nvchad cmd is gone (e.g. restored session buffers):
-- map the job's controlling tty to the tmux client attached to it. env -u TMUX
-- so the DEFAULT (warm) socket is queried, never the outer WM (-L wm) one.
local function warm_session_from_tty()
  local chan = vim.b.terminal_job_id
  if not chan then
    return nil
  end
  local ok, pid = pcall(vim.fn.jobpid, chan)
  if not ok or not pid or pid <= 0 then
    return nil
  end
  local ok_link, tty = pcall(vim.loop.fs_readlink, ("/proc/%d/fd/0"):format(pid))
  if not ok_link or not tty or tty:sub(1, 1) ~= "/" then
    return nil
  end
  local out = vim.fn.system("env -u TMUX tmux list-clients -F '#{client_tty} #{client_session}' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  for line in out:gmatch("[^\r\n]+") do
    local client_tty, sess = line:match("^(%S+)%s+(%S+)")
    if client_tty == tty then
      return sess
    end
  end
  return nil
end

-- Live pane content (history included). capture-pane always reads the LIVE
-- pane even while the client view is frozen in copy-mode. Drop the final
-- newline so the split array indexes EXACTLY like `tail -n` counts lines
-- (the pane's empty cursor line stays, the split artifact goes).
local function warm_capture_lines(sess)
  local out = vim.fn.system("env -u TMUX tmux capture-pane -t " .. vim.fn.shellescape(sess) .. " -p -S -500 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.split(out:gsub("\n$", ""), "\n", { plain = true })
end

-- Frozen-state + viewport height in one tmux call. pane_in_mode is pane state
-- (unlike the broken #{scroll_position} client state), so it reliably confirms
-- copy-mode. Returns (frozen, pane_height) or nil.
local function warm_pane_state(sess)
  local out = vim.fn.system(
    "env -u TMUX tmux display-message -p -t " .. vim.fn.shellescape(sess) .. " '#{pane_in_mode} #{pane_height}' 2>/dev/null"
  )
  if vim.v.shell_error ~= 0 then
    return nil
  end
  local mode, height = out:match("^%s*(%d+)%s+(%d+)")
  if not mode or not height then
    return nil
  end
  return mode ~= "0", tonumber(height)
end

-- Find the copy-mode "[N/M]" indicator row in the displayed screen. tmux
-- overlays it on the TOP row of the frozen viewport; scanning bottom-up within
-- the last screenful, the row also bounds the viewport. Returns
-- { scroll = N, top_row = r } or nil.
-- `window` = rows from buffer end that may hold the indicator row (the frozen
-- viewport top; caller passes pane_height + margin). The indicator match is
-- SUFFIX-anchored: copy-mode text rendered before it — e.g. a search's
-- "(2 results) 15:46:26 [28/46]" — does not disturb the [N/M] capture.
local function warm_copymode_top(buf, window)
  local count = vim.api.nvim_buf_line_count(buf)
  local from = math.max(1, count - 200)
  local rows = vim.api.nvim_buf_get_lines(buf, from - 1, count, false)
  for i = #rows, 1, -1 do
    local n, m = rows[i]:match("%[(%d+)/(%d+)%]%s*$")
    if n and tonumber(n) <= tonumber(m) and (#rows - i) < window then
      return { scroll = tonumber(n), top_row = from + i - 1 }
    end
  end
  return nil
end

-- Tail-relative 1-based index of `text` in captured lines: last occurrence,
-- blank lines never anchor, trailing whitespace insignificant.
local function warm_tail_index(lines, text)
  text = text:gsub("[%s\r]+$", "")
  if text == "" then
    return nil
  end
  for i = #lines, 1, -1 do
    if lines[i]:gsub("[%s\r]+$", "") == text then
      return #lines - i + 1
    end
  end
  return nil
end

local function warm_hint_message(sess, from_tail, to_tail)
  if not from_tail then
    return ("tmux:%s | access: tmux attach -t %s | last output: tmux capture-pane -t %s -p -S -100 | tail -n 50")
      :format(sess, sess, sess)
  end
  -- tail -n A | head -n N yields tail-relative lines -A..-(A-N+1)
  local count = from_tail - to_tail + 1
  -- ADAPTIVE depth: the capture must reach back >= from_tail lines, or
  -- `tail -n A` silently addresses the wrong window when the selection sits
  -- deep in history (a fixed -S -100 broke ranges once A passed ~100).
  local depth = from_tail + count
  return ("tmux:%s | lines -%d:-%d from tail: tmux capture-pane -t %s -p -S -%d | tail -n %d | head -n %d")
    :format(sess, from_tail, to_tail, sess, depth, from_tail, count)
end

local function send_warm_hint(kind)
  local buf = vim.api.nvim_get_current_buf()
  local sess = vim.b[buf].warm_tmux_session or warm_session_from_tty()
  if not sess or not sess:match "^nvim%-" then
    vim.notify("No warm tmux session found for this terminal", vim.log.levels.WARN, { title = "Warm terminal hint" })
    return
  end

  local msg
  if kind ~= "t" then
    local start_line, end_line = vim.fn.line ".", vim.fn.line "."
    if kind == "x" then
      start_line = vim.fn.line "v"
      end_line = vim.fn.line "."
      if start_line > end_line then
        start_line, end_line = end_line, start_line
      end
    end
    local sel = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    if kind == "x" then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    end

    -- Layer 1: frozen pane — exact arithmetic from the [N/M] indicator.
    local frozen, height = warm_pane_state(sess)
    local cm = frozen and height and warm_copymode_top(buf, height + 8) or nil
    if cm and height then
      local bottom = cm.top_row + height - 1
      if bottom <= vim.api.nvim_buf_line_count(buf) and start_line >= cm.top_row and end_line <= bottom then
        local base = cm.scroll + 1
        msg = warm_hint_message(sess, base + (bottom - start_line), base + (bottom - end_line))
      end
    end

    -- Layer 2: live pane (or selection outside the frozen viewport) —
    -- content-anchor the selection in the live capture, tail side first.
    if not msg then
      local lines = warm_capture_lines(sess)
      if lines then
        local n = #sel
        for p = n, 1, -1 do
          local k = warm_tail_index(lines, sel[p])
          if k then
            msg = warm_hint_message(sess, k + p - 1, k + p - n)
            break
          end
        end
      end
    end
  end

  msg = msg or warm_hint_message(sess)
  agent_term.send_to_agent(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "Warm terminal hint sent" })
end

-- Dont resize terminals vertically.
vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_option_value("winfixwidth", true, {})
    vim.api.nvim_set_option_value("winfixheight", true, {})
    vim.keymap.set("n", "]f", function() jump_terminal_file_ref(true) end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Next file reference in terminal",
    })
    vim.keymap.set("n", "[f", function() jump_terminal_file_ref(false) end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Previous file reference in terminal",
    })
    vim.keymap.set("n", "gf", open_terminal_cfile_in_tab, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Open terminal file reference in new tab",
    })
    vim.keymap.set("t", "gf", function()
      vim.cmd "stopinsert"
      open_terminal_cfile_in_tab()
    end, {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = "Open terminal file reference in new tab",
    })
    vim.keymap.set("t", " ", " ", {
      buffer = buf,
      nowait = true,
      desc = "Bypass leader timeout so space is sent immediately",
    })
    -- Warm tmux terminals only: nvchad stores the termopen cmd on the buffer
    -- entry BEFORE termopen runs, so the `-s nvim-<id>-<dir>` session is
    -- parseable here. Buffer-local mappings keep the global t <C-l>
    -- (agent-term close) intact everywhere else, including the agent term
    -- itself (its cmd attaches agent@*, which never matches nvim%-).
    local term_opts = vim.g.nvchad_terms and vim.g.nvchad_terms[tostring(buf)]
    local sess = (term_opts and warm_session_from_cmd(term_opts.cmd)) or warm_session_from_tty()
    if sess and sess:match "^nvim%-" then
      vim.b[buf].warm_tmux_session = sess
      vim.keymap.set("t", "<C-l>", function() send_warm_hint("t") end, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = "Send tmux session hint to agent terminal",
      })
      vim.keymap.set("n", "<C-l>", function() send_warm_hint("n") end, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = "Send tmux session + cursor line hint to agent terminal",
      })
      vim.keymap.set("x", "<C-l>", function() send_warm_hint("x") end, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = "Send tmux session + selection hint to agent terminal",
      })
    end
  end,
})
-- Neither when toggle hide. Force reapply option.
vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*",
  callback = function()
    if vim.bo.buftype == "terminal" then
      vim.api.nvim_set_option_value("winfixwidth", true, {})
      vim.api.nvim_set_option_value("winfixheight", true, {})
    end
  end,
})

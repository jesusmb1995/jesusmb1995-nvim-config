#!/usr/bin/env bash
# Agent-terminal suite: project-keyed identity (session agent@<md5-8 cwd>,
# nvchad buffer id agentTerm-<dir key>).
#
# Phase 1 (headless unit, runs on whatever nvim executes the suite — host or
# container): naming hooks — session name hashes the cwd, term id is
# per-project, no removed-API calls (servername() deleted in nvim 0.12).
#
# Phase 2 (e2e, real tmux + two REAL nvims): the two scenarios that matter:
#   A. SAME project in two nvims -> BOTH warm-attach the ONE shared
#      agent@<hash> session (attached client count 2). Warm re-use per
#      project, exactly as requested.
#   B. DIFFERENT projects in two nvims -> TWO distinct agent@<hash> sessions
#      (one per project), never shared.
# Fake `claude` (the tool fallback) on PATH = sleep wrapper.
# Run: bash user/repos/nvim/test_agent_term.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$HERE/lua/mappings/agent-term.lua"

FAILURES=0
PASS() { printf 'PASS: %s\n' "$1"; }
FAIL() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
EXPECT_OK() { if [ "$1" -eq 0 ]; then PASS "$2"; else FAIL "$2 (rc=$1)"; fi; }

command -v nvim >/dev/null 2>&1 || { printf 'FAIL: nvim not found on PATH\n'; exit 1; }
command -v tmux >/dev/null 2>&1 || { printf 'FAIL: tmux not found on PATH\n'; exit 1; }
[ -f "$MODULE" ] || { printf 'FAIL: module not found: %s\n' "$MODULE"; exit 1; }

# ---------------------------------------------------------------------------
# Phase 1: headless unit
# ---------------------------------------------------------------------------
LUA_TEST="$(mktemp "${TMPDIR:-/tmp}/agent_term_test.XXXXXX.lua")"
trap 'rm -f "$LUA_TEST"' EXIT

cat > "$LUA_TEST" <<'EOF'
local failures = 0
local function fail(msg)
  print("FAIL: " .. msg)
  failures = failures + 1
end

vim.g.mapleader = " "
local module_path = assert(os.getenv "AGENT_TERM_MODULE", "AGENT_TERM_MODULE not set")
local M = dofile(module_path)
assert(type(M._agent_session_name) == "function", "M._agent_session_name export missing")
assert(type(M._agent_term_id) == "function", "M._agent_term_id export missing")

-- Session name is the project hash, NOT instance-keyed: same cwd always
-- yields the same agent@<h8>, so warm re-use per project works and there is
-- no per-instance ~suffix left anywhere.
local s1 = M._agent_session_name "/home/user/proj a"
local s2 = M._agent_session_name "/home/user/proj a"
local s3 = M._agent_session_name "/home/user/other"
if s1 == s2 and s1:match "^agent@%x%x%x%x%x%x%x%x$" then
  print("PASS: session name stable per cwd + 8-hex form (" .. s1 .. ")")
else
  fail(("session name: got %q / %q, want stable agent@<h8>"):format(s1, s2))
end
if s1 ~= s3 then
  print("PASS: different cwd -> different session")
else
  fail("different cwd hashed to the same session")
end
if s1:find("~", 1, true) then
  fail("session name still carries a per-instance ~ suffix")
else
  print "PASS: no per-instance ~ suffix in session name"
end

-- Term buffer id is per-project (fixes one-nvim-multi-tab re-use of the old
-- global 'agentTerm' singleton); checked via chdir below.
print "UNIT-DONE"
EOF

# _agent_term_id takes no args (uses getcwd); drive it via chdir into real
# sandbox dirs created by the shell wrapper.
UNIT_SB="$(mktemp -d)"
mkdir -p "$UNIT_SB/proj a"
cat >> "$LUA_TEST" <<EOF
vim.fn.chdir "$UNIT_SB/proj a"
local idA = M._agent_term_id()
vim.fn.chdir "/tmp"
local idB = M._agent_term_id()
local wantA = "agentTerm-$(printf '%s' "$UNIT_SB/proj a" | sed 's/[^[:alnum:]-]/_/g')"
if idA == wantA and idB == "agentTerm-_tmp" then
  print("PASS: term id per-project + sanitized (" .. idA .. ")")
else
  fail(("term id: got %q / %q, want %q"):format(idA, idB, wantA))
end
if failures > 0 then
  print(("FAILED: %d case(s)"):format(failures))
  os.exit(1)
end
print "ALL UNIT TESTS PASSED"
os.exit(0)
EOF

# Lint: the servername() VimL function was REMOVED in nvim 0.12 (E117);
# vim.v.servername is the canonical accessor on all versions.
if grep -q "vim\.fn\.servername()" "$MODULE"; then
    FAIL "agent-term.lua calls vim.fn.servername() (removed in nvim 0.12)"
else
    PASS "agent-term.lua free of removed servername() call"
fi

AGENT_TERM_MODULE="$MODULE" nvim --headless -u NONE -l "$LUA_TEST"
RC=$?
rm -rf "$UNIT_SB"
if [ "$RC" -eq 0 ]; then
    PASS "headless nvim agent-term unit suite"
else
    FAIL "headless nvim agent-term unit suite (rc=$RC)"
fi

# ---------------------------------------------------------------------------
# Phase 2: e2e — two real nvims driven through tmux
# ---------------------------------------------------------------------------
E2E_DIR="$(mktemp -d)"
mkdir -p "$E2E_DIR/tmux" "$E2E_DIR/projA" "$E2E_DIR/projB" "$E2E_DIR/bin"
cat > "$E2E_DIR/bin/claude" <<'STUB'
#!/usr/bin/env bash
exec sleep 999
STUB
chmod +x "$E2E_DIR/bin/claude"

cat > "$E2E_DIR/init.lua" <<'INIT'
vim.g.mapleader = " "
-- Stub nvchad.term with a REAL attach: run the cmd in a terminal buffer so
-- the tmux client is genuine (what the deployed NvChad does).
package.preload["nvchad.term"] = function()
  return {
    toggle = function(opts)
      if opts.cmd then
        vim.cmd "vnew"
        vim.fn.termopen(opts.cmd)
      end
    end,
  }
end
dofile(assert(os.getenv "AGENT_TERM_MODULE"))
INIT

TX2() { env -u TMUX TMUX_TMPDIR="$E2E_DIR/tmux" tmux "$@"; }

# Scenario A: SAME project in two nvims -> ONE shared session, 2 clients.
HASH_A=$(printf '%s' "$E2E_DIR/projA" | md5sum | cut -c1-8)
TX2 new-session -d -s "agent@$HASH_A" -x 200 -y 50 'sleep 999' >/dev/null 2>&1
EXPECT_OK $? "e2e-A: pre-warmed agent@$HASH_A (detached) exists"

for N in 1 2; do
    TX2 new-session -d -s "nA$N" -x 220 -y 50 \
      "cd '$E2E_DIR/projA' && PATH='$E2E_DIR/bin':\$PATH AGENT_TERM_MODULE='$MODULE' nvim -u '$E2E_DIR/init.lua'" \
      >/dev/null 2>&1
done
sleep 6
TX2 send-keys -t nA1 Space; sleep 0.4; TX2 send-keys -t nA1 C-l; sleep 2
TX2 send-keys -t nA2 Space; sleep 0.4; TX2 send-keys -t nA2 C-l; sleep 2

SESSIONS="$(TX2 list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null)"
echo "$SESSIONS" | sed 's/^/    e2e-A session: /'

SHARED=$(echo "$SESSIONS" | awk -v s="agent@$HASH_A" '$1 == s { print $2 }')
[ "${SHARED:-x}" = "2" ]
EXPECT_OK $? "e2e-A: same project -> ONE shared agent@$HASH_A with 2 attached clients (got '${SHARED:-none}')"

N_INST=$(echo "$SESSIONS" | grep -cE "^agent@$HASH_A~")
[ "$N_INST" = "0" ]
EXPECT_OK $? "e2e-A: no stray per-instance agent@$HASH_A~... sessions (got $N_INST)"

TX2 kill-session -t nA1 >/dev/null 2>&1; TX2 kill-session -t nA2 >/dev/null 2>&1
TX2 kill-server 2>/dev/null || true

# Scenario B: DIFFERENT projects -> distinct sessions, never shared.
mkdir -p "$E2E_DIR/tmux2"
TX3() { env -u TMUX TMUX_TMPDIR="$E2E_DIR/tmux2" tmux "$@"; }
HASH_B=$(printf '%s' "$E2E_DIR/projB" | md5sum | cut -c1-8)

for N in 1 2; do
    DIR="$E2E_DIR/proj$N"; mkdir -p "$DIR"
    TX3 new-session -d -s "nB$N" -x 220 -y 50 \
      "cd '$DIR' && PATH='$E2E_DIR/bin':\$PATH AGENT_TERM_MODULE='$MODULE' nvim -u '$E2E_DIR/init.lua'" \
      >/dev/null 2>&1
done
sleep 6
TX3 send-keys -t nB1 Space; sleep 0.4; TX3 send-keys -t nB1 C-l; sleep 3
TX3 send-keys -t nB2 Space; sleep 0.4; TX3 send-keys -t nB2 C-l; sleep 3

SESSIONS_B="$(TX3 list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null)"
echo "$SESSIONS_B" | sed 's/^/    e2e-B session: /'

HASH_1=$(printf '%s' "$E2E_DIR/proj1" | md5sum | cut -c1-8)
HASH_2=$(printf '%s' "$E2E_DIR/proj2" | md5sum | cut -c1-8)
ATT_1=$(echo "$SESSIONS_B" | awk -v s="agent@$HASH_1" '$1 == s { print $2 }')
ATT_2=$(echo "$SESSIONS_B" | awk -v s="agent@$HASH_2" '$1 == s { print $2 }')
[ "${ATT_1:-0}" = "1" ]
EXPECT_OK $? "e2e-B: proj1 got its own session attached once (got '${ATT_1:-none}')"
[ "${ATT_2:-0}" = "1" ]
EXPECT_OK $? "e2e-B: proj2 got its own session attached once (got '${ATT_2:-none}')"

TX3 kill-server 2>/dev/null || true
rm -rf "$E2E_DIR"

if [ "$FAILURES" -ne 0 ]; then
    printf 'FAILED: %d assertion(s)\n' "$FAILURES"
    exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0

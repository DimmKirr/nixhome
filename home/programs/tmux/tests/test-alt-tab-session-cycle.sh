#!/usr/bin/env bash
# Integration test: Alt+Tab (M-Tab) and Shift+Alt+Tab (M-BTab) cycle tmux
# sessions via a real PTY-attached client.
#
# Follows test_snapshot.py conventions:
#   - isolated socket in a tempdir
#   - minimal tmux.conf (status off, /bin/sh)
# Uses Python to attach a tmux client inside a real PTY and write raw
# key bytes to the PTY master fd — the same path a real terminal uses.
# tmux send-keys bypasses the client key handler, so it can't trigger
# `bind -n` bindings; writing to the PTY master does.
#
# Usage: bash test-alt-tab-session-cycle.sh [path-to-tmux.conf]
# Exit 0 = PASS, nonzero = FAIL (exit code = failure count)
set -euo pipefail

CONF="${1:-}"
WORK=$(mktemp -d /tmp/tmux-alt-tab-test.XXXXXX)
SOCK="$WORK/sock"

cleanup() {
  # Kill the Python PTY driver first
  [[ -f "$WORK/driver.pid" ]] && kill "$(cat "$WORK/driver.pid")" 2>/dev/null || true
  tmux -S "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Minimal conf mirroring TmuxFixture.
MERGED_CONF="$WORK/tmux.conf"
cat > "$MERGED_CONF" <<'BASECONF'
set -g status off
set -g default-shell /bin/sh
set -g default-command /bin/sh
BASECONF
if [[ -n "$CONF" && -f "$CONF" ]]; then
  cat "$CONF" >> "$MERGED_CONF"
fi

# --- Setup: three sessions ---
tmux -S "$SOCK" -f "$MERGED_CONF" new-session -d -s A -x 80 -y 24
tmux -S "$SOCK" new-session -d -s B -x 80 -y 24
tmux -S "$SOCK" new-session -d -s C -x 80 -y 24

# --- Run the actual test in Python ---
# Python handles: PTY allocation, tmux attach, writing raw key bytes,
# querying client_session, assertions.
exec python3 - "$SOCK" "$WORK" <<'PYEOF'
import os, pty, subprocess, sys, time

SOCK = sys.argv[1]
WORK = sys.argv[2]

def tmux(*args):
    r = subprocess.run(["tmux", "-S", SOCK, *args],
                       capture_output=True, text=True)
    return r.stdout.strip()

def client_session():
    return tmux("list-clients", "-F", "#{client_session}").split("\n")[0]

def wait_for(condition, timeout=5.0, interval=0.1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(interval)
    return False

# Allocate PTY and fork.  Child attaches tmux; parent drives the test.
master_fd, slave_fd = pty.openpty()
pid = os.fork()

if pid == 0:
    # Child: become session leader, attach slave as controlling terminal.
    os.close(master_fd)
    os.setsid()
    os.dup2(slave_fd, 0)
    os.dup2(slave_fd, 1)
    os.dup2(slave_fd, 2)
    if slave_fd > 2:
        os.close(slave_fd)
    os.execvp("tmux", ["tmux", "-S", SOCK, "attach-session", "-t", "A"])
    os._exit(1)

# Parent: drives the test via master_fd.
os.close(slave_fd)

# Save driver PID for cleanup.
with open(os.path.join(WORK, "driver.pid"), "w") as f:
    f.write(str(pid))

# Drain PTY output in background (prevent buffer full → child blocks).
drain_pid = os.fork()
if drain_pid == 0:
    try:
        while True:
            os.read(master_fd, 4096)
    except OSError:
        pass
    os._exit(0)

# Wait for tmux client to attach.
if not wait_for(lambda: client_session() != ""):
    print("ABORT: no PTY client attached")
    os.kill(pid, 9)
    os.kill(drain_pid, 9)
    sys.exit(1)

# M-Tab   = ESC + Tab       = \x1b \x09
# M-BTab  = ESC + Shift-Tab = \x1b \x1b [  Z  (CSI Z with ESC prefix for Alt)
#   tmux recognises ESC followed by the backtab CSI sequence as M-BTab.
M_TAB  = b"\x1b\x09"
M_BTAB = b"\x1b\x1b[Z"

passed = 0
failed = 0

def report(label, expected, actual):
    global passed, failed
    if actual == expected:
        print(f"  PASS: {label} (expected={expected}, got={actual})")
        passed += 1
    else:
        print(f"  FAIL: {label} (expected={expected}, got={actual})")
        failed += 1

print("=== Alt+Tab session cycling — integration test ===")
print(f"Socket:  {SOCK}")
print()

# Test 1: starts on A
print("Test 1: client attached to session A")
report("initial session", "A", client_session())

# Test 2: M-Tab → A→B
print("Test 2: M-Tab cycles A → B")
os.write(master_fd, M_TAB)
wait_for(lambda: client_session() == "B")
report("session after M-Tab", "B", client_session())

# Test 3: M-Tab → B→C
print("Test 3: M-Tab cycles B → C")
os.write(master_fd, M_TAB)
wait_for(lambda: client_session() == "C")
report("session after M-Tab", "C", client_session())

# Test 4: M-Tab wraps → C→A
print("Test 4: M-Tab wraps C → A")
os.write(master_fd, M_TAB)
wait_for(lambda: client_session() == "A")
report("session after M-Tab (wrap)", "A", client_session())

# Test 5: M-BTab reverse → A→C
print("Test 5: M-BTab cycles A → C (reverse)")
os.write(master_fd, M_BTAB)
wait_for(lambda: client_session() == "C")
report("session after M-BTab", "C", client_session())

# Test 6: M-BTab reverse → C→B
print("Test 6: M-BTab cycles C → B (reverse)")
os.write(master_fd, M_BTAB)
wait_for(lambda: client_session() == "B")
report("session after M-BTab", "B", client_session())

print()
print(f"=== Results: {passed} passed, {failed} failed ===")

# Cleanup child processes.
os.kill(drain_pid, 9)
os.waitpid(drain_pid, 0)
os.kill(pid, 9)
os.waitpid(pid, 0)
os.close(master_fd)

sys.exit(failed)
PYEOF

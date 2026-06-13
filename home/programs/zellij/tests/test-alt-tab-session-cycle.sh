#!/usr/bin/env bash
# Integration test: Alt+Tab (M-Tab) and Shift+Alt+Tab cycles zellij
# sessions via a real PTY-attached client.
#
# Mirrors home/programs/tmux/tests/test-alt-tab-session-cycle.sh:
#   - isolated config dir in a tempdir
#   - bare layout (no plugins/tips)
#   - PTY-attached client via Python pty.openpty() + os.execvp()
#   - raw key bytes written to PTY master fd
#   - session assertion via $ZELLIJ_SESSION_NAME echoed to a marker file
#
# Usage: bash test-alt-tab-session-cycle.sh [path-to-cycle-script]
# Exit 0 = PASS, nonzero = FAIL (exit code = failure count)
set -euo pipefail

ZELLIJ="${ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}"
if [[ -z "$ZELLIJ" ]]; then
  echo "SKIP: zellij not found in PATH (set ZELLIJ_BIN to override)"
  exit 0
fi
echo "Using zellij: $ZELLIJ ($($ZELLIJ --version))"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../.." && pwd)"
CYCLE_SCRIPT="${1:-$REPO_ROOT/home/scripts/zellij-cycle-session.sh}"
if [[ ! -x "$CYCLE_SCRIPT" ]]; then
  echo "ABORT: cycle script not found or not executable: $CYCLE_SCRIPT"
  exit 1
fi

WORK=$(mktemp -d /tmp/zellij-alt-tab-test.XXXXXX)
MARKER="$WORK/current-session"

cleanup() {
  ZELLIJ_CONFIG_DIR="$WORK/config" "$ZELLIJ" kill-all-sessions --yes 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- Isolated config: bare layout, /bin/sh, no tips ---
CONFIG_DIR="$WORK/config"
mkdir -p "$CONFIG_DIR/layouts"

cat > "$CONFIG_DIR/layouts/bare.kdl" <<KDLEOF
layout {
    pane
}
KDLEOF

KEYBINDS="${KEYBINDS:-true}"
if [[ "$KEYBINDS" == "true" ]]; then
  KEYBIND_BLOCK='keybinds {
    shared_except "locked" {
        bind "Alt Tab" {
            Run "'"$CYCLE_SCRIPT"'" "next" {
                close_on_exit true
            }
        }
        bind "Shift Alt Tab" {
            Run "'"$CYCLE_SCRIPT"'" "prev" {
                close_on_exit true
            }
        }
    }
}'
else
  KEYBIND_BLOCK=""
fi

cat > "$CONFIG_DIR/config.kdl" <<KDLEOF
default_layout "bare"
default_shell "/bin/sh"
session_serialization false
pane_frames false
$KEYBIND_BLOCK
KDLEOF

export ZELLIJ_CONFIG_DIR="$CONFIG_DIR"
# Force /bin/sh to avoid zsh init noise
export SHELL=/bin/sh

# --- Create three background sessions ---
"$ZELLIJ" attach --create-background A 2>/dev/null
"$ZELLIJ" attach --create-background B 2>/dev/null
"$ZELLIJ" attach --create-background C 2>/dev/null
sleep 1

echo "Sessions created: $("$ZELLIJ" list-sessions --short --no-formatting | tr '\n' ' ')"

# --- Run test in Python ---
exec python3 - "$ZELLIJ" "$WORK" "$MARKER" "$CYCLE_SCRIPT" <<'PYEOF'
import os, pty, subprocess, sys, time

ZELLIJ = sys.argv[1]
WORK = sys.argv[2]
MARKER = sys.argv[3]
CYCLE_SCRIPT = sys.argv[4]
CONFIG_DIR = os.path.join(WORK, "config")
ENV = {**os.environ, "ZELLIJ_CONFIG_DIR": CONFIG_DIR, "SHELL": "/bin/sh"}

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

def probe_session():
    """Write a command to the PTY that saves $ZELLIJ_SESSION_NAME to a marker file.

    After switch-session, the PTY shows the new session's pane, whose
    shell has the correct $ZELLIJ_SESSION_NAME for that session.
    """
    try:
        os.unlink(MARKER)
    except FileNotFoundError:
        pass
    # Clear line, then write probe command
    os.write(master_fd, b"\x03")  # Ctrl-C to cancel any partial input
    time.sleep(0.1)
    os.write(master_fd, f"echo $ZELLIJ_SESSION_NAME > {MARKER}\n".encode())

def read_marker(timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            content = open(MARKER).read().strip()
            if content:
                return content
        except FileNotFoundError:
            pass
        time.sleep(0.2)
    return ""

# --- Allocate PTY and attach to session A ---
master_fd, slave_fd = pty.openpty()
pid = os.fork()
if pid == 0:
    os.close(master_fd); os.setsid()
    os.dup2(slave_fd, 0); os.dup2(slave_fd, 1); os.dup2(slave_fd, 2)
    if slave_fd > 2: os.close(slave_fd)
    os.execvpe(ZELLIJ, [ZELLIJ, "attach", "A"], ENV)
    os._exit(1)
os.close(slave_fd)

# Drain PTY output.
drain_pid = os.fork()
if drain_pid == 0:
    try:
        while True: os.read(master_fd, 4096)
    except OSError: pass
    os._exit(0)

# Wait for zellij + shell init. Dismiss any startup tip with Esc.
time.sleep(3)
os.write(master_fd, b"\x1b")  # Esc — dismiss tips/popups
time.sleep(0.5)
os.write(master_fd, b"\n")    # Enter — get a clean prompt
time.sleep(0.5)

print("=== Alt+Tab session cycling — zellij integration test ===")
print(f"Zellij: {ZELLIJ}")
print()

# --- Discover session order (zellij uses creation order, not alphabetical) ---
order_out = subprocess.run(
    [ZELLIJ, "list-sessions", "--short", "--no-formatting"],
    capture_output=True, text=True, env=ENV
).stdout.strip().split("\n")
order = sorted(s.strip() for s in order_out if s.strip())
print(f"Session order: {order}")

def next_session(current):
    idx = order.index(current)
    return order[(idx + 1) % len(order)]

def prev_session(current):
    idx = order.index(current)
    return order[(idx - 1) % len(order)]

# --- Test 1: starts on A ---
print("Test 1: client attached to session A")
probe_session()
cur = read_marker()
report("initial session", "A", cur)

# --- Test 2: M-Tab → next ---
expect = next_session(cur) if cur in order else "?"
print(f"Test 2: M-Tab cycles {cur} → {expect}")
os.write(master_fd, M_TAB)
time.sleep(2)
os.write(master_fd, b"\x1b")
time.sleep(0.5)
probe_session()
cur = read_marker()
report(f"session after M-Tab", expect, cur)

# --- Test 3: M-Tab → next ---
expect = next_session(cur) if cur in order else "?"
print(f"Test 3: M-Tab cycles {cur} → {expect}")
os.write(master_fd, M_TAB)
time.sleep(2)
os.write(master_fd, b"\x1b")
time.sleep(0.5)
probe_session()
cur = read_marker()
report(f"session after M-Tab", expect, cur)

# --- Test 4: M-Tab wraps → back to start ---
expect = next_session(cur) if cur in order else "?"
print(f"Test 4: M-Tab wraps {cur} → {expect}")
os.write(master_fd, M_TAB)
time.sleep(2)
os.write(master_fd, b"\x1b")
time.sleep(0.5)
probe_session()
cur = read_marker()
report(f"session after M-Tab (wrap)", expect, cur)

# --- Test 5: M-BTab reverse ---
expect = prev_session(cur) if cur in order else "?"
print(f"Test 5: M-BTab cycles {cur} → {expect} (reverse)")
os.write(master_fd, M_BTAB)
time.sleep(2)
os.write(master_fd, b"\x1b")
time.sleep(0.5)
probe_session()
cur = read_marker()
report(f"session after M-BTab", expect, cur)

# --- Test 6: M-BTab reverse ---
expect = prev_session(cur) if cur in order else "?"
print(f"Test 6: M-BTab cycles {cur} → {expect} (reverse)")
os.write(master_fd, M_BTAB)
time.sleep(2)
os.write(master_fd, b"\x1b")
time.sleep(0.5)
probe_session()
cur = read_marker()
report(f"session after M-BTab", expect, cur)

print()
print(f"=== Results: {passed} passed, {failed} failed ===")

os.kill(drain_pid, 9); os.waitpid(drain_pid, 0)
os.kill(pid, 9); os.waitpid(pid, 0)
os.close(master_fd)
sys.exit(failed)
PYEOF

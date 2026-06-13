#!/usr/bin/env bash
# Integration test: zellij keybindings from NMD-89.
#
# Phase 1 — Tab navigation (single session, multiple tabs):
#   Tests Shift+Left/Right, tmux-mode prefix+c/1/2/x
#
# Phase 2 — Session cycling (multiple sessions):
#   Tests tmux-mode prefix+( and prefix+)
#
# Pattern mirrors test-alt-tab-session-cycle.sh:
#   - isolated config dir in a tempdir
#   - bare layout (no plugins/tips)
#   - PTY-attached client via Python pty.openpty()
#   - raw key bytes written to PTY master fd
#   - marker file assertions
#
# Usage: bash test-keybindings.sh
# Exit 0 = PASS, nonzero = FAIL (exit code = failure count)
set -euo pipefail

ZELLIJ="${ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}"
if [[ -z "$ZELLIJ" ]]; then
  echo "SKIP: zellij not found in PATH (set ZELLIJ_BIN to override)"
  exit 0
fi
echo "Using zellij: $ZELLIJ ($($ZELLIJ --version))"

# Resolve the cycle script via git repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../.." && pwd)"
CYCLE_SCRIPT="$REPO_ROOT/home/scripts/zellij-cycle-session.sh"
if [[ ! -f "$CYCLE_SCRIPT" ]]; then
  echo "ABORT: zellij-cycle-session.sh not found at $CYCLE_SCRIPT"
  exit 1
fi
chmod +x "$CYCLE_SCRIPT"
echo "Cycle script: $CYCLE_SCRIPT"

WORK=$(mktemp -d /tmp/zellij-keybind-test.XXXXXX)
MARKER="$WORK/probe"

cleanup() {
  ZELLIJ_CONFIG_DIR="$WORK/config" "$ZELLIJ" kill-all-sessions --yes 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- Isolated config: bare layout, /bin/sh, keybinds under test ---
CONFIG_DIR="$WORK/config"
mkdir -p "$CONFIG_DIR/layouts"

cat > "$CONFIG_DIR/layouts/bare.kdl" <<'KDLEOF'
layout {
    pane
}
KDLEOF

cat > "$CONFIG_DIR/config.kdl" <<KDLEOF
default_layout "bare"
default_shell "/bin/sh"
session_serialization false
pane_frames false

keybinds {
    shared_except "locked" {
        bind "Shift Left"  { GoToPreviousTab; }
        bind "Shift Right" { GoToNextTab; }
        bind "Alt Tab" {
            Run "$CYCLE_SCRIPT" "next" {
                close_on_exit true
            }
        }
        bind "Shift Alt Tab" {
            Run "$CYCLE_SCRIPT" "prev" {
                close_on_exit true
            }
        }
    }
    scroll {
        bind "?" { SwitchToMode "EnterSearch"; SearchInput 0; }
    }
    tmux {
        bind "T" {
            LaunchOrFocusPlugin "session-manager" {
                floating true
                move_to_focused_tab true
            };
            SwitchToMode "Normal";
        }
        bind "X" { Quit; }
        bind "/" { SwitchToMode "EnterSearch"; SearchInput 0; }
        bind "w" {
            LaunchOrFocusPlugin "session-manager" {
                floating true
                move_to_focused_tab true
            };
            SwitchToMode "Normal";
        }
        bind "e" { EditScrollback; SwitchToMode "Normal"; }
        bind "(" {
            Run "$CYCLE_SCRIPT" "prev" {
                close_on_exit true
            };
            SwitchToMode "Normal";
        }
        bind ")" {
            Run "$CYCLE_SCRIPT" "next" {
                close_on_exit true
            };
            SwitchToMode "Normal";
        }
    }
}
KDLEOF

export ZELLIJ_CONFIG_DIR="$CONFIG_DIR"
export SHELL=/bin/sh

# --- Create sessions for both phases ---
# Phase 1 uses "test-kb" for tab tests
# Phase 2 uses A, B, C for session cycling
"$ZELLIJ" attach --create-background test-kb 2>/dev/null
"$ZELLIJ" attach --create-background A 2>/dev/null
"$ZELLIJ" attach --create-background B 2>/dev/null
"$ZELLIJ" attach --create-background C 2>/dev/null
sleep 1
echo "Sessions created: $("$ZELLIJ" list-sessions --short --no-formatting | tr '\n' ' ')"

# --- Run tests in Python ---
exec python3 - "$ZELLIJ" "$WORK" "$MARKER" "$CYCLE_SCRIPT" <<'PYEOF'
import os, pty, signal, subprocess, sys, time

ZELLIJ = sys.argv[1]
WORK = sys.argv[2]
MARKER = sys.argv[3]
CYCLE_SCRIPT = sys.argv[4]
CONFIG_DIR = os.path.join(WORK, "config")
ENV = {**os.environ, "ZELLIJ_CONFIG_DIR": CONFIG_DIR, "SHELL": "/bin/sh"}

# --- Key byte sequences ---
CTRL_B      = b"\x02"                  # tmux-mode prefix
SHIFT_LEFT  = b"\x1b[1;2D"            # xterm Shift+Left
SHIFT_RIGHT = b"\x1b[1;2C"            # xterm Shift+Right
M_TAB       = b"\x1b\x09"             # Alt+Tab
M_BTAB      = b"\x1b\x1b[Z"           # Shift+Alt+Tab

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

def send(keys, pause=0.3):
    os.write(master_fd, keys)
    time.sleep(pause)

def shell_cmd(cmd, pause=0.5):
    send(b"\x03", 0.1)
    send(cmd.encode() + b"\n", pause)

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

def probe_marker(var_name="MY_TAB"):
    """Echo a shell variable to the marker file and read it back."""
    try:
        os.unlink(MARKER)
    except FileNotFoundError:
        pass
    shell_cmd(f"echo ${var_name} > {MARKER}", 0.5)
    return read_marker()

def start_pty(session_name):
    """Fork a PTY-attached zellij client. Returns (master_fd, pid, drain_pid)."""
    m_fd, s_fd = pty.openpty()
    p = os.fork()
    if p == 0:
        os.close(m_fd); os.setsid()
        os.dup2(s_fd, 0); os.dup2(s_fd, 1); os.dup2(s_fd, 2)
        if s_fd > 2: os.close(s_fd)
        os.execvpe(ZELLIJ, [ZELLIJ, "attach", session_name], ENV)
        os._exit(1)
    os.close(s_fd)
    d = os.fork()
    if d == 0:
        try:
            while True: os.read(m_fd, 4096)
        except OSError: pass
        os._exit(0)
    return m_fd, p, d

def stop_pty(m_fd, p, d):
    """Kill PTY processes and close fd."""
    os.kill(d, 9); os.waitpid(d, 0)
    os.kill(p, 9); os.waitpid(p, 0)
    os.close(m_fd)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 1: Tab navigation (single session "test-kb")
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print("=" * 60)
print("PHASE 1: Tab navigation")
print("=" * 60)
print()

master_fd, pid, drain_pid = start_pty("test-kb")
time.sleep(3)
send(b"\x1b", 0.5)
send(b"\n", 0.5)

# Setup: label tab 1
print("Setup: labeling tab 1")
shell_cmd("export MY_TAB=1", 0.3)

# Test 1: prefix+c creates new tab
print("Test 1: tmux mode — prefix+c creates new tab")
send(CTRL_B, 0.3)
send(b"c", 1.5)
send(b"\x1b", 0.3)
shell_cmd("export MY_TAB=2", 0.3)
cur = probe_marker()
report("prefix+c created tab 2, focus on tab 2", "2", cur)

# Test 2: prefix+1 goes to tab 1
print("Test 2: tmux mode — prefix+1 goes to tab 1")
send(CTRL_B, 0.3)
send(b"1", 1.0)
cur = probe_marker()
report("prefix+1 switched to tab 1", "1", cur)

# Test 3: prefix+2 goes to tab 2
print("Test 3: tmux mode — prefix+2 goes to tab 2")
send(CTRL_B, 0.3)
send(b"2", 1.0)
cur = probe_marker()
report("prefix+2 switched to tab 2", "2", cur)

# Test 4: Shift+Left goes to previous tab
print("Test 4: Shift+Left — goes to previous tab")
send(SHIFT_LEFT, 1.0)
cur = probe_marker()
report("Shift+Left from tab 2 → tab 1", "1", cur)

# Test 5: Shift+Right goes to next tab
print("Test 5: Shift+Right — goes to next tab")
send(SHIFT_RIGHT, 1.0)
cur = probe_marker()
report("Shift+Right from tab 1 → tab 2", "2", cur)

# Test 6: Shift+Left wraps around
print("Test 6: Shift+Left wraps — tab 1 → tab 2")
send(SHIFT_LEFT, 1.0)
cur = probe_marker()
report("Shift+Left to tab 1 first", "1", cur)
send(SHIFT_LEFT, 1.0)
cur = probe_marker()
report("Shift+Left wraps tab 1 → tab 2", "2", cur)

# Test 7: prefix+x closes pane/tab
print("Test 7: tmux mode — prefix+x closes current pane")
send(CTRL_B, 0.3)
send(b"c", 1.5)
send(b"\x1b", 0.3)
shell_cmd("export MY_TAB=3", 0.3)
cur = probe_marker()
report("tab 3 created", "3", cur)
send(CTRL_B, 0.3)
send(b"x", 1.5)
cur = probe_marker()
report("after closing tab 3, fell back to another tab", True, cur in ("1", "2"))

stop_pty(master_fd, pid, drain_pid)
print()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 2: Session cycling via tmux mode prefix+( / prefix+)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print("=" * 60)
print("PHASE 2: Session cycling (tmux mode prefix+(/) )")
print("=" * 60)
print()

# Discover sorted session order (cycle script sorts alphabetically)
order_out = subprocess.run(
    [ZELLIJ, "list-sessions", "--short", "--no-formatting"],
    capture_output=True, text=True, env=ENV
).stdout.strip().split("\n")
order = sorted(s.strip() for s in order_out if s.strip())
# Filter to just A, B, C for predictable cycling
abc = [s for s in order if s in ("A", "B", "C")]
print(f"Session order (all): {order}")
print(f"Session order (A/B/C): {abc}")

def next_session(current, sessions):
    idx = sessions.index(current)
    return sessions[(idx + 1) % len(sessions)]

def prev_session(current, sessions):
    idx = sessions.index(current)
    return sessions[(idx - 1) % len(sessions)]

def probe_session():
    """Write $ZELLIJ_SESSION_NAME to marker."""
    try:
        os.unlink(MARKER)
    except FileNotFoundError:
        pass
    shell_cmd(f"echo $ZELLIJ_SESSION_NAME > {MARKER}", 0.5)
    return read_marker()

# Attach to session A
master_fd, pid, drain_pid = start_pty("A")
time.sleep(3)
send(b"\x1b", 0.5)
send(b"\n", 0.5)

# Test 8: verify starting session
print("Test 8: attached to session A")
cur = probe_session()
report("initial session", "A", cur)

# Test 9: prefix+) → next session
expect = next_session("A", order) if "A" in order else "?"
print(f"Test 9: prefix+) cycles A → {expect}")
send(CTRL_B, 0.3)
send(b")", 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"prefix+) from A", expect, cur)

# Test 10: prefix+) → next again
if cur in order:
    expect = next_session(cur, order)
else:
    expect = "?"
print(f"Test 10: prefix+) cycles {cur} → {expect}")
send(CTRL_B, 0.3)
send(b")", 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"prefix+) next", expect, cur)

# Test 11: prefix+( → previous session
if cur in order:
    expect = prev_session(cur, order)
else:
    expect = "?"
print(f"Test 11: prefix+( cycles {cur} → {expect}")
send(CTRL_B, 0.3)
send(b"(", 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"prefix+( prev", expect, cur)

# Test 12: prefix+( → previous again
if cur in order:
    expect = prev_session(cur, order)
else:
    expect = "?"
print(f"Test 12: prefix+( cycles {cur} → {expect}")
send(CTRL_B, 0.3)
send(b"(", 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"prefix+( prev", expect, cur)

stop_pty(master_fd, pid, drain_pid)
print()

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PHASE 3: Session cycling via Alt+Tab / Shift+Alt+Tab (shared_except)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print("=" * 60)
print("PHASE 3: Session cycling (Alt+Tab / Shift+Alt+Tab)")
print("=" * 60)
print()

# Reattach to A
master_fd, pid, drain_pid = start_pty("A")
time.sleep(3)
send(b"\x1b", 0.5)
send(b"\n", 0.5)

# Test 13: Alt+Tab → next
cur = probe_session()
if cur in order:
    expect = next_session(cur, order)
else:
    expect = "?"
print(f"Test 13: Alt+Tab cycles {cur} → {expect}")
send(M_TAB, 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"Alt+Tab next", expect, cur)

# Test 14: Shift+Alt+Tab → previous
if cur in order:
    expect = prev_session(cur, order)
else:
    expect = "?"
print(f"Test 14: Shift+Alt+Tab cycles {cur} → {expect}")
send(M_BTAB, 0.3)
time.sleep(2)
send(b"\x1b", 0.5)
cur = probe_session()
report(f"Shift+Alt+Tab prev", expect, cur)

stop_pty(master_fd, pid, drain_pid)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
print()
print(f"=== Results: {passed} passed, {failed} failed ===")
sys.exit(failed)
PYEOF

"""
End-to-end tests for tmux-snapshot.

Runs against real tmux + real tmuxp on isolated sockets. No mocks.
Each test starts/kills its own tmux server so they're parallel-safe.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

import sys
sys.path.insert(0, str(Path(__file__).parent))
import snapshot as snap


def tmux(socket: str, *args: str, check: bool = True,
         env: dict | None = None) -> str:
    res = subprocess.run(
        ["tmux", "-S", socket, *args],
        capture_output=True, text=True, env=env,
    )
    if check and res.returncode != 0:
        raise AssertionError(f"tmux {' '.join(args)} failed: {res.stderr}")
    return res.stdout


def tmuxp_load(socket: str, yaml: Path, *, env: dict | None = None) -> None:
    subprocess.run(
        ["tmuxp", "load", "-S", socket, "-d", "-y", str(yaml)],
        capture_output=True, text=True, check=True, env=env,
    )


def list_pane_geometry(socket: str, session: str) -> list[tuple[int, int, int, int]]:
    raw = tmux(socket, "list-panes", "-s", "-t", session,
               "-F", "#{pane_top} #{pane_left} #{pane_width} #{pane_height}")
    rows = []
    for line in raw.splitlines():
        if not line:
            continue
        rows.append(tuple(int(x) for x in line.split()))
    return sorted(rows)


def pane_at(socket: str, session: str, top: int, left: int) -> str:
    """Return pane_id at given visual position."""
    raw = tmux(socket, "list-panes", "-s", "-t", session,
               "-F", "#{pane_top} #{pane_left} #{pane_id}")
    for line in raw.splitlines():
        t, l, pid = line.split()
        if int(t) == top and int(l) == left:
            return pid
    raise AssertionError(f"no pane at top={top}, left={left}; got:\n{raw}")


def pane_content(socket: str, pane_id: str) -> str:
    return tmux(socket, "capture-pane", "-t", pane_id, "-p")


def read_cell_id(socket: str, pane_id: str, *,
                 env: dict | None = None) -> str:
    """Read $CELL_ID from a pane's process env — no TTY/shell interaction.

    Path: tmux format-string query (`#{pane_pid}`) → read OS process env
    via `/proc/<pid>/environ` (Linux) or `ps -E` (macOS/BSD). Same channel
    snapshot.py uses on the save side (`_read_pane_env`), so symmetric.

    Replaces the older `send-keys 'printf @@$CELL_ID@@'` + `capture-pane`
    + regex scrape, which required (1) a live shell with PTY echoing,
    (2) a polling loop on the screen buffer, and (3) careful regex sync.
    """
    pane_pid = tmux(socket, "display-message", "-p", "-t", pane_id,
                    "#{pane_pid}", env=env).strip()
    return snap._read_pane_env(pane_pid, "CELL_ID")


class TmuxFixture:
    """Per-test isolated tmux + tmuxp environment.

    Symmetric config: both the save-side tmux (run directly via the
    `tmux()` helper) and the load-side tmux (run by tmuxp internally)
    must see the same tmux.conf, otherwise pane geometry differs after
    round-trip — the user's real ~/.config/tmux/tmux.conf would leak in
    on the load side via the default HOME. We solve this by writing a
    minimal conf into a per-test fake HOME and forcing both subprocesses
    to use it.
    """

    def __init__(self, work: Path):
        self.work = work
        self.work.mkdir(parents=True, exist_ok=True)
        self.sock = str(work / "sock")
        self.load_sock = str(work / "load_sock")
        self.yaml_dir = work / "tmuxp"
        self.yaml_dir.mkdir(exist_ok=True)

        # Fake HOME with a deterministic minimal tmux config. status=off
        # so pane geometry equals the full session size on both sides.
        self.home = work / "fake_home"
        self.home.mkdir(exist_ok=True)
        self.conf = self.home / ".tmux.conf"
        self.conf.write_text(
            "set -g status off\n"
            # Use /bin/sh so we don't inherit zsh init noise (compinit
            # prompts, autosuggestions, etc.) when the load-side tmuxp
            # spawns shells in the empty fake HOME. CELL_ID export still
            # works — POSIX sh handles it fine.
            "set -g default-shell /bin/sh\n"
            "set -g default-command /bin/sh\n"
        )
        # Block XDG fallback to ~/.config/tmux/tmux.conf on the user's box.
        (self.home / ".config").mkdir(exist_ok=True)

        self.env = {**os.environ,
                    "HOME": str(self.home),
                    "XDG_CONFIG_HOME": str(self.home / ".config")}

    def kill_all(self) -> None:
        for s in (self.sock, self.load_sock):
            subprocess.run(["tmux", "-S", s, "kill-server"],
                           capture_output=True)


def normalize_layout(s: str) -> str:
    """Strip checksum prefix and leaf pane indices for comparison.
    Leaf format: WxH,X,Y,N — the trailing N is the pane index, drop it."""
    s = re.sub(r"^[0-9a-f]{4},", "", s)
    # Replace WxH,X,Y,N -> WxH,X,Y (N is one or more digits, followed by , } ] or end)
    s = re.sub(r"(\d+x\d+,\d+,\d+),\d+", r"\1", s)
    return s


# ------------------------------------------------------------------ tests


class RoundTripTests(unittest.TestCase):
    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    # ---- 1. visual order, simple even-horizontal ----
    def test_three_pane_even_horizontal_round_trip(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "180", "-y", "40", "-n", "win1")
        tmux(sock, "split-window", "-h", "-t", "rt:win1")
        tmux(sock, "split-window", "-h", "-t", "rt:win1")
        tmux(sock, "select-layout", "-t", "rt:win1", "even-horizontal")

        before = list_pane_geometry(sock, "rt")
        before_layout = tmux(sock, "list-windows", "-t", "rt",
                             "-F", "#{window_layout}").strip()

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        self.assertTrue(target.exists())

        tmux(sock, "kill-server")
        tmuxp_load(self.fx.load_sock, target)
        time.sleep(0.2)

        after = list_pane_geometry(self.fx.load_sock, "rt")
        after_layout = tmux(self.fx.load_sock, "list-windows", "-t", "rt",
                            "-F", "#{window_layout}").strip()

        self.assertEqual(before, after, "pane geometry mismatch after round-trip")
        self.assertEqual(normalize_layout(before_layout),
                         normalize_layout(after_layout))

    # ---- 2. visual order with main-horizontal (creation order != visual order) ----
    def test_main_horizontal_panes_land_in_correct_positions(self):
        """The bug fix: panes must be emitted in visual order, not pane_index."""
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "omv")
        tmux(sock, "split-window", "-v", "-t", "rt:omv")
        tmux(sock, "split-window", "-h", "-t", "rt:omv")
        tmux(sock, "select-layout", "-t", "rt:omv", "main-horizontal")

        # Tag each pane via send-keys so we can identify positions post-load.
        # We use start_command via respawn-pane so the command persists across
        # the freeze/load (pane_current_command basename is captured).
        for pid, ident in [("%0", "TOPBAR"), ("%1", "BOTLEFT"), ("%2", "BOTRIGHT")]:
            # Use a uniquely-named sleep-ish binary so basename round-trips
            # something identifying. Easiest: use distinct shell scripts.
            pass

        # Capture geometry & visual order before save
        positions_before = sorted(set(
            (int(t), int(l)) for t, l, *_ in
            (line.split() for line in
             tmux(sock, "list-panes", "-t", "rt:omv",
                  "-F", "#{pane_top} #{pane_left}").splitlines() if line)
        ))

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)

        # The YAML must list panes in the same order tmux's list-panes returns
        # them when sorted by (top, left). Verify directly.
        text = target.read_text()
        cell_ids = re.findall(r"CELL_ID:\s*'(\d+)'", text)
        # CELL_IDs must appear in visual-order. Pull live pane_ids by visual
        # order to compare.
        visual_order = []
        for line in tmux(sock, "list-panes", "-t", "rt:omv",
                         "-F", "#{pane_top} #{pane_left} #{pane_id}").splitlines():
            t, l, pid = line.split()
            visual_order.append((int(t), int(l), pid.lstrip("%")))
        visual_order.sort()
        expected = [pid for _, _, pid in visual_order]
        self.assertEqual(cell_ids, expected,
                         f"YAML CELL_IDs not in visual order:\n{text}")

        # Now actually round-trip and verify panes land in the right positions.
        tmux(sock, "kill-server")
        tmuxp_load(self.fx.load_sock, target)
        time.sleep(0.2)
        self.assertEqual(positions_before,
                         sorted(set(
                             (int(t), int(l)) for line in
                             tmux(self.fx.load_sock, "list-panes", "-s", "-t", "rt",
                                  "-F", "#{pane_top} #{pane_left}").splitlines()
                             if line
                             for t, l in [line.split()]
                         )))

    # ---- 3. dot in window name ----
    def test_dot_in_window_name(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "nmd.gg")
        # window_id -> tmux split must use @id, not name (else dot bug)
        wid = tmux(sock, "list-windows", "-t", "rt",
                   "-F", "#{window_id}").strip()
        tmux(sock, "split-window", "-h", "-t", wid)
        tmux(sock, "split-window", "-v", "-t", wid)

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        text = target.read_text()
        # All 3 panes must have CELL_ID; none missing.
        cell_ids = re.findall(r"CELL_ID:\s*'(\d+)'", text)
        self.assertEqual(len(cell_ids), 3,
                         f"expected 3 CELL_IDs (dot-in-name bug), got {len(cell_ids)}\n{text}")

        # Round-trip must reproduce window name.
        tmux(sock, "kill-server")
        tmuxp_load(self.fx.load_sock, target)
        time.sleep(0.2)
        names = tmux(self.fx.load_sock, "list-windows", "-t", "rt",
                     "-F", "#{window_name}").splitlines()
        self.assertIn("nmd.gg", names)

    # ---- 4. layout string preservation ----
    def test_layout_string_preserved(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win")
        tmux(sock, "split-window", "-v", "-t", "rt:win")
        tmux(sock, "split-window", "-h", "-t", "rt:win")
        tmux(sock, "select-layout", "-t", "rt:win", "main-horizontal")

        layout_before = tmux(sock, "list-windows", "-t", "rt",
                             "-F", "#{window_layout}").strip()
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        # The layout line in YAML must match byte-for-byte.
        self.assertIn(f"layout: {layout_before}", target.read_text())

    # ---- 5. REPL handling ----
    def test_repl_panes_kept_with_default_shell(self):
        """REPL panes (python/node/...) keep their slot in the layout but
        have shell_command rewritten to 'zsh' so tmuxp load doesn't
        relaunch the REPL on restore."""
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "120", "-y", "30", "-n", "win")
        tmux(sock, "split-window", "-h", "-t", "rt:win")
        pids = tmux(sock, "list-panes", "-t", "rt:win",
                    "-F", "#{pane_id}").split()
        # Run a long-lived python so pane_current_command shows "python3".
        tmux(sock, "send-keys", "-t", pids[1],
             "python3 -c 'import time; time.sleep(60)'", "Enter")
        # Poll for python detection — startup time varies wildly across
        # environments (cold cache, slow filesystems, devcell containers).
        cur: list[str] = []
        for _ in range(60):  # up to 6s
            time.sleep(0.1)
            cur = tmux(sock, "list-panes", "-t", "rt:win",
                       "-F", "#{pane_current_command}").splitlines()
            if any("python" in c for c in cur):
                break
        self.assertTrue(any("python" in c for c in cur),
                        f"python pane not detected after 6s: {cur}")

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        text = target.read_text()
        # All panes kept (layout integrity)
        cell_ids = re.findall(r"CELL_ID:\s*'(\d+)'", text)
        self.assertEqual(len(cell_ids), 2,
                         f"expected both panes kept, got {len(cell_ids)}\n{text}")
        # No REPL command should appear in shell_command
        self.assertNotIn("python", text,
                         f"REPL command leaked into YAML:\n{text}")

    def test_versioned_repl_basenames_detected(self):
        """python3.13 / python2.7 / etc. should also be treated as REPLs."""
        for cmd in ("python3.13", "python2.7", "ipython3", "node20"):
            p = snap.Pane(
                pane_id="%1", pane_index=1, top=0, left=0,
                width=80, height=24,
                current_command=cmd, start_command="",
                focus=False, cwd="/",
            )
            self.assertTrue(p.is_repl, f"{cmd} should be REPL")
            self.assertEqual(p.shell_command, "zsh",
                             f"{cmd} should rewrite to zsh")

    # ---- 6. CELL_ID injection ----
    def test_cell_id_matches_pane_id_without_percent(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "120", "-y", "30", "-n", "win")
        tmux(sock, "split-window", "-h", "-t", "rt:win")

        live_pids = [
            l.lstrip("%")
            for l in tmux(sock, "list-panes", "-t", "rt:win",
                          "-F", "#{pane_id}").split()
            if l
        ]
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        text = target.read_text()
        cell_ids = re.findall(r"CELL_ID:\s*'(\d+)'", text)
        self.assertEqual(sorted(cell_ids), sorted(live_pids))


# ForegroundArgvTests removed. The full-argv capture they exercised was
# rolled back pending the design decision in NMD-57. Re-add this class
# (and the snapshot helper it tested) once the dilemma is resolved.


class MainHorizontalMirroredRoundTripTests(unittest.TestCase):
    """End-to-end scenario from the user's tmux config (`prefix S h`):

    1. Create new session
    2. Split vertically (top/bottom)
    3. Split top pane horizontally (top-left/top-right + bottom)
    4. Apply `main-horizontal-mirrored` layout (with main-pane-height=2)
    5. Snapshot via tmux-snapshot
    6. Kill server
    7. tmuxp load on a fresh socket
    8. Verify pane geometry + layout topology match exactly

    Uses the symmetric-config fixture (HOME override + minimal tmux.conf)
    so geometry comparisons are deterministic across Linux/macOS.
    """

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    # Visual order after main-horizontal-mirrored layout is:
    # Panel Left (top-left), Panel Right (top-right), Panel Bottom (the
    # large mirrored "main" pane). Sort key (top, left) yields exactly
    # that order: top-left and top-right share the smallest pane_top with
    # different pane_left; bottom has the largest pane_top.
    PANE_NAMES = ["Panel Left", "Panel Right", "Panel Bottom"]

    def test_split_v_split_h_main_horizontal_mirrored_round_trip(self):
        sock = self.fx.sock
        env = self.fx.env

        # 1. Create new session (200x48 — wide enough to exercise splits)
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)

        # 2. Split vertically -> pane 1 (top), pane 2 (bottom)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)

        # 3. Split TOP pane horizontally -> pane 1 (top-left), pane 3 (top-right)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)

        # 4. Apply main-horizontal-mirrored (the `prefix S h` action)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

        # 4.1. Name each pane in visual order so we can prove on restore
        # that contents went into the SAME visual slot. CELL_ID is what
        # actually round-trips through tmuxp (`environment:` block); we
        # build a {cell_id -> name} mapping here so post-load we can
        # translate the CELL_ID back to the human-readable name.
        before_panes = self._list_panes_visual(sock, env)
        self.assertEqual(len(before_panes), 3, f"expected 3 panes: {before_panes}")
        cell_id_to_name: dict[str, str] = {}
        for (top, left, w, h, pane_id), name in zip(before_panes, self.PANE_NAMES):
            cell_id = pane_id.lstrip("%")
            cell_id_to_name[cell_id] = name
            # Set pane title for human inspection / debugging
            tmux(sock, "select-pane", "-t", pane_id, "-T", name, env=env)

        before_state = {
            "geometry": [(t, l, w, h) for t, l, w, h, _ in before_panes],
            "names_in_visual_order": list(self.PANE_NAMES),
            "cell_id_to_name": cell_id_to_name,
            "layout": tmux(sock, "list-windows", "-t", "rt",
                           "-F", "#{window_layout}", env=env).strip(),
        }
        (self.work / "before.json").write_text(json.dumps(before_state, indent=2))

        # 5. Save snapshot via our tool
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        self.assertTrue(target.exists())

        # 6. Kill server
        tmux(sock, "kill-server", env=env, check=False)

        # 7. Load via snap.load_session. For canonical preset layouts
        # (this test's case) load_session does an automatic post-load
        # re-apply of the preset, so the visual lands correctly without
        # the user having to press `S h`.
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)

        # 8. Read each loaded pane's CELL_ID via the shell, then translate
        # to the original name through the cell_id_to_name map.
        after_panes = self._list_panes_visual(self.fx.load_sock, env)
        names_after = []
        for top, left, w, h, pane_id in after_panes:
            cid = self._read_cell_id(self.fx.load_sock, pane_id, env)
            name = cell_id_to_name.get(cid, f"<unknown CELL_ID={cid}>")
            names_after.append(name)

        after_state = {
            "geometry": [(t, l, w, h) for t, l, w, h, _ in after_panes],
            "names_in_visual_order": names_after,
            "layout": tmux(self.fx.load_sock, "list-windows", "-t", "rt",
                           "-F", "#{window_layout}", env=env).strip(),
        }
        (self.work / "after.json").write_text(json.dumps(after_state, indent=2))

        # Geometry: visual coordinates must match
        self.assertEqual(before_state["geometry"], after_state["geometry"],
                         f"pane geometry mismatch\n"
                         f"before: {before_state['geometry']}\n"
                         f"after:  {after_state['geometry']}")

        # Layout topology
        self.assertEqual(normalize_layout(before_state["layout"]),
                         normalize_layout(after_state["layout"]),
                         f"layout topology mismatch\n"
                         f"before: {before_state['layout']}\n"
                         f"after:  {after_state['layout']}")

        # KEY ASSERTION — named panes land in the SAME visual positions.
        # If geometry matches but names are scrambled, panes are in the
        # wrong slots (the bug the user suspects).
        self.assertEqual(self.PANE_NAMES, names_after,
                         f"named panes landed in wrong visual positions:\n"
                         f"  expected (top→bottom, left→right): {self.PANE_NAMES}\n"
                         f"  got:                                {names_after}\n"
                         f"  geometry was equal, so contents were swapped between slots.")

    def test_force_load_into_running_server_with_renamed_session(self):
        """The `prefix C-r` path: session is live on a server, gets
        renamed aside, then reloaded from YAML on the SAME server.
        Existing tests load onto a fresh socket; this exercises the
        scenario the user actually hits via the keybind.
        """
        sock = self.fx.sock
        env = self.fx.env

        # 1. Build a mirrored-layout session. Use a "DEMO" name to mirror
        # the user's actual reproduction.
        tmux(sock, "new-session", "-d", "-s", "DEMO",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        wid = tmux(sock, "list-windows", "-t", "DEMO",
                   "-F", "#{window_id}", env=env).strip()
        tmux(sock, "split-window", "-v", "-t", wid, env=env)
        top = tmux(sock, "list-panes", "-t", wid,
                   "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", wid,
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", wid,
             "main-horizontal-mirrored", env=env)

        # 2. Save snapshot.
        target = snap.save_session("DEMO", socket=sock, out_dir=self.fx.yaml_dir)

        # 3. Rename DEMO -> DEMO.bak.$ to mimic snapshotRestoreCurrent.
        tmux(sock, "rename-session", "-t", "DEMO", "DEMO_bak_test", env=env)

        # 4. Force-load DEMO onto the SAME socket. This is the path the
        # user's `prefix C-r` triggers via run-shell.
        snap.load_session(target, socket=sock, env=env)
        time.sleep(0.3)

        # 5. Both sessions exist now.
        sessions = tmux(sock, "list-sessions", "-F", "#{session_name}",
                        env=env).splitlines()
        self.assertIn("DEMO", sessions)
        self.assertIn("DEMO_bak_test", sessions)

        # 6. Saved layout was canonical mirrored, so load_session
        # re-applies the preset. Result: bottom strip h=2, two larger
        # panes on top. No manual `S h` required.
        raw = tmux(sock, "list-panes", "-t", "DEMO:win",
                   "-F", "#{pane_top} #{pane_height}",
                   env=env).splitlines()
        rows = sorted((int(t), int(h)) for t, h in
                      (l.split() for l in raw if l.strip()))
        self.assertEqual(rows[0][0], 0, f"top row not at top=0: {rows}")
        self.assertEqual(rows[1][0], 0, f"top row second pane not at top=0: {rows}")
        self.assertEqual(rows[-1][1], 2,
                         f"bottom strip not h=2 after load: {rows}")

        # 7. Re-apply must be idempotent.
        before = tmux(sock, "display-message", "-p", "-t", "DEMO:win",
                      "#{window_layout}", env=env).strip()
        tmux(sock, "select-layout", "-t", "DEMO:win",
             "main-horizontal-mirrored", env=env)
        after = tmux(sock, "display-message", "-p", "-t", "DEMO:win",
                     "#{window_layout}", env=env).strip()
        self.assertEqual(before, after,
                         f"re-apply changed layout (not idempotent):\n"
                         f"before: {before}\nafter:  {after}")

    def test_custom_layout_slots_round_trip(self):
        """@layout-6..9 are user-defined "save layout to slot" globals.
        Must be captured at save time and restored on load — the slots
        live in tmux server runtime state, so without us they reset
        when the server restarts.
        """
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "120", "-y", "30", "-n", "win", env=env)

        # Two slots set, two unset — only set ones should round-trip.
        tmux(sock, "set-option", "-g", "@layout-6",
             "abcd,120x30,0,0,0", env=env)
        tmux(sock, "set-option", "-g", "@layout-9",
             "ef01,120x30,0,0[120x15,0,0,0,120x14,0,16,1]", env=env)

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        text = target.read_text()
        self.assertIn("custom_layouts:", text,
                      f"missing custom_layouts block:\n{text}")
        # Slot keys must be present
        self.assertIn("'6':", text)
        self.assertIn("'9':", text)
        self.assertNotIn("'7':", text)
        self.assertNotIn("'8':", text)

        # Round-trip: kill server, load on fresh socket, verify slots set.
        tmux(sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.3)

        got_6 = tmux(self.fx.load_sock, "show-options", "-gv",
                     "@layout-6", env=env).strip()
        got_9 = tmux(self.fx.load_sock, "show-options", "-gv",
                     "@layout-9", env=env).strip()
        self.assertEqual(got_6, "abcd,120x30,0,0,0")
        self.assertEqual(got_9, "ef01,120x30,0,0[120x15,0,0,0,120x14,0,16,1]")

    def test_save_emits_preset_layouts_for_canonical_only(self):
        """preset_layouts: must be emitted for canonical layouts so
        load can auto-canonicalize. Custom-resized layouts must NOT
        get the entry — that's how we preserve their geometry.
        """
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        self.assertIn("preset_layouts:", target.read_text())
        self.assertIn("main-horizontal-mirrored", target.read_text())

    def test_load_handles_dot_in_window_name(self):
        """Dotted window names (e.g. nmd.gg) — load_session must target
        select-layout by window_id (@N), not session:name.
        """
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        wid = tmux(sock, "list-windows", "-t", "rt",
                   "-F", "#{window_id}", env=env).strip()
        tmux(sock, "rename-window", "-t", wid, "nmd.gg", env=env)
        tmux(sock, "split-window", "-v", "-t", wid, env=env)
        top = tmux(sock, "list-panes", "-t", wid,
                   "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", wid,
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", wid,
             "main-horizontal-mirrored", env=env)
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stderr(buf):
            snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.3)
        self.assertNotIn("WARN", buf.getvalue(),
                         f"warnings during re-apply:\n{buf.getvalue()}")

    def test_two_pane_mirrored_preserves_pane_identity_round_trip(self):
        """Reproduces the `pve` window case from NMD-pve-sorted.yaml.

        Two-pane horizontal split with main-pane-height=2 and
        main-horizontal-mirrored applied: pane_index 0 is in the main slot
        (bottom, h=2), pane_index 1 is the top (h=47). The saved layout's
        DFS order is [top, bottom], i.e. [pane_index_1, pane_index_0].

        Current save sorts panes by pane_index → YAML pane order
        [pane_index_0, pane_index_1]. tmuxp creates panes in YAML order
        and DFS-substitutes them into the layout, swapping content
        between the visual slots. Since 2-pane layouts don't match
        detect_preset_layout (needs 3+ panes), there's no post-load
        re-apply to fix it.

        Asserts: the CELL_ID at each visual slot survives the round trip.
        """
        sock = self.fx.sock
        env = self.fx.env

        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)

        # CELL_ID at top slot vs bottom slot before save.
        before_panes = self._list_panes_visual(sock, env)
        self.assertEqual(len(before_panes), 2,
                         f"setup: expected 2 panes, got {before_panes}")
        top_pid_before  = before_panes[0][-1]    # smallest pane_top
        bot_pid_before  = before_panes[-1][-1]
        top_cell_before = top_pid_before.lstrip("%")
        bot_cell_before = bot_pid_before.lstrip("%")
        # Sanity: bottom strip really is h=2
        self.assertEqual(before_panes[-1][3], 2,
                         f"setup: bottom strip h != 2: {before_panes}")

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)

        after_panes = self._list_panes_visual(self.fx.load_sock, env)
        self.assertEqual(len(after_panes), 2,
                         f"expected 2 panes after load: {after_panes}")
        self.assertEqual(after_panes[-1][3], 2,
                         f"bottom strip h != 2 after load: {after_panes}")
        top_pid_after = after_panes[0][-1]
        bot_pid_after = after_panes[-1][-1]
        top_cell_after = self._read_cell_id(self.fx.load_sock, top_pid_after, env)
        bot_cell_after = self._read_cell_id(self.fx.load_sock, bot_pid_after, env)

        self.assertEqual(top_cell_after, top_cell_before,
                         f"TOP slot CELL_ID changed across round-trip.\n"
                         f"  before: top={top_cell_before}, bot={bot_cell_before}\n"
                         f"  after:  top={top_cell_after},  bot={bot_cell_after}\n"
                         f"  (contents swapped — pane_index sort vs DFS order mismatch)")
        self.assertEqual(bot_cell_after, bot_cell_before,
                         f"BOTTOM slot CELL_ID changed across round-trip")

    def test_detect_preset_skips_user_resized_layout(self):
        """Unit test for the canonical-only detector: asymmetric
        secondary widths are NOT a preset, equal widths are. Used by
        documentation tests only — the production save/load path no
        longer enforces presets, so this flag is informational.
        """
        # User dragged dividers — widths 74, 18, 64, 63 (asymmetric).
        custom = ("9f34,222x53,0,0[222x50,0,0"
                  "{74x50,0,0,240,18x50,75,0,241,64x50,94,0,242,63x50,159,0,243},"
                  "222x2,0,51,239]")
        # Canonical mirrored — widths 55, 55, 55, 54 (equal ±1).
        canonical = ("3672,222x53,0,0[222x50,0,0"
                     "{55x50,0,0,240,55x50,56,0,241,55x50,112,0,242,54x50,168,0,243},"
                     "222x2,0,51,239]")
        self.assertIsNone(snap.detect_preset_layout(custom),
                          "asymmetric layout wrongly marked as preset")
        self.assertEqual(snap.detect_preset_layout(canonical),
                         "main-horizontal-mirrored")

    # Regression test for the user-reported bug: re-applying a preset
    # layout (e.g. via `prefix S h`) after a snap.load_session must NOT
    # scramble pane content. Pane_index emit order makes this work.
    def test_reapply_preset_layout_after_round_trip_preserves_pane_roles(self):
        sock = self.fx.sock
        env = self.fx.env

        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

        before_panes = self._list_panes_visual(sock, env)
        cell_id_to_name: dict[str, str] = {}
        for (top, left, w, h, pane_id), name in zip(before_panes, self.PANE_NAMES):
            cell_id_to_name[pane_id.lstrip("%")] = name

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)
        tmuxp_load(self.fx.load_sock, target, env=env)
        time.sleep(0.6)

        # Step 4 — re-apply the same preset layout post-restore.
        tmux(self.fx.load_sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)

        reapply_panes = self._list_panes_visual(self.fx.load_sock, env)
        names_reapply = [
            cell_id_to_name.get(self._read_cell_id(self.fx.load_sock, pid, env),
                                 "<unknown>")
            for _, _, _, _, pid in reapply_panes
        ]
        self.assertEqual(self.PANE_NAMES, names_reapply,
                         f"re-applying main-horizontal-mirrored scrambled "
                         f"named panes: expected {self.PANE_NAMES}, "
                         f"got {names_reapply}")

    def _list_panes_visual(self, sock: str, env: dict) -> list:
        """List panes sorted by (top, left). Returns (top, left, w, h, pane_id)."""
        raw = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_top} #{pane_left} #{pane_width} #{pane_height} #{pane_id}",
                   env=env).splitlines()
        return sorted(
            (int(t), int(l), int(w), int(h), pid)
            for t, l, w, h, pid in (line.split() for line in raw if line.strip())
        )

    def _read_cell_id(self, sock: str, pane_id: str, env: dict) -> str:
        # Delegates to the module helper — reads CELL_ID from the pane
        # process's OS env (same channel snapshot.py uses), so no PTY,
        # no shell echo polling, no buffer regex.
        return read_cell_id(sock, pane_id, env=env)


# ------------------------------------------------------------------ layout rewrite helpers


def layout_checksum(body: str) -> str:
    """tmux's layout checksum: right-rotate-1 + add, mod 16-bit."""
    c = 0
    for ch in body.encode():
        c = ((c >> 1) | ((c & 1) << 15)) & 0xFFFF
        c = (c + ch) & 0xFFFF
    return f"{c:04x}"


def _split_top_level_children(s: str) -> list[str]:
    """Split a layout-string children list at depth-0 commas.

    Children are either leaves `WxH,X,Y,N` (3 internal commas at depth 0!)
    or subtrees `WxH,X,Y[...]` / `WxH,X,Y{...}`. We track bracket depth and
    count commas inside each child via the leading geometry pattern.
    """
    children: list[str] = []
    i = 0
    while i < len(s):
        # Each child starts with WxH,X,Y (3 numbers, 2 commas)
        m = re.match(r"\d+x\d+,\d+,\d+", s[i:])
        if not m:
            raise ValueError(f"bad layout child at offset {i}: {s[i:]!r}")
        end = i + m.end()
        # Either a subtree opener follows, or a leaf id ",N"
        if end < len(s) and s[end] in "[{":
            opener = s[end]
            closer = "]" if opener == "[" else "}"
            depth = 1
            j = end + 1
            while j < len(s) and depth > 0:
                if s[j] == opener:
                    depth += 1
                elif s[j] == closer:
                    depth -= 1
                j += 1
            child = s[i:j]
            i = j
        elif end < len(s) and s[end] == ",":
            m2 = re.match(r",\d+", s[end:])
            if not m2:
                raise ValueError(f"bad leaf id at {end}: {s[end:]!r}")
            child = s[i:end + m2.end()]
            i = end + m2.end()
        else:
            child = s[i:end]
            i = end
        children.append(child)
        if i < len(s) and s[i] == ",":
            i += 1
    return children


def reverse_root_children(layout: str) -> str:
    """Swap the top-level children of `[...]`. Recompute the checksum.

    Used to flip a `[subtree, leaf]` (e.g. main-horizontal-mirrored where
    the small main strip is the LAST DFS leaf) into `[leaf, subtree]` so
    the bottom strip becomes the FIRST DFS leaf — making YAML[0] (which
    becomes pane_index 0 after tmuxp load) land in the main slot.
    """
    body = re.sub(r"^[0-9a-f]{4},", "", layout)
    m = re.match(r"^(\d+x\d+,\d+,\d+)\[(.*)\]$", body)
    if not m:
        return layout  # not a top-level horizontal split — leave alone
    prefix, inner = m.groups()
    children = _split_top_level_children(inner)
    if len(children) < 2:
        return layout
    new_inner = ",".join(reversed(children))
    new_body = f"{prefix}[{new_inner}]"
    return f"{layout_checksum(new_body)},{new_body}"


# ------------------------------------------------------------------ fixture tests

FIXTURE_DIR = Path(__file__).parent / "fixtures"


class UserFixtureTests(unittest.TestCase):
    """Load the user's actual NMD.yaml and assert the load behavior.

    The fixture was saved by the current snapshot tool (visual-order emit)
    on a real session that used `main-horizontal-mirrored` for several
    windows. We use the `nixhome` window (last in the YAML, mirrored shape:
    `[topgroup, bottom_strip]`) as the canonical case.
    """

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def _load(self, yaml_path: Path) -> None:
        # Use snap.load_session (not bare tmuxp_load) — it honors the
        # `preset_layouts:` block and post-load re-applies main-* presets,
        # which is the round-trip path real users hit via `tmuxsave/load`.
        snap.load_session(yaml_path, socket=self.fx.load_sock, env=self.fx.env)
        time.sleep(0.8)

    def _panes_visual(self, window: str) -> list:
        raw = tmux(self.fx.load_sock, "list-panes",
                   "-t", f"NMD:{window}",
                   "-F", "#{pane_top} #{pane_left} #{pane_width} #{pane_height} #{pane_id}",
                   env=self.fx.env).splitlines()
        return sorted(
            (int(t), int(l), int(w), int(h), pid)
            for t, l, w, h, pid in (line.split() for line in raw if line.strip())
        )

    def _read_cell_id(self, pane_id: str) -> str:
        return read_cell_id(self.fx.load_sock, pane_id, env=self.fx.env)

    def test_as_saved_yaml_loads_with_correct_visual_order(self):
        """Sanity: the saved fixture round-trips visually correctly.

        nixhome window has mirrored shape: top-left=111, top-right=112,
        bottom (main)=110. The fixture is in the post-fix emit format —
        YAML[0] is the main pane (110) and the layout's root children are
        reversed — so snap.load_session's post-load re-apply lands content
        in the canonical visual slots.
        """
        self._load(FIXTURE_DIR / "NMD-saved.yaml")
        panes = self._panes_visual("nixhome")
        self.assertEqual(len(panes), 3)
        cell_ids = [self._read_cell_id(pid) for *_, pid in panes]
        self.assertEqual(cell_ids, ["111", "112", "110"],
                         "visual round-trip broken: nixhome panes "
                         "should be top-left=111, top-right=112, bottom=110")

    def test_reapply_main_horizontal_mirrored_after_load_keeps_main_at_bottom(self):
        """Regression for the user-reported scramble.

        Pressing `prefix S h` (manual re-apply of main-horizontal-mirrored)
        after a load must NOT move the original main-slot pane out of the
        bottom slot. Pre-fix, save sorted by pane_index put a secondary
        pane at YAML[0]; tmuxp made it pane_index 0; then the re-apply
        forced THAT pane (not the original main) into the main slot,
        scrambling content. Fix: emit_yaml hoists the main pane to YAML[0]
        and reverses the layout's root children for *-mirrored presets,
        so pane_index 0 ↔ main role survives load + arbitrary re-apply.
        """
        self._load(FIXTURE_DIR / "NMD-saved.yaml")
        env = self.fx.env
        tmux(self.fx.load_sock, "set-window-option", "-t", "NMD:nixhome",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "NMD:nixhome",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.3)
        panes = self._panes_visual("nixhome")
        cell_ids = [self._read_cell_id(pid) for *_, pid in panes]
        self.assertEqual(cell_ids[2], "110",
                         "bottom slot after re-apply should still be CELL_ID 110")

    def test_repeated_reapply_is_idempotent_for_mirrored_layout(self):
        """Pressing `prefix S h` multiple times must not drift content
        across visual slots. Pane_index 0 ↔ main pane is invariant under
        repeated `select-layout main-horizontal-mirrored`, which keeps
        the result stable across any number of re-applies.
        """
        self._load(FIXTURE_DIR / "NMD-saved.yaml")

        env = self.fx.env
        tmux(self.fx.load_sock, "set-window-option", "-t", "NMD:nixhome",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "NMD:nixhome",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.3)
        cell_ids_first = [self._read_cell_id(pid)
                          for *_, pid in self._panes_visual("nixhome")]
        self.assertEqual(cell_ids_first, ["111", "112", "110"],
                         f"first re-apply scrambled visuals: {cell_ids_first}")

        # Second re-apply: must be a no-op visually.
        tmux(self.fx.load_sock, "select-layout", "-t", "NMD:nixhome",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)
        cell_ids_second = [self._read_cell_id(pid)
                           for *_, pid in self._panes_visual("nixhome")]
        self.assertEqual(cell_ids_first, cell_ids_second,
                         f"second re-apply not idempotent: {cell_ids_second}")


class LabelFixtureLoadTests(unittest.TestCase):
    """Load a real-shape fixture that carries CELL_LABEL entries and assert
    the labels land on the right panes in the loaded session.

    The fixture (`fixtures/NMD-2026-05-31.yaml`) is a single-window
    main-horizontal-mirrored layout — same shape as the user's live
    `nixhome` window — with the canary mapping:

        pane_index N (bottom main, CELL_ID 110)  → 'Three Renamed'
        pane_index N+1 (top-left, CELL_ID 111)   → 'One Renamed'
        pane_index N+2 (top-right, CELL_ID 112)  → 'Two Renamed'

    (N is whichever base-index the test socket runs with — 0 or 1.)
    """

    SESSION = "NMD-2026-05-31"
    EXPECTED_LABELS = {"One Renamed", "Two Renamed", "Three Renamed"}

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def _load(self) -> None:
        snap.load_session(FIXTURE_DIR / "NMD-2026-05-31.yaml",
                          socket=self.fx.load_sock, env=self.fx.env)
        time.sleep(0.8)

    def _labels_by_pane_index(self) -> dict[int, str]:
        raw = tmux(self.fx.load_sock, "list-panes",
                   "-t", f"{self.SESSION}:nixhome",
                   "-F", "#{pane_index}\t#{@label}",
                   env=self.fx.env).splitlines()
        out: dict[int, str] = {}
        for line in raw:
            if not line.strip():
                continue
            idx, _, label = line.partition("\t")
            out[int(idx)] = label
        return out

    def test_one_renamed_appears_in_loaded_session(self):
        """The user's specific check: load the fixture, prove 'One Renamed'
        is on some pane in the loaded session."""
        self._load()
        labels = set(self._labels_by_pane_index().values())
        self.assertIn("One Renamed", labels,
                      f"'One Renamed' missing — got labels: {labels}")

    def test_all_canary_labels_appear_in_loaded_session(self):
        """Stronger check: all three canary labels must land on panes."""
        self._load()
        labels = set(self._labels_by_pane_index().values())
        # Drop empty strings if base-index difference creates a 4th unnamed pane
        labels.discard("")
        self.assertEqual(self.EXPECTED_LABELS, labels,
                         f"label set mismatch — got: {labels}")

    def test_labels_track_cell_ids(self):
        """Strongest check: the label↔CELL_ID mapping from the YAML
        survives load. Reads $CELL_ID from each pane's shell env (via the
        env block) and asserts each CELL_ID lines up with its expected
        label per the fixture."""
        self._load()
        # CELL_ID → expected label (from the fixture)
        expected = {
            "110": "Three Renamed",
            "111": "One Renamed",
            "112": "Two Renamed",
        }
        # Build pane_index → pane_id and pane_index → @label maps
        raw = tmux(self.fx.load_sock, "list-panes",
                   "-t", f"{self.SESSION}:nixhome",
                   "-F", "#{pane_index}\t#{pane_id}\t#{@label}",
                   env=self.fx.env).splitlines()
        for line in raw:
            if not line.strip():
                continue
            idx, pid, label = line.split("\t", 2)
            # Read CELL_ID from the pane's process env directly — no
            # shell echo polling, same channel snapshot.py uses on save.
            cell_id = read_cell_id(self.fx.load_sock, pid, env=self.fx.env)
            self.assertTrue(cell_id, f"CELL_ID not readable from {pid}")
            want = expected.get(cell_id)
            self.assertIsNotNone(want,
                                 f"unexpected CELL_ID {cell_id} on {pid}")
            self.assertEqual(want, label,
                             f"pane CELL_ID={cell_id} got label "
                             f"{label!r}, expected {want!r}")

    def test_dump_loaded_session_and_grep_one_renamed(self):
        """Load the fixture, dump the live tmux state to an ASCII file
        under .context/tmuxp-debug/<ISO>-tmuxp-test.txt, then grep that
        file for 'One Renamed'.

        File-mediated check on purpose: same artifact format as
        `task debug:tmuxp` so a failing test leaves a diffable dump on
        disk, and the verification doesn't trust in-memory tmux output —
        only what got written to the file.
        """
        self._load()

        # Dump location: project-root .context/tmuxp-debug/<ISO>-tmuxp-test.txt.
        # Path resolution: this test file is at
        # <root>/home/scripts/tmux/snapshot/test_snapshot.py — climb 4
        # parents to reach <root>.
        project_root = Path(__file__).resolve().parents[4]
        dump_dir = project_root / ".context" / "tmuxp-debug"
        dump_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
        dump_path = dump_dir / f"{stamp}-tmuxp-test.txt"

        # Same per-pane format the `task debug:tmuxp` task uses (30-panes.txt).
        # Window-by-window iteration via window_id (@N) — dotted window
        # names break tmux's `-t session:name` parser, this fixture's
        # `nixhome` is fine but the convention stays consistent.
        lines: list[str] = []
        lines.append(f"# Loaded-session dump for {self.SESSION} at {stamp}")
        lines.append(f"# Source fixture: {FIXTURE_DIR / 'NMD-2026-05-31.yaml'}")
        lines.append("")
        wids = tmux(self.fx.load_sock, "list-windows",
                    "-t", self.SESSION, "-F", "#{window_id}",
                    env=self.fx.env).split()
        for wid in wids:
            wname = tmux(self.fx.load_sock, "display-message", "-p",
                         "-t", wid, "#{window_name}",
                         env=self.fx.env).strip()
            lines.append(f"== {wname} ({wid}) ==")
            panes_raw = tmux(self.fx.load_sock, "list-panes", "-t", wid,
                             "-F", "idx=#{pane_index} id=#{pane_id} "
                                   "top=#{pane_top} left=#{pane_left} "
                                   "label='#{@label}' title='#{pane_title}'",
                             env=self.fx.env)
            lines.append(panes_raw.rstrip())
            layout = tmux(self.fx.load_sock, "display-message", "-p",
                          "-t", wid, "#{window_layout}",
                          env=self.fx.env).strip()
            lines.append(f"layout: {layout}")
            lines.append("")
        dump_path.write_text("\n".join(lines))

        # The verification: read the dump back and grep for the canary.
        content = dump_path.read_text()
        self.assertIn(
            "One Renamed", content,
            f"'One Renamed' missing from {dump_path}\n--- dump ---\n{content}")


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def test_save_all_writes_manifest_with_all_sessions(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "A",
             "-x", "80", "-y", "24")
        tmux(sock, "new-session", "-d", "-s", "B", "-x", "80", "-y", "24")
        tmux(sock, "new-session", "-d", "-s", "C", "-x", "80", "-y", "24")

        snap.save_all(socket=sock, out_dir=self.fx.yaml_dir,
                      manifest=self.fx.yaml_dir / ".session-order")
        manifest = (self.fx.yaml_dir / ".session-order").read_text().splitlines()
        self.assertEqual(set(manifest), {"A", "B", "C"})
        # Each session yaml exists
        for name in ("A", "B", "C"):
            self.assertTrue((self.fx.yaml_dir / f"{name}.yaml").exists())


class BackupTests(unittest.TestCase):
    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)

    def tearDown(self):
        self._td.cleanup()

    def test_backup_creates_tiers_and_rotates(self):
        src = self.work / "S.yaml"
        src.write_text("session_name: S\nwindows: []\n")
        base = self.work / "backups"
        # Burst many backups across days to test rotation
        start = datetime(2026, 1, 1, 12, 0, 0)
        for d in range(0, 20):
            snap.backup("S", src=src, base=base, now=start + timedelta(days=d))
        # daily limit=7
        daily = sorted((base / "daily").glob("S-*.yaml"))
        self.assertLessEqual(len(daily), 7)
        # weekly limit=4
        weekly = sorted((base / "weekly").glob("S-*.yaml"))
        self.assertLessEqual(len(weekly), 4)
        # monthly limit=12 — one per month, only one month in 20 days
        monthly = sorted((base / "monthly").glob("S-*.yaml"))
        self.assertEqual(len(monthly), 1)


class EmptySessionTest(unittest.TestCase):
    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def test_single_pane_session_does_not_crash(self):
        sock = self.fx.sock
        tmux(sock, "-f", "/dev/null", "new-session", "-d", "-s", "rt",
             "-x", "80", "-y", "24")
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        text = target.read_text()
        self.assertIn("session_name: rt", text)
        # Round-trip
        tmux(sock, "kill-server")
        tmuxp_load(self.fx.load_sock, target)
        time.sleep(0.2)
        out = tmux(self.fx.load_sock, "list-sessions",
                   "-F", "#{session_name}").strip()
        self.assertEqual(out, "rt")


class PaneTitleRoundTripTests(unittest.TestCase):
    """Title-based round-trip: more robust than CELL_ID-via-shell.

    Same scenario as MainHorizontalMirroredRoundTripTests.test_reapply_*,
    but identifies panes by `#{pane_title}` (queried directly from tmux)
    instead of shelling into each pane to read `$CELL_ID`.
    """

    PANE_NAMES = ["left", "right", "bottom"]

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def _visual_panes(self, sock: str) -> list:
        raw = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_top} #{pane_left} #{pane_id}",
                   env=self.fx.env).splitlines()
        return sorted(
            (int(t), int(l), pid)
            for t, l, pid in (line.split() for line in raw if line.strip())
        )

    def _titles_in_visual_order(self, sock: str) -> list[str]:
        return [
            tmux(sock, "display-message", "-p", "-t", pid, "#{pane_title}",
                 env=self.fx.env).strip()
            for _, _, pid in self._visual_panes(sock)
        ]

    def _build_three_pane_mirrored(self, sock: str) -> None:
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

    def _build_three_pane_main_horizontal(self, sock: str) -> None:
        """3-pane main-horizontal (NON-mirrored): big main on TOP,
        two small secondaries on the BOTTOM row."""
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        # Split vertically → top, bottom
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        # Split the BOTTOM pane horizontally → top, bottom-left, bottom-right
        bot_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        bot_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in bot_pane if l)[-1][1]
        tmux(sock, "split-window", "-h", "-t", bot_id, env=env)
        # main-pane-height controls the big main strip on top
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "20", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal", env=env)

    def test_titles_survive_save_load_reapply(self):
        sock = self.fx.sock
        env = self.fx.env
        self._build_three_pane_mirrored(sock)

        # Tag panes by visual position with human-readable titles
        for (top, left, pid), name in zip(self._visual_panes(sock),
                                          self.PANE_NAMES):
            tmux(sock, "select-pane", "-t", pid, "-T", name, env=env)

        before_titles = self._titles_in_visual_order(sock)
        self.assertEqual(self.PANE_NAMES, before_titles,
                         "pre-save title tagging did not stick")

        # Snapshot the layout
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        self.assertIn("CELL_TITLE", target.read_text(),
                      "snapshot YAML missing CELL_TITLE entries")

        # Kill + load (load_session re-applies preset + restores titles)
        tmux(sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)

        after_load_titles = self._titles_in_visual_order(self.fx.load_sock)

        # Re-apply the same preset (simulates user pressing `prefix S h`
        # after a fresh load) — the scenario the user suspects scrambles.
        tmux(self.fx.load_sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)

        after_reapply_titles = self._titles_in_visual_order(self.fx.load_sock)

        self.assertEqual(self.PANE_NAMES, after_load_titles,
                         f"titles scrambled after load:\n"
                         f"  expected: {self.PANE_NAMES}\n"
                         f"  got:      {after_load_titles}")
        self.assertEqual(self.PANE_NAMES, after_reapply_titles,
                         f"titles scrambled after re-apply:\n"
                         f"  expected: {self.PANE_NAMES}\n"
                         f"  got:      {after_reapply_titles}")

    def test_main_horizontal_titles_survive_save_load_reapply(self):
        """Non-mirrored variant: main pane on TOP, two secondaries below.

        Visual order (top→bottom, left→right): top, bottom-left, bottom-right.
        After save → kill → load → re-apply `main-horizontal`, the titles
        must land in the SAME visual slots.
        """
        sock = self.fx.sock
        env = self.fx.env
        expected = ["top", "bottom-left", "bottom-right"]
        self._build_three_pane_main_horizontal(sock)

        # Tag panes by visual position
        for (top, left, pid), name in zip(self._visual_panes(sock), expected):
            tmux(sock, "select-pane", "-t", pid, "-T", name, env=env)

        before_titles = self._titles_in_visual_order(sock)
        self.assertEqual(expected, before_titles,
                         "pre-save title tagging did not stick")

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        yaml_text = target.read_text()
        self.assertIn("CELL_TITLE", yaml_text,
                      "snapshot YAML missing CELL_TITLE entries")
        # Confirm the preset is recorded so load_session re-applies it
        self.assertIn("win: main-horizontal", yaml_text,
                      "main-horizontal preset not detected at save time")

        tmux(sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)
        after_load_titles = self._titles_in_visual_order(self.fx.load_sock)

        # Simulate user pressing `prefix S H` (apply main-horizontal again)
        tmux(self.fx.load_sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "20", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "rt:win",
             "main-horizontal", env=env)
        time.sleep(0.2)
        after_reapply_titles = self._titles_in_visual_order(self.fx.load_sock)

        self.assertEqual(expected, after_load_titles,
                         f"titles scrambled after load:\n"
                         f"  expected: {expected}\n"
                         f"  got:      {after_load_titles}")
        self.assertEqual(expected, after_reapply_titles,
                         f"titles scrambled after re-apply:\n"
                         f"  expected: {expected}\n"
                         f"  got:      {after_reapply_titles}")


class PaneLabelRoundTripTests(unittest.TestCase):
    """Label-based round-trip — @label is the user-set name from the
    "Rename Pane" menu (`prefix > n` in tmux.nix), stored as a pane-scoped
    user option (`set -p @label "..."`). Distinct from `pane_title` which
    is the OSC/terminal-title channel that `PaneTitleRoundTripTests` covers.

    Canary mapping mirrors the live debug state captured under
    `.context/tmuxp-debug/2026-05-30T06-40-36Z-NMD-live-post-save-with-labels.txt`:

        pane_index 0 (bottom / main)  → label "Three Renamed"
        pane_index 1 (top-left)       → label "One Renamed"
        pane_index 2 (top-right)      → label "Two Renamed"

    The deliberate idx↔label scramble (One≠0, Two≠2 in visual order)
    means any pane-ordering regression — at save, at load, or after
    `prefix S h` re-apply — surfaces as a wrong label in the wrong slot.

    Multi-word labels with embedded spaces exercise the YAML quoting
    round-trip (the values are single-quoted in CELL_LABEL emit).
    """

    # Visual-order expected: (top-left, top-right, bottom) for mirrored.
    EXPECTED_VISUAL_MIRRORED = ["One Renamed", "Two Renamed", "Three Renamed"]
    # pane_index → label assignment
    LABELS_BY_INDEX = {0: "Three Renamed", 1: "One Renamed", 2: "Two Renamed"}

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def _visual_panes(self, sock: str) -> list:
        raw = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_top} #{pane_left} #{pane_id}",
                   env=self.fx.env).splitlines()
        return sorted(
            (int(t), int(l), pid)
            for t, l, pid in (line.split() for line in raw if line.strip())
        )

    def _labels_in_visual_order(self, sock: str) -> list[str]:
        return [
            tmux(sock, "display-message", "-p", "-t", pid, "#{@label}",
                 env=self.fx.env).strip()
            for _, _, pid in self._visual_panes(sock)
        ]

    def _indexed_panes(self, sock: str) -> list[tuple[int, str]]:
        """Returns [(pane_index, pane_id), ...] sorted by pane_index."""
        raw = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_index} #{pane_id}",
                   env=self.fx.env).splitlines()
        items = []
        for line in raw:
            if not line.strip():
                continue
            idx, pid = line.split()
            items.append((int(idx), pid))
        items.sort(key=lambda x: x[0])
        return items

    def _apply_canary_labels(self, sock: str) -> None:
        """Set @label per pane_index using the LABELS_BY_INDEX canary.

        Uses the EXACT command the "Rename Pane" menu binding runs
        (`set -p @label "..."`) — NOT `select-pane -T` — so we exercise
        the same code path the user does.
        """
        env = self.fx.env
        # pane_index in tmux is 0-based or 1-based depending on base-index;
        # the fixture defaults to 0-based, so LABELS_BY_INDEX keys match.
        idx_to_pid = dict(self._indexed_panes(sock))
        for idx, label in self.LABELS_BY_INDEX.items():
            pid = idx_to_pid.get(idx)
            self.assertIsNotNone(
                pid, f"no pane at pane_index={idx} — fixture mismatch")
            tmux(sock, "set-option", "-p", "-t", pid, "@label", label, env=env)

    def _build_three_pane_mirrored(self, sock: str) -> None:
        """3-pane main-horizontal-mirrored: main on BOTTOM, two on top."""
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

    def test_save_emits_cell_label(self):
        """Save side: snapshot YAML must contain CELL_LABEL entries for
        each labeled pane. Direct inverse of the regression the live debug
        captured (5055-byte YAML, 0 label hits, all panes labeled live)."""
        sock = self.fx.sock
        self._build_three_pane_mirrored(sock)
        self._apply_canary_labels(sock)

        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        yaml_text = target.read_text()

        # All three canary labels must appear, single-quoted (spaces inside)
        for label in self.LABELS_BY_INDEX.values():
            self.assertIn(f"CELL_LABEL: '{label}'", yaml_text,
                          f"label {label!r} missing from saved YAML")

    def test_labels_survive_save_load_reapply(self):
        """Full round-trip: save → kill → load → re-apply preset.
        After each step, the three canary labels must occupy the same
        VISUAL slots as before save."""
        sock = self.fx.sock
        env = self.fx.env
        self._build_three_pane_mirrored(sock)
        self._apply_canary_labels(sock)

        before = self._labels_in_visual_order(sock)
        self.assertEqual(self.EXPECTED_VISUAL_MIRRORED, before,
                         "pre-save canary labels did not land as expected")

        # Save
        target = snap.save_session("rt", socket=sock, out_dir=self.fx.yaml_dir)
        self.assertIn("CELL_LABEL", target.read_text(),
                      "snapshot YAML missing CELL_LABEL entries")

        # Kill + load (load_session re-applies preset + restores titles + labels)
        tmux(sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)
        after_load = self._labels_in_visual_order(self.fx.load_sock)

        # Re-apply the preset (simulates user pressing `prefix S h`).
        tmux(self.fx.load_sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)
        after_reapply = self._labels_in_visual_order(self.fx.load_sock)

        self.assertEqual(self.EXPECTED_VISUAL_MIRRORED, after_load,
                         f"labels scrambled after load:\n"
                         f"  expected: {self.EXPECTED_VISUAL_MIRRORED}\n"
                         f"  got:      {after_load}")
        self.assertEqual(self.EXPECTED_VISUAL_MIRRORED, after_reapply,
                         f"labels scrambled after re-apply:\n"
                         f"  expected: {self.EXPECTED_VISUAL_MIRRORED}\n"
                         f"  got:      {after_reapply}")


class CellIdStabilityTests(unittest.TestCase):
    """Regression: CELL_IDs in saved YAML must be stable across consecutive
    saves of the same continuously-alive session — including saves
    separated by a preset-layout re-apply.

    Lineage observed in .context/tmuxp-debug/NMD-*.yml:
        T1 (14:15, applied-layout-and-saved):       CELL_IDs 816..838
        T2 (14:19, snapshot-loaded-and-existing):   CELL_IDs 816..838  (stable)
        T3 (14:20, layout-applied-snapshot-saved):  CELL_IDs 850..872  (all changed)

    Cell-IDs are `pane_id.lstrip('%')` (see snapshot.Pane.cell_id), so any
    change in CELL_ID across saves means tmux destroyed/recreated panes.
    `select-layout` is documented as geometry-only; CELL_IDs MUST survive it.
    """

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    @staticmethod
    def _cell_ids(yaml_text: str) -> list[str]:
        return re.findall(r"CELL_ID:\s*'(\d+)'", yaml_text)

    def _snapshot_copy(self, label: str) -> tuple[Path, str]:
        """Save the session and copy YAML aside (save_session overwrites)."""
        target = snap.save_session("rt", socket=self.fx.sock,
                                   out_dir=self.fx.yaml_dir)
        text = target.read_text()
        aside = self.work / f"snap-{label}.yaml"
        aside.write_text(text)
        return aside, text

    def _build_mirrored_session(self) -> None:
        """3-pane main-horizontal-mirrored on `rt:win`."""
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

    def test_cell_ids_stable_across_consecutive_no_op_saves(self):
        """Two back-to-back saves of an idle session: CELL_IDs identical."""
        self._build_mirrored_session()

        _, text_a = self._snapshot_copy("A")
        _, text_b = self._snapshot_copy("B")

        ids_a = self._cell_ids(text_a)
        ids_b = self._cell_ids(text_b)
        self.assertEqual(ids_a, ids_b,
                         f"CELL_IDs changed between two no-op saves:\n"
                         f"  A: {ids_a}\n  B: {ids_b}")
        self.assertEqual(len(ids_a), 3, f"expected 3 CELL_IDs, got {ids_a}")

    def test_cell_ids_stable_across_preset_layout_reapply(self):
        """Re-applying `main-horizontal-mirrored` between saves must not
        change CELL_IDs — `select-layout` is a geometry-only op.

        This is the lineage T2→T3 from the debug YAMLs: same session,
        layout re-applied between saves, all 23 CELL_IDs shifted by +34.
        """
        sock = self.fx.sock
        env = self.fx.env
        self._build_mirrored_session()

        _, text_a = self._snapshot_copy("A")

        # Re-apply the same preset. Geometry-only — pane identity must hold.
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.1)

        _, text_b = self._snapshot_copy("B")

        # And once more, to catch any drift that only shows after 2+ re-applies.
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.1)
        _, text_c = self._snapshot_copy("C")

        ids_a = self._cell_ids(text_a)
        ids_b = self._cell_ids(text_b)
        ids_c = self._cell_ids(text_c)

        self.assertEqual(ids_a, ids_b,
                         f"CELL_IDs changed across a single preset re-apply:\n"
                         f"  before: {ids_a}\n  after:  {ids_b}\n"
                         f"  delta:  {[int(b) - int(a) for a, b in zip(ids_a, ids_b)]}")
        self.assertEqual(ids_a, ids_c,
                         f"CELL_IDs drifted across two preset re-applies:\n"
                         f"  T0: {ids_a}\n  T2: {ids_c}")

    def test_cell_ids_stable_across_multi_window_lineage(self):
        """Mirrors the NMD debug lineage: multiple windows, each with a
        canonical mirrored layout. Save → re-apply each window's preset
        → save. CELL_IDs must be identical across the two saves.

        Catches the regression where re-applying the layout to several
        windows in sequence (as `snap.load_session` does post-load)
        re-creates panes and shifts every CELL_ID by a constant offset.
        """
        sock = self.fx.sock
        env = self.fx.env

        windows = ["pve", "omv", "play"]
        # Build first window via new-session, then new-window for the rest.
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", windows[0], env=env)
        for wname in windows[1:]:
            tmux(sock, "new-window", "-t", "rt:", "-n", wname, env=env)

        # Give each window a 3-pane mirrored layout.
        for wname in windows:
            target_win = f"rt:{wname}"
            tmux(sock, "split-window", "-v", "-t", target_win, env=env)
            top_pane = tmux(sock, "list-panes", "-t", target_win,
                            "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
            top_id = sorted((int(l.split()[0]), l.split()[1])
                            for l in top_pane if l)[0][1]
            tmux(sock, "split-window", "-h", "-t", top_id, env=env)
            tmux(sock, "set-window-option", "-t", target_win,
                 "main-pane-height", "2", env=env)
            tmux(sock, "select-layout", "-t", target_win,
                 "main-horizontal-mirrored", env=env)

        _, text_a = self._snapshot_copy("A")

        # Re-apply preset on every window — same op `snap.load_session`
        # performs after tmuxp finishes loading.
        for wname in windows:
            tmux(sock, "select-layout", "-t", f"rt:{wname}",
                 "main-horizontal-mirrored", env=env)
        time.sleep(0.1)

        _, text_b = self._snapshot_copy("B")

        ids_a = self._cell_ids(text_a)
        ids_b = self._cell_ids(text_b)
        self.assertEqual(len(ids_a), 9,
                         f"expected 9 CELL_IDs (3 windows × 3 panes): {ids_a}")
        self.assertEqual(ids_a, ids_b,
                         f"multi-window lineage lost CELL_ID stability:\n"
                         f"  before: {ids_a}\n  after:  {ids_b}\n"
                         f"  deltas: {[int(b) - int(a) for a, b in zip(ids_a, ids_b)]}")


class CellIdLoadLineageTests(unittest.TestCase):
    """CELL_IDs must be sticky to a pane across snapshot reloads.

    The pane's running process is the "cell" — software that re-execs
    itself (or that the user re-runs) needs a stable identifier across
    tmuxp reloads so it can recognise it's continuing a previous cell.

    Today CELL_ID is derived from tmux's live `%pane_id`, which is
    re-minted by tmux every time tmuxp creates a fresh pane. So the
    saved YAML's CELL_ID drifts on every reload.

    These tests pin the contract: a single CELL_ID per pane, persistent
    across an arbitrary number of save → reload → save cycles.
    """

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)
        # Extra sockets so we can do multi-hop reloads (each tmuxp load
        # needs its own server to mimic real reload semantics).
        self.sock_b = str(self.work / "sock_b")
        self.sock_c = str(self.work / "sock_c")

    def tearDown(self):
        for s in (self.sock_b, self.sock_c):
            subprocess.run(["tmux", "-S", s, "kill-server"],
                           capture_output=True)
        self.fx.kill_all()
        self._td.cleanup()

    @staticmethod
    def _cell_ids(yaml_text: str) -> list[str]:
        return re.findall(r"CELL_ID:\s*'(\d+)'", yaml_text)

    def _save_to(self, sock: str, dest: Path) -> str:
        """Save session 'rt' on `sock` and copy the YAML to `dest`."""
        out_dir = dest.parent / f"yaml-{dest.stem}"
        out_dir.mkdir(exist_ok=True)
        target = snap.save_session("rt", socket=sock, out_dir=out_dir)
        text = target.read_text()
        dest.write_text(text)
        return text

    def _build_session(self, sock: str) -> None:
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

    def test_cell_ids_survive_primary_reload(self):
        """One reload: build → save → reload elsewhere → save.
        Both saves must agree on CELL_IDs.
        """
        env = self.fx.env
        self._build_session(self.fx.sock)

        yaml0 = self.work / "rt-0.yaml"
        text0 = self._save_to(self.fx.sock, yaml0)
        ids0 = self._cell_ids(text0)
        self.assertEqual(len(ids0), 3, ids0)

        tmux(self.fx.sock, "kill-server", env=env, check=False)
        snap.load_session(yaml0, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)

        yaml1 = self.work / "rt-1.yaml"
        text1 = self._save_to(self.fx.load_sock, yaml1)
        ids1 = self._cell_ids(text1)

        self.assertEqual(ids0, ids1,
                         f"CELL_IDs drifted across one reload:\n"
                         f"  pre-reload:  {ids0}\n"
                         f"  post-reload: {ids1}")

    def test_cell_ids_survive_secondary_reload(self):
        """Two reloads. CELL_IDs must equal the original across both."""
        env = self.fx.env
        self._build_session(self.fx.sock)

        yaml0 = self.work / "rt-0.yaml"
        text0 = self._save_to(self.fx.sock, yaml0)
        ids0 = self._cell_ids(text0)

        tmux(self.fx.sock, "kill-server", env=env, check=False)
        snap.load_session(yaml0, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)
        yaml1 = self.work / "rt-1.yaml"
        text1 = self._save_to(self.fx.load_sock, yaml1)
        ids1 = self._cell_ids(text1)

        tmux(self.fx.load_sock, "kill-server", env=env, check=False)
        snap.load_session(yaml1, socket=self.sock_b, env=env)
        time.sleep(0.6)
        yaml2 = self.work / "rt-2.yaml"
        text2 = self._save_to(self.sock_b, yaml2)
        ids2 = self._cell_ids(text2)

        self.assertEqual(ids0, ids1, "drifted on first reload")
        self.assertEqual(ids0, ids2,
                         f"drifted on second reload:\n"
                         f"  original: {ids0}\n"
                         f"  reload#2: {ids2}")

    def test_cell_ids_survive_tertiary_reload(self):
        """Three reloads. CELL_IDs must equal the original across all."""
        env = self.fx.env
        self._build_session(self.fx.sock)

        yaml0 = self.work / "rt-0.yaml"
        text0 = self._save_to(self.fx.sock, yaml0)
        ids0 = self._cell_ids(text0)

        sockets = [self.fx.sock, self.fx.load_sock, self.sock_b, self.sock_c]
        yamls = [yaml0]
        all_ids = [ids0]
        for hop in range(3):
            tmux(sockets[hop], "kill-server", env=env, check=False)
            snap.load_session(yamls[-1], socket=sockets[hop + 1], env=env)
            time.sleep(0.6)
            y = self.work / f"rt-{hop + 1}.yaml"
            text = self._save_to(sockets[hop + 1], y)
            yamls.append(y)
            all_ids.append(self._cell_ids(text))

        for hop, ids in enumerate(all_ids):
            self.assertEqual(ids0, ids,
                             f"CELL_IDs drifted at hop {hop}:\n"
                             f"  original (hop 0): {ids0}\n"
                             f"  hop {hop}:        {ids}")


class CellIdFollowsPaneTests(unittest.TestCase):
    """CELL_ID must follow the pane process, not the visual slot.

    If the user (or a layout op) moves a pane to a different position,
    the CELL_ID at the NEW position is the moved pane's original ID —
    not a fresh one and not the previous occupant's ID.
    """

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    @staticmethod
    def _cell_id_for_pane(yaml_text: str, pane_index: int) -> str:
        """Pull the CELL_ID of the Nth pane in YAML order (per first
        `panes:` block — first window only, single-window tests)."""
        ids = re.findall(r"CELL_ID:\s*'(\d+)'", yaml_text)
        return ids[pane_index]

    def _save(self, sock: str, label: str) -> str:
        out_dir = self.work / f"yaml-{label}"
        out_dir.mkdir(exist_ok=True)
        return snap.save_session("rt", socket=sock, out_dir=out_dir).read_text()

    def _build_3pane_mirrored(self, sock: str) -> None:
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "rt",
             "-x", "200", "-y", "48", "-n", "win", env=env)
        tmux(sock, "split-window", "-v", "-t", "rt:win", env=env)
        top_pane = tmux(sock, "list-panes", "-t", "rt:win",
                        "-F", "#{pane_top} #{pane_id}", env=env).splitlines()
        top_id = sorted((int(l.split()[0]), l.split()[1])
                        for l in top_pane if l)[0][1]
        tmux(sock, "split-window", "-h", "-t", top_id, env=env)
        tmux(sock, "set-window-option", "-t", "rt:win",
             "main-pane-height", "2", env=env)
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)

    def _build_3pane_mirrored_loaded(self) -> str:
        """Build, save, reload — so panes have *persistent* CELL_IDs
        (set via tmuxp's environment block). Returns the load socket.
        Tests use the loaded session to prove CELL_IDs follow panes,
        not just freshly-minted-from-pane_id values that would coincidentally
        survive every op.
        """
        env = self.fx.env
        self._build_3pane_mirrored(self.fx.sock)
        target = snap.save_session("rt", socket=self.fx.sock,
                                   out_dir=self.fx.yaml_dir)
        tmux(self.fx.sock, "kill-server", env=env, check=False)
        snap.load_session(target, socket=self.fx.load_sock, env=env)
        time.sleep(0.6)
        return self.fx.load_sock

    def _panes_by_position(self, sock: str) -> list[tuple[int, int, str]]:
        """[(top, left, pane_id), ...] sorted by visual position."""
        env = self.fx.env
        raw = tmux(sock, "list-panes", "-t", "rt:win",
                   "-F", "#{pane_top} #{pane_left} #{pane_id}",
                   env=env).splitlines()
        return sorted((int(t), int(l), pid)
                      for t, l, pid in (ln.split() for ln in raw if ln.strip()))

    def _save_and_map(self, sock: str, label: str) -> dict[str, str]:
        """Save, then return {pane_id: CELL_ID} read directly from live tmux."""
        # Save (writes YAML) but we don't need it; read CELL_IDs from the
        # live session via snap.query_session, which is what save_session
        # uses internally — this avoids YAML order coupling.
        self._save(sock, label)
        sess = snap.query_session("rt", socket=sock)
        out: dict[str, str] = {}
        for w in sess.windows:
            for p in w.panes:
                out[p.pane_id] = p.cell_id
        return out

    def test_cell_id_follows_pane_through_swap(self):
        """`tmux swap-pane` reorders panes; CELL_IDs must travel with
        the pane process, not stay at the visual position."""
        sock = self._build_3pane_mirrored_loaded()
        env = self.fx.env

        before = self._panes_by_position(sock)
        # Take pane_ids at top-left (index 0) and bottom (index 2)
        tl_pid_before = before[0][2]
        bot_pid_before = before[2][2]

        before_map = self._save_and_map(sock, "pre")
        tl_cell_before = before_map[tl_pid_before]
        bot_cell_before = before_map[bot_pid_before]
        self.assertNotEqual(tl_cell_before, bot_cell_before, "sanity")

        # Swap top-left with bottom.
        tmux(sock, "swap-pane", "-s", tl_pid_before, "-t", bot_pid_before,
             env=env)
        time.sleep(0.1)

        after_map = self._save_and_map(sock, "post")
        # Same pane_ids exist (swap doesn't destroy/create), and each
        # carries the same CELL_ID it had before — the pane process is
        # unchanged, only its visual slot moved.
        self.assertEqual(before_map, after_map,
                         f"CELL_IDs changed across swap-pane:\n"
                         f"  before: {before_map}\n"
                         f"  after:  {after_map}")

        # And the CELL_ID at the visual top-left slot is now the one
        # that moved there — not the slot's old value.
        after = self._panes_by_position(sock)
        tl_pid_after = after[0][2]
        self.assertEqual(tl_pid_after, bot_pid_before,
                         "swap didn't put bottom pane at top-left")
        self.assertEqual(after_map[tl_pid_after], bot_cell_before,
                         "CELL_ID at top-left should now be the swapped-in "
                         "pane's original CELL_ID")

    def test_cell_id_follows_pane_through_layout_reapply(self):
        """Re-applying a preset layout (geometry op only) must not
        renumber CELL_IDs on a session that already has persistent ones
        (post-reload state)."""
        sock = self._build_3pane_mirrored_loaded()
        env = self.fx.env

        before = self._save_and_map(sock, "pre")

        # Re-apply preset (the `prefix S h` action).
        tmux(sock, "select-layout", "-t", "rt:win",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.1)
        # And rotate panes (another geometry op).
        tmux(sock, "rotate-window", "-t", "rt:win", env=env)
        time.sleep(0.1)

        after = self._save_and_map(sock, "post")
        self.assertEqual(before, after,
                         f"CELL_IDs changed across layout reapply + rotate:\n"
                         f"  before: {before}\n  after:  {after}")

    def test_cell_id_follows_pane_through_resize(self):
        """`resize-pane` is geometry only — never affects CELL_ID."""
        sock = self._build_3pane_mirrored_loaded()
        env = self.fx.env

        before = self._save_and_map(sock, "pre")

        # Pick the bottom pane (largest in mirrored layout) and shrink it.
        bot_pid = self._panes_by_position(sock)[2][2]
        tmux(sock, "resize-pane", "-t", bot_pid, "-y", "10", env=env)
        time.sleep(0.1)

        after = self._save_and_map(sock, "post")
        self.assertEqual(before, after,
                         f"CELL_IDs changed across resize-pane:\n"
                         f"  before: {before}\n  after:  {after}")


class ReadPaneEnvContractTests(unittest.TestCase):
    """`_read_pane_env` must read an env var from a known child process on
    whatever platform the tests run on. No tmux, no tmuxp — this isolates
    the OS bridge from the rest of the pipeline.

    On macOS the implementation falls back to `ps -E`, which is restricted
    by hardened-runtime / sandbox in many setups. These tests pin the
    contract so a regression there can't hide behind tmux fixtures.
    """

    SENTINEL = "contract_xyz_42"

    def _spawn_child_with_cell_id(self, value: str) -> subprocess.Popen:
        proc = subprocess.Popen(
            ["sleep", "60"],
            env={**os.environ, "CELL_ID": value},
        )
        time.sleep(0.1)  # let exec complete so initial environ is settled
        return proc

    def test_reads_cell_id_from_own_child_initial_environ(self):
        """Platform-native path — uses /proc on Linux, `ps -E` on macOS.
        REDs on macOS today; GREEN on Linux."""
        proc = self._spawn_child_with_cell_id(self.SENTINEL)
        try:
            got = snap._read_pane_env(str(proc.pid), "CELL_ID")
            self.assertEqual(
                got, self.SENTINEL,
                f"_read_pane_env returned {got!r} for pid {proc.pid}; "
                f"platform fallback (/proc or ps -E) is broken",
            )
        finally:
            proc.kill(); proc.wait()

    @unittest.skipUnless(
        shutil.which("ps"), "ps not available")
    def test_reads_cell_id_via_ps_fallback(self):
        """Force the BSD/macOS `ps -E` branch even on Linux so CI catches
        regressions in the non-/proc code path without a Mac runner."""
        # Probe: does `ps -E` actually surface env on this host? If the
        # platform itself doesn't expose env via ps, skip — we'd be
        # testing the OS, not our code.
        probe = self._spawn_child_with_cell_id("probe_value")
        try:
            try:
                out = subprocess.run(
                    ["ps", "-E", "-ww", "-o", "command=", "-p", str(probe.pid)],
                    capture_output=True, text=True, check=True,
                ).stdout
            except subprocess.CalledProcessError:
                self.skipTest("`ps -E` not supported on this host")
            if "CELL_ID=probe_value" not in out:
                self.skipTest(
                    "`ps -E` does not expose process env on this host "
                    "(hardened runtime / sandbox / SIP)")
        finally:
            probe.kill(); probe.wait()

        proc = self._spawn_child_with_cell_id(self.SENTINEL)
        try:
            # Force the ps branch by making /proc/<pid>/environ "not exist".
            real_exists = Path.exists
            def fake_exists(self):
                if str(self).startswith("/proc/") and str(self).endswith("/environ"):
                    return False
                return real_exists(self)
            with mock.patch.object(Path, "exists", fake_exists):
                got = snap._read_pane_env(str(proc.pid), "CELL_ID")
            self.assertEqual(
                got, self.SENTINEL,
                "ps -E fallback failed to read CELL_ID from own child",
            )
        finally:
            proc.kill(); proc.wait()


class MultiLoadTests(unittest.TestCase):
    """Feature: `tmux-snapshot load A B C` loads multiple sessions sequentially."""

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def test_load_multiple_sessions_by_name(self):
        """tmux-snapshot load A B C creates all three sessions."""
        sock = self.fx.sock
        env = self.fx.env
        names = ["alpha", "bravo", "charlie"]
        for i, name in enumerate(names):
            tmux(sock, "new-session", "-d", "-s", name,
                 "-x", "80", "-y", "24", "-n", f"win{i}", env=env)
        for name in names:
            snap.save_session(name, socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        snap.load_session(self.fx.yaml_dir / "alpha.yaml",
                          socket=self.fx.load_sock, env=env)
        snap.load_session(self.fx.yaml_dir / "bravo.yaml",
                          socket=self.fx.load_sock, env=env)
        snap.load_session(self.fx.yaml_dir / "charlie.yaml",
                          socket=self.fx.load_sock, env=env)
        time.sleep(0.3)

        sessions = sorted(tmux(self.fx.load_sock, "list-sessions",
                               "-F", "#{session_name}", env=env).split())
        self.assertEqual(sorted(names), sessions)

    def test_cli_load_accepts_multiple_names(self):
        """CLI: `tmux-snapshot load A B C` loads all three sessions."""
        sock = self.fx.sock
        env = self.fx.env
        names = ["ses1", "ses2", "ses3"]
        for name in names:
            tmux(sock, "new-session", "-d", "-s", name,
                 "-x", "80", "-y", "24", env=env)
        for name in names:
            snap.save_session(name, socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        rc = snap.main(["-S", self.fx.load_sock,
                        "-o", str(self.fx.yaml_dir),
                        "load"] + names)
        self.assertEqual(rc, 0)
        time.sleep(0.3)

        sessions = sorted(tmux(self.fx.load_sock, "list-sessions",
                               "-F", "#{session_name}", env=env).split())
        self.assertEqual(sorted(names), sessions)

    def test_cli_load_single_name_still_works(self):
        """Backward compat: `tmux-snapshot load A` still works."""
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "only",
             "-x", "80", "-y", "24", env=env)
        snap.save_session("only", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        rc = snap.main(["-S", self.fx.load_sock,
                        "-o", str(self.fx.yaml_dir),
                        "load", "only"])
        self.assertEqual(rc, 0)
        time.sleep(0.3)
        out = tmux(self.fx.load_sock, "list-sessions",
                   "-F", "#{session_name}", env=env).strip()
        self.assertEqual(out, "only")

    def test_cli_load_reports_each_session(self):
        """CLI should print [OK] for each loaded session."""
        sock = self.fx.sock
        env = self.fx.env
        for name in ["x", "y"]:
            tmux(sock, "new-session", "-d", "-s", name,
                 "-x", "80", "-y", "24", env=env)
            snap.save_session(name, socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            snap.main(["-S", self.fx.load_sock,
                       "-o", str(self.fx.yaml_dir),
                       "load", "x", "y"])
        output = buf.getvalue()
        self.assertIn("[OK] loaded x.yaml", output)
        self.assertIn("[OK] loaded y.yaml", output)


class ListSnapshotsTests(unittest.TestCase):
    """Feature: `tmux-snapshot list` shows session names with window info."""

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.yaml_dir = self.work / "tmuxp"
        self.yaml_dir.mkdir()

    def tearDown(self):
        self._td.cleanup()

    def _write_yaml(self, name: str, window_names: list[str]) -> None:
        lines = [f"session_name: {name}", "windows:"]
        for wn in window_names:
            lines.append(f"  - window_name: {wn}")
            lines.append("    layout: abcd,80x24,0,0,0")
            lines.append("    options: {}")
            lines.append("    panes:")
            lines.append("    - shell_command: zsh")
            lines.append("      environment:")
            lines.append("        CELL_ID: '1'")
        (self.yaml_dir / f"{name}.yaml").write_text("\n".join(lines) + "\n")

    def test_list_snapshots_returns_structured_data(self):
        """list_snapshots() returns session info with window names."""
        self._write_yaml("NMD", ["mc", "pve", "home"])
        self._write_yaml("DIMM", ["dev", "logs"])
        result = snap.list_snapshots(self.yaml_dir)
        self.assertEqual(len(result), 2)
        by_name = {r["name"]: r for r in result}
        self.assertEqual(by_name["NMD"]["window_count"], 3)
        self.assertEqual(by_name["NMD"]["window_names"], ["mc", "pve", "home"])
        self.assertEqual(by_name["DIMM"]["window_count"], 2)
        self.assertEqual(by_name["DIMM"]["window_names"], ["dev", "logs"])

    def test_list_snapshots_empty_dir(self):
        result = snap.list_snapshots(self.yaml_dir)
        self.assertEqual(result, [])

    def test_list_snapshots_sorted_alphabetically(self):
        self._write_yaml("ZZZ", ["w1"])
        self._write_yaml("AAA", ["w1"])
        self._write_yaml("MMM", ["w1"])
        result = snap.list_snapshots(self.yaml_dir)
        names = [r["name"] for r in result]
        self.assertEqual(names, ["AAA", "MMM", "ZZZ"])

    def test_cli_list_outputs_formatted_lines(self):
        """CLI: `tmux-snapshot list` outputs tab-separated lines."""
        self._write_yaml("NMD", ["mc", "pve", "home"])
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = snap.main(["-o", str(self.yaml_dir), "list"])
        self.assertEqual(rc, 0)
        output = buf.getvalue()
        self.assertIn("NMD", output)
        self.assertIn("3", output)

    def test_cli_list_with_ansi_flag(self):
        """CLI: `tmux-snapshot list --ansi` outputs ANSI-colored tags."""
        self._write_yaml("S1", ["alpha", "beta"])
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = snap.main(["-o", str(self.yaml_dir), "list", "--ansi"])
        self.assertEqual(rc, 0)
        output = buf.getvalue()
        self.assertIn("\033[", output)
        self.assertIn("alpha", output)
        self.assertIn("beta", output)

    def test_list_skips_non_yaml_files(self):
        """Non-.yaml files in the directory are ignored."""
        self._write_yaml("good", ["w1"])
        (self.yaml_dir / ".session-order").write_text("good\n")
        (self.yaml_dir / "notes.txt").write_text("not a yaml\n")
        result = snap.list_snapshots(self.yaml_dir)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["name"], "good")

    def test_list_handles_quoted_window_names(self):
        """Window names with special chars are properly parsed."""
        self._write_yaml("test", ["nmd.gg", "k3s"])
        result = snap.list_snapshots(self.yaml_dir)
        self.assertEqual(result[0]["window_names"], ["nmd.gg", "k3s"])


class PickerIntegrationTests(unittest.TestCase):
    """Integration: simulate the prefix+T picker flow end-to-end."""

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def test_list_then_load_round_trip(self):
        """list → pick first line → extract name → load succeeds."""
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "project",
             "-x", "80", "-y", "24", "-n", "editor", env=env)
        tmux(sock, "new-window", "-t", "project", "-n", "logs", env=env)
        snap.save_session("project", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-server", env=env, check=False)

        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            snap.main(["-o", str(self.fx.yaml_dir), "list", "--ansi"])
        lines = buf.getvalue().strip().splitlines()
        self.assertEqual(len(lines), 1)

        line = lines[0]
        parts = line.split("\t")
        self.assertEqual(parts[0], "project")
        self.assertEqual(parts[1], "2")
        self.assertIn("editor", parts[2])
        self.assertIn("logs", parts[2])
        self.assertIn("\033[48;2;68;71;90;38;2;189;193;215m", parts[2])

        name = parts[0]
        rc = snap.main(["-S", self.fx.load_sock,
                        "-o", str(self.fx.yaml_dir),
                        "load", name])
        self.assertEqual(rc, 0)
        time.sleep(0.3)
        sessions = tmux(self.fx.load_sock, "list-sessions",
                        "-F", "#{session_name}", env=env).strip()
        self.assertEqual(sessions, "project")

    def test_delete_extracts_name_from_tabbed_line(self):
        """Simulates what snapshotDelete does: cut -f1 | sed strip marker."""
        import subprocess
        line = "● NMD\t9\t\033[48;2;68;71;90;38;2;189;193;215m mc \033[0m"
        result = subprocess.run(
            ["sh", "-c", "cut -f1 | sed 's/^[● ]*//'"],
            input=line, capture_output=True, text=True
        )
        self.assertEqual(result.stdout.strip(), "NMD")

    def test_delete_extracts_name_without_marker(self):
        """cut+sed on a non-live session (no marker) still works."""
        import subprocess
        line = "  DIMM\t3\ttags"
        result = subprocess.run(
            ["sh", "-c", "cut -f1 | sed 's/^[● ]*//'"],
            input=line, capture_output=True, text=True
        )
        self.assertEqual(result.stdout.strip(), "DIMM")


class MarkLiveTests(unittest.TestCase):
    """Feature: `tmux-snapshot list --mark-live` marks active sessions."""

    def setUp(self):
        self._td = TemporaryDirectory()
        self.work = Path(self._td.name)
        self.fx = TmuxFixture(self.work)

    def tearDown(self):
        self.fx.kill_all()
        self._td.cleanup()

    def test_live_session_gets_marker(self):
        """A session that's running in tmux gets the ● prefix."""
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "alive",
             "-x", "80", "-y", "24", env=env)
        tmux(sock, "new-session", "-d", "-s", "other",
             "-x", "80", "-y", "24", env=env)
        snap.save_session("alive", socket=sock, out_dir=self.fx.yaml_dir)
        snap.save_session("other", socket=sock, out_dir=self.fx.yaml_dir)
        tmux(sock, "kill-session", "-t", "other", env=env)

        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            snap.main(["-S", sock, "-o", str(self.fx.yaml_dir),
                       "list", "--mark-live"])
        output = buf.getvalue()
        lines = {l.split("\t")[0]: l for l in output.strip().splitlines()}
        self.assertTrue(lines["● alive"].startswith("● alive"))
        self.assertTrue(lines["  other"].startswith("  other"))

    def test_no_mark_live_flag_omits_markers(self):
        """Without --mark-live, no markers are prepended."""
        sock = self.fx.sock
        env = self.fx.env
        tmux(sock, "new-session", "-d", "-s", "test",
             "-x", "80", "-y", "24", env=env)
        snap.save_session("test", socket=sock, out_dir=self.fx.yaml_dir)

        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            snap.main(["-S", sock, "-o", str(self.fx.yaml_dir), "list"])
        output = buf.getvalue()
        self.assertTrue(output.startswith("test\t"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

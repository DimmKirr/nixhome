"""
End-to-end tests for tmux-snapshot.

Runs against real tmux + real tmuxp on isolated sockets. No mocks.
Each test starts/kills its own tmux server so they're parallel-safe.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory

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
        """Send `echo @@$CELL_ID@@` and parse the value from the pane buffer."""
        tmux(sock, "send-keys", "-t", pane_id,
             'printf "@@%s@@\\n" "$CELL_ID"', "Enter", env=env)
        for _ in range(40):
            time.sleep(0.05)
            buf = tmux(sock, "capture-pane", "-t", pane_id, "-p", env=env)
            m = re.search(r"@@(\w*)@@", buf)
            if m and m.group(1):  # non-empty match (i.e. CELL_ID was set)
                return m.group(1)
        raise AssertionError(
            f"timed out reading CELL_ID from pane {pane_id}; buffer:\n{buf}")


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
        tmuxp_load(self.fx.load_sock, yaml_path, env=self.fx.env)
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
        tmux(self.fx.load_sock, "send-keys", "-t", pane_id,
             'printf "@@%s@@\\n" "$CELL_ID"', "Enter", env=self.fx.env)
        for _ in range(60):
            time.sleep(0.05)
            buf = tmux(self.fx.load_sock, "capture-pane", "-t", pane_id, "-p",
                       env=self.fx.env)
            m = re.search(r"@@(\w+)@@", buf)
            if m:
                return m.group(1)
        raise AssertionError(f"CELL_ID not readable from {pane_id}")

    def test_as_saved_yaml_loads_with_correct_visual_order(self):
        """Sanity: the saved fixture round-trips visually correctly.

        nixhome window has mirrored shape: top-left (CELL_ID 111),
        top-right (112), bottom strip (110). YAML emit was visual order
        so YAML[0]=111, [1]=112, [2]=110. tmuxp maps YAML[i]→layout DFS
        leaf[i], which equals visual order, so the load should look right.
        """
        self._load(FIXTURE_DIR / "NMD-saved.yaml")
        panes = self._panes_visual("nixhome")
        self.assertEqual(len(panes), 3)
        cell_ids = [self._read_cell_id(pid) for *_, pid in panes]
        self.assertEqual(cell_ids, ["111", "112", "110"],
                         "visual round-trip broken: nixhome panes "
                         "should be top-left=111, top-right=112, bottom=110")

    @unittest.expectedFailure
    def test_as_saved_yaml_breaks_on_reapply_main_horizontal_mirrored(self):
        """The user-reported bug. Re-applying the preset scrambles panes.

        After load: pane_index 0 = first YAML pane (CELL_ID 111, originally
        top-left). select-layout main-horizontal-mirrored puts pane_index 0
        in the main slot (bottom). Original top-left content moves to bottom,
        breaking the user's mental model.
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
        # If pane_index↔role were preserved, the bottom strip would still
        # be 110 after re-apply. Bug: it isn't.
        self.assertEqual(cell_ids[2], "110",
                         "bottom slot after re-apply should still be CELL_ID 110")

    def test_handcrafted_yaml_plus_reapply_preserves_roles_and_visual(self):
        """Proof of the viable workflow: pane_index-order YAML + post-load
        re-apply of the preset layout produces correct visual AND correct
        pane_index↔role mapping.

        Why post-load re-apply is required: tmux's layout parser ignores
        the X,Y coordinates in custom layout strings and recomputes
        geometry from declaration order — first child at top, second
        below, etc. So reordering the YAML children alone misplaces
        panes visually. But it DOES put pane_index 0 at the original
        main role, so a single `select-layout main-horizontal-mirrored`
        post-load reflows everything correctly.

        Implication: the architectural fix isn't just emit-order — the
        snapshot tool needs to also save the active preset and replay
        it on load.
        """
        src = (FIXTURE_DIR / "NMD-saved.yaml").read_text()

        # Rewrite only the nixhome window: reverse the layout's root
        # children + reverse the panes list so the bottom strip is first.
        # (The other mirrored windows are unchanged for this focused test.)
        old_layout = "7be3,222x53,0,0[222x50,0,0{111x50,0,0,111,110x50,112,0,112},222x2,0,51,110]"
        new_layout = reverse_root_children(old_layout)
        self.assertNotEqual(old_layout, new_layout)
        # New DFS leaf order: bottom strip (110), then top-left (111), top-right (112)

        modified = src.replace(old_layout, new_layout)

        # Reorder the nixhome panes block so YAML order matches new DFS:
        # [110 (bottom), 111 (top-left), 112 (top-right)]
        old_panes_block = (
            "    panes:\n"
            "    - focus: 'true'\n"
            "      shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '111'\n"
            "    - shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '112'\n"
            "    - shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '110'\n"
        )
        new_panes_block = (
            "    panes:\n"
            "    - shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '110'\n"
            "    - focus: 'true'\n"
            "      shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '111'\n"
            "    - shell_command: /bin/sh\n"
            "      environment:\n"
            "        CELL_ID: '112'\n"
        )
        self.assertIn(old_panes_block, modified)
        modified = modified.replace(old_panes_block, new_panes_block)

        out = self.work / "NMD-fixed.yaml"
        out.write_text(modified)

        self._load(out)

        # Post-load re-apply of the preset (the workflow this test proves).
        env = self.fx.env
        tmux(self.fx.load_sock, "set-window-option", "-t", "NMD:nixhome",
             "main-pane-height", "2", env=env)
        tmux(self.fx.load_sock, "select-layout", "-t", "NMD:nixhome",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.3)

        # Visual order: top-left=111, top-right=112, bottom=110 (mirrored).
        # Re-applying preset is now idempotent because pane_index↔role is
        # correct: pane 0 = CELL_ID 110 (the original main).
        panes = self._panes_visual("nixhome")
        cell_ids = [self._read_cell_id(pid) for *_, pid in panes]
        self.assertEqual(cell_ids, ["111", "112", "110"],
                         f"post-reapply visual wrong: {cell_ids}")

        # Idempotent: a second re-apply must produce the same result.
        tmux(self.fx.load_sock, "select-layout", "-t", "NMD:nixhome",
             "main-horizontal-mirrored", env=env)
        time.sleep(0.2)
        panes2 = self._panes_visual("nixhome")
        cell_ids2 = [self._read_cell_id(pid) for *_, pid in panes2]
        self.assertEqual(cell_ids, cell_ids2,
                         f"second re-apply not idempotent: {cell_ids2}")


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


if __name__ == "__main__":
    unittest.main(verbosity=2)

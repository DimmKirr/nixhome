#!/usr/bin/env python3
"""
tmux-snapshot — per-session tmux save/load tool.

Replaces the bash `tmuxsave` pipeline. Emits tmuxp-compatible YAML so
existing `tmuxp load` flows (tmuxload-dk, tmuxload-wk) keep working.

Single source of truth: live tmux state, queried once per session.
Panes are emitted in visual order (top-down, left-to-right) so
`tmuxp load` recreates them in the correct positions.
"""
from __future__ import annotations

import argparse
import dataclasses
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

INTERPRETERS = {
    "python", "python2", "python3",
    "ipython", "ipython3", "bpython",
    "node", "nodejs",
    "ruby", "irb",
    "lua", "luajit",
    "ghci", "iex",
    "julia", "R",
}

# Full-argv capture (`_foreground_argv`) was prototyped here but rolled back
# pending design decision in NMD-57 — see ticket for trade-offs (heuristic
# fallback vs. wrapper-side env-var instrumentation). Until then, panes are
# saved with `current_command` basename only.


@dataclasses.dataclass(frozen=True)
class Pane:
    pane_id: str         # "%17" — server-global
    pane_index: int      # window-local, may be sparse
    top: int
    left: int
    width: int
    height: int
    current_command: str # "zsh", "ssh", "python3" — basename
    start_command: str   # the original command (may be empty if shell)
    focus: bool
    cwd: str

    @property
    def cell_id(self) -> str:
        # pane_id without the leading '%'
        return self.pane_id.lstrip("%")

    @property
    def is_repl(self) -> bool:
        cmd = (self.current_command or "").strip()
        if not cmd:
            return False
        base = cmd.split("/")[-1]
        # Strip version suffix (e.g. python3.13 -> python) so versioned
        # interpreter binaries are detected too.
        stem = re.split(r"[.\d]", base)[0]
        return base in INTERPRETERS or stem in INTERPRETERS

    @property
    def shell_command(self) -> str:
        """Best-effort recoverable command for the pane.

        REPL panes (python, node, irb, ...) are replaced with the default
        shell so `tmuxp load` doesn't relaunch a REPL on restore. We keep
        the pane itself so the layout's pane count stays consistent.
        """
        if self.is_repl:
            return "zsh"
        cmd = (self.current_command or "").strip()
        return cmd or "zsh"


@dataclasses.dataclass(frozen=True)
class Window:
    window_id: str       # "@5"
    window_index: int
    name: str
    layout: str
    options: dict[str, str]
    panes: tuple[Pane, ...]
    focus: bool
    start_directory: str


@dataclasses.dataclass(frozen=True)
class Session:
    name: str
    windows: tuple[Window, ...]


def _tmux(socket: str | None, *args: str) -> str:
    cmd = ["tmux"]
    if socket:
        cmd += ["-S", socket]
    cmd += list(args)
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return res.stdout


# Field separator for tmux -F format strings. Picked something that won't
# appear in window/pane names or layouts.
SEP = "\x1f"


def query_session(name: str, socket: str | None = None) -> Session:
    """Build a Session from live tmux state."""
    win_fmt = SEP.join([
        "#{window_id}",
        "#{window_index}",
        "#{window_name}",
        "#{window_layout}",
        "#{window_active}",
        "#{?window_active,1,0}",   # focus marker
        "#{pane_current_path}",    # use first pane's cwd as window cwd
        "#{window_options}",       # key=val pairs (newline separated by tmux)
    ])
    raw = _tmux(socket, "list-windows", "-t", name, "-F", win_fmt)
    windows: list[Window] = []
    for line in raw.splitlines():
        if not line:
            continue
        wid, widx, wname, wlayout, _wactive, focus_flag, cwd, _opts = line.split(SEP, 7)
        panes = _query_panes(wid, socket)
        # Pull main-pane-height etc. from window options (we only persist a
        # small allowlist to keep YAML noise low).
        options = _query_window_options(wid, socket)
        windows.append(Window(
            window_id=wid,
            window_index=int(widx),
            name=wname,
            layout=wlayout,
            options=options,
            panes=panes,
            focus=(focus_flag == "1"),
            start_directory=cwd,
        ))
    return Session(name=name, windows=tuple(windows))


def _query_panes(window_id: str, socket: str | None) -> tuple[Pane, ...]:
    """Query panes for a window by window_id (@N) — dot-in-name safe."""
    pane_fmt = SEP.join([
        "#{pane_id}",
        "#{pane_index}",
        "#{pane_top}",
        "#{pane_left}",
        "#{pane_width}",
        "#{pane_height}",
        "#{pane_current_command}",
        "#{pane_start_command}",
        "#{?pane_active,1,0}",
        "#{pane_current_path}",
    ])
    raw = _tmux(socket, "list-panes", "-t", window_id, "-F", pane_fmt)
    panes: list[Pane] = []
    for line in raw.splitlines():
        if not line:
            continue
        pid, pidx, top, left, w, h, cur, start, active, cwd = line.split(SEP, 9)
        panes.append(Pane(
            pane_id=pid,
            pane_index=int(pidx),
            top=int(top),
            left=int(left),
            width=int(w),
            height=int(h),
            current_command=cur,
            start_command=start,
            focus=(active == "1"),
            cwd=cwd,
        ))
    # Sort by pane_index, NOT visual position.
    #
    # tmuxp creates panes in YAML order, assigning sequential pane_index
    # 0, 1, 2, ... tmux preset layouts (main-horizontal[-mirrored],
    # main-vertical[-mirrored]) put pane_index 0 in the "main" slot.
    # Emitting in pane_index order preserves the index↔role mapping
    # so a future `select-layout main-*` (e.g. `prefix S h`) lands the
    # original "main" content in the canonical main slot.
    #
    # Caveat: tmux's layout parser ignores X,Y values in the layout
    # string and recomputes geometry from declaration order. For
    # *-mirrored saved layouts, the visual immediately after load shows
    # the main content shifted (e.g. at top-left for mirrored bottom).
    # The `load` subcommand re-applies the preset for *canonical* layouts
    # (see preset_layouts metadata + detect_preset_layout) to fix this.
    # Custom-resized layouts skip the re-apply, so divider positions
    # survive — at the cost of a one-time post-load rotation that goes
    # away if the user presses `prefix S h`.
    panes.sort(key=lambda p: p.pane_index)
    return tuple(panes)


# Only persist a tiny allowlist of window options — anything else is noise.
_PERSISTED_WINDOW_OPTIONS = {"main-pane-height", "main-pane-width"}


_CUSTOM_LAYOUT_SLOTS = (6, 7, 8, 9)


def query_custom_layouts(socket: str | None = None) -> dict[str, str]:
    """Read @layout-6..9 global tmux options.

    These are user-defined "remember this layout" slots — the layout
    string at each slot is restored to a window via select-layout. Saved
    so the slots survive a server restart.
    """
    out: dict[str, str] = {}
    for slot in _CUSTOM_LAYOUT_SLOTS:
        try:
            val = _tmux(socket, "show-options", "-gv", f"@layout-{slot}").strip()
        except subprocess.CalledProcessError:
            continue
        if val:
            out[str(slot)] = val
    return out


def _query_window_options(window_id: str, socket: str | None) -> dict[str, str]:
    raw = _tmux(socket, "show-window-options", "-t", window_id)
    out: dict[str, str] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or " " not in line:
            continue
        key, _, val = line.partition(" ")
        if key in _PERSISTED_WINDOW_OPTIONS:
            out[key] = val
    return out


# ------------------------------------------------------------------ preset detection


def _split_top_level_children(s: str) -> list[str]:
    """Split a layout-string children list at depth-0 commas.

    Children are leaves `WxH,X,Y,N` (3 internal commas at depth 0!)
    or subtrees `WxH,X,Y[...]` / `WxH,X,Y{...}`. We parse each child by
    matching the geometry prefix then either a leaf-id or a bracketed
    subtree.
    """
    out: list[str] = []
    i = 0
    while i < len(s):
        m = re.match(r"\d+x\d+,\d+,\d+", s[i:])
        if not m:
            raise ValueError(f"bad layout child at {i}: {s[i:]!r}")
        end = i + m.end()
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
            out.append(s[i:j])
            i = j
        elif end < len(s) and s[end] == ",":
            m2 = re.match(r",\d+", s[end:])
            if not m2:
                raise ValueError(f"bad leaf id at {end}: {s[end:]!r}")
            out.append(s[i:end + m2.end()])
            i = end + m2.end()
        else:
            out.append(s[i:end])
            i = end
        if i < len(s) and s[i] == ",":
            i += 1
    return out


def _wh(node: str) -> tuple[int, int]:
    """Parse WxH from the leading geometry of a layout node."""
    m = re.match(r"(\d+)x(\d+)", node)
    if not m:
        raise ValueError(f"no WxH prefix in {node!r}")
    return int(m.group(1)), int(m.group(2))


def _secondaries_canonical(group: str, dim_index: int) -> bool:
    """Are the children of a `{...}` or `[...]` subtree all equal-sized
    along `dim_index` (0=width, 1=height)? Allow ±1 for rounding.

    Used to distinguish a canonical preset (equal secondaries) from a
    user-resized layout (asymmetric divider positions).
    """
    inner_match = re.match(r"^\d+x\d+,\d+,\d+([\[\{])(.*)([\]\}])$", group)
    if not inner_match:
        return False
    inner = inner_match.group(2)
    try:
        kids = _split_top_level_children(inner)
    except ValueError:
        return False
    if len(kids) < 2:
        return True
    sizes = [_wh(k)[dim_index] for k in kids]
    lo, hi = min(sizes), max(sizes)
    return (hi - lo) <= 1


def detect_preset_layout(layout: str) -> str | None:
    """Return tmux preset name iff the layout matches a canonical preset.

    Shape match:
      [leaf, {leaves}]   → main-horizontal           (main on top)
      [{leaves}, leaf]   → main-horizontal-mirrored  (main on bottom)
      {leaf, [leaves]}   → main-vertical             (main on left)
      {[leaves], leaf}   → main-vertical-mirrored    (main on right)

    Canonical check: secondaries must be equal-sized (±1 for rounding).
    A user-dragged divider produces asymmetric secondaries, which we
    treat as a custom layout — no preset name is emitted, so the load
    path won't enforce a canonical re-apply and the saved layout
    survives byte-exact.

    Even-* and tiled layouts aren't detected; they're idempotent under
    re-apply, so we don't need preset metadata.
    """
    body = re.sub(r"^[0-9a-f]{4},", "", layout)
    m = re.match(r"^\d+x\d+,\d+,\d+([\[\{])(.*)([\]\}])$", body)
    if not m:
        return None  # single pane
    opener, inner, closer = m.groups()
    try:
        children = _split_top_level_children(inner)
    except ValueError:
        return None
    if len(children) != 2:
        return None
    a, b = children
    a_is_leaf = ("[" not in a) and ("{" not in a)
    b_is_leaf = ("[" not in b) and ("{" not in b)
    a_has_brace = "{" in a
    b_has_brace = "{" in b
    a_has_bracket = "[" in a
    b_has_bracket = "[" in b

    # main-horizontal*: secondaries are in a {} group, equal WIDTHS.
    # main-vertical*:   secondaries are in a [] group, equal HEIGHTS.
    if opener == "[":
        if a_is_leaf and b_has_brace and _secondaries_canonical(b, 0):
            return "main-horizontal"
        if b_is_leaf and a_has_brace and _secondaries_canonical(a, 0):
            return "main-horizontal-mirrored"
    elif opener == "{":
        if a_is_leaf and b_has_bracket and _secondaries_canonical(b, 1):
            return "main-vertical"
        if b_is_leaf and a_has_bracket and _secondaries_canonical(a, 1):
            return "main-vertical-mirrored"
    return None


# ------------------------------------------------------------------ YAML emit

# Hand-rolled emitter — keeps layout strings byte-for-byte and avoids a
# pyyaml dependency. Only emits the subset of tmuxp's schema we use.

def _yaml_quote(s: str) -> str:
    """Quote a scalar for safe YAML embedding. Always single-quoted."""
    return "'" + s.replace("'", "''") + "'"


def _needs_quote(s: str) -> bool:
    if not s:
        return True
    # If the string contains anything YAML-ish, quote it.
    bad = set(":#&*!|>'\"%@`,[]{}")
    if any(c in bad for c in s):
        return True
    if s != s.strip():
        return True
    # Numbers, booleans, null get quoted to keep them strings.
    if s.lower() in {"true", "false", "yes", "no", "null", "~"}:
        return True
    try:
        float(s)
        return True
    except ValueError:
        pass
    return False


def _scalar(s: str) -> str:
    return _yaml_quote(s) if _needs_quote(s) else s


def emit_yaml(session: Session,
              custom_layouts: dict[str, str] | None = None) -> str:
    lines: list[str] = []
    lines.append(f"session_name: {_scalar(session.name)}")

    # preset_layouts: extra top-level key (tmuxp ignores unknown keys).
    # Only emitted for canonical preset shapes (equal secondaries) — see
    # detect_preset_layout. Custom-resized layouts get no entry, so the
    # load path skips the post-load re-apply and preserves geometry
    # byte-exact.
    presets: dict[str, str] = {}
    for w in session.windows:
        p = detect_preset_layout(w.layout)
        if p:
            presets[w.name] = p
    if presets:
        lines.append("preset_layouts:")
        for name, preset in presets.items():
            lines.append(f"  {_scalar(name)}: {preset}")

    # custom_layouts: global @layout-6..9 slots. Restored on load via
    # `tmux set-option -g`. Layouts contain commas/brackets, so always
    # quoted.
    if custom_layouts:
        lines.append("custom_layouts:")
        for slot, layout in sorted(custom_layouts.items()):
            lines.append(f"  '{slot}': {_yaml_quote(layout)}")

    lines.append("windows:")
    for w in session.windows:
        # First line of each window: focus marker if applicable, else layout.
        # We always lead with "- " on the first key to mark a list element.
        first_line_emitted = False

        def add(key: str, val: str, *, indent: int = 4):
            nonlocal first_line_emitted
            prefix = "  - " if not first_line_emitted else " " * indent
            lines.append(f"{prefix}{key}: {val}")
            first_line_emitted = True

        if w.focus:
            add("focus", "'true'")
        # layout string is plain — never quote it (tmuxp parses both).
        add("layout", w.layout)
        # options
        if w.options:
            add("options", "")
            for k, v in sorted(w.options.items()):
                lines.append(f"      {k}: {_scalar(v)}")
        else:
            add("options", "{}")

        # Panes in pane_index order — see _query_panes for why. REPLs are
        # kept (layout integrity) but their shell_command is replaced with
        # the default shell, see Pane.shell_command.
        if w.panes:
            add("panes", "")
            for p in w.panes:
                _emit_pane(lines, p)
        else:
            add("panes", "[]")

        if w.start_directory:
            add("start_directory", _scalar(w.start_directory))
        add("window_name", _scalar(w.name))

    return "\n".join(lines) + "\n"


def _emit_pane(lines: list[str], p: Pane) -> None:
    # First pane key always starts with "    - " (under "panes:")
    first = True
    def add(key: str, val: str):
        nonlocal first
        prefix = "    - " if first else "      "
        lines.append(f"{prefix}{key}: {val}")
        first = False

    if p.focus:
        add("focus", "'true'")
    add("shell_command", _scalar(p.shell_command))
    add("environment", "")
    lines.append(f"        CELL_ID: {_yaml_quote(p.cell_id)}")


# ------------------------------------------------------------------ commands

DEFAULT_OUT_DIR = Path("~/.config/tmuxp").expanduser()
MANIFEST = DEFAULT_OUT_DIR / ".session-order"
BACKUP_BASE = DEFAULT_OUT_DIR / "backups"


def save_session(name: str, *, socket: str | None = None,
                 out_dir: Path = DEFAULT_OUT_DIR) -> Path:
    sess = query_session(name, socket=socket)
    custom = query_custom_layouts(socket=socket)
    yaml = emit_yaml(sess, custom_layouts=custom)
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{name}.yaml"
    target.write_text(yaml)
    return target


def load_session(yaml_path: Path, *,
                 socket: str | None = None,
                 tmuxp_bin: str = "tmuxp",
                 env: dict | None = None) -> None:
    """Load a snapshot via tmuxp, then re-apply any saved preset layouts.

    Re-apply only runs for windows whose saved layout was canonical
    (equal secondaries) — those are the layouts where a preset is
    semantically what the user wants. Custom-resized layouts have no
    `preset_layouts:` entry, so they load byte-exact with no geometry
    enforcement (custom divider positions survive).
    """
    text = Path(yaml_path).read_text()
    presets = _parse_preset_layouts(text)
    custom_layouts = _parse_custom_layouts(text)
    session_name = _read_session_name(text)

    cmd = [tmuxp_bin, "load"]
    if socket:
        cmd += ["-S", socket]
    cmd += ["-d", "-y", str(yaml_path)]
    subprocess.run(cmd, check=True, env=env)

    # Restore @layout-6..9 global options first — these are server-wide,
    # not session-scoped, so doing it before/after re-apply doesn't matter.
    for slot, layout in custom_layouts.items():
        try:
            tmux_cmd = ["tmux"]
            if socket:
                tmux_cmd += ["-S", socket]
            tmux_cmd += ["set-option", "-g", f"@layout-{slot}", layout]
            subprocess.run(tmux_cmd, check=True, capture_output=True,
                           text=True, env=env)
        except subprocess.CalledProcessError as e:
            print(f"[WARN] restore @layout-{slot}: {e.stderr or e}",
                  file=sys.stderr)

    if not presets:
        return

    # Target by window_id (@N), not `session:name` — dotted names
    # (e.g. "nmd.gg") confuse tmux's `-t` parser.
    name_to_id = _list_window_ids(session_name, socket=socket, env=env)
    for window_name, preset in presets.items():
        wid = name_to_id.get(window_name)
        if wid is None:
            print(f"[WARN] re-apply {preset}: window {window_name!r} not found",
                  file=sys.stderr)
            continue
        try:
            tmux_cmd = ["tmux"]
            if socket:
                tmux_cmd += ["-S", socket]
            tmux_cmd += ["select-layout", "-t", wid, preset]
            subprocess.run(tmux_cmd, check=True, capture_output=True,
                           text=True, env=env)
        except subprocess.CalledProcessError as e:
            print(f"[WARN] re-apply {preset} on {window_name} ({wid}): "
                  f"{e.stderr or e}", file=sys.stderr)


def _parse_top_level_map(yaml_text: str, block_key: str) -> dict[str, str]:
    """Read a flat `<key>:\\n  k: v\\n  ...` block from snapshot YAML.

    Values may be single-quoted (we strip outer quotes and unescape ''
    pairs). Block ends at the next non-indented line.
    """
    out: dict[str, str] = {}
    in_block = False
    for line in yaml_text.splitlines():
        if not in_block:
            if line.rstrip() == f"{block_key}:":
                in_block = True
            continue
        if line.startswith("  ") and not line.startswith("   "):
            stripped = line[2:]
            key, _, val = stripped.partition(":")
            key = key.strip().strip("'\"")
            val = val.strip()
            if val.startswith("'") and val.endswith("'") and len(val) >= 2:
                val = val[1:-1].replace("''", "'")
            if key and val:
                out[key] = val
        elif line == "":
            continue
        else:
            break
    return out


def _parse_preset_layouts(yaml_text: str) -> dict[str, str]:
    return _parse_top_level_map(yaml_text, "preset_layouts")


def _parse_custom_layouts(yaml_text: str) -> dict[str, str]:
    return _parse_top_level_map(yaml_text, "custom_layouts")


def _list_window_ids(session: str, *,
                     socket: str | None = None,
                     env: dict | None = None) -> dict[str, str]:
    cmd = ["tmux"]
    if socket:
        cmd += ["-S", socket]
    cmd += ["list-windows", "-t", session,
            "-F", f"#{{window_name}}{SEP}#{{window_id}}"]
    res = subprocess.run(cmd, capture_output=True, text=True,
                         check=True, env=env)
    out: dict[str, str] = {}
    for line in res.stdout.splitlines():
        if SEP in line:
            name, _, wid = line.partition(SEP)
            out[name] = wid
    return out


def _read_session_name(yaml_text: str) -> str:
    for line in yaml_text.splitlines():
        if line.startswith("session_name:"):
            return line.split(":", 1)[1].strip().strip("'\"")
    raise ValueError("no session_name in YAML")


def list_sessions(socket: str | None = None) -> list[str]:
    """Return session names ordered by last activity (most recent first)."""
    raw = _tmux(socket, "list-sessions", "-F", "#{session_activity} #{session_name}")
    rows = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        act, _, sname = line.partition(" ")
        rows.append((int(act), sname))
    rows.sort(reverse=True)
    return [s for _, s in rows]


def save_all(socket: str | None = None,
             out_dir: Path = DEFAULT_OUT_DIR,
             manifest: Path | None = None) -> list[Path]:
    if manifest is None:
        manifest = out_dir / ".session-order"
    names = list_sessions(socket=socket)
    written: list[Path] = []
    for name in names:
        try:
            written.append(save_session(name, socket=socket, out_dir=out_dir))
        except subprocess.CalledProcessError as e:
            print(f"[ERR] {name}: {e.stderr or e}", file=sys.stderr)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(names) + ("\n" if names else ""))
    return written


# ------------------------------------------------------------------ backups

_BACKUP_LIMITS = {"recent": 7, "daily": 7, "weekly": 4, "monthly": 12}


def _period(dt: datetime, tier: str) -> str | None:
    if tier == "daily":
        return dt.strftime("%Y-%m-%d")
    if tier == "weekly":
        return dt.strftime("%G-W%V")
    if tier == "monthly":
        return dt.strftime("%Y-%m")
    return None


def backup(session: str, *, src: Path, base: Path = BACKUP_BASE,
           now: datetime | None = None) -> None:
    if not src.exists():
        return
    if now is None:
        now = datetime.now()
    stamp = now.strftime("%Y-%m-%dT%H-%M-%S")
    fname = f"{session}-{stamp}.yaml"

    for tier, limit in _BACKUP_LIMITS.items():
        tdir = base / tier
        tdir.mkdir(parents=True, exist_ok=True)
        # Tiered tiers (not "recent") keep one entry per period.
        if tier != "recent":
            current = _period(now, tier)
            for f in tdir.glob(f"{session}-*.yaml"):
                d = _parse_dt(f, session)
                if d and _period(d, tier) == current:
                    f.unlink()
        shutil.copy2(src, tdir / fname)
        # Rotate: drop oldest beyond limit
        files = sorted(tdir.glob(f"{session}-*.yaml"))
        for f in files[:-limit]:
            f.unlink()


def _parse_dt(p: Path, session: str) -> datetime | None:
    stem = p.stem
    prefix = f"{session}-"
    if not stem.startswith(prefix):
        return None
    try:
        return datetime.strptime(stem[len(prefix):], "%Y-%m-%dT%H-%M-%S")
    except ValueError:
        return None


# ------------------------------------------------------------------ CLI

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="tmux-snapshot")
    p.add_argument("-S", "--socket-path", default=None,
                   help="tmux socket path (passes through to tmux -S)")
    p.add_argument("-o", "--out-dir", default=str(DEFAULT_OUT_DIR),
                   help="directory for snapshot yamls")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_save = sub.add_parser("save", help="save one session")
    p_save.add_argument("name")
    p_save.add_argument("--no-backup", action="store_true")

    p_all = sub.add_parser("save-all", help="save every session + manifest")
    p_all.add_argument("--no-backup", action="store_true")

    p_load = sub.add_parser("load",
                            help="tmuxp load + re-apply saved preset layouts")
    p_load.add_argument("name", help="session name OR yaml path")

    args = p.parse_args(argv)
    out_dir = Path(args.out_dir).expanduser()

    if args.cmd == "save":
        target = save_session(args.name, socket=args.socket_path, out_dir=out_dir)
        print(f"[OK] {target.name}")
        if not args.no_backup:
            backup(args.name, src=target, base=out_dir / "backups")
        return 0

    if args.cmd == "load":
        # Accept either a bare session name (resolved against out_dir) or
        # an explicit path.
        candidate = Path(args.name)
        target_yaml = candidate if candidate.suffix == ".yaml" else out_dir / f"{args.name}.yaml"
        load_session(target_yaml, socket=args.socket_path)
        print(f"[OK] loaded {target_yaml.name}")
        return 0

    if args.cmd == "save-all":
        written = save_all(socket=args.socket_path, out_dir=out_dir)
        for path in written:
            print(f"[OK] {path.name}")
            if not args.no_backup:
                backup(path.stem, src=path, base=out_dir / "backups")
        print(f"[OK] .session-order ({len(written)} sessions)")
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())

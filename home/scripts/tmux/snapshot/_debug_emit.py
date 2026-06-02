#!/usr/bin/env python3
"""In-process snapshot.py emit for `task debug:tmuxp`.

Loads snapshot.py as a module, runs query_session + emit_yaml against the
live tmux state, writes the result to $OUT. No file is written under
~/.config/tmuxp — this is a read-only introspection of what snapshot.py
WOULD emit if the user pressed save right now.

Reads from env:
  SNAP_PATH    absolute path to snapshot.py
  SESSION      tmux session name
  OUT          output path for the emitted YAML
"""
from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import traceback


def main() -> int:
    try:
        snap_path = os.environ["SNAP_PATH"]
        session = os.environ["SESSION"]
        out = pathlib.Path(os.environ["OUT"])
    except KeyError as e:
        print(f"missing env var: {e}", file=sys.stderr)
        return 2

    try:
        spec = importlib.util.spec_from_file_location("snap", snap_path)
        snap = importlib.util.module_from_spec(spec)
        # Register in sys.modules BEFORE exec_module — Python 3.13's
        # dataclass introspection looks up cls.__module__ via sys.modules
        # and fails with AttributeError on None if the module isn't there.
        sys.modules["snap"] = snap
        spec.loader.exec_module(snap)
        sess = snap.query_session(session)
        custom = snap.query_custom_layouts()
        text = snap.emit_yaml(sess, custom_layouts=custom)
        out.write_text(text)
        print(f"wrote {out} ({len(text)} bytes)")
        return 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())

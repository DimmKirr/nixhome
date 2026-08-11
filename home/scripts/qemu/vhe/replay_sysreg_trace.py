#!/usr/bin/env python3
"""
replay_sysreg_trace — feed a Hyper-V sysreg trace fixture through vhe_core.

Takes a fixture produced by parse_sysreg_trace.py, replays its EL2 accesses
(op1 == 4, in trace order) through the vhe_replay binary, and reports any
the emulation core cannot handle.

Exit 0: every EL2 access handled (or redirected) — the core covers the trace.
Exit 1: unhandled sysregs remain — printed ranked by frequency; that list is
        the KVM-port work queue (NMD-253).

Usage: replay_sysreg_trace.py <fixture.json> [--replay-bin PATH]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path


def replay(fixture: dict, replay_bin: str) -> Counter:
    el2 = [e for e in fixture["trace"] if e["op1"] == 4]
    if not el2:
        return Counter()

    lines = "".join(
        f"{e['rw']} {int(e['reg'], 16):x} {int(e['val'], 16):x}\n"
        for e in el2)
    res = subprocess.run([replay_bin], input=lines,
                         capture_output=True, text=True, check=True)
    results = res.stdout.splitlines()
    if len(results) != len(el2):
        raise RuntimeError(
            f"replay binary answered {len(results)} of {len(el2)} accesses")

    unhandled: Counter = Counter()
    for e, outcome in zip(el2, results):
        if outcome == "unhandled":
            key = (e["op0"], e["op1"], e["crn"], e["crm"], e["op2"])
            unhandled[key] += 1
    return unhandled


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fixture")
    ap.add_argument("--replay-bin", default=str(Path(__file__).parent / "vhe_replay"))
    args = ap.parse_args(argv[1:])

    with open(args.fixture) as f:
        fixture = json.load(f)

    unhandled = replay(fixture, args.replay_bin)
    if not unhandled:
        print("all EL2 accesses handled")
        return 0

    print(f"{sum(unhandled.values())} unhandled accesses, "
          f"{len(unhandled)} unique sysregs (most frequent first):")
    for (op0, op1, crn, crm, op2), n in unhandled.most_common():
        print(f"  {op0},{op1},{crn},{crm},{op2}  x{n}")
    print("fail: emulation core does not cover this trace")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))

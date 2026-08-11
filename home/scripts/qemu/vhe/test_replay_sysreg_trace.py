"""
Tests for the VHE replay harness.

replay_sysreg_trace.py feeds a parse_sysreg_trace fixture's trace through
the compiled vhe_core (via the vhe_replay line-protocol binary) and fails
if any EL2 sysreg access is unhandled. This is the red-driver for the KVM
port: point it at the real Hyper-V fixture and implement until it's green.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
REPLAY_BIN = Path(tempfile.gettempdir()) / "vhe_replay"


def sysreg(op0, op1, crn, crm, op2):
    return (op0 << 20) | (op2 << 17) | (op1 << 14) | (crn << 10) | (crm << 1)


def entry(op0, op1, crn, crm, op2, rw="w", val=0):
    return {
        "pc": "0x0", "reg": hex(sysreg(op0, op1, crn, crm, op2)),
        "op0": op0, "op1": op1, "crn": crn, "crm": crm, "op2": op2,
        "rw": rw, "rt": 0, "val": hex(val), "handled": False,
    }


def fixture(entries):
    return {"summary": {}, "sysregs": [], "trace": entries}


HCR_E2H = 1 << 34


class ReplayHarnessTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(
            ["cc", "-std=gnu11", "-Wall", "-Wextra", "-Werror",
             "-o", str(REPLAY_BIN),
             str(HERE / "vhe_replay.c"), str(HERE / "vhe_core.c")],
            check=True)

    def run_harness(self, fx) -> subprocess.CompletedProcess:
        with tempfile.NamedTemporaryFile("w", suffix=".json",
                                         delete=False) as f:
            json.dump(fx, f)
            path = f.name
        return subprocess.run(
            [sys.executable, str(HERE / "replay_sysreg_trace.py"),
             path, "--replay-bin", str(REPLAY_BIN)],
            capture_output=True, text=True)

    def test_all_handled_fixture_exits_zero(self):
        # HCR_EL2 write is pure shadow — always handled
        res = self.run_harness(fixture([entry(3, 4, 1, 1, 0, "w", 0)]))
        self.assertEqual(res.returncode, 0, res.stderr)

    def test_unhandled_el2_reg_exits_one_and_names_it(self):
        # S3_4_C3_C0_0 (DACR32_EL2) — not in any table
        res = self.run_harness(fixture([entry(3, 4, 3, 0, 0)]))
        self.assertEqual(res.returncode, 1)
        self.assertIn("3,4,3,0,0", res.stdout)

    def test_redirect_counts_as_handled(self):
        # Set E2H via HCR_EL2 first, then SCTLR_EL2 redirects — handled
        res = self.run_harness(fixture([
            entry(3, 4, 1, 1, 0, "w", HCR_E2H),
            entry(3, 4, 1, 0, 0, "w", 0x30D00805),
        ]))
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_non_el2_entries_are_skipped(self):
        # CNTPCT_EL0 (op1=3) is not EL2 — must not count as unhandled
        res = self.run_harness(fixture([entry(3, 3, 14, 0, 1, "r")]))
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_unhandled_summary_is_ranked_by_frequency(self):
        res = self.run_harness(fixture(
            [entry(3, 4, 3, 0, 0)] +          # DACR32_EL2 x1
            [entry(3, 4, 2, 6, 0)] * 3        # unknown reg x3 — must rank first
        ))
        self.assertEqual(res.returncode, 1)
        # line 0 is the header; line 1 is the top-ranked (most frequent) entry
        first = res.stdout.strip().splitlines()[1]
        self.assertIn("3,4,2,6,0", first)


if __name__ == "__main__":
    unittest.main()

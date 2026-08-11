"""
Tests for parse_sysreg_trace — HVF sysreg trap JSONL → replay fixture.

Input lines are produced by the hvf-sysreg-trace.patch fprintf; the
sample lines here are byte-identical to that format (verified against
a compiled copy of the patched fragment).
"""
from __future__ import annotations

import io
import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import parse_sysreg_trace as pst

# Byte-identical to the patch's fprintf output.
LINE_HANDLED_READ = (
    '{"pc":"0xffff800008001234","reg":"0x32f800",'
    '"op0":3,"op1":3,"crn":14,"crm":0,"op2":1,'
    '"rw":"r","rt":5,"val":"0x123456789a","handled":true}'
)
LINE_UNHANDLED_WRITE = (
    '{"pc":"0xffff800008005678","reg":"0x310802",'
    '"op0":3,"op1":4,"crn":2,"crm":1,"op2":0,'
    '"rw":"w","rt":0,"val":"0xdeadbeef0000","handled":false}'
)
LINE_UNHANDLED_READ = (
    '{"pc":"0xffff80000800abcd","reg":"0x310402",'
    '"op0":3,"op1":4,"crn":1,"crm":1,"op2":0,'
    '"rw":"r","rt":12,"val":"0x0","handled":false}'
)


def parse(text: str) -> dict:
    return pst.build_fixture(pst.parse_lines(io.StringIO(text)))


class TestParseLines(unittest.TestCase):
    def test_parses_single_line(self):
        entries = pst.parse_lines(io.StringIO(LINE_HANDLED_READ + "\n"))
        self.assertEqual(len(entries), 1)
        e = entries[0]
        self.assertEqual(e["pc"], "0xffff800008001234")
        self.assertEqual(e["reg"], "0x32f800")
        self.assertEqual((e["op0"], e["op1"], e["crn"], e["crm"], e["op2"]),
                         (3, 3, 14, 0, 1))
        self.assertEqual(e["rw"], "r")
        self.assertEqual(e["rt"], 5)
        self.assertEqual(e["val"], "0x123456789a")
        self.assertTrue(e["handled"])

    def test_skips_blank_lines(self):
        entries = pst.parse_lines(
            io.StringIO(f"\n{LINE_HANDLED_READ}\n\n{LINE_UNHANDLED_WRITE}\n"))
        self.assertEqual(len(entries), 2)

    def test_rejects_malformed_json_with_line_number(self):
        text = LINE_HANDLED_READ + "\nnot json\n"
        with self.assertRaises(pst.TraceError) as ctx:
            pst.parse_lines(io.StringIO(text))
        self.assertIn("line 2", str(ctx.exception))

    def test_rejects_missing_fields_with_line_number(self):
        with self.assertRaises(pst.TraceError) as ctx:
            pst.parse_lines(io.StringIO('{"pc":"0x0"}\n'))
        self.assertIn("line 1", str(ctx.exception))

    def test_rejects_encoding_mismatch(self):
        # op0..op2 fields must round-trip to the packed reg value
        bad = LINE_HANDLED_READ.replace('"op0":3', '"op0":2')
        with self.assertRaises(pst.TraceError) as ctx:
            pst.parse_lines(io.StringIO(bad + "\n"))
        self.assertIn("encoding mismatch", str(ctx.exception))


class TestSysregNames(unittest.TestCase):
    def test_knows_vttbr_el2(self):
        self.assertEqual(pst.sysreg_name(3, 4, 2, 1, 0), "VTTBR_EL2")

    def test_knows_hcr_el2(self):
        self.assertEqual(pst.sysreg_name(3, 4, 1, 1, 0), "HCR_EL2")

    def test_unknown_reg_is_none(self):
        self.assertIsNone(pst.sysreg_name(2, 7, 15, 15, 7))


class TestBuildFixture(unittest.TestCase):
    def test_empty_trace(self):
        fx = parse("")
        self.assertEqual(fx["summary"]["total_traps"], 0)
        self.assertEqual(fx["summary"]["unhandled_traps"], 0)
        self.assertEqual(fx["sysregs"], [])
        self.assertEqual(fx["trace"], [])

    def test_summary_counts(self):
        fx = parse("\n".join([LINE_HANDLED_READ, LINE_UNHANDLED_WRITE,
                              LINE_UNHANDLED_WRITE, LINE_UNHANDLED_READ]))
        self.assertEqual(fx["summary"]["total_traps"], 4)
        self.assertEqual(fx["summary"]["handled_traps"], 1)
        self.assertEqual(fx["summary"]["unhandled_traps"], 3)
        self.assertEqual(fx["summary"]["unique_sysregs"], 3)

    def test_per_reg_aggregation(self):
        fx = parse("\n".join([LINE_UNHANDLED_WRITE, LINE_UNHANDLED_WRITE]))
        (reg,) = fx["sysregs"]
        self.assertEqual(reg["reg"], "0x310802")
        self.assertEqual(reg["name"], "VTTBR_EL2")
        self.assertEqual(reg["reads"], 0)
        self.assertEqual(reg["writes"], 2)
        self.assertEqual(reg["unhandled"], 2)

    def test_unhandled_regs_sorted_by_frequency(self):
        fx = parse("\n".join([LINE_UNHANDLED_READ, LINE_UNHANDLED_WRITE,
                              LINE_UNHANDLED_WRITE]))
        names = [r["name"] for r in fx["sysregs"]]
        self.assertEqual(names, ["VTTBR_EL2", "HCR_EL2"])

    def test_trace_preserves_order_for_replay(self):
        fx = parse("\n".join([LINE_HANDLED_READ, LINE_UNHANDLED_WRITE]))
        self.assertEqual(len(fx["trace"]), 2)
        self.assertEqual(fx["trace"][0]["reg"], "0x32f800")
        self.assertEqual(fx["trace"][1]["reg"], "0x310802")


class TestCli(unittest.TestCase):
    def run_cli(self, *args, stdin: str = "") -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(Path(__file__).parent / "parse_sysreg_trace.py"),
             *args],
            input=stdin, capture_output=True, text=True)

    def test_reads_file_and_emits_fixture(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl",
                                         delete=False) as f:
            f.write(LINE_UNHANDLED_WRITE + "\n")
            path = f.name
        res = self.run_cli(path)
        self.assertEqual(res.returncode, 0, res.stderr)
        fx = json.loads(res.stdout)
        self.assertEqual(fx["summary"]["total_traps"], 1)

    def test_reads_stdin_with_dash(self):
        res = self.run_cli("-", stdin=LINE_HANDLED_READ + "\n")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(json.loads(res.stdout)["summary"]["total_traps"], 1)

    def test_malformed_input_exits_nonzero(self):
        res = self.run_cli("-", stdin="garbage\n")
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("line 1", res.stderr)


if __name__ == "__main__":
    unittest.main()

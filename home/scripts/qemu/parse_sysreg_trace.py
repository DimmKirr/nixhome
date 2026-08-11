#!/usr/bin/env python3
"""
parse_sysreg_trace — HVF sysreg trap JSONL → replay fixture.

Consumes the JSON-line trace emitted by the hvf-sysreg-trace.patch
(QEMU_HVF_SYSREG_TRACE env var) and produces a fixture with:
  - summary: trap counts, unique sysregs
  - sysregs: per-register aggregation, unhandled-first, by frequency
  - trace:   the full ordered sequence, for Phase 2 replay tests

Usage: parse_sysreg_trace.py <trace.jsonl | ->  > fixture.json
"""
from __future__ import annotations

import json
import sys
from typing import IO

REQUIRED_FIELDS = {
    "pc", "reg", "op0", "op1", "crn", "crm", "op2", "rw", "rt", "val",
    "handled",
}

# Mirrors target/arm/hvf/hvf.c SYSREG() encoding
OP0_SHIFT, OP1_SHIFT, CRN_SHIFT, CRM_SHIFT, OP2_SHIFT = 20, 14, 10, 1, 17


def pack_sysreg(op0: int, op1: int, crn: int, crm: int, op2: int) -> int:
    return ((op0 << OP0_SHIFT) | (op1 << OP1_SHIFT) | (crn << CRN_SHIFT)
            | (crm << CRM_SHIFT) | (op2 << OP2_SHIFT))


# (op0, op1, crn, crm, op2) → architectural name, for the EL2 sysregs
# Hyper-V is expected to touch. Extend as the trace reveals more.
SYSREG_NAMES = {
    (3, 4, 0, 0, 0): "VPIDR_EL2",
    (3, 4, 0, 0, 5): "VMPIDR_EL2",
    (3, 4, 1, 0, 0): "SCTLR_EL2",
    (3, 4, 1, 1, 0): "HCR_EL2",
    (3, 4, 1, 1, 1): "MDCR_EL2",
    (3, 4, 1, 1, 2): "CPTR_EL2",
    (3, 4, 1, 1, 3): "HSTR_EL2",
    (3, 4, 1, 1, 7): "HACR_EL2",
    (3, 4, 2, 0, 0): "TTBR0_EL2",
    (3, 4, 2, 0, 1): "TTBR1_EL2",
    (3, 4, 2, 0, 2): "TCR_EL2",
    (3, 4, 2, 1, 0): "VTTBR_EL2",
    (3, 4, 2, 1, 2): "VTCR_EL2",
    (3, 4, 3, 0, 0): "DACR32_EL2",
    (3, 4, 4, 0, 1): "ELR_EL2",
    (3, 4, 4, 1, 0): "SP_EL1",
    (3, 4, 5, 2, 0): "ESR_EL2",
    (3, 4, 6, 0, 0): "FAR_EL2",
    (3, 4, 6, 0, 4): "HPFAR_EL2",
    (3, 4, 10, 2, 0): "MAIR_EL2",
    (3, 4, 12, 0, 0): "VBAR_EL2",
    (3, 4, 13, 0, 2): "TPIDR_EL2",
    (3, 4, 14, 0, 3): "CNTVOFF_EL2",
    (3, 4, 14, 1, 0): "CNTHCTL_EL2",
    (3, 4, 14, 2, 0): "CNTHP_TVAL_EL2",
    (3, 4, 14, 2, 1): "CNTHP_CTL_EL2",
    (3, 4, 14, 2, 2): "CNTHP_CVAL_EL2",
}


class TraceError(Exception):
    pass


def sysreg_name(op0: int, op1: int, crn: int, crm: int, op2: int) -> str | None:
    return SYSREG_NAMES.get((op0, op1, crn, crm, op2))


def parse_lines(stream: IO[str]) -> list[dict]:
    entries = []
    for lineno, line in enumerate(stream, start=1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as e:
            raise TraceError(f"line {lineno}: not valid JSON: {e}") from e
        missing = REQUIRED_FIELDS - set(entry)
        if missing:
            raise TraceError(
                f"line {lineno}: missing fields: {sorted(missing)}")
        packed = pack_sysreg(entry["op0"], entry["op1"], entry["crn"],
                             entry["crm"], entry["op2"])
        if packed != int(entry["reg"], 16):
            raise TraceError(
                f"line {lineno}: encoding mismatch: reg={entry['reg']} but "
                f"op fields pack to {packed:#x}")
        entries.append(entry)
    return entries


def build_fixture(entries: list[dict]) -> dict:
    regs: dict[str, dict] = {}
    for e in entries:
        agg = regs.setdefault(e["reg"], {
            "reg": e["reg"],
            "name": sysreg_name(e["op0"], e["op1"], e["crn"], e["crm"],
                                e["op2"]),
            "op0": e["op0"], "op1": e["op1"], "crn": e["crn"],
            "crm": e["crm"], "op2": e["op2"],
            "reads": 0, "writes": 0, "unhandled": 0,
        })
        agg["reads" if e["rw"] == "r" else "writes"] += 1
        if not e["handled"]:
            agg["unhandled"] += 1

    # Unhandled first, most-frequent first — Phase 2 works top-down
    sysregs = sorted(
        regs.values(),
        key=lambda r: (-r["unhandled"], -(r["reads"] + r["writes"])))

    unhandled_traps = sum(1 for e in entries if not e["handled"])
    return {
        "summary": {
            "total_traps": len(entries),
            "handled_traps": len(entries) - unhandled_traps,
            "unhandled_traps": unhandled_traps,
            "unique_sysregs": len(regs),
        },
        "sysregs": sysregs,
        "trace": entries,
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        if argv[1] == "-":
            entries = parse_lines(sys.stdin)
        else:
            with open(argv[1]) as f:
                entries = parse_lines(f)
    except (TraceError, OSError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    json.dump(build_fixture(entries), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

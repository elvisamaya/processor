#!/usr/bin/env python3
"""cpi_table.py - collect RESULT lines from the core simulations into a table.

    python3 scripts/cpi_table.py build

CPI (cycles per instruction) = clock cycles / instructions retired.
Single-cycle is always 1.0 but needs a long clock period; the pipeline's CPI
is above 1.0 because of stalls and flushes, but each cycle is ~5x shorter.
"""
import re
import sys
from pathlib import Path

CORES = [("core_single", "single-cycle"),
         ("core_pipe_nofwd", "pipeline, stall only"),
         ("core_pipe", "pipeline + forwarding")]


def load(build, core):
    out = {}
    path = Path(build) / f"{core}.log"
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        m = re.search(r"RESULT \S*/(\S+) instret=(\d+) cycles=(\d+)", line)
        if m:
            out[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return out


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else "build"
    data = {c: load(build, c) for c, _ in CORES}
    progs = list(data["core_single"]) or list(data["core_pipe"])

    head = f"| {'program':<12} | {'instructions':>12} | " + " | ".join(f"{n:>22}" for _, n in CORES) + " |"
    print(head)
    print("|" + "|".join("-" * (len(p) + 0) for p in head.split("|")[1:-1]) + "|")
    totals = {c: [0, 0] for c, _ in CORES}
    for p in progs:
        n = data["core_single"].get(p, (0, 0))[0]
        cells = []
        for c, _ in CORES:
            ins, cyc = data[c].get(p, (0, 0))
            totals[c][0] += ins
            totals[c][1] += cyc
            cells.append(f"{cyc / ins:>22.3f}" if ins else f"{'-':>22}")
        print(f"| {p:<12} | {n:>12} | " + " | ".join(cells) + " |")
    cells = [f"{t[1] / t[0]:>22.3f}" if t[0] else f"{'-':>22}" for t in totals.values()]
    print(f"| {'ALL':<12} | {totals['core_single'][0]:>12} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()

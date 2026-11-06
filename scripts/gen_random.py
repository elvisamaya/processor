#!/usr/bin/env python3
"""gen_random.py - generate a random (but always terminating) RV32I program.

Hand-written tests only cover the cases someone thought of. Random programs
throw thousands of instruction combinations at the core - especially
back-to-back dependencies, loads followed by uses, and branches right after
the instruction that sets their operands - which is where pipeline bugs hide.
The golden model (rviss.py) provides the expected result, so no one has to
work out the answers by hand.

    python3 scripts/gen_random.py --seed 3 -o build/random_3.s

Rules that keep every program legal and finite:
  * s0 (x8) is a fixed base pointer for loads/stores; it is never overwritten
  * t6 (x31) is reserved as a loop counter
  * branches and jumps only go forward, except small counted loops
  * memory accesses are naturally aligned, inside a 256-byte window
"""
import argparse
import random

POOL = [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12]     # small pool -> lots of dependencies
R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
BR_OPS = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOADS = [("lb", 1), ("lh", 2), ("lw", 4), ("lbu", 1), ("lhu", 2)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.lines = []
        self.label_n = 0

    def reg(self, allow_zero=True):
        if allow_zero and self.r.random() < 0.05:
            return "x0"
        return f"x{self.r.choice(POOL)}"

    def dst(self):
        return "x0" if self.r.random() < 0.03 else f"x{self.r.choice(POOL)}"

    def label(self):
        self.label_n += 1
        return f"L{self.label_n}"

    def emit(self, s):
        self.lines.append("        " + s)

    def one(self, in_loop=False):
        """Emit one random instruction (or a small group)."""
        r = self.r
        kind = r.choices(
            ["r", "i", "sh", "lui", "auipc", "load", "store", "branch", "jal", "loop"],
            weights=[25, 18, 6, 2, 2, 14, 10, 12, 3, 0 if in_loop else 3])[0]
        if kind == "r":
            self.emit(f"{r.choice(R_OPS)} {self.dst()}, {self.reg()}, {self.reg()}")
        elif kind == "i":
            self.emit(f"{r.choice(I_OPS)} {self.dst()}, {self.reg()}, {r.randint(-2048, 2047)}")
        elif kind == "sh":
            self.emit(f"{r.choice(SH_OPS)} {self.dst()}, {self.reg()}, {r.randint(0, 31)}")
        elif kind == "lui":
            self.emit(f"lui {self.dst()}, {r.randint(0, 0xFFFFF)}")
        elif kind == "auipc":
            self.emit(f"auipc {self.dst()}, {r.randint(0, 0xFFFFF)}")
        elif kind == "load":
            op, size = r.choice(LOADS)
            self.emit(f"{op} {self.dst()}, {r.randrange(0, 256, size)}(s0)")
        elif kind == "store":
            op, size = r.choice(STORES)
            self.emit(f"{op} {self.reg()}, {r.randrange(0, 256, size)}(s0)")
        elif kind == "branch":                       # forward branch over 1-3 instructions
            target = self.label()
            self.emit(f"{r.choice(BR_OPS)} {self.reg()}, {self.reg()}, {target}")
            for _ in range(r.randint(1, 3)):
                self.one(in_loop=True)
            self.lines.append(f"{target}:")
        elif kind == "jal":                          # forward jump, link register used later
            target = self.label()
            self.emit(f"jal {self.dst()}, {target}")
            for _ in range(r.randint(1, 2)):
                self.one(in_loop=True)
            self.lines.append(f"{target}:")
        elif kind == "loop":                         # small counted loop (backward branch)
            top = self.label()
            self.emit(f"li t6, {r.randint(2, 6)}")
            self.lines.append(f"{top}:")
            for _ in range(r.randint(2, 6)):
                self.one(in_loop=True)
            self.emit("addi t6, t6, -1")
            self.emit(f"bnez t6, {top}")

    def program(self, length):
        self.lines.append(f"# random program, {length} items")
        self.emit("li s0, 0x800")
        for reg in POOL:                             # random starting values
            self.emit(f"li x{reg}, {self.r.randint(-2**31, 2**31 - 1)}")
        for i in range(0, 256, 4):                   # random memory contents
            self.emit(f"li x1, {self.r.randint(-2**31, 2**31 - 1)}")
            self.emit(f"sw x1, {i}(s0)")
        for _ in range(length):
            self.one()
        self.emit("ecall")
        return "\n".join(self.lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--length", type=int, default=400)
    ap.add_argument("-o", "--output", required=True)
    a = ap.parse_args()
    with open(a.output, "w") as f:
        f.write(Gen(a.seed).program(a.length))


if __name__ == "__main__":
    main()

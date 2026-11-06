#!/usr/bin/env python3
"""rviss.py - RV32I instruction-set simulator (the "golden model").

Runs a program one instruction at a time, exactly as the ISA spec describes,
with no notion of clocks or pipelines. Its final state is the answer the
hardware must match:

    python3 scripts/rviss.py build/fib.hex --out build/fib

writes
    build/fib.regs   final x0..x31, one hex word per line
    build/fib.dmem   final data memory, one hex word per line
    build/fib.count  number of instructions executed (hex)

Memory model matches the hardware: separate 4 KiB instruction and data
memories, data addresses wrap at 4 KiB, ECALL/EBREAK stop the program.
"""
import argparse
import sys

MASK = 0xFFFFFFFF
DMEM_BYTES = 4096
IMEM_WORDS = 1024


def sext(value, bits):
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def signed(x):
    return x - (1 << 32) if x & 0x80000000 else x


class ISS:
    def __init__(self, program):
        self.imem = program + [0] * (IMEM_WORDS - len(program))
        self.dmem = bytearray(DMEM_BYTES)
        self.x = [0] * 32
        self.pc = 0
        self.count = 0

    # ---- memory helpers (little-endian) ----
    def load(self, addr, size, is_signed):
        addr &= DMEM_BYTES - 1
        val = int.from_bytes(self.dmem[addr:addr + size], "little")
        return sext(val, 8 * size) & MASK if is_signed else val

    def store(self, addr, size, val):
        addr &= DMEM_BYTES - 1
        self.dmem[addr:addr + size] = (val & ((1 << (8 * size)) - 1)).to_bytes(size, "little")

    def step(self):
        ins = self.imem[(self.pc >> 2) % IMEM_WORDS]
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 0x7
        rs1 = self.x[(ins >> 15) & 0x1F]
        rs2 = self.x[(ins >> 20) & 0x1F]
        f7 = ins >> 25
        imm_i = sext(ins >> 20, 12)
        imm_s = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        imm_b = sext((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                     (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        imm_u = ins & 0xFFFFF000
        imm_j = sext((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                     (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)

        next_pc = (self.pc + 4) & MASK
        result = None
        self.count += 1

        if op == 0b0110111:                         # LUI
            result = imm_u
        elif op == 0b0010111:                       # AUIPC
            result = (self.pc + imm_u) & MASK
        elif op == 0b1101111:                       # JAL
            result = next_pc
            next_pc = (self.pc + imm_j) & MASK
        elif op == 0b1100111:                       # JALR
            result = next_pc
            next_pc = (rs1 + imm_i) & MASK & ~1
        elif op == 0b1100011:                       # branches
            taken = {0: rs1 == rs2, 1: rs1 != rs2,
                     4: signed(rs1) < signed(rs2), 5: signed(rs1) >= signed(rs2),
                     6: rs1 < rs2, 7: rs1 >= rs2}.get(f3)
            if taken is None:
                raise RuntimeError(f"illegal branch at pc={self.pc:#x}")
            if taken:
                next_pc = (self.pc + imm_b) & MASK
        elif op == 0b0000011:                       # loads
            addr = (rs1 + imm_i) & MASK
            size, sgn = {0: (1, True), 1: (2, True), 2: (4, False),
                         4: (1, False), 5: (2, False)}[f3]
            result = self.load(addr, size, sgn)
        elif op == 0b0100011:                       # stores
            addr = (rs1 + imm_s) & MASK
            self.store(addr, {0: 1, 1: 2, 2: 4}[f3], rs2)
        elif op in (0b0010011, 0b0110011):          # ALU immediate / register
            b = imm_i & MASK if op == 0b0010011 else rs2
            sh = b & 0x1F
            alt = (f7 >> 5) & 1
            if f3 == 0:
                result = (rs1 - b) if (op == 0b0110011 and alt) else (rs1 + b)
            elif f3 == 1: result = rs1 << sh
            elif f3 == 2: result = int(signed(rs1) < signed(b))
            elif f3 == 3: result = int(rs1 < b)
            elif f3 == 4: result = rs1 ^ b
            elif f3 == 5: result = (signed(rs1) >> sh) if alt else (rs1 >> sh)
            elif f3 == 6: result = rs1 | b
            else:         result = rs1 & b
            result &= MASK
        elif op == 0b0001111:                       # FENCE: no-op
            pass
        elif ins in (0x00000073, 0x00100073):       # ECALL / EBREAK
            return False
        else:
            raise RuntimeError(f"illegal instruction {ins:08x} at pc={self.pc:#x}")

        if result is not None and rd != 0:
            self.x[rd] = result & MASK
        self.pc = next_pc
        return True

    def run(self, max_steps, trace=False):
        while True:
            pc = self.pc
            running = self.step()
            if trace:
                print(f"{self.count:6d}  pc={pc:08x}  ins={self.imem[(pc >> 2) % IMEM_WORDS]:08x}")
            if not running:
                return
            if self.count >= max_steps:
                raise RuntimeError(f"no ECALL after {max_steps} instructions (infinite loop?)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("hex")
    ap.add_argument("--out", required=True, help="output prefix")
    ap.add_argument("--max-steps", type=int, default=200000)
    ap.add_argument("--trace", action="store_true")
    a = ap.parse_args()

    program = [int(line, 16) for line in open(a.hex) if line.strip()]
    iss = ISS(program)
    try:
        iss.run(a.max_steps, a.trace)
    except RuntimeError as e:
        sys.exit(f"{a.hex}: {e}")

    with open(a.out + ".regs", "w") as f:
        f.writelines(f"{v:08x}\n" for v in iss.x)
    with open(a.out + ".dmem", "w") as f:
        for i in range(0, DMEM_BYTES, 4):
            f.write(f"{int.from_bytes(iss.dmem[i:i + 4], 'little'):08x}\n")
    with open(a.out + ".count", "w") as f:
        f.write(f"{iss.count:08x}\n")
    print(f"{a.hex}: {iss.count} instructions, a0 = {signed(iss.x[10])}")


if __name__ == "__main__":
    main()

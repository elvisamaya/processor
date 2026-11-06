# arith.s - every ALU instruction, with values chosen to hit the edge cases
# (negative numbers, overflow, shifts by 0 and 31, signed vs unsigned compare).
# Each result is also stored to memory starting at 0x100.

        li   s0, 0x100          # result pointer

        li   t0, 0x7FFFFFFF     # largest positive int
        li   t1, -1             # 0xFFFFFFFF
        li   t2, 0x80000000     # most negative int
        li   t3, 5
        li   t4, -7

        add  a0, t0, t3         # overflow wraps to negative
        sw   a0, 0(s0)
        sub  a0, t2, t3         # wraps to positive
        sw   a0, 4(s0)
        sub  a0, t3, t4         # 5 - (-7) = 12
        sw   a0, 8(s0)
        addi a0, t4, -2048      # most negative 12-bit immediate
        sw   a0, 12(s0)
        addi a0, t3, 2047       # most positive 12-bit immediate
        sw   a0, 16(s0)

        and  a0, t1, t0
        sw   a0, 20(s0)
        or   a0, t2, t3
        sw   a0, 24(s0)
        xor  a0, t1, t3
        sw   a0, 28(s0)
        andi a0, t1, 0x0F0
        sw   a0, 32(s0)
        ori  a0, t3, -16        # immediate is sign-extended
        sw   a0, 36(s0)
        xori a0, t3, -1         # bitwise NOT
        sw   a0, 40(s0)

        slt  a0, t4, t3         # -7 < 5 signed      -> 1
        sw   a0, 44(s0)
        sltu a0, t4, t3         # 0xFFFFFFF9 < 5 unsigned -> 0
        sw   a0, 48(s0)
        slt  a0, t2, t0         # min < max          -> 1
        sw   a0, 52(s0)
        slti a0, t4, -6         # -7 < -6            -> 1
        sw   a0, 56(s0)
        sltiu a0, t3, -1        # 5 < 0xFFFFFFFF     -> 1
        sw   a0, 60(s0)
        sltiu a0, zero, 1       # seqz idiom         -> 1
        sw   a0, 64(s0)

        li   t5, 31
        sll  a0, t3, t5         # 5 << 31
        sw   a0, 68(s0)
        srl  a0, t2, t5         # logical: 1
        sw   a0, 72(s0)
        sra  a0, t2, t5         # arithmetic: -1
        sw   a0, 76(s0)
        li   t6, 33             # only the low 5 bits count -> shift by 1
        sll  a0, t3, t6
        sw   a0, 80(s0)
        slli a0, t1, 0
        sw   a0, 84(s0)
        srli a0, t4, 4
        sw   a0, 88(s0)
        srai a0, t4, 1          # -7 >> 1 = -4
        sw   a0, 92(s0)

        lui  a0, 0xDEADB
        sw   a0, 96(s0)
        auipc a1, 0             # a1 = address of this instruction
        sw   a1, 100(s0)
        li   a2, 0x12345678     # lui + addi with a negative low part
        sw   a2, 104(s0)
        li   a3, 0xFFFFF800
        sw   a3, 108(s0)

        addi zero, t3, 1        # writes to x0 are discarded
        add  a4, zero, zero
        sw   a4, 112(s0)

        ecall

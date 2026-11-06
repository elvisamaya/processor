# hazards.s - back-to-back dependencies that a pipeline must handle:
# results used 1, 2 and 3 instructions later, load-use, a load feeding a
# store and a branch, and a JAL link register used immediately.
# A single-cycle core runs this trivially; a pipeline only gets it right
# with correct stalling or forwarding.

        li   s0, 0x500

        # distance-1, -2, -3 dependencies through a chain
        li   t0, 1
        addi t1, t0, 1          # uses t0 from 1 instr ago  -> 2
        add  t2, t1, t0         # t1 (1 ago), t0 (2 ago)     -> 3
        add  t3, t2, t1         # t2 (1 ago), t1 (2 ago)     -> 5
        add  t4, t3, t0         # t0 from far back           -> 6
        add  t4, t4, t4         # same register both sides   -> 12
        add  t4, t4, t4         # -> 24

        # the most recent write must win (two writes in flight to s1)
        li   s1, 111
        li   s1, 222
        add  s2, s1, zero       # must see 222

        # load-use: loaded value needed by the very next instruction
        sw   t4, 0(s0)
        lw   a0, 0(s0)
        addi a1, a0, 1          # 25
        lw   a2, 0(s0)
        add  a3, a2, a2         # both operands from the load -> 48

        # load feeding a store (as the data and as the address)
        li   t5, 0x504
        sw   t5, 8(s0)
        lw   a4, 8(s0)          # a4 = 0x504
        sw   a1, 0(a4)          # store to address from the load
        lw   a5, 0(a4)          # 25
        lw   a6, 0(s0)
        sw   a6, 12(s0)         # load result as store data

        # load feeding a branch
        lw   t6, 0(s0)
        bnez t6, taken1
        addi s3, s3, 100        # must be skipped
taken1: addi s3, s3, 1

        # x0 is never forwarded: writes to x0 must stay invisible
        addi zero, zero, 55
        add  s4, zero, zero     # 0

        # JAL link used immediately
        jal  ra, next
next:   addi s5, ra, 0          # address of 'next'

        # branch on a value computed just before
        li   t0, 5
        li   t1, 5
        sub  t2, t0, t1
        beqz t2, taken2
        addi s3, s3, 100
taken2: addi s3, s3, 1

        # loop with a dependency carried through memory
        li   t0, 10
        sw   zero, 16(s0)
memlp:  lw   t1, 16(s0)
        addi t1, t1, 3
        sw   t1, 16(s0)
        addi t0, t0, -1
        bnez t0, memlp
        lw   s6, 16(s0)         # 30

        ecall

# branches.s - every branch condition both taken and not taken, plus
# JAL/JALR calls and returns. s1 counts correct outcomes; any wrong path
# adds 100 to s2 so a mistake shows up in the final registers.

        li   s1, 0
        li   s2, 0
        li   t0, -1
        li   t1, 1

        beq  t1, t1, ok1        # taken
        addi s2, s2, 100
ok1:    addi s1, s1, 1
        beq  t0, t1, bad        # not taken
        addi s1, s1, 1

        bne  t0, t1, ok2        # taken
        addi s2, s2, 100
ok2:    addi s1, s1, 1
        bne  t1, t1, bad
        addi s1, s1, 1

        blt  t0, t1, ok3        # -1 < 1 signed: taken
        addi s2, s2, 100
ok3:    addi s1, s1, 1
        blt  t1, t0, bad
        addi s1, s1, 1

        bge  t1, t0, ok4        # 1 >= -1: taken
        addi s2, s2, 100
ok4:    addi s1, s1, 1
        bge  t0, t1, bad
        addi s1, s1, 1
        bge  t1, t1, ok5        # equal counts as >=
        addi s2, s2, 100
ok5:    addi s1, s1, 1

        bltu t1, t0, ok6        # 1 < 0xFFFFFFFF unsigned: taken
        addi s2, s2, 100
ok6:    addi s1, s1, 1
        bltu t0, t1, bad
        addi s1, s1, 1

        bgeu t0, t1, ok7        # taken
        addi s2, s2, 100
ok7:    addi s1, s1, 1
        bgeu t1, t0, bad
        addi s1, s1, 1

        # backward branch: count down from 10
        li   t2, 10
        li   t3, 0
loop:   addi t3, t3, 3
        addi t2, t2, -1
        bnez t2, loop           # t3 = 30

        # function call and return
        li   a0, 6
        call square             # a0 = 36
        mv   s3, a0
        li   a0, -9
        call square             # a0 = 81
        add  s3, s3, a0         # 117

        # computed jump through a register
        auipc t4, 0             # t4 = address of this instruction
        addi t4, t4, 16         # address of 'land' (4 instructions later)
        jalr ra, 0(t4)          # ra = address of next instruction
        addi s2, s2, 100        # skipped
land:   mv   s4, ra

        j    done
bad:    addi s2, s2, 100
done:   ecall

# square(a0) -> a0 * a0 by repeated addition (no multiplier in RV32I)
square: bgez a0, sq_pos
        neg  a0, a0
sq_pos: mv   t5, a0
        li   t6, 0
sq_lp:  beqz t5, sq_end
        add  t6, t6, a0
        addi t5, t5, -1
        j    sq_lp
sq_end: mv   a0, t6
        ret

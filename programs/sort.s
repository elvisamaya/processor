# sort.s - fill 32 words with pseudo-random values (linear congruential
# generator), then bubble sort them in place as signed integers.
# Lots of loads, stores, data-dependent branches and loop overhead.

        li   s1, 32             # number of elements
        li   s0, 0x400          # array base

        # x(n+1) = x(n) * 1103515245 + 12345, using shift-and-add (no MUL in RV32I)
        li   t0, 2024           # seed
        mv   t1, s0
        mv   t2, s1
fill:   li   a0, 1103515245
        li   a1, 0              # product
        mv   a2, t0
mul:    andi a3, a2, 1
        beqz a3, skip
        add  a1, a1, a0
skip:   slli a0, a0, 1
        srli a2, a2, 1
        bnez a2, mul
        li   a3, 12345
        add  t0, a1, a3
        sw   t0, 0(t1)
        addi t1, t1, 4
        addi t2, t2, -1
        bnez t2, fill

        # bubble sort
        addi s2, s1, -1         # outer passes
outer:  mv   t1, s0
        mv   t2, s2
        li   s3, 0              # swapped flag
inner:  lw   a0, 0(t1)
        lw   a1, 4(t1)
        ble  a0, a1, noswap
        sw   a1, 0(t1)
        sw   a0, 4(t1)
        li   s3, 1
noswap: addi t1, t1, 4
        addi t2, t2, -1
        bnez t2, inner
        beqz s3, sorted         # early exit if no swaps
        addi s2, s2, -1
        bnez s2, outer

        # verify: a0 = number of out-of-order neighbours (must be 0)
sorted: li   a0, 0
        mv   t1, s0
        addi t2, s1, -1
check:  lw   a1, 0(t1)
        lw   a2, 4(t1)
        ble  a1, a2, inorder
        addi a0, a0, 1
inorder: addi t1, t1, 4
        addi t2, t2, -1
        bnez t2, check
        ecall

# memory.s - byte, halfword and word loads and stores at every alignment,
# including sign extension of negative bytes and halfwords.

        li   s0, 0x200

        li   t0, 0x80FF7F01
        sw   t0, 0(s0)

        lb   a0, 0(s0)          # 0x01        -> 1
        lb   a1, 1(s0)          # 0x7F        -> 127
        lb   a2, 2(s0)          # 0xFF        -> -1
        lb   a3, 3(s0)          # 0x80        -> -128
        lbu  a4, 2(s0)          # 0xFF        -> 255
        lbu  a5, 3(s0)          # 0x80        -> 128
        lh   a6, 0(s0)          # 0x7F01      -> 32513
        lh   a7, 2(s0)          # 0x80FF      -> negative
        lhu  s2, 2(s0)          # 0x80FF      -> 33023
        lw   s3, 0(s0)

        # byte stores into a zeroed word, one lane at a time
        sb   t0, 4(s0)          # stores 0x01 to byte 0
        li   t1, 0xAB
        sb   t1, 5(s0)
        li   t1, 0xCD
        sb   t1, 6(s0)
        li   t1, 0xEF
        sb   t1, 7(s0)
        lw   s4, 4(s0)          # 0xEFCDAB01

        # halfword stores
        li   t1, 0x1234
        sh   t1, 8(s0)
        li   t1, -2             # 0xFFFE
        sh   t1, 10(s0)
        lw   s5, 8(s0)          # 0xFFFE1234

        # overwrite one byte in the middle of an existing word
        li   t1, 0x55
        sb   t1, 1(s0)
        lw   s6, 0(s0)          # 0x80FF5501

        # negative offsets
        addi s1, s0, 16
        sw   t0, -4(s1)         # writes 0x20C
        lw   s7, -4(s1)

        # copy a 4-word block with a loop
        li   t2, 4
        mv   t3, s0             # src
        addi t4, s0, 0x40       # dst
copy:   lw   t5, 0(t3)
        sw   t5, 0(t4)
        addi t3, t3, 4
        addi t4, t4, 4
        addi t2, t2, -1
        bnez t2, copy

        ecall

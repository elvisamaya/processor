# fib.s - first 30 Fibonacci numbers written to memory at 0x300.
# a0 holds fib(29) = 514229 at the end.

        li   s0, 0x300          # array base
        li   s1, 30             # count
        li   t0, 0              # fib(n-2)
        li   t1, 1              # fib(n-1)
        sw   t0, 0(s0)
        sw   t1, 4(s0)
        addi s0, s0, 8
        addi s1, s1, -2

loop:   add  t2, t0, t1         # fib(n)
        sw   t2, 0(s0)
        mv   t0, t1
        mv   t1, t2
        addi s0, s0, 4
        addi s1, s1, -1
        bnez s1, loop

        mv   a0, t1
        ecall

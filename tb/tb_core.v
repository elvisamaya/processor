// tb_core.v - runs one program on a core and compares the final state
// against the golden model (scripts/rviss.py):
//   - all 32 registers
//   - all 1024 words of data memory
//   - the number of instructions retired
//
// Plusargs:  +prog=build/fib   (expects fib.hex, fib.regs, fib.dmem, fib.count)
`timescale 1ns/1ps

module tb_core;
    localparam integer MAX_CYCLES = 200000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire        halted, illegal_seen;
    wire [31:0] cycles, instret;

    core_single dut (
        .clk(clk), .rst_n(rst_n), .halted(halted), .illegal_seen(illegal_seen),
        .cycles(cycles), .instret(instret)
    );

    reg [31:0]   exp_regs  [0:31];
    reg [31:0]   exp_dmem  [0:1023];
    reg [31:0]   exp_count [0:0];
    reg [8*200-1:0] prog;
    integer      i, errors = 0;

    initial begin
        if (!$value$plusargs("prog=%s", prog)) begin
            $display("usage: vvp tb_core.vvp +prog=build/<name>");
            $finish;
        end

        // fill instruction memory with NOPs, then load the program
        for (i = 0; i < 1024; i = i + 1) dut.u_imem.mem[i] = 32'h0000_0013;
        $readmemh({prog, ".hex"},   dut.u_imem.mem);
        $readmemh({prog, ".regs"},  exp_regs);
        $readmemh({prog, ".dmem"},  exp_dmem);
        $readmemh({prog, ".count"}, exp_count);

        if ($test$plusargs("vcd")) begin
            $dumpfile({prog, ".vcd"});
            $dumpvars(0, tb_core);
        end

        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;

        while (!halted && cycles < MAX_CYCLES) @(posedge clk);
        @(negedge clk);

        if (!halted) begin
            errors = errors + 1;
            $display("  ERROR: no ECALL within %0d cycles (pc stuck?)", MAX_CYCLES);
        end
        if (illegal_seen) begin
            errors = errors + 1;
            $display("  ERROR: an illegal instruction was executed");
        end
        for (i = 0; i < 32; i = i + 1)
            if (dut.u_rf.regs[i] !== exp_regs[i] && i != 0) begin
                errors = errors + 1;
                $display("  ERROR: x%0d = %h, expected %h", i, dut.u_rf.regs[i], exp_regs[i]);
            end
        for (i = 0; i < 1024; i = i + 1)
            if (dut.u_dmem.mem[i] !== exp_dmem[i]) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("  ERROR: mem[%h] = %h, expected %h", i * 4, dut.u_dmem.mem[i], exp_dmem[i]);
            end
        if (instret !== exp_count[0]) begin
            errors = errors + 1;
            $display("  ERROR: retired %0d instructions, golden model executed %0d",
                     instret, exp_count[0]);
        end

        $display("RESULT %0s instret=%0d cycles=%0d CPI=%0.3f errors=%0d",
                 prog, instret, cycles, 1.0 * cycles / instret, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule

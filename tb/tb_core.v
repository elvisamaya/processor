// tb_core.v - runs one program on a core and compares the final state
// against the golden model (scripts/rviss.py):
//   - all 32 registers
//   - all 1024 words of data memory
//   - the number of instructions retired
//
// Plusargs:  +prog=build/fib   (expects fib.hex, fib.regs, fib.dmem, fib.count)
// Defines:   -DPIPELINE selects core_pipe instead of core_single
`timescale 1ns/1ps

module tb_core;
    localparam integer MAX_CYCLES = 200000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    wire        halted, illegal_seen;
    wire [31:0] cycles, instret;

`ifdef PIPELINE
    core_pipe dut (
`else
    core_single dut (
`endif
        .clk(clk), .rst_n(rst_n), .halted(halted), .illegal_seen(illegal_seen),
        .cycles(cycles), .instret(instret)
    );

`ifdef PIPELINE
    // +trace: print which instruction (by PC) occupies each stage, every cycle.
    // "--" is an empty slot (bubble).
    function [8*6-1:0] slot(input valid, input [31:0] pc);
        slot = valid ? {"  ", hex4(pc)} : "    --";
    endfunction
    function [8*4-1:0] hex4(input [31:0] v);
        integer k; reg [3:0] nib;
        begin
            for (k = 0; k < 4; k = k + 1) begin
                nib = v >> (4 * (3 - k));
                hex4[8*(3-k) +: 8] = (nib < 10) ? ("0" + nib) : ("a" + nib - 10);
            end
        end
    endfunction
    reg [31:0] exmem_pc_t, memwb_pc_t;     // PCs tracked for display only
    always @(posedge clk) begin
        if (!dut.halted) begin
            memwb_pc_t <= exmem_pc_t;
            exmem_pc_t <= dut.idex_pc;
        end
    end
    always @(negedge clk) begin
        if ($test$plusargs("trace") && rst_n && !dut.halted)
            $display("%5d |%s |%s |%s |%s |%s | %0s%0s",
                     dut.cycles,
                     slot(!dut.fetch_stop, dut.pc),
                     slot(dut.ifid_valid,  dut.ifid_pc),
                     slot(dut.idex_valid,  dut.idex_pc),
                     slot(dut.exmem_valid, exmem_pc_t),
                     slot(dut.memwb_valid, memwb_pc_t),
                     dut.stall ? "stall (load-use / RAW) " : "",
                     dut.ex_redirect ? "taken -> flush IF,ID" : "");
    end
    initial if ($test$plusargs("trace"))
        $display("cycle |    IF |    ID |    EX |   MEM |    WB |");
`endif

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

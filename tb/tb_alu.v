// tb_alu.v - checks every ALU operation against a reference model:
// hand-picked corner cases first, then 20,000 random vectors.
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_alu;
    reg  [3:0]  op;
    reg  [31:0] a, b;
    wire [31:0] y;

    alu dut (.op(op), .a(a), .b(b), .y(y));

    integer errors = 0, checks = 0, seed = 11, i, k;

    // Reference model, written differently from the RTL on purpose
    function [31:0] model(input [3:0] f_op, input [31:0] x, input [31:0] z);
        integer sx, sz;
        reg [63:0] ext;
        begin
            sx = x; sz = z;                       // integer = signed 32-bit
            case (f_op)
                `ALU_ADD:  model = x + z;
                `ALU_SUB:  model = x + (~z + 1);  // two's complement subtract
                `ALU_SLL:  model = x << z[4:0];
                `ALU_SLT:  model = (sx < sz) ? 1 : 0;
                `ALU_SLTU: model = (x < z) ? 1 : 0;
                `ALU_XOR:  model = x ^ z;
                `ALU_SRL:  model = x >> z[4:0];
                `ALU_SRA:  begin ext = {{32{x[31]}}, x}; model = ext >> z[4:0]; end
                `ALU_OR:   model = x | z;
                `ALU_AND:  model = x & z;
                default:   model = 0;
            endcase
        end
    endfunction

    task check(input [3:0] t_op, input [31:0] t_a, input [31:0] t_b);
        begin
            op = t_op; a = t_a; b = t_b;
            #1;
            checks = checks + 1;
            if (y !== model(t_op, t_a, t_b)) begin
                errors = errors + 1;
                if (errors < 10)
                    $display("  ERROR: op=%0d a=%h b=%h -> y=%h, expected %h",
                             t_op, t_a, t_b, y, model(t_op, t_a, t_b));
            end
        end
    endtask

    reg [31:0] corners [0:7];
    initial begin
        corners[0] = 32'h0000_0000;  corners[1] = 32'h0000_0001;
        corners[2] = 32'hFFFF_FFFF;  corners[3] = 32'h8000_0000;
        corners[4] = 32'h7FFF_FFFF;  corners[5] = 32'h0000_001F;
        corners[6] = 32'h0000_0020;  corners[7] = 32'hDEAD_BEEF;

        // corner cases: every op x every pair of corner values
        for (k = 0; k <= 9; k = k + 1)
            for (i = 0; i < 64; i = i + 1)
                check(k[3:0], corners[i / 8], corners[i % 8]);

        // random vectors
        for (i = 0; i < 20000; i = i + 1)
            check({$random(seed)} % 10, $random(seed), $random(seed));

        $display("tb_alu: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule

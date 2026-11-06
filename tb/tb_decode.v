// tb_decode.v - immediate generator + decoder on real encoded instructions.
// Each instruction below was hand-encoded (or produced by scripts/rvasm.py)
// and the expected fields come from the RISC-V spec.
`timescale 1ns/1ps
`include "rv32i_defs.vh"

module tb_decode;
    reg  [31:0] instr;
    wire [31:0] imm;
    wire        reg_write, mem_read, mem_write, b_imm, branch, jal, jalr;
    wire        uses_rs1, uses_rs2, halt, illegal;
    wire [1:0]  wb_sel, a_sel;
    wire [3:0]  alu_op;

    imm_gen u_imm (.instr(instr), .imm(imm));
    decoder u_dec (
        .instr(instr), .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel(wb_sel), .a_sel(a_sel), .b_imm(b_imm), .alu_op(alu_op),
        .branch(branch), .jal(jal), .jalr(jalr), .uses_rs1(uses_rs1), .uses_rs2(uses_rs2),
        .halt(halt), .illegal(illegal)
    );

    integer errors = 0, n = 0;

    // ctrl = {reg_write, mem_read, mem_write, branch, jal, jalr, halt, illegal}
    task check(input [31:0] i, input [31:0] exp_imm, input [3:0] exp_op,
               input [7:0] exp_ctrl, input [8*24-1:0] name);
        reg [7:0] got;
        begin
            instr = i; #1; n = n + 1;
            got = {reg_write, mem_read, mem_write, branch, jal, jalr, halt, illegal};
            if (imm !== exp_imm || alu_op !== exp_op || got !== exp_ctrl) begin
                errors = errors + 1;
                $display("  ERROR %0s (%h): imm=%h/%h alu=%0d/%0d ctrl=%b/%b",
                         name, i, imm, exp_imm, alu_op, exp_op, got, exp_ctrl);
            end
        end
    endtask

    initial begin
        //            instruction    expected imm   alu op      ctrl         name
        check(32'hFFF00093, 32'hFFFF_FFFF, `ALU_ADD,  8'b1000_0000, "addi x1,x0,-1");
        check(32'h7FF10113, 32'h0000_07FF, `ALU_ADD,  8'b1000_0000, "addi x2,x2,2047");
        check(32'h40115193, 32'h0000_0401, `ALU_SRA,  8'b1000_0000, "srai x3,x2,1");
        check(32'h00115193, 32'h0000_0001, `ALU_SRL,  8'b1000_0000, "srli x3,x2,1");
        check(32'h403100B3, 32'h0000_0000, `ALU_SUB,  8'b1000_0000, "sub x1,x2,x3");
        check(32'h003120B3, 32'h0000_0000, `ALU_SLT,  8'b1000_0000, "slt x1,x2,x3");
        check(32'hABCDE0B7, 32'hABCD_E000, `ALU_ADD,  8'b1000_0000, "lui x1,0xABCDE");
        check(32'h00001117, 32'h0000_1000, `ALU_ADD,  8'b1000_0000, "auipc x2,1");
        check(32'hFFC12083, 32'hFFFF_FFFC, `ALU_ADD,  8'b1100_0000, "lw x1,-4(x2)");
        check(32'h00112423, 32'h0000_0008, `ALU_ADD,  8'b0010_0000, "sw x1,8(x2)");
        check(32'hFE208EE3, 32'hFFFF_FFFC, `ALU_ADD,  8'b0001_0000, "beq x1,x2,-4");
        check(32'h0020C463, 32'h0000_0008, `ALU_ADD,  8'b0001_0000, "blt x1,x2,8");
        check(32'h008000EF, 32'h0000_0008, `ALU_ADD,  8'b1000_1000, "jal ra,8");
        check(32'hFF9FF0EF, 32'hFFFF_FFF8, `ALU_ADD,  8'b1000_1000, "jal ra,-8");
        check(32'h00008067, 32'h0000_0000, `ALU_ADD,  8'b1000_0100, "jalr x0,0(ra)");
        check(32'h00000073, 32'h0000_0000, `ALU_ADD,  8'b0000_0010, "ecall");
        check(32'h00000000, 32'h0000_0000, `ALU_ADD,  8'b0000_0001, "illegal (all zero)");

        $display("tb_decode: %0d instructions, %0d errors", n, errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule

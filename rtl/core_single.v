// core_single.v
// Single-cycle RV32I core: every instruction is fetched, decoded, executed,
// accesses memory and writes back in ONE clock cycle. Simple and easy to
// reason about, but the clock period must cover the slowest instruction
// (a load: fetch -> decode -> register read -> ALU -> memory -> write-back).
//
//   pc -> imem -> decoder/regfile/imm -> ALU -> dmem -> write-back mux -> regfile
//
// Programs end with ECALL/EBREAK, which raises `halted`.
`timescale 1ns/1ps
`default_nettype none
`include "rv32i_defs.vh"

module core_single (
    input  wire        clk,
    input  wire        rst_n,
    output reg         halted,
    output reg         illegal_seen,
    output reg  [31:0] cycles,
    output reg  [31:0] instret      // instructions retired
);
    // ---------------- fetch ----------------
    reg  [31:0] pc;
    wire [31:0] instr;
    imem u_imem (.addr(pc), .instr(instr));

    // ---------------- decode ----------------
    wire        reg_write, mem_write, b_imm, branch, jal, jalr, halt, illegal;
    /* verilator lint_off UNUSEDSIGNAL */
    wire        mem_read, uses_rs1, uses_rs2;   // only needed by the pipeline's hazard logic
    /* verilator lint_on UNUSEDSIGNAL */
    wire [1:0]  wb_sel, a_sel;
    wire [3:0]  alu_op;
    decoder u_dec (
        .instr(instr), .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .wb_sel(wb_sel), .a_sel(a_sel), .b_imm(b_imm), .alu_op(alu_op),
        .branch(branch), .jal(jal), .jalr(jalr), .uses_rs1(uses_rs1), .uses_rs2(uses_rs2),
        .halt(halt), .illegal(illegal)
    );

    wire [31:0] imm;
    imm_gen u_imm (.instr(instr), .imm(imm));

    wire [31:0] rs1_val, rs2_val, wb_data;
    wire        rf_we = reg_write && !halted;
    regfile u_rf (
        .clk(clk), .we(rf_we), .waddr(instr[11:7]), .wdata(wb_data),
        .raddr1(instr[19:15]), .raddr2(instr[24:20]), .rdata1(rs1_val), .rdata2(rs2_val)
    );

    // ---------------- execute ----------------
    wire [31:0] alu_a = (a_sel == `A_PC)   ? pc    :
                        (a_sel == `A_ZERO) ? 32'd0 : rs1_val;
    wire [31:0] alu_b = b_imm ? imm : rs2_val;
    wire [31:0] alu_y;
    alu u_alu (.op(alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

    wire taken;
    branch_cmp u_br (.funct3(instr[14:12]), .a(rs1_val), .b(rs2_val), .taken(taken));

    wire [31:0] pc_plus4  = pc + 32'd4;
    wire [31:0] pc_target = pc + imm;                   // JAL and branches
    wire [31:0] next_pc   = jalr                ? {alu_y[31:1], 1'b0} :
                            (jal || (branch && taken)) ? pc_target   : pc_plus4;

    // ---------------- memory ----------------
    wire [31:0] mem_rdata, mem_wdata, load_data;
    wire [3:0]  mem_be;
    lsu u_lsu (
        .funct3(instr[14:12]), .addr_lo(alu_y[1:0]),
        .store_data(rs2_val), .mem_wdata(mem_wdata), .mem_be(mem_be),
        .mem_rdata(mem_rdata), .load_data(load_data)
    );
    dmem u_dmem (
        .clk(clk), .we(mem_write && !halted), .be(mem_be),
        .addr(alu_y), .wdata(mem_wdata), .rdata(mem_rdata)
    );

    // ---------------- write-back ----------------
    assign wb_data = (wb_sel == `WB_MEM) ? load_data :
                     (wb_sel == `WB_PC4) ? pc_plus4  : alu_y;

    // ---------------- state update ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc           <= 32'd0;
            halted       <= 1'b0;
            illegal_seen <= 1'b0;
            cycles       <= 32'd0;
            instret      <= 32'd0;
        end else if (!halted) begin
            pc      <= next_pc;
            cycles  <= cycles + 32'd1;
            instret <= instret + 32'd1;
            if (halt)    halted       <= 1'b1;
            if (illegal) illegal_seen <= 1'b1;
        end
    end
endmodule

`default_nettype wire

// tb_regfile.v - register file: x0 behaviour, write/read-back,
// write-through, and a random test against a reference array.
`timescale 1ns/1ps

module tb_regfile;
    reg         clk = 0, we = 0;
    reg  [4:0]  waddr = 0, raddr1 = 0, raddr2 = 0;
    reg  [31:0] wdata = 0;
    wire [31:0] rdata1, rdata2;

    regfile #(.BYPASS(1)) dut (.clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
                 .raddr1(raddr1), .raddr2(raddr2), .rdata1(rdata1), .rdata2(rdata2));

    always #5 clk = ~clk;

    reg [31:0] model [0:31];
    integer errors = 0, seed = 3, i;

    task expect_eq(input [31:0] got, input [31:0] exp, input [8*40-1:0] what);
        if (got !== exp) begin
            errors = errors + 1;
            if (errors < 10) $display("  ERROR @%0t: %0s = %h, expected %h", $time, what, got, exp);
        end
    endtask

    initial begin
        for (i = 0; i < 32; i = i + 1) model[i] = 0;

        // 1. writing x0 must have no effect
        @(negedge clk); we = 1; waddr = 0; wdata = 32'hFFFF_FFFF;
        @(negedge clk); we = 0; raddr1 = 0; raddr2 = 0; #1;
        expect_eq(rdata1, 0, "x0 port 1");
        expect_eq(rdata2, 0, "x0 port 2");

        // 2. write every register, read each back on both ports
        for (i = 1; i < 32; i = i + 1) begin
            @(negedge clk); we = 1; waddr = i; wdata = 32'h1000_0000 + i * 32'h0101;
            model[i] = wdata;
        end
        @(negedge clk); we = 0;
        for (i = 0; i < 32; i = i + 1) begin
            raddr1 = i; raddr2 = 31 - i; #1;
            expect_eq(rdata1, model[i], "read-back port 1");
            expect_eq(rdata2, model[31 - i], "read-back port 2");
        end

        // 3. write-through: reading the register being written returns the new value
        @(negedge clk); we = 1; waddr = 5; wdata = 32'hCAFE_F00D; raddr1 = 5; raddr2 = 6; #1;
        expect_eq(rdata1, 32'hCAFE_F00D, "write-through");
        expect_eq(rdata2, model[6], "unrelated register during write");
        model[5] = 32'hCAFE_F00D;

        // 4. random reads and writes
        for (i = 0; i < 5000; i = i + 1) begin
            @(negedge clk);
            we = $random(seed); waddr = $random(seed); wdata = $random(seed);
            raddr1 = $random(seed); raddr2 = $random(seed); #1;
            expect_eq(rdata1, (raddr1 == 0) ? 0 : (we && waddr == raddr1) ? wdata : model[raddr1], "random port 1");
            expect_eq(rdata2, (raddr2 == 0) ? 0 : (we && waddr == raddr2) ? wdata : model[raddr2], "random port 2");
            if (we && waddr != 0) model[waddr] = wdata;
        end

        $display("tb_regfile: %0d errors", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $finish;
    end
endmodule

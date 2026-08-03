timescale 1ns / 1ps

module riscv_5stage_tb;

    reg clk;
    reg reset;

    wire [31:0] debug_pc;
    wire [31:0] debug_wb_data;
    wire [4:0]  debug_wb_rd;
    wire        debug_wb_regwrite;

    riscv_5stage_core dut (
        .clk               (clk),
        .reset             (reset),
        .debug_pc          (debug_pc),
        .debug_wb_data     (debug_wb_data),
        .debug_wb_rd       (debug_wb_rd),
        .debug_wb_regwrite (debug_wb_regwrite)
    );

    // ============================================================
    // CLOCK
    // ============================================================

    always #5 clk = ~clk;

    // ============================================================
    // R-TYPE ENCODER
    // ============================================================

    function [31:0] encode_rtype;

        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin

            encode_rtype = {
                funct7,
                rs2,
                rs1,
                funct3,
                rd,
                7'b0110011
            };

        end

    endfunction

    // ============================================================
    // I-TYPE ENCODER
    // ============================================================

    function [31:0] encode_itype;

        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;

        begin

            encode_itype = {
                imm[11:0],
                rs1,
                funct3,
                rd,
                7'b0010011
            };

        end

    endfunction

    // ============================================================
    // LW ENCODER
    // ============================================================

    function [31:0] encode_lw;

        input integer imm;
        input [4:0] rs1;
        input [4:0] rd;

        begin

            encode_lw = {
                imm[11:0],
                rs1,
                3'b010,
                rd,
                7'b0000011
            };

        end

    endfunction

    // ============================================================
    // SW ENCODER
    // ============================================================

    function [31:0] encode_sw;

        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;

        begin

            encode_sw = {
                imm[11:5],
                rs2,
                rs1,
                3'b010,
                imm[4:0],
                7'b0100011
            };

        end

    endfunction

    // ============================================================
    // BEQ ENCODER
    // ============================================================

    function [31:0] encode_beq;

        input integer imm;
        input [4:0] rs1;
        input [4:0] rs2;

        begin

            encode_beq = {
                imm[12],
                imm[10:5],
                rs2,
                rs1,
                3'b000,
                imm[4:1],
                imm[11],
                7'b1100011
            };

        end

    endfunction

    // ============================================================
    // TEST PROGRAM
    // ============================================================

    initial begin

        clk   = 1'b0;
        reset = 1'b1;

        // --------------------------------------------------------
        // Instruction 1
        // ADDI x1, x0, 10
        // x1 = 10
        // --------------------------------------------------------

        dut.imem[0] = encode_itype(
            10,
            5'd0,
            3'b000,
            5'd1
        );

        // --------------------------------------------------------
        // Instruction 2
        // ADDI x2, x0, 20
        // x2 = 20
        // --------------------------------------------------------

        dut.imem[1] = encode_itype(
            20,
            5'd0,
            3'b000,
            5'd2
        );

        // --------------------------------------------------------
        // Instruction 3
        // ADD x3, x1, x2
        // x3 = 30
        // Tests forwarding
        // --------------------------------------------------------

        dut.imem[2] = encode_rtype(
            7'b0000000,
            5'd2,
            5'd1,
            3'b000,
            5'd3
        );

        // --------------------------------------------------------
        // Instruction 4
        // SUB x4, x3, x1
        // x4 = 20
        // Tests forwarding
        // --------------------------------------------------------

        dut.imem[3] = encode_rtype(
            7'b0100000,
            5'd1,
            5'd3,
            3'b000,
            5'd4
        );

        // --------------------------------------------------------
        // Instruction 5
        // SW x4, 0(x0)
        // memory[0] = 20
        // --------------------------------------------------------

        dut.imem[4] = encode_sw(
            0,
            5'd4,
            5'd0
        );

        // --------------------------------------------------------
        // Instruction 6
        // LW x5, 0(x0)
        // x5 = 20
        // --------------------------------------------------------

        dut.imem[5] = encode_lw(
            0,
            5'd0,
            5'd5
        );

        // --------------------------------------------------------
        // Instruction 7
        // ADD x6, x5, x1
        // x6 = 30
        // Tests load-use hazard
        // --------------------------------------------------------

        dut.imem[6] = encode_rtype(
            7'b0000000,
            5'd1,
            5'd5,
            3'b000,
            5'd6
        );

        // --------------------------------------------------------
        // Instruction 8
        // BEQ x6, x6, +8
        // Branch taken
        // --------------------------------------------------------

        dut.imem[7] = encode_beq(
            8,
            5'd6,
            5'd6
        );

        // --------------------------------------------------------
        // Instruction 9
        // This should be flushed
        // ADDI x7, x0, 999
        // --------------------------------------------------------

        dut.imem[8] = encode_itype(
            999,
            5'd0,
            3'b000,
            5'd7
        );

        // --------------------------------------------------------
        // Instruction 10
        // ADDI x8, x0, 100
        // --------------------------------------------------------

        dut.imem[9] = encode_itype(
            100,
            5'd0,
            3'b000,
            5'd8
        );

        // --------------------------------------------------------
        // Start processor
        // --------------------------------------------------------

        #20;

        reset = 1'b0;

        #300;

        // ========================================================
        // RESULTS
        // ========================================================

        $display("----------------------------------------");
        $display("5-STAGE RISC-V PROCESSOR TEST");
        $display("----------------------------------------");

        $display("x1  = %0d", dut.registers[1]);
        $display("x2  = %0d", dut.registers[2]);
        $display("x3  = %0d", dut.registers[3]);
        $display("x4  = %0d", dut.registers[4]);
        $display("x5  = %0d", dut.registers[5]);
        $display("x6  = %0d", dut.registers[6]);
        $display("x7  = %0d", dut.registers[7]);
        $display("x8  = %0d", dut.registers[8]);

        $display("Memory[0] = %0d", dut.dmem[0]);

        $display("----------------------------------------");

        if (
            dut.registers[1] == 10 &&
            dut.registers[2] == 20 &&
            dut.registers[3] == 30 &&
            dut.registers[4] == 20 &&
            dut.registers[5] == 20 &&
            dut.registers[6] == 30 &&
            dut.registers[7] == 0 &&
            dut.registers[8] == 100 &&
            dut.dmem[0] == 20
        )

            $display("TEST PASSED");

        else

            $display("TEST FAILED");

        $display("----------------------------------------");

        $finish;

    end

endmodule

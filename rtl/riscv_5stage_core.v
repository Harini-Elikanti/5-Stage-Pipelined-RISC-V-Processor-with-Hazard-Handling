`timescale 1ns / 1ps

module riscv_5stage_core #(
    parameter IMEM_DEPTH = 256,
    parameter DMEM_DEPTH = 256
)(
    input clk,
    input reset,

    output [31:0] debug_pc,
    output [31:0] debug_wb_data,
    output [4:0]  debug_wb_rd,
    output        debug_wb_regwrite
);

    // ============================================================
    // OPCODES
    // ============================================================

    localparam [6:0] OPCODE_RTYPE  = 7'b0110011;
    localparam [6:0] OPCODE_ITYPE  = 7'b0010011;
    localparam [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam [6:0] OPCODE_STORE  = 7'b0100011;
    localparam [6:0] OPCODE_BRANCH = 7'b1100011;

    // ============================================================
    // ALU CONTROL
    // ============================================================

    localparam [3:0] ALU_ADD = 4'b0000;
    localparam [3:0] ALU_SUB = 4'b0001;
    localparam [3:0] ALU_AND = 4'b0010;
    localparam [3:0] ALU_OR  = 4'b0011;
    localparam [3:0] ALU_XOR = 4'b0100;

    // ============================================================
    // PROGRAM COUNTER
    // ============================================================

    reg [31:0] pc;
    wire [31:0] pc_next;

    assign debug_pc = pc;

    // ============================================================
    // INSTRUCTION MEMORY
    // ============================================================

    reg [31:0] imem [0:IMEM_DEPTH-1];

    wire [31:0] instruction;

    assign instruction = imem[pc[9:2]];

    // ============================================================
    // IF/ID PIPELINE REGISTER
    // ============================================================

    reg [31:0] ifid_pc;
    reg [31:0] ifid_pc4;
    reg [31:0] ifid_instruction;

    // ============================================================
    // INSTRUCTION DECODE
    // ============================================================

    wire [6:0] opcode;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [6:0] funct7;

    assign opcode = ifid_instruction[6:0];
    assign rd     = ifid_instruction[11:7];
    assign funct3 = ifid_instruction[14:12];
    assign rs1    = ifid_instruction[19:15];
    assign rs2    = ifid_instruction[24:20];
    assign funct7 = ifid_instruction[31:25];

    // ============================================================
    // CONTROL SIGNALS
    // ============================================================

    reg       ctrl_regwrite;
    reg       ctrl_memread;
    reg       ctrl_memwrite;
    reg       ctrl_memtoreg;
    reg       ctrl_alusrc;
    reg       ctrl_branch;
    reg [3:0] ctrl_alucontrol;

    reg use_rs1;
    reg use_rs2;

    always @(*) begin

        ctrl_regwrite   = 1'b0;
        ctrl_memread    = 1'b0;
        ctrl_memwrite   = 1'b0;
        ctrl_memtoreg   = 1'b0;
        ctrl_alusrc     = 1'b0;
        ctrl_branch     = 1'b0;
        ctrl_alucontrol = ALU_ADD;

        use_rs1 = 1'b0;
        use_rs2 = 1'b0;

        case (opcode)

            // ====================================================
            // R-TYPE
            // ====================================================

            OPCODE_RTYPE: begin

                ctrl_regwrite = 1'b1;

                use_rs1 = 1'b1;
                use_rs2 = 1'b1;

                case (funct3)

                    3'b000: begin

                        if (funct7 == 7'b0100000)
                            ctrl_alucontrol = ALU_SUB;
                        else
                            ctrl_alucontrol = ALU_ADD;

                    end

                    3'b111:
                        ctrl_alucontrol = ALU_AND;

                    3'b110:
                        ctrl_alucontrol = ALU_OR;

                    3'b100:
                        ctrl_alucontrol = ALU_XOR;

                    default:
                        ctrl_alucontrol = ALU_ADD;

                endcase

            end

            // ====================================================
            // ADDI
            // ====================================================

            OPCODE_ITYPE: begin

                ctrl_regwrite = 1'b1;
                ctrl_alusrc   = 1'b1;

                use_rs1 = 1'b1;

                ctrl_alucontrol = ALU_ADD;

            end

            // ====================================================
            // LW
            // ====================================================

            OPCODE_LOAD: begin

                ctrl_regwrite = 1'b1;
                ctrl_memread  = 1'b1;
                ctrl_memtoreg = 1'b1;
                ctrl_alusrc   = 1'b1;

                use_rs1 = 1'b1;

                ctrl_alucontrol = ALU_ADD;

            end

            // ====================================================
            // SW
            // ====================================================

            OPCODE_STORE: begin

                ctrl_memwrite = 1'b1;
                ctrl_alusrc   = 1'b1;

                use_rs1 = 1'b1;
                use_rs2 = 1'b1;

                ctrl_alucontrol = ALU_ADD;

            end

            // ====================================================
            // BEQ
            // ====================================================

            OPCODE_BRANCH: begin

                if (funct3 == 3'b000) begin

                    ctrl_branch = 1'b1;

                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;

                    ctrl_alucontrol = ALU_SUB;

                end

            end

            default: begin
            end

        endcase

    end

    // ============================================================
    // IMMEDIATE GENERATOR
    // ============================================================

    reg [31:0] immediate;

    always @(*) begin

        case (opcode)

            // I-Type
            OPCODE_ITYPE,
            OPCODE_LOAD: begin

                immediate = {
                    {20{ifid_instruction[31]}},
                    ifid_instruction[31:20]
                };

            end

            // S-Type
            OPCODE_STORE: begin

                immediate = {
                    {20{ifid_instruction[31]}},
                    ifid_instruction[31:25],
                    ifid_instruction[11:7]
                };

            end

            // B-Type
            OPCODE_BRANCH: begin

                immediate = {
                    {19{ifid_instruction[31]}},
                    ifid_instruction[31],
                    ifid_instruction[7],
                    ifid_instruction[30:25],
                    ifid_instruction[11:8],
                    1'b0
                };

            end

            default:
                immediate = 32'b0;

        endcase

    end

    // ============================================================
    // REGISTER FILE
    // ============================================================

    reg [31:0] registers [0:31];

    wire [31:0] reg_read_data1;
    wire [31:0] reg_read_data2;

    // ============================================================
    // WRITEBACK SIGNALS
    // ============================================================

    reg [31:0] memwb_alu_result;
    reg [31:0] memwb_memory_data;
    reg [4:0]  memwb_rd;

    reg        memwb_regwrite;
    reg        memwb_memtoreg;

    wire [31:0] wb_data;

    assign wb_data =
        memwb_memtoreg ? memwb_memory_data :
                         memwb_alu_result;

   assign reg_read_data1 =
        (rs1 == 5'd0) ? 32'b0 :
        (memwb_regwrite && (memwb_rd == rs1)) ? wb_data :
        registers[rs1];

assign reg_read_data2 =
        (rs2 == 5'd0) ? 32'b0 :
        (memwb_regwrite && (memwb_rd == rs2)) ? wb_data :
        registers[rs2];

    assign debug_wb_data     = wb_data;
    assign debug_wb_rd       = memwb_rd;
    assign debug_wb_regwrite = memwb_regwrite;

    // ============================================================
    // ID/EX PIPELINE REGISTER
    // ============================================================

    reg [31:0] idex_pc;
    reg [31:0] idex_read_data1;
    reg [31:0] idex_read_data2;
    reg [31:0] idex_immediate;

    reg [4:0] idex_rs1;
    reg [4:0] idex_rs2;
    reg [4:0] idex_rd;

    reg       idex_regwrite;
    reg       idex_memread;
    reg       idex_memwrite;
    reg       idex_memtoreg;
    reg       idex_alusrc;
    reg       idex_branch;

    reg [3:0] idex_alucontrol;

    // ============================================================
    // EX/MEM PIPELINE REGISTER
    // ============================================================

    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_write_data;

    reg [4:0] exmem_rd;

    reg       exmem_regwrite;
    reg       exmem_memread;
    reg       exmem_memwrite;
    reg       exmem_memtoreg;

    // ============================================================
    // FORWARDING UNIT
    // ============================================================

    reg [1:0] forward_a;
    reg [1:0] forward_b;

    always @(*) begin

        forward_a = 2'b00;
        forward_b = 2'b00;

        // EX/MEM -> EX

        if (exmem_regwrite &&
            !exmem_memread &&
            (exmem_rd != 5'd0) &&
            (exmem_rd == idex_rs1)) begin

            forward_a = 2'b10;

        end
        else if (memwb_regwrite &&
                 (memwb_rd != 5'd0) &&
                 (memwb_rd == idex_rs1)) begin

            forward_a = 2'b01;

        end

        if (exmem_regwrite &&
            !exmem_memread &&
            (exmem_rd != 5'd0) &&
            (exmem_rd == idex_rs2)) begin

            forward_b = 2'b10;

        end
        else if (memwb_regwrite &&
                 (memwb_rd != 5'd0) &&
                 (memwb_rd == idex_rs2)) begin

            forward_b = 2'b01;

        end

    end

    // ============================================================
    // EX STAGE
    // ============================================================

    reg [31:0] ex_operand_a;
    reg [31:0] ex_forwarded_b;
    reg [31:0] ex_alu_b;
    reg [31:0] ex_alu_result;

    wire ex_zero;

    always @(*) begin

        case (forward_a)

            2'b00:
                ex_operand_a = idex_read_data1;

            2'b01:
                ex_operand_a = wb_data;

            2'b10:
                ex_operand_a = exmem_alu_result;

            default:
                ex_operand_a = idex_read_data1;

        endcase

        case (forward_b)

            2'b00:
                ex_forwarded_b = idex_read_data2;

            2'b01:
                ex_forwarded_b = wb_data;

            2'b10:
                ex_forwarded_b = exmem_alu_result;

            default:
                ex_forwarded_b = idex_read_data2;

        endcase

        if (idex_alusrc)
            ex_alu_b = idex_immediate;
        else
            ex_alu_b = ex_forwarded_b;

    end

    always @(*) begin

        case (idex_alucontrol)

            ALU_ADD:
                ex_alu_result = ex_operand_a + ex_alu_b;

            ALU_SUB:
                ex_alu_result = ex_operand_a - ex_alu_b;

            ALU_AND:
                ex_alu_result = ex_operand_a & ex_alu_b;

            ALU_OR:
                ex_alu_result = ex_operand_a | ex_alu_b;

            ALU_XOR:
                ex_alu_result = ex_operand_a ^ ex_alu_b;

            default:
                ex_alu_result = 32'b0;

        endcase

    end

    assign ex_zero = (ex_alu_result == 32'b0);

    // ============================================================
    // BRANCH LOGIC
    // ============================================================

    wire        branch_taken;
    wire [31:0] branch_target;

    assign branch_taken =
        idex_branch && ex_zero;

    assign branch_target =
        idex_pc + idex_immediate;

    // ============================================================
    // DATA MEMORY
    // ============================================================

    reg [31:0] dmem [0:DMEM_DEPTH-1];

    wire [31:0] memory_read_data;

    assign memory_read_data =
        dmem[exmem_alu_result[9:2]];

    // ============================================================
    // HAZARD DETECTION
    // ============================================================

    wire load_use_hazard;

    assign load_use_hazard =
        idex_memread &&
        (idex_rd != 5'd0) &&
        (
            (use_rs1 && (idex_rd == rs1)) ||
            (use_rs2 && (idex_rd == rs2))
        );

    // ============================================================
    // NEXT PC
    // ============================================================

    assign pc_next =
        branch_taken ?
        branch_target :
        pc + 32'd4;

    // ============================================================
    // SEQUENTIAL PIPELINE
    // ============================================================

    integer i;

    always @(posedge clk) begin

        if (reset) begin

            pc <= 32'b0;

            ifid_pc          <= 32'b0;
            ifid_pc4         <= 32'b0;
            ifid_instruction <= 32'h00000013;

            idex_pc         <= 32'b0;
            idex_read_data1 <= 32'b0;
            idex_read_data2 <= 32'b0;
            idex_immediate  <= 32'b0;

            idex_rs1 <= 5'b0;
            idex_rs2 <= 5'b0;
            idex_rd  <= 5'b0;

            idex_regwrite   <= 1'b0;
            idex_memread    <= 1'b0;
            idex_memwrite   <= 1'b0;
            idex_memtoreg   <= 1'b0;
            idex_alusrc     <= 1'b0;
            idex_branch     <= 1'b0;
            idex_alucontrol <= ALU_ADD;

            exmem_alu_result <= 32'b0;
            exmem_write_data <= 32'b0;
            exmem_rd         <= 5'b0;

            exmem_regwrite <= 1'b0;
            exmem_memread  <= 1'b0;
            exmem_memwrite <= 1'b0;
            exmem_memtoreg <= 1'b0;

            memwb_alu_result  <= 32'b0;
            memwb_memory_data <= 32'b0;
            memwb_rd          <= 5'b0;

            memwb_regwrite <= 1'b0;
            memwb_memtoreg <= 1'b0;

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'b0;

        end
        else begin

            // ====================================================
            // WRITEBACK
            // ====================================================

            if (memwb_regwrite && (memwb_rd != 5'd0))
                registers[memwb_rd] <= wb_data;

            registers[0] <= 32'b0;

            // ====================================================
            // MEMORY WRITE
            // ====================================================

            if (exmem_memwrite)
                dmem[exmem_alu_result[9:2]] <= exmem_write_data;

            // ====================================================
            // MEM/WB
            // ====================================================

            memwb_alu_result  <= exmem_alu_result;
            memwb_memory_data <= memory_read_data;
            memwb_rd          <= exmem_rd;

            memwb_regwrite <= exmem_regwrite;
            memwb_memtoreg <= exmem_memtoreg;

            // ====================================================
            // EX/MEM
            // ====================================================

            exmem_alu_result <= ex_alu_result;
            exmem_write_data <= ex_forwarded_b;
            exmem_rd         <= idex_rd;

            exmem_regwrite <= idex_regwrite;
            exmem_memread  <= idex_memread;
            exmem_memwrite <= idex_memwrite;
            exmem_memtoreg <= idex_memtoreg;

            // ====================================================
            // ID/EX
            // ====================================================

            if (branch_taken || load_use_hazard) begin

                // Insert bubble

                idex_pc         <= 32'b0;
                idex_read_data1 <= 32'b0;
                idex_read_data2 <= 32'b0;
                idex_immediate  <= 32'b0;

                idex_rs1 <= 5'b0;
                idex_rs2 <= 5'b0;
                idex_rd  <= 5'b0;

                idex_regwrite   <= 1'b0;
                idex_memread    <= 1'b0;
                idex_memwrite   <= 1'b0;
                idex_memtoreg   <= 1'b0;
                idex_alusrc     <= 1'b0;
                idex_branch     <= 1'b0;
                idex_alucontrol <= ALU_ADD;

            end
            else begin

                idex_pc         <= ifid_pc;
                idex_read_data1 <= reg_read_data1;
                idex_read_data2 <= reg_read_data2;
                idex_immediate  <= immediate;

                idex_rs1 <= rs1;
                idex_rs2 <= rs2;
                idex_rd  <= rd;

                idex_regwrite   <= ctrl_regwrite;
                idex_memread    <= ctrl_memread;
                idex_memwrite   <= ctrl_memwrite;
                idex_memtoreg   <= ctrl_memtoreg;
                idex_alusrc     <= ctrl_alusrc;
                idex_branch     <= ctrl_branch;
                idex_alucontrol <= ctrl_alucontrol;

            end

            // ====================================================
            // IF/ID
            // ====================================================

            if (branch_taken) begin

                // Flush wrong-path instruction

                ifid_pc          <= 32'b0;
                ifid_pc4         <= 32'b0;
                ifid_instruction <= 32'h00000013;

            end
            else if (!load_use_hazard) begin

                ifid_pc          <= pc;
                ifid_pc4         <= pc + 32'd4;
                ifid_instruction <= instruction;

            end

            // ====================================================
            // PC
            // ====================================================

            if (!load_use_hazard)
                pc <= pc_next;

        end

    end

    // ============================================================
    // INITIALIZE MEMORIES
    // ============================================================

    initial begin

        for (i = 0; i < IMEM_DEPTH; i = i + 1)
            imem[i] = 32'h00000013;

        for (i = 0; i < DMEM_DEPTH; i = i + 1)
            dmem[i] = 32'b0;

    end

endmodule

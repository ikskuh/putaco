/**************************************************
* THIS FILE IS GENERATED. MODIFICATION IS FUTILE! *
**************************************************/

`timescale 1ns / 1ps;

module PutacoCore(
    input  [6:0] CODE_DATA,
    input        CODE_STROBE,
    output [6:0] CODE_LABEL,
    output       CODE_SEEK_n,
    output       CODE_HALT_n,
    output [7:0] MEM_ADDR,
    inout  [7:0] MEM_DATA,
    output       MEM_CS_n,
    output       MEM_OE_n,
    output       MEM_WE_n,
    input        AUX_RESET
);
    supply0 GND;
    supply1 VCC;

    /**
      * Constants
     */
    localparam FI = 0;
    localparam FO = 1;
    localparam IO = 2;
    localparam EX = 3;

    /**
      * Instances
     */
    CD74HC173 IR_FF_i0(); // IR_FF[0]
    CD74HC173 IR_FF_i1(); // IR_FF[1]
    CD74HC173 OP_FF_i0(); // OP_FF[0]
    CD74HC173 OP_FF_i1(); // OP_FF[1]
    CD74HC173 ACC_A_i0(); // ACC_A[0]
    CD74HC173 ACC_A_i1(); // ACC_A[1]
    CD74HC173 ACC_B_i0(); // ACC_B[0]
    CD74HC173 ACC_B_i1(); // ACC_B[1]
    CD74HC173 STATE_FF(); // STATE_FF
    SST39SF040 #(
        .INIT_FILE("zig-out/aux/alu.bin"),
        .INIT_FORMAT("raw")
    ) ALU(); // ALU
    CD74HC541 OP_BUF(); // OP_BUF
    CD74HC541 ACC_BUF(); // ACC_BUF
    CD74HC541 ALUMUX_i0(); // ALUMUX[0]
    CD74HC541 ALUMUX_i1(); // ALUMUX[1]
    CD74HC138 OPCMUX(); // OPCMUX
    SN74HC157 OPDMUX_i0(); // OPDMUX[0]
    SN74HC157 OPDMUX_i1(); // OPDMUX[1]
    CD74HC08 AND2(); // AND2
    CD74HC08 AND_MUX(); // AND_MUX
    CD74HC21 AND4_1(); // AND4_1
    CD74HC21 AND4_2(); // AND4_2
    SN74HC540 NOT(); // NOT
    CD74HC688 EQ0(); // EQ0
    CD74HC221 #(
        .RX1_OHMS(3000),
        .CX1_PF(4700),
        .RX2_OHMS(3000),
        .CX2_PF(4700)
    ) TIM1(); // TIM1
    CD74HC221 #(
        .RX1_OHMS(3000),
        .CX1_PF(4700),
        .RX2_OHMS(3000),
        .CX2_PF(4700)
    ) TIM2(); // TIM2

    /**
      * Wires
     */
    wire       STATE_FI; // STATE_FI
    wire       STATE_FO; // STATE_FO
    wire       STATE_IO; // STATE_IO
    wire       STATE_EX; // STATE_EX
    wire       STATE_FI_n; // STATE_FI#
    wire       STATE_FO_n; // STATE_FO#
    wire       STATE_IO_n; // STATE_IO#
    wire       STATE_EX_n; // STATE_EX#
    wire       OPCODE_ALU_n; // OPCODE_ALU#
    wire       OPCODE_HALT_n; // OPCODE_HALT#
    wire       OPCODE_SET_n; // OPCODE_SET#
    wire       OPCODE_LD_n; // OPCODE_LD#
    wire       OPCODE_ST_n; // OPCODE_ST#
    wire       OPCODE_JMP_n; // OPCODE_JMP#
    wire       OPCODE_JZ_n; // OPCODE_JZ#
    wire       OPCODE_JNZ_n; // OPCODE_JNZ#
    wire       OPCODE_DJNZ_n; // OPCODE_DJNZ#
    wire [7:0] BUS; // BUS
    wire       ACC_BANK_A_n; // ACC_BANK_A#
    wire       ACC_BANK_B_n; // ACC_BANK_B#
    wire [7:0] ACC; // ACC
    wire [7:0] IR; // IR
    wire [7:0] OP; // OP
    wire       TRIG_EXEC; // TRIG_EXEC
    wire       OE_n; // OE#
    wire       WE_n; // WE#
    wire       CLK; // CLK
    wire       ADV; // ADV

    /**
      * Assignments
     */
    assign IR_FF_i0.MR = AUX_RESET;
    assign IR_FF_i1.MR = AUX_RESET;
    assign OP_FF_i0.MR = AUX_RESET;
    assign OP_FF_i1.MR = AUX_RESET;
    assign ACC_A_i0.MR = AUX_RESET;
    assign ACC_A_i1.MR = AUX_RESET;
    assign ACC_B_i0.MR = AUX_RESET;
    assign ACC_B_i1.MR = AUX_RESET;
    assign STATE_FF.MR = AUX_RESET;
    assign NOT.OE1_n = GND;
    assign NOT.OE2_n = GND;
    assign AND2.A[0] = IR[4];
    assign AND2.B[0] = STATE_FO;
    assign AND4_2.A[0] = STATE_FO_n;
    assign AND4_2.B[0] = STATE_IO_n;
    assign AND4_2.C[0] = STATE_EX_n;
    assign AND4_2.D[0] = VCC;
    assign STATE_FF.OE1_n = GND;
    assign STATE_FF.OE2_n = GND;
    assign STATE_FF.CP = ADV;
    assign STATE_FF.E1_n = GND;
    assign STATE_FF.E2_n = GND;
    assign STATE_FF.D[0] = STATE_EX;
    assign STATE_FF.D[1] = STATE_FI;
    assign STATE_FF.D[2] = AND2.Y[0];
    assign STATE_FF.D[3] = (AND_MUX.Y[0] | AND_MUX.Y[1]);
    assign STATE_FI = AND4_2.Y[0];
    assign STATE_FO = STATE_FF.Q[1];
    assign STATE_IO = STATE_FF.Q[2];
    assign STATE_EX = STATE_FF.Q[3];
    assign NOT.A[7] = IR[4];
    assign AND_MUX.A[0] = IR[4];
    assign AND_MUX.B[0] = STATE_IO;
    assign AND_MUX.A[1] = NOT.Y_n[7];
    assign AND_MUX.B[1] = STATE_FO;
    assign AND_MUX.A[2] = GND;
    assign AND_MUX.B[2] = GND;
    assign AND_MUX.A[3] = GND;
    assign AND_MUX.B[3] = GND;
    assign NOT.A[0] = STATE_FI;
    assign NOT.A[1] = STATE_FO;
    assign NOT.A[2] = STATE_IO;
    assign NOT.A[3] = STATE_EX;
    assign STATE_FI_n = NOT.Y_n[0];
    assign STATE_FO_n = NOT.Y_n[1];
    assign STATE_IO_n = NOT.Y_n[2];
    assign STATE_EX_n = NOT.Y_n[3];
    assign NOT.A[4] = IR[3];
    assign OPCODE_ALU_n = (STATE_EX_n | NOT.Y_n[4]);
    assign OPCMUX.G0_n = STATE_EX_n;
    assign OPCMUX.G1_n = IR[3];
    assign OPCMUX.G2 = VCC;
    assign OPCMUX.A[2:0] = IR[2:0];
    assign OPCODE_HALT_n = OPCMUX.Y_n[0];
    assign OPCODE_SET_n = OPCMUX.Y_n[1];
    assign OPCODE_LD_n = OPCMUX.Y_n[2];
    assign OPCODE_ST_n = OPCMUX.Y_n[3];
    assign OPCODE_JMP_n = OPCMUX.Y_n[4];
    assign OPCODE_JZ_n = OPCMUX.Y_n[5];
    assign OPCODE_JNZ_n = OPCMUX.Y_n[6];
    assign OPCODE_DJNZ_n = OPCMUX.Y_n[7];
    assign BUS[7:0] = (0 /* TODO: joined */);
    assign IR_FF_i0.D[3:0] = CODE_DATA[3:0];
    assign IR_FF_i1.D[3:0] = { GND, CODE_DATA[6:4] };
    assign IR_FF_i0.E1_n = STATE_FI_n;
    assign IR_FF_i1.E1_n = STATE_FI_n;
    assign IR_FF_i0.E2_n = GND;
    assign IR_FF_i1.E2_n = GND;
    assign IR_FF_i0.CP = CLK;
    assign IR_FF_i1.CP = CLK;
    assign IR_FF_i0.OE1_n = GND;
    assign IR_FF_i1.OE1_n = GND;
    assign IR_FF_i0.OE2_n = GND;
    assign IR_FF_i1.OE2_n = GND;
    assign IR[7:0] = { IR_FF_i1.Q[3:0], IR_FF_i0.Q[3:0] };
    assign OPDMUX_i0.S = STATE_FO_n;
    assign OPDMUX_i1.S = STATE_FO_n;
    assign OPDMUX_i0.G_n = GND;
    assign OPDMUX_i1.G_n = GND;
    assign OPDMUX_i0.A[3:0] = CODE_DATA[3:0];
    assign OPDMUX_i1.A[3:0] = { IR[5], CODE_DATA[6:4] };
    assign OPDMUX_i0.B[3:0] = MEM_DATA[3:0];
    assign OPDMUX_i1.B[3:0] = MEM_DATA[7:4];
    assign AND2.A[1] = STATE_FO_n;
    assign AND2.B[1] = STATE_IO_n;
    assign OP_FF_i0.D[3:0] = OPDMUX_i0.Y[3:0];
    assign OP_FF_i1.D[3:0] = OPDMUX_i1.Y[3:0];
    assign OP_FF_i0.E1_n = AND2.Y[1];
    assign OP_FF_i1.E1_n = AND2.Y[1];
    assign OP_FF_i0.E2_n = GND;
    assign OP_FF_i1.E2_n = GND;
    assign OP_FF_i0.CP = CLK;
    assign OP_FF_i1.CP = CLK;
    assign OP_FF_i0.OE1_n = GND;
    assign OP_FF_i1.OE1_n = GND;
    assign OP_FF_i0.OE2_n = GND;
    assign OP_FF_i1.OE2_n = GND;
    assign OP[7:0] = { OP_FF_i1.Q[3:0], OP_FF_i0.Q[3:0] };
    assign OP_BUF.A[7:0] = OP[7:0];
    assign OP_BUF.OE1_n = OPCODE_SET_n;
    assign OP_BUF.OE2_n = OE_n;
    assign AND4_1.A[0] = OPCODE_ALU_n;
    assign AND4_1.B[0] = OPCODE_SET_n;
    assign AND4_1.C[0] = OPCODE_LD_n;
    assign AND4_1.D[0] = OPCODE_DJNZ_n;
    assign ACC_BANK_A_n = IR[6];
    assign ACC_BANK_B_n = !(IR[6]);
    assign ACC_A_i0.D[3:0] = BUS[3:0];
    assign ACC_A_i1.D[3:0] = BUS[7:4];
    assign ACC_A_i0.E1_n = AND4_1.Y[0];
    assign ACC_A_i1.E1_n = AND4_1.Y[0];
    assign ACC_A_i0.E2_n = ACC_BANK_A_n;
    assign ACC_A_i1.E2_n = ACC_BANK_A_n;
    assign ACC_A_i0.CP = CLK;
    assign ACC_A_i1.CP = CLK;
    assign ACC_A_i0.OE1_n = ACC_BANK_A_n;
    assign ACC_A_i1.OE1_n = ACC_BANK_A_n;
    assign ACC_A_i0.OE2_n = STATE_FI;
    assign ACC_A_i1.OE2_n = STATE_FI;
    assign ACC_B_i0.D[3:0] = BUS[3:0];
    assign ACC_B_i1.D[3:0] = BUS[7:4];
    assign ACC_B_i0.E1_n = AND4_1.Y[0];
    assign ACC_B_i1.E1_n = AND4_1.Y[0];
    assign ACC_B_i0.E2_n = ACC_BANK_B_n;
    assign ACC_B_i1.E2_n = ACC_BANK_B_n;
    assign ACC_B_i0.CP = CLK;
    assign ACC_B_i1.CP = CLK;
    assign ACC_B_i0.OE1_n = ACC_BANK_B_n;
    assign ACC_B_i1.OE1_n = ACC_BANK_B_n;
    assign ACC_B_i0.OE2_n = STATE_FI;
    assign ACC_B_i1.OE2_n = STATE_FI;
    assign ACC[7:0] = (0 /* TODO: joined */);
    assign ACC_BUF.A[7:0] = ACC[7:0];
    assign ACC_BUF.OE1_n = OPCODE_ST_n;
    assign ACC_BUF.OE2_n = OE_n;
    assign AND2.A[2] = STATE_IO_n;
    assign AND2.B[2] = OPCODE_LD_n;
    assign AND4_1.A[1] = STATE_IO_n;
    assign AND4_1.B[1] = OPCODE_LD_n;
    assign AND4_1.C[1] = OPCODE_ST_n;
    assign AND4_1.D[1] = VCC;
    assign MEM_CS_n = AND4_1.Y[1];
    assign MEM_OE_n = (AND2.Y[2] | OE_n);
    assign MEM_WE_n = (OPCODE_ST_n | WE_n);
    assign MEM_ADDR[7:0] = OP[7:0];
    assign ALUMUX_i0.OE1_n = OPCODE_ALU_n;
    assign ALUMUX_i1.OE1_n = OPCODE_ALU_n;
    assign ALUMUX_i0.OE2_n = OE_n;
    assign ALUMUX_i1.OE2_n = OE_n;
    assign ALUMUX_i0.A[7:0] = OP[7:0];
    assign ALUMUX_i1.A[7:0] = { 5'b00000, IR[2:0] };
    assign AND2.A[3] = OPCODE_ALU_n;
    assign AND2.B[3] = OPCODE_DJNZ_n;
    assign ALU.A[18:16] = (0 /* TODO: joined */);
    assign ALU.A[15:8] = ACC[7:0];
    assign ALU.A[7:0] = (0 /* TODO: joined */);
    assign ALU.OE_n = OE_n;
    assign ALU.CE_n = AND2.Y[3];
    assign ALU.WE_n = VCC;
    assign NOT.A[5] = OPCODE_DJNZ_n;
    assign EQ0.A[7:0] = ACC[7:0];
    assign EQ0.B[7:0] = { 7'b0000000, NOT.Y_n[5] };
    assign EQ0.E_n = GND;
    assign NOT.A[6] = EQ0.Y_n;
    assign AND4_2.A[1] = OPCODE_JMP_n;
    assign AND4_2.B[1] = (OPCODE_JZ_n | EQ0.Y_n);
    assign AND4_2.C[1] = (OPCODE_JNZ_n | NOT.Y_n[6]);
    assign AND4_2.D[1] = (OPCODE_DJNZ_n | NOT.Y_n[6]);
    assign CODE_LABEL[6:0] = OP[6:0];
    assign CODE_SEEK_n = (AND4_2.Y[1] | WE_n);
    assign CODE_HALT_n = OPCODE_HALT_n;
    assign TRIG_EXEC = (CODE_STROBE | TIM2._2Q);
    assign TIM1._1A_n = GND;
    assign TIM1._1B = TRIG_EXEC;
    assign TIM1._1R_n = VCC;
    assign TIM1._2A_n = GND;
    assign TIM1._2B = TRIG_EXEC;
    assign TIM1._2R_n = VCC;
    assign TIM2._1A_n = GND;
    assign TIM2._1B = OE_n;
    assign TIM2._1R_n = VCC;
    assign TIM2._2A_n = ADV;
    assign TIM2._2B = VCC;
    assign TIM2._2R_n = (STATE_FF.Q[2] | STATE_FF.Q[3]);
    assign OE_n = TIM1._1Q_n;
    assign WE_n = TIM1._2Q_n;
    assign CLK = WE_n;
    assign ADV = TIM2._1Q;

endmodule

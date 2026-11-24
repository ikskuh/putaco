`timescale 1ns / 1ps

module PutacoCore(
    // code interface
    input [6:0] c_data,
    input       c_strobe,

    output [6:0] c_label,
    output       c_seek_n,
    output       c_halt_n,

    // memory interface
    inout [7:0] mem_addr,
    output [7:0] mem_data,
    output      mem_cs,
    output      mem_oe,
    output      mem_we,

    input reset
);  
    supply0 GND;
    supply1 VCC;

    FI
    FO
    IO
    EX

    /**
     * Component Declarations
     */

    SST39SF040 #(
        .INIT_FILE("zig-out/aux/alu.bin"),
        .INIT_FORMAT("raw")  
    ) ALU();
    
    CD74HC173 IR_1();
    CD74HC173 IR_2();
    wire [7:0] IR = { IR_2.DQ, IR_1.DQ };

    CD74HC173 OP_1();
    CD74HC173 OP_2();
    wire [7:0] OP = { OP_2.DQ, OP_1.DQ };

    CD74HC173 ACC_A_1();
    CD74HC173 ACC_A_2();
    wire [7:0] ACC_A = { ACC_A_2.DQ, ACC_A_1.DQ };

    CD74HC173 ACC_B_1();
    CD74HC173 ACC_B_2();
    wire [7:0] ACC_B = { ACC_B_2.DQ, ACC_B_1.DQ };

    CD74HC173 STATE_FF(
        .MR(reset)
    );

    CD74HC541 OP_BUF();
    CD74HC541 ACC_BUF();
    CD74HC541 ALUMUX_1();
    CD74HC541 ALUMUX_2();
    CD74HC138 OPCMUX();
    SN74HC157 OPDMUX_1();
    SN74HC157 OPDMUX_2();
    CD74HC08 AND2();
    CD74HC08 AND_MUX();
    CD74HC21 AND4_1();
    CD74HC21 AND4_2();
    SN74HC540 NOT();
    CD74HC688 EQ0();

    /**
     * Component Declarations
     */
    assign IR.MR       = reset;
    assign OP.MR       = reset;
    assign ACC_A.MR    = reset;
    assign ACC_B.MR    = reset;
    assign STATE_FF.MR = reset;

    assign NOT.OE1_n   = GND;
    assign NOT.OE2_n   = GND;

    assign AND2.A[0]       = IR[4];
    assign AND2.B[0]       = STATE_FO;

    // patch reset state from "0000" to "this is still FI" 
    assign AND4_2.A[0]     = STATE_FO_n;
    assign AND4_2.B[0]     = STATE_IO_n;
    assign AND4_2.C[0]     = STATE_EX_n;
    assign AND4_2.D[0]     = HIGH;

    assign STATE_FF.OE_n    <= GND
    assign STATE_FF.OE2_n   <= GND
    assign STATE_FF.CLK    <= CLK
    assign STATE_FF.E1_n    <= GND
    assign STATE_FF.E2_n    <= GND
    assign STATE_FF.D[FI]  <= STATE_EX
    assign STATE_FF.D[FO]  <= STATE_FI
    assign STATE_FF.D[IO]  <= AND2.Y[0]
    assign STATE_FF.D[EX]  <= (AND_MUX.Y[0] | AND_MUX.Y[1]) ~ R'L'     (* diode or, forms mux 2:1 *)

    STATE_FI        <= AND4_2.Y[0]      (* in theory, we could also OR the STATE_FF.D[FI] into this, but it's redundant *)
    STATE_FO        <= STATE_FF.Q[FO]
    STATE_IO        <= STATE_FF.Q[IO]
    STATE_EX        <= STATE_FF.Q[EX]

    NOT.A[7]        <= IR[4]

    AND_MUX.A[0]    <= IR[4]
    AND_MUX.B[0]    <= STATE_IO

    AND_MUX.A[1]    <= NOT.Y_n[7]
    AND_MUX.B[1]    <= STATE_FO

    AND_MUX.A[2]    <= GND
    AND_MUX.B[2]    <= GND
    AND_MUX.A[3]    <= GND
    AND_MUX.B[3]    <= GND

    NOT.A[0]        <= STATE_FI
    NOT.A[1]        <= STATE_FO
    NOT.A[2]        <= STATE_IO
    NOT.A[3]        <= STATE_EX

    STATE_FI_n       <= NOT.Y_n[0]
    STATE_FO_n       <= NOT.Y_n[1]
    STATE_IO_n       <= NOT.Y_n[2]
    STATE_EX_n       <= NOT.Y_n[3]

    (* aliases for instructions *)
    NOT.A[4]        <= IR[3]
    OPCODE_ALU_n     <= (STATE_EX_n | NOT.Y_n[4]) ~ R'L'       (* diode or *)

    (* make OPCMUX.Y[] only GND when STATE_EX.Q & !IR[3] *)
    OPCMUX.G0_n      <= STATE_EX_n
    OPCMUX.G1_n      <= IR[3]
    OPCMUX.G2       <= VCC
    OPCMUX.A[2:0]   <= IR[2:0]

    OPCODE_HALT_n    <= OPCMUX.Y_n[0]
    OPCODE_SET_n     <= OPCMUX.Y_n[1]
    OPCODE_LD_n      <= OPCMUX.Y_n[2]
    OPCODE_ST_n      <= OPCMUX.Y_n[3]
    OPCODE_JMP_n     <= OPCMUX.Y_n[4]
    OPCODE_JZ_n      <= OPCMUX.Y_n[5]
    OPCODE_JNZ_n     <= OPCMUX.Y_n[6]
    OPCODE_DJNZ_n    <= OPCMUX.Y_n[7]

    BUS             <= ALU.DATA ~ MEM.DATA ~ OP_BUF.Q ~ ACC_BUF.Q ~ R'LLLLLLLL'     (* tristate join *)

    IR.D            <= { GND, CODE.DATA[6:0] }
    IR.E1_n          <= STATE_FI_n
    IR.E2_n          <= GND
    IR.CLK          <= CODE.STROBE
    IR.OE_n          <= GND
    IR.OE2_n         <= GND

    OPDMUX[*].A_n/B  <= STATE_FO_n
    OPDMUX[*].G_n    <= GND
    OPDMUX[0].A     <= CODE.DATA[3:0]
    OPDMUX[1].A     <= { IR[5], CODE.DATA[6:4] }
    OPDMUX[0].B     <= MEM.DATA[3:0]
    OPDMUX[1].B     <= MEM.DATA[7:4]

    AND2.A[1]       <= STATE_FO_n
    AND2.B[1]       <= STATE_IO_n

    OP.D            <= { OPDMUX[1].Y[3:0], OPDMUX[0].Y[3:0] }
    OP.E1_n          <= AND2.Y[1]
    OP.E2_n          <= GND
    OP.CLK          <= CLK
    OP.OE_n          <= GND
    OP.OE2_n         <= GND

    OP_BUF.D        <= OP.Q
    OP_BUF.OE_n      <= OPCODE_SET_n
    OP_BUF.OE2_n     <= GND

    AND4_1.A[0]     <= OPCODE_ALU_n
    AND4_1.B[0]     <= OPCODE_SET_n
    AND4_1.C[0]     <= OPCODE_LD_n
    AND4_1.D[0]     <= OPCODE_DJNZ_n

    ACC_BANK_A_n     <= IR[6]
    ACC_BANK_B_n     <= !IR[6] ~ R'H'             (* mosfet inverter (2N7000) *)

    ACC_A.D         <= BUS
    ACC_A.E1_n       <= AND4_1.Y[0]
    ACC_A.E2_n       <= ACC_BANK_A_n
    ACC_A.CLK       <= CLK
    ACC_A.OE_n       <= ACC_BANK_A_n
    ACC_A.OE2_n      <= STATE_FI                 (* prevent glitching when fetching new state *)

    ACC_B.D         <= BUS
    ACC_B.E1_n       <= AND4_1.Y[0]
    ACC_B.E2_n       <= ACC_BANK_B_n
    ACC_B.CLK       <= CLK
    ACC_B.OE_n       <= ACC_BANK_B_n
    ACC_B.OE2_n      <= STATE_FI                 (* prevent glitching when fetching new state *)

    ACC             <= ACC_A ~ ACC_B ~ R'LLLLLLLL'  (* tristate join of both accumulators *)

    ACC_BUF.D       <= ACC
    ACC_BUF.OE_n     <= OPCODE_ST_n
    ACC_BUF.OE2_n    <= GND

    AND2.A[2]       <= STATE_IO_n
    AND2.B[2]       <= OPCODE_LD_n

    AND4_1.A[1]     <= STATE_IO_n
    AND4_1.B[1]     <= OPCODE_LD_n
    AND4_1.C[1]     <= OPCODE_ST_n
    AND4_1.D[1]     <= VCC

    MEM.CS_n         <= AND4_1.Y[1]
    MEM.OE_n         <= AND2.Y[2]
    MEM.WE_n         <= OPCODE_ST_n
    MEM.ADDR        <= OP.Q

    ALUMUX[*].OE_n   <= OPCODE_ALU_n
    ALUMUX[*].OE2_n  <= GND
    ALUMUX[0].A     <= OP.Q
    ALUMUX[1].A     <= { 'LLLLL', IR[2:0] }

    AND2.A[3]       <= OPCODE_ALU_n
    AND2.B[3]       <= OPCODE_DJNZ_n

    ALU.A[18:16]    <= ALUMUX[1].Y[2:0] ~ R'LLH'        (* buffer + resistor bias => mux 2:1 *)
    ALU.A[15: 8]    <= ACC
    ALU.A[ 7: 0]    <= ALUMUX[0].Y[7:0] ~ R'LLLLLLLH'   (* buffer + resistor bias => mux 2:1 *)
    ALU.OE_n         <= AND2.Y[3]
    ALU.CS_n         <= GND
    ALU.WE_n         <= VCC

    NOT.A[5]        <= OPCODE_DJNZ_n                     (* make positive logic *)

    EQ0.A           <= ACC
    EQ0.B           <= { 'LLLLLLL', NOT.Y_n[5] }         (* is H if OPCODE_DJNZ_n is L *)
    EQ0.E_n          <= GND

    NOT.A[6]        <= EQ0.Y_n

    AND4_2.A[1]     <= OPCODE_JMP_n
    AND4_2.B[1]     <= (OPCODE_JZ_n | EQ0.Y_n) ~ R'L'         (* diode or *)
    AND4_2.C[1]     <= (OPCODE_JNZ_n | NOT.Y_n[6]) ~ R'L'     (* diode or *)
    AND4_2.D[1]     <= (OPCODE_DJNZ_n | NOT.Y_n[6]) ~ R'L'    (* diode or *)

    CODE.LABEL      <= OP[6:0]
    CODE.SEEK_n      <= AND4_2.Y[1]
    CODE.HALT_n      <= OPCODE_HALT_n
     
endmodule

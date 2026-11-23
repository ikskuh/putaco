const std = @import("std");

/// The name of the two accumulator registers.
pub const Register = enum(u1) {
    a = 0,
    b = 1,
};

/// A Putaco operand code.
/// Defines what an instruction does.
pub const OpCode = enum(u4) {
    halt = 0x0,
    set = 0x1,
    ld = 0x2,
    st = 0x3,
    jmp = 0x4,
    jz = 0x5,
    jnz = 0x6,
    djnz = 0x7,
    add = 0x8,
    sub = 0x9,
    @"and" = 0xA,
    xor = 0xB,
    shx = 0xC,
    mul = 0xD,
    divs = 0xE,
    neg = 0xF,

    pub fn is_alu(op: OpCode) bool {
        return (@backingInt(op) & 0x8) != 0;
    }

    pub fn is_branch(op: OpCode) bool {
        return switch (op) {
            .jmp, .jz, .jnz, .djnz => true,
            else => false,
        };
    }

    pub fn requires_acc(op: OpCode) bool {
        return switch (op) {
            .halt => false, // does not consume ACC, only OP
            .set => true,
            .ld => true,
            .st => true,
            .jmp => false, // does not consume ACC, only OP
            .jz => true,
            .jnz => true,
            .djnz => true,
            .add => true,
            .sub => true,
            .@"and" => true,
            .xor => true,
            .shx => true,
            .mul => true,
            .divs => true,
            .neg => true,
        };
    }
};

///
/// An 8-bit word stored in a Putaco program.
///
pub const CodeWord = packed union(u8) {
    pub const zero: CodeWord = @bitCast(@as(u8, 0));

    instruction: InstructionWord,
    operand: OperandWord,
    label: LabelWord,
};

///
/// An instruction word encodes an operation the Putaco machine shall
/// execute.
///
pub const InstructionWord = packed struct(u8) {
    pub const zero: InstructionWord = @bitCast(@as(u8, 0));

    /// The operation the machine shall execute.
    opcode: OpCode,
    /// If set, the operand is treated as an address in program memory,
    /// and the machine will load the actual operand from memory.
    indirect: bool,
    /// The high bit of the operand value.
    operand_h: u1,
    register: Register,
    /// Must be set to false to mark the code word as a non-label.
    label: bool = false,
};

///
/// The operand word encodes the lower 7 bit of an instruction operand value.
///
pub const OperandWord = packed struct(u8) {
    pub const zero: OperandWord = @bitCast(@as(u8, 0));

    /// The low 7 bits of the operand value.
    operand_l: u7,
    /// Must be set to false to mark the code word as a non-label.
    label: bool = false,
};

///
/// A label word marks a jump location on the Putaco program memory.
///
pub const LabelWord = packed struct(u8) {
    pub const zero: LabelWord = @bitCast(@as(u8, 0));

    /// The 7-bit branching target which is used to seek the instruction stream forward.
    branch_id: u7,
    /// Must be set to true to mark the code word as a label.
    label: bool = true,
};

/// Encodes an instruction into a pair of two code words.
pub fn encode_instruction(opcode: OpCode, indirect: bool, register: Register, operand: u8) [2]CodeWord {
    return .{
        .{
            .instruction = .{
                .opcode = opcode,
                .indirect = indirect,
                .register = register,
                .operand_h = @intCast(operand >> 7),
            },
        },
        .{
            .operand = .{
                .operand_l = @intCast(operand & 0x7F),
            },
        },
    };
}

pub const simulator = struct {
    pub const MemoryInterface = struct {
        context: ?*anyopaque,
        read_fn: *const fn (ctx: ?*anyopaque, addr: u8) u8,
        write_fn: *const fn (ctx: ?*anyopaque, addr: u8, value: u8) void,

        pub fn read(intf: MemoryInterface, addr: u8) u8 {
            return intf.read_fn(intf.context, addr);
        }

        pub fn write(intf: MemoryInterface, addr: u8, value: u8) void {
            intf.write_fn(intf.context, addr, value);
        }
    };

    pub const Result = enum {
        seeking,
        waiting,
        executing,
        halt,
    };

    pub const Simulator = struct {
        const State = enum {
            fetch_instr,
            fetch_op,
            indirect_op,
            execute,
        };
        const OpAssembly = packed struct(u8) {
            operand_l: u7,
            operand_h: u1,
        };
        const AluIndex = packed struct(u19) {
            op: u8,
            acc: u8,
            instr: u3,
        };

        const alu: *const [8 * 256 * 256]u8 = @embedFile("alu.bin");

        state: State = .fetch_instr,

        instr: InstructionWord = undefined,
        op: u8 = undefined,
        acc_a: u8 = 0,
        acc_b: u8 = 0,
        seek: LabelWord = .zero,

        pub fn step(sim: *Simulator, mem: MemoryInterface, code: CodeWord) Result {
            if (code.label.label and sim.seek == code.label) {
                // The the new code word is the label we seek,
                // we leave seek mode:
                sim.seek = .zero;
            }

            // CPU is seeking a specific location:
            if (sim.seek.label) {
                return .seeking;
            }

            // CPU does not execute labels:
            if (code.label.label) {
                return .waiting;
            }

            var result: Result = .waiting;
            sim.state = exc: switch (sim.state) {
                .fetch_instr => {
                    sim.instr = code.instruction;
                    break :exc .fetch_op;
                },

                .fetch_op => {
                    sim.op = @bitCast(OpAssembly{
                        .operand_l = code.operand.operand_l,
                        .operand_h = sim.instr.operand_h,
                    });
                    continue :exc if (sim.instr.indirect)
                        .indirect_op
                    else
                        .execute;
                },

                .indirect_op => {
                    sim.op = mem.read(sim.op);
                    continue :exc .execute;
                },

                .execute => {
                    const acc = switch (sim.instr.register) {
                        .a => &sim.acc_a,
                        .b => &sim.acc_b,
                    };
                    result = .executing;
                    switch (sim.instr.opcode) {
                        .halt => result = .halt,
                        .set => {
                            acc.* = sim.op;
                        },
                        .ld => {
                            acc.* = mem.read(sim.op);
                        },
                        .st => {
                            mem.write(sim.op, acc.*);
                        },

                        .jmp => {
                            sim.seek = .{ .branch_id = @truncate(sim.op) };
                        },
                        .jz => {
                            if (acc.* == 0) {
                                sim.seek = .{ .branch_id = @truncate(sim.op) };
                            }
                        },
                        .jnz => {
                            if (acc.* != 0) {
                                sim.seek = .{ .branch_id = @truncate(sim.op) };
                            }
                        },
                        .djnz => {
                            acc.* -= 1;
                            if (acc.* != 0) {
                                sim.seek = .{ .branch_id = @truncate(sim.op) };
                            }
                        },

                        .@"and", .xor, .add, .sub, .neg, .shx, .mul, .divs => {
                            std.debug.assert(sim.instr.opcode.is_alu());
                            const index: u19 = @bitCast(AluIndex{
                                .op = sim.op,
                                .acc = acc.*,
                                .instr = @truncate(@backingInt(sim.instr.opcode)),
                            });

                            acc.* = alu[index];
                        },
                    }

                    break :exc .fetch_instr;
                },
            };
            return result;
        }
    };
};

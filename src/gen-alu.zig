const std = @import("std");

const Lut = extern struct {
    items: [256][256]u8,
};

const Alu = struct {
    ops: [8]Lut,
};

pub fn main(init: std.process.Init) !void {
    const ops: [8]*const fn (u8, u8) u8 = .{
        alu_add, // 0
        alu_sub, // 1
        alu_and, // 2
        alu_xor, // 3
        alu_shl, // 4
        alu_shr, // 5
        alu_asr, // 6
        alu_neg, // 7
    };

    const alu = try init.arena.allocator().create(Alu);

    for (&alu.ops, ops) |*lut, opcode| {
        for (&lut.items, 0..) |*row, acc| {
            for (row, 0..) |*cell, op| {
                cell.* = opcode(@intCast(acc), @intCast(op));
            }
        }
    }

    try std.Io.File.stdout().writeStreamingAll(init.io, std.mem.asBytes(&alu.ops));
}

fn alu_add(acc: u8, op: u8) u8 {
    return acc +% op;
}

fn alu_sub(acc: u8, op: u8) u8 {
    return acc -% op;
}

fn alu_and(acc: u8, op: u8) u8 {
    return acc & op;
}

fn alu_xor(acc: u8, op: u8) u8 {
    return acc ^ op;
}

fn alu_shl(acc: u8, op: u8) u8 {
    var out = acc;
    for (0..op) |_| {
        out <<= 1;
    }
    return out;
}

fn alu_shr(acc: u8, op: u8) u8 {
    var out = acc;
    for (0..op) |_| {
        out >>= 1;
    }
    return out;
}

fn alu_asr(acc: u8, op: u8) u8 {
    const msb = (acc & 0x80);
    var out = acc;
    for (0..op) |_| {
        out >>= 1;
        out |= msb;
    }
    return out;
}

fn alu_neg(acc: u8, op: u8) u8 {
    return op -% acc;
}

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
        alu_shx, // 4
        alu_mul, // 5
        alu_divs, // 6
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

fn alu_shx(acc: u8, op: u8) u8 {
    const cnt: i8 = @bitCast(op);
    return switch (cnt) {
        -7...-1 => return acc >> @intCast(-cnt),
        0 => return acc,
        1...7 => return acc << @intCast(cnt),
        else => 0,
    };
}

fn alu_mul(acc: u8, op: u8) u8 {
    return acc *% op;
}

fn alu_divs(acc: u8, op: u8) u8 {
    if (op == 0) {
        // special case: SQRT(op) instead of divide-by-zero

        const in: f32 = @floatFromInt(acc);
        return @intFromFloat(16 * @sqrt(in));
    }

    const num: i8 = @bitCast(acc);

    const div: i8 = @intCast(@divFloor(@as(i9, num), op));

    return @bitCast(div);
}

fn alu_neg(acc: u8, op: u8) u8 {
    return op -% acc;
}

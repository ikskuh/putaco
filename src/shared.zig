const std = @import("std");

const StringImpl = opaque {
    pub fn len(s: *align(4) const StringImpl) usize {
        const l_ptr: *const u32 = @ptrCast(s);
        return l_ptr.*;
    }

    pub fn to_slice(s: *align(4) const StringImpl) []const u8 {
        const _len = s.len();
        const head: [*]const u8 = @ptrCast(s);
        return head[4..][0.._len];
    }

    pub fn format(s: *align(4) const StringImpl, writer: *std.Io.Writer) !void {
        try writer.print("\"{f}\"", .{std.zig.fmtString(s.to_slice())});
    }
};

pub const String = *align(4) const StringImpl;

pub const StringPool = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    intern_map: std.StringArrayHashMapUnmanaged(String) = .empty,

    pub fn init(gpa: std.mem.Allocator) StringPool {
        return .{
            .gpa = gpa,
            .arena = .init(gpa),
        };
    }

    pub fn deinit(pool: *StringPool) void {
        pool.arena.deinit();
        pool.intern_map.deinit(pool.gpa);
        pool.* = undefined;
    }

    pub fn get_or_put(pool: *StringPool, s: []const u8) !String {
        const len = std.math.cast(u32, s.len) orelse return error.OutOfMemory;
        const gop = try pool.intern_map.getOrPut(pool.gpa, s);
        if (!gop.found_existing) {
            errdefer _ = pool.intern_map.swapRemove(s);

            const bytes = try pool.arena.allocator().allocBytesAligned(.@"4", 4 + s.len, @returnAddress());
            std.mem.writeInt(u32, bytes[0..4], len, .native);
            @memcpy(bytes[4..][0..s.len], s);

            gop.value_ptr.* = @ptrCast(bytes);
        }
        return gop.value_ptr.*;
    }
};

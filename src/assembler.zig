const std = @import("std");

const putaco = @import("putaco");

pub fn main(init: std.process.Init) !u8 {
    const source: []const u8 = blk: {
        var writer: std.Io.Writer.Allocating = .init(init.arena.allocator());

        var buffer: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().reader(init.io, &buffer);

        _ = try reader.interface.streamRemaining(&writer.writer);

        break :blk writer.written();
    };

    std.log.info("assemble {} sources bytes", .{source.len});

    var assembler: Assembler = .init(init.gpa);
    defer assembler.deinit();

    try assembler.assemble(source);

    std.log.info("ram used:    {}/240", .{assembler.next_ram_addr - 16});
    std.log.info("labels used: {}/128", .{assembler.next_label});
    std.log.info("symbols:     {}", .{assembler.symbols.count()});
    std.log.info("codesize:    {}", .{assembler.code.items.len});
    std.log.info("patches:     {}", .{assembler.patches.items.len});

    if (try std.Io.File.stdout().isTty(init.io)) {
        std.log.warn("cannot write code to terminal!", .{});
        return 0;
    }

    try std.Io.File.stdout().writeStreamingAll(init.io, std.mem.sliceAsBytes(assembler.code.items));

    return 0;
}

const Assembler = struct {
    gpa: std.mem.Allocator,

    arena: std.heap.ArenaAllocator,

    labels: std.AutoArrayHashMapUnmanaged(String, u7) = .empty,
    symbols: std.AutoArrayHashMapUnmanaged(String, u8) = .empty,
    intern_map: std.StringArrayHashMapUnmanaged(String) = .empty,

    next_label: u7 = 0,
    next_ram_addr: u8 = 16,

    code: std.ArrayList(putaco.CodeWord) = .empty,
    patches: std.ArrayList(struct { usize, String }) = .empty,

    pub fn init(gpa: std.mem.Allocator) Assembler {
        return Assembler{
            .gpa = gpa,
            .arena = .init(gpa),
        };
    }

    pub fn deinit(as: *Assembler) void {
        as.labels.deinit(as.gpa);
        as.intern_map.deinit(as.gpa);
        as.symbols.deinit(as.gpa);
        as.patches.deinit(as.gpa);
        as.code.deinit(as.gpa);
        as.arena.deinit();
        as.* = undefined;
    }

    pub fn assemble(as: *Assembler, source: []const u8) !void {
        var line_iter = std.mem.tokenizeScalar(u8, source, '\n');

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(
                u8,
                if (std.mem.indexOfScalar(u8, raw_line, ';')) |idx| raw_line[0..idx] else raw_line,
                "\r\t ",
            );
            if (line.len == 0)
                continue;

            // std.log.info("line: \"{f}\"", .{std.zig.fmtString(line)});

            // Handle labels (local or non-local):
            if (std.mem.indexOfScalar(u8, line, ':')) |label_pos| {
                if (label_pos != line.len - 1)
                    @panic("TODO: error handling, code after label");

                const name_str = line[0..label_pos];

                if (!is_symbol_name(name_str)) {
                    @panic("TODO: error handling, invalid label character");
                }

                const label_id = as.next_label;
                if (as.next_label == 127)
                    @panic("TODO: Fix label overflow issue");
                as.next_label += 1;

                try as.define_symbol(name_str, label_id);

                try as.code.append(as.gpa, .{
                    .label = .{
                        .branch_id = label_id,
                    },
                });

                continue;
            }

            var iter: LineIter = .init(line);

            const dir_or_op_name = iter.next() orelse @panic("TODO: error handling, syntax error");

            const eql = std.ascii.eqlIgnoreCase;

            if (eql(dir_or_op_name, ".constant")) {
                const name_str = iter.next() orelse @panic("TODO: error handling, missing parameter");

                if (!iter.take(","))
                    @panic("TODO: error handling, expected comma");

                const value_str = iter.next() orelse @panic("TODO: error handling, missing value");

                const value = try as.parse_value(value_str);

                try as.define_symbol(name_str, value);
            } else if (eql(dir_or_op_name, ".alloc")) {
                const name_str = iter.next() orelse @panic("TODO: error handling, missing parameter");

                const size: u8 = if (iter.has_next()) blk: {
                    if (!iter.take(","))
                        @panic("TODO: error handling, expected comma");

                    const value_str = iter.next() orelse @panic("TODO: error handling, missing value");

                    break :blk try as.parse_value(value_str);
                } else 1;

                const addr = as.next_ram_addr;
                as.next_ram_addr += size;

                try as.define_symbol(name_str, addr);
            } else {
                const opcode = for (std.enums.values(putaco.OpCode)) |opcode| {
                    if (eql(@tagName(opcode), dir_or_op_name))
                        break opcode;
                } else @panic("TODO: error handling, unknown opcode");

                const is_indirect = iter.take("*");

                const operand_str = iter.next() orelse @panic("TODO: error handling, missing operand");

                const operand, const required_patch = try as.parse_value_allow_undefined(operand_str);

                const result = putaco.encode_instruction(opcode, is_indirect, operand);

                const offset = as.code.items.len;

                try as.code.appendSlice(as.gpa, &result);

                if (required_patch) |patch| {
                    try as.patches.append(as.gpa, .{ offset, patch });
                }
            }
        }

        for (as.patches.items) |patch| {
            const offset, const symbol = patch;

            std.debug.assert(offset + 1 < as.code.items.len);

            const value = as.symbols.get(symbol) orelse @panic("TODO: Error handling: Missing symbol");

            as.code.items[offset + 0].instruction.operand_h = @intCast(value >> 7);
            as.code.items[offset + 1].operand.operand_l = @intCast(value & 0x7F);
        }
    }

    fn parse_value_allow_undefined(as: *Assembler, text: []const u8) error{ InvalidCharacter, Overflow, OutOfMemory }!struct { u8, ?String } {
        const value = as.parse_value(text) catch |err| switch (err) {
            error.UndefinedSymbol => {
                // Return placeholder value for later,
                // we know that `text` is a valid symbol name, as otherwise we
                // would have received InvalidCharacter:
                return .{ 0xAA, try as.intern_string(text) };
            },

            error.InvalidCharacter, error.Overflow, error.OutOfMemory => |e| return e,
        };
        return .{ value, null };
    }

    fn parse_value(as: *Assembler, text: []const u8) error{ InvalidCharacter, Overflow, UndefinedSymbol, OutOfMemory }!u8 {
        if (std.mem.startsWith(u8, text, "'")) {
            if (!std.mem.endsWith(u8, text, "'"))
                return error.InvalidCharacter;
            if (text.len != 3)
                return error.InvalidCharacter;
            return text[1];
        }

        if (std.fmt.parseInt(u8, text, 0)) |value| {
            return value;
        } else |err| switch (err) {
            error.InvalidCharacter => {},
            error.Overflow => return error.Overflow,
        }

        if (is_symbol_name(text)) {
            const str = try as.intern_string(text);

            if (as.symbols.get(str)) |sym| {
                return sym;
            }

            return error.UndefinedSymbol;
        }

        return error.InvalidCharacter;
    }

    fn define_symbol(as: *Assembler, name: []const u8, value: u8) !void {
        const name_id = try as.intern_string(name);

        const gop = try as.symbols.getOrPut(as.gpa, name_id);
        if (gop.found_existing)
            @panic("TODO: error handling, duplicate symbol");
        gop.value_ptr.* = value;
    }

    fn is_symbol_name(text: []const u8) bool {
        for (text, 0..) |c, i| {
            switch (c) {
                '_', '.' => {},
                'a'...'z' => {},
                'A'...'Z' => {},
                '0'...'9' => if (i == 0)
                    return false,
                else => return false,
            }
        }
        return true;
    }

    const String = *const opaque {
        fn to_slice(s: String) []const u8 {
            const head: [*]const u8 = @ptrCast(s);

            const len = std.mem.readInt(u32, head[0..4], .native);
            return head[4..][0..len];
        }

        pub fn format(s: String, writer: *std.Io.Writer) !void {
            try writer.print("\"{s}\"", .{std.zig.fmtString(s.to_slice())});
        }
    };

    fn intern_string(as: *Assembler, s: []const u8) !String {
        const len = std.math.cast(u32, s.len) orelse return error.OutOfMemory;
        const gop = try as.intern_map.getOrPut(as.gpa, s);
        if (!gop.found_existing) {
            errdefer _ = as.intern_map.swapRemove(s);

            const bytes = try as.arena.allocator().allocBytesAligned(.@"4", 4 + s.len, @returnAddress());
            std.mem.writeInt(u32, bytes[0..4], len, .native);
            @memcpy(bytes[4..][0..s.len], s);

            gop.value_ptr.* = @ptrCast(bytes);
        }
        return gop.value_ptr.*;
    }

    const LineIter = struct {
        line: []const u8,
        limit: usize,

        pub fn init(line: []const u8) LineIter {
            return LineIter{
                .line = line,
                .limit = line.len,
            };
        }

        pub fn take(li: *LineIter, text: []const u8) bool {
            const previous = li.line;
            const str = li.next() orelse return false;
            if (std.mem.eql(u8, str, text))
                return true;
            li.line = previous;
            return false;
        }

        pub fn has_next(li: LineIter) bool {
            return li.line.len != 0;
        }

        fn next(li: *LineIter) ?[]const u8 {
            const line = li.line;
            if (line.len == 0)
                return null;
            std.debug.assert(li.limit > 0);
            li.limit -= 1;

            var len: usize = 0;
            while (len < line.len) {
                if (len == 0 and is_word_sep(line[len])) {
                    // when the first char is the word separator, only consume that:
                    len = 1;
                    break;
                }
                if (len != 0 and is_word_sep(line[len]))
                    break;
                len += 1;
            }

            // Store the word found:
            const result = line[0..len];

            // Also seek forward all space characters:
            while (len < line.len and is_space(line[len])) {
                len += 1;
            }

            li.line = line[len..];
            return result;
        }

        fn is_word_sep(c: u8) bool {
            if (is_space(c))
                return true;

            return switch (c) {
                ',', '*' => true,
                else => false,
            };
        }

        const is_space = std.ascii.isWhitespace;
    };
};

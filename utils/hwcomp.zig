const std = @import("std");

pub fn main(init: std.process.Init) !u8 {
    const source: []const u8 = blk: {
        var writer: std.Io.Writer.Allocating = .init(init.arena.allocator());

        var buffer: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().reader(init.io, &buffer);

        _ = try reader.interface.streamRemaining(&writer.writer);

        break :blk writer.written();
    };

    var tok: Tokenizer = .{
        .code = source,
    };
    {
        errdefer {
            const line, const col = location_from_pos(source, tok.pos);
            std.debug.print("syntax error in {}:{}\n", .{ line, col });
        }

        while (try tok.next()) |token| {
            std.debug.print("{}\n", .{token});
        }
    }

    return 0;
}

fn location_from_pos(str: []const u8, pos: usize) struct { u32, u32 } {
    var line: u32 = 1;
    var col: u32 = 1;
    for (str[0..pos]) |c| {
        if (c == '\n') {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }
    return .{ line, col };
}

const Tokenizer = struct {
    code: []const u8,
    pos: usize = 0,

    pub fn next(tok: *Tokenizer) error{ SyntaxError, InvalidNumber }!?Token {
        try tok.skip_whitespace();
        if (tok.pos >= tok.code.len)
            return null;

        select: switch (tok.code[tok.pos]) {
            '.' => return tok.make_simple(.@"."),
            ',' => return tok.make_simple(.@","),
            ':' => return tok.make_simple(.@":"),
            '<' => return tok.make_simple(.@"<="),
            '[' => return tok.make_simple(.@"["),
            ']' => return tok.make_simple(.@"]"),
            '(' => return tok.make_simple(.@"("),
            ')' => return tok.make_simple(.@")"),
            '{' => return tok.make_simple(.@"{"),
            '}' => return tok.make_simple(.@"}"),
            '*' => return tok.make_simple(.@"*"),
            '|' => return tok.make_simple(.@"|"),
            '&' => return tok.make_simple(.@"&"),
            '!' => return tok.make_simple(.@"!"),
            '~' => return tok.make_simple(.@"~"),

            '\'' => {
                const str = try tok.slurp_string();
                for (str) |c| {
                    if (logic_to_bit(c) == null)
                        return error.SyntaxError;
                }
                return .{
                    .logic = str,
                };
            },

            '0'...'9' => {
                const str = tok.slurp(is_digit);
                std.debug.assert(str.len >= 1);
                const num = std.fmt.parseInt(u32, str, 10) catch return error.InvalidNumber;
                return .{
                    .integer = num,
                };
            },

            'A'...'Q',
            'a'...'q',
            'S'...'Z',
            's'...'z',
            '#',
            '_',
            '/',
            => {
                const str = tok.slurp(is_identifier);
                return .{
                    .identifier = str,
                };
            },

            'R', 'r' => {
                if (tok.pos + 1 < tok.code.len)
                    continue :select '_'; // continue with identifier case
                if (tok.code[tok.pos + 1] != '\'')
                    continue :select '_'; // continue with identifier case
                tok.pos += 1;
                const str = try tok.slurp_string();
                for (str) |c| {
                    if (logic_to_bit(c) == null)
                        return error.SyntaxError;
                }
                return .{
                    .resistor = str,
                };
            },

            else => return error.SyntaxError,
        }
    }

    fn slurp(tok: *Tokenizer, comptime accepted: fn (u8) bool) []const u8 {
        const start = tok.pos;
        while (tok.pos < tok.code.len and accepted(tok.code[tok.pos])) {
            tok.pos += 1;
        }
        const end = tok.pos;
        return tok.code[start..end];
    }

    fn slurp_string(tok: *Tokenizer) error{SyntaxError}![]const u8 {
        tok.pos += 1;
        const start = tok.pos;
        while (tok.pos < tok.code.len and tok.code[tok.pos] != '\'') {
            tok.pos += 1;
        }
        if (tok.pos >= tok.code.len)
            return error.SyntaxError;
        if (tok.code[tok.pos] != '\'')
            return error.SyntaxError;
        const end = tok.pos;
        tok.pos += 1;
        return tok.code[start..end];
    }

    fn make_simple(tok: *Tokenizer, token: Token) Token {
        const len = @tagName(token).len;
        std.debug.assert(len == 1 or len == 2);
        tok.pos += len;
        return token;
    }

    fn skip_whitespace(tok: *Tokenizer) error{SyntaxError}!void {
        while (tok.pos < tok.code.len) {
            if (!is_space(tok.code[tok.pos]))
                break;
            tok.pos += 1;
        }
        if (std.mem.startsWith(u8, tok.code[tok.pos..], "(*")) {
            const end = std.mem.indexOfPos(u8, tok.code, tok.pos, "*)") orelse return error.SyntaxError;
            tok.pos = end + 2;
            return tok.skip_whitespace();
        }
    }

    fn is_space(c: u8) bool {
        return switch (c) {
            '\r', ' ', '\t', '\n' => true,
            else => false,
        };
    }

    fn is_digit(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            else => false,
        };
    }

    fn is_identifier(c: u8) bool {
        return switch (c) {
            'a'...'z' => true,
            'A'...'Z' => true,
            '0'...'9' => true,
            '_', '#', '/' => true,
            else => false,
        };
    }

    fn logic_to_bit(c: u8) ?u1 {
        return switch (c) {
            '0', 'l', 'L' => 0,
            '1', 'h', 'H' => 1,
            else => null,
        };
    }
};

const Token = union(enum) {
    const Type = std.meta.Tag(Token);

    @".",
    @",",
    @":",
    @"<=",
    @"[",
    @"]",
    @"(",
    @")",

    @"{",
    @"}",

    /// Wildcard
    @"*",

    /// Diode OR
    @"|",

    /// Diode AND
    @"&",

    /// Logic inversion
    @"!",

    /// The bus joiner
    @"~",

    /// Resistor network, e.g. `R'H'`, `R'LLLLLLLH'`.
    /// Token body is content between quotes.
    resistor: []const u8,

    /// Logic values, e.g. `'H'`, `'HHLLHLH'`
    /// Token body is content between quotes.
    logic: []const u8,

    /// Identifier, e.g. `WE#` or `OPMUX_1`.
    identifier: []const u8,

    /// An integer value
    integer: u32,
};

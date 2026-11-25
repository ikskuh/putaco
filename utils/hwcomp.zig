const std = @import("std");

const shared = @import("shared");

const String = shared.String;
const StringPool = shared.StringPool;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;

    var strings: StringPool = .init(arena);
    defer strings.deinit();

    const source: SourceFile = blk: {
        var writer: std.Io.Writer.Allocating = .init(arena);

        var buffer: [4096]u8 = undefined;
        var reader = std.Io.File.stdin().reader(init.io, &buffer);

        _ = try reader.interface.streamRemaining(&writer.writer);

        break :blk try Tokenizer.run(arena, writer.written(), &strings);
    };

    var parser: Parser = .{
        .source = &source,
        .strings = &strings,
    };

    errdefer {
        const info = source.get_token_line_info(parser.pos);
        std.debug.print("syntax error in {}:{}\n", .{ info.line, info.column });
    }

    var compiler: Compiler = .{ .arena = arena };
    defer compiler.deinit(gpa);

    try compiler.compile(gpa, &parser);

    return 0;
}

const SourceFile = struct {
    code: []const u8,
    tokens: []const Token,
    offsets: []const usize,

    fn get_token_line_info(source: SourceFile, index: usize) LineInfo {
        return location_from_pos(source.code, source.offsets[index]);
    }

    fn get_char_line_info(source: SourceFile, pos: usize) LineInfo {
        return location_from_pos(source.code, pos);
    }

    fn location_from_pos(str: []const u8, pos: usize) LineInfo {
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
        return .{ .line = line, .column = col };
    }
};

const LineInfo = struct {
    line: u32,
    column: u32,
};

const Compiler = struct {
    arena: std.mem.Allocator,
    interfaces: std.AutoHashMapUnmanaged(String, *Interface) = .empty,
    instances: std.AutoArrayHashMapUnmanaged(String, *Instance) = .empty,
    wires: std.AutoArrayHashMapUnmanaged(String, Wire) = .empty,
    constants: ConstMap = .empty,
    assignments: std.ArrayList(Assignment) = .empty,

    pub fn deinit(cc: *Compiler, gpa: std.mem.Allocator) void {
        cc.instances.deinit(gpa);
        cc.interfaces.deinit(gpa);
        cc.wires.deinit(gpa);
        cc.constants.deinit(gpa);
        cc.assignments.deinit(gpa);
        cc.* = undefined;
    }

    pub fn throw_error(cc: *Compiler, maybe_parser: ?*Parser, comptime fmt: []const u8, args: anytype) error{SemanticError} {
        _ = cc;

        if (maybe_parser) |parser| {
            const pos = parser.pos;
            if (pos < parser.source.offsets.len) {
                const line = parser.source.get_token_line_info(pos);

                std.log.err("{}:{}: " ++ fmt, .{ line.line, line.column } ++ args);
            } else {
                std.log.err(fmt, args);
            }
        } else {
            std.log.err(fmt, args);
        }
        return error.SemanticError;
    }

    pub fn compile(cc: *Compiler, gpa: std.mem.Allocator, parser: *Parser) !void {
        while (!parser.eof()) {
            std.log.info("top level {?f}", .{parser.peek()});
            if (parser.try_take(.kw_component)) {
                const intf = try parser.take_interface(cc.arena, .component);

                const gop = try cc.interfaces.getOrPut(gpa, intf.name);
                if (gop.found_existing) {
                    return cc.throw_error(parser, "duplicate intf: {f}", .{intf.name});
                }
                gop.value_ptr.* = try cc.arena.create(Interface);
                gop.value_ptr.*.* = intf;
            } else if (parser.try_take(.kw_port)) {
                // ports directly create instances, not interfaces
                const intf = try parser.take_interface(cc.arena, .port);

                const gop = try cc.instances.getOrPut(gpa, intf.name);
                if (gop.found_existing) {
                    return cc.throw_error(parser, "duplicate port/instance: {f}", .{intf.name});
                }

                const intf_ptr = try cc.arena.create(Interface);
                intf_ptr.* = intf;

                gop.value_ptr.* = try Instance.create(cc.arena, intf_ptr, null);
            } else if (parser.try_take(.kw_instance)) {
                const name = try parser.take(.identifier);

                var multiplicity: ?u32 = null;
                if (parser.try_take(.@"[")) {
                    multiplicity = try parser.take(.integer);
                    if (multiplicity.? <= 1) {
                        return cc.throw_error(parser, "instance multiplicity must be at least 2!", .{});
                    }
                    try parser.take(.@"]");
                }

                try parser.take(.@"=");
                const type_name = try parser.take(.identifier);

                if (cc.wires.get(name) != null) {
                    return cc.throw_error(parser, "conflict: wire {f} already exists", .{name});
                }

                const intf = cc.interfaces.get(type_name) orelse {
                    return cc.throw_error(parser, "unknown interface {f}", .{type_name});
                };

                const gop = try cc.instances.getOrPut(gpa, name);
                if (gop.found_existing) {
                    return cc.throw_error(parser, "duplicate instance: {f}", .{name});
                }
                gop.value_ptr.* = try Instance.create(cc.arena, intf, multiplicity);
            } else if (parser.try_take(.kw_wire)) {
                const rref = try parser.take_rref();
                if (cc.instances.get(rref.name) != null) {
                    return cc.throw_error(parser, "conflict: instance {f} already exists", .{rref.name});
                }

                const gop = try cc.wires.getOrPut(gpa, rref.name);
                if (gop.found_existing) {
                    return cc.throw_error(parser, "duplicate wire: {f}", .{rref.name});
                }
                gop.value_ptr.* = .{
                    .name = rref.name,
                    .width = switch (rref.access) {
                        .full => 1,
                        .index, .broadcast => return error.SyntaxError,
                        .range => |r| r.width(),
                    },
                };
            } else if (parser.try_take(.kw_const)) {
                const name = try parser.take(.identifier);

                try parser.take(.@"=");

                const value = try parser.take(.integer);
                const gop = try cc.constants.getOrPut(gpa, name);
                if (gop.found_existing) {
                    return cc.throw_error(parser, "duplicate constant: {f}", .{name});
                }
                gop.value_ptr.* = value;
            } else if (parser.can_take(.identifier)) {
                const ref = try parser.take_ref();

                try parser.take(.@"<=");

                const expr = try parser.parse_expr(cc.arena);

                const assignment: Assignment = .{
                    .target = ref,
                    .source = expr,
                };

                try cc.validate_assignment(parser, assignment);

                try cc.assignments.append(gpa, assignment);
            } else {
                std.log.err("unexpected token {?f}", .{parser.peek()});
                return error.SyntaxError;
            }
        }

        try cc.validate_all_ports_assigned();
    }

    fn validate_all_ports_assigned(cc: *Compiler) !void {
        for (cc.instances.keys(), cc.instances.values()) |instance_name, instance| {
            for (instance.devices, 0..) |device, device_id| {
                for (device.ports.keys(), device.ports.values()) |port_name, *port| {
                    const driver_requirement = instance.get_pin_props(port);

                    for (0..port.interface.width) |bit_index| {
                        const driven = port.assigned.isSet(bit_index);

                        switch (driver_requirement) {
                            .must_not_drive => if (driven) {
                                const _discard = cc.throw_error(null, "{f}[{d}].{f}[{}] must not be driven.", .{
                                    instance_name, device_id,
                                    port_name,     bit_index,
                                });
                                switch (_discard) {
                                    error.SemanticError => {},
                                }
                            },

                            .needs_driver => if (!driven) {
                                const _discard = cc.throw_error(null, "{f}[{d}].{f}[{}] must be driven by another signal.", .{
                                    instance_name, device_id,
                                    port_name,     bit_index,
                                });
                                switch (_discard) {
                                    error.SemanticError => {},
                                }
                            },

                            .should_have_driver => if (!driven) {
                                std.log.warn("{f}[{d}].{f}[{}] should be driven by another signal.", .{
                                    instance_name, device_id,
                                    port_name,     bit_index,
                                });
                            },

                            // Just happily ignore these pins:
                            .may_have_driver => {},
                        }
                    }
                }
            }
        }
    }

    fn validate_assignment(cc: *Compiler, parser: *Parser, assignment: Assignment) !void {
        const dst_width = try cc.validate_ref(parser, assignment.target, .assignment);

        const src_width = try cc.validate_expr(parser, assignment.source);

        if (dst_width != src_width) {
            return cc.throw_error(parser, "assignment width mismatch. expected {} bits, but got {}", .{
                dst_width,
                src_width,
            });
        }
    }

    fn validate_expr(cc: *Compiler, parser: *Parser, expr: *const Expression) !u32 {
        return switch (expr.*) {
            .hardwired => |logic| logic.width, // always ok
            .resistors => |logic| logic.width, // always ok
            .reference => |ref| try cc.validate_ref(parser, ref, .expression),

            .concat => |sequence| {
                var width: u32 = 0;
                for (sequence) |*child| {
                    width += try cc.validate_expr(parser, child);
                }
                return width;
            },

            .joined, .diode_or, .diode_and => |siblings| {
                var width: u32 = undefined;
                for (siblings, 0..) |*sibling, i| {
                    const w = try cc.validate_expr(parser, sibling);
                    if (i == 0) {
                        width = w;
                    }
                    if (w != width) {
                        return cc.throw_error(parser, "network size mismatch: expected {}, found {}", .{
                            width,
                            w,
                        });
                    }
                }
                std.debug.assert(width > 0);
                return width;
            },

            .inverted => |child| return try cc.validate_expr(parser, child),
        };
    }

    fn validate_ref(cc: *Compiler, parser: *Parser, ref: Reference, context: enum { assignment, expression }) !u32 {
        switch (ref) {
            .instance => |_iref| {
                const iref, const sref = _iref;

                const inst = cc.instances.get(iref.name) orelse {
                    return cc.throw_error(parser, "undeclared instance {f}", .{iref.name});
                };

                switch (iref.access) {
                    .singleton => if (inst.multiplicity != null) {
                        return cc.throw_error(parser, "{f}: apply broadcast or indexing to multi-instances", .{iref.name});
                    },
                    .broadcast => switch (context) {
                        .assignment => if (inst.multiplicity == null) {
                            return cc.throw_error(parser, "{f}: broadcast can only be applied to multi-instances", .{iref.name});
                        },
                        .expression => return cc.throw_error(parser, "{f}: broadcast can only be used left of '<='", .{iref.name}),
                    },
                    .indexed => |index| if (inst.multiplicity) |limit| {
                        const idx = try index.resolve(&cc.constants);
                        if (idx >= limit) {
                            return cc.throw_error(parser, "{f}: index {} is out of range for {} instances", .{
                                iref.name,
                                idx,
                                limit,
                            });
                        }
                    } else {
                        return cc.throw_error(parser, "indexing can only be applied to multi-instances", .{});
                    },
                }

                const port = inst.interface.ports.get(sref.name) orelse {
                    return cc.throw_error(parser, "component {f} (via instance {f}) has no port {f}", .{
                        iref.name,
                        inst.interface.name,
                        sref.name,
                    });
                };

                if (!try sref.is_valid_for_width(&cc.constants, port.width)) {
                    return cc.throw_error(parser, "out of bounds access for port {f}:{f}", .{ iref.name, port.name });
                }

                return try sref.get_width(port.width);
            },

            .wire => |wref| {
                const wire = cc.wires.get(wref.name) orelse {
                    return cc.throw_error(parser, "undeclared wire {f}", .{wref.name});
                };

                if (!try wref.is_valid_for_width(&cc.constants, wire.width)) {
                    return cc.throw_error(parser, "out of bounds access for wire {f}", .{wire.name});
                }

                return wref.get_width(wire.width);
            },
        }
    }
};

const Assignment = struct {
    target: Reference,
    source: *const Expression,
};

const Interface = struct {
    pub const Kind = enum { port, component };

    name: String,
    kind: Kind,
    ports: std.AutoArrayHashMapUnmanaged(String, Port) = .empty,
};

const Port = struct {
    name: String,
    width: u32,
    dir: Direction,
};

const Instance = struct {
    interface: *const Interface,
    multiplicity: ?u32,

    devices: []Device,

    pub fn create(arena: std.mem.Allocator, interface: *const Interface, multiplicity: ?u32) !*Instance {
        const inst = try arena.create(Instance);
        errdefer arena.destroy(inst);

        inst.* = .{
            .interface = interface,
            .multiplicity = multiplicity,
            .devices = try arena.alloc(Device, multiplicity orelse 1),
        };

        for (inst.devices) |*device| {
            device.* = .{};
            try device.ports.ensureTotalCapacity(arena, interface.ports.count());
            for (interface.ports.keys(), interface.ports.values()) |key, *value| {
                device.ports.putAssumeCapacityNoClobber(key, .{
                    .interface = value, // we can safely store the Interface-internal ref here as the interface won't be mutated anymore.
                });
            }
        }

        return inst;
    }

    pub const DriveProperties = enum {
        /// This pin must not be driven in any case.
        must_not_drive,

        /// This pin always requires a driver.
        needs_driver,

        /// It's allowed for this pin to have a driver, but none is required.
        /// Rationale: This is for "tristate" outputs, where the pin can receive drive in some cases, but doesn't interpret the voltage.
        may_have_driver,

        /// It's allowed to not drive this pin, but it is recommended to do it.
        /// Rationale: An "inout" pin can consume the data in some cases.
        should_have_driver,
    };

    pub fn get_pin_props(instance: *const Instance, port: *const DevicePort) DriveProperties {
        return switch (instance.interface.kind) {
            .component => switch (port.interface.dir) {
                .out => .must_not_drive, // outputs must not have a driver
                .in => .needs_driver, // component inputs must all have a driver assigned.

                .inout => .should_have_driver, // Not every inout pin of a component needs to be treated as an input, but we should consider this
                .tristate => .may_have_driver,
            },
            .port => switch (port.interface.dir) {
                .out => .needs_driver, // outputs from our design always need a driver
                .in => .must_not_drive, // inputs must never be driven.

                .inout, .tristate => .should_have_driver, // tri-state outputs should have a driver, as otherwise they could be inputs.
            },
        };
    }

    /// A device is one of the elements inside an instance.
    const Device = struct {
        ports: std.AutoArrayHashMapUnmanaged(String, DevicePort) = .empty,
    };

    /// A device port contains information about the actual assignments/consumptions.
    const DevicePort = struct {
        interface: *const Port,

        // Each bit marks if a port signal is assigned.
        assigned: std.bit_set.Integer(64) = .empty,

        // Each bit marks if a port signal was connected to another port.
        connected: std.bit_set.Integer(64) = .empty,
    };
};

const Wire = struct {
    name: String,
    width: u32,
};

const Direction = enum {
    /// This is an input pin which never drives a signal.
    in,

    /// This is an output pin which always drives a signal.
    out,

    /// This is a tri-state pin which can drive the signal, and may interprets it.
    inout,

    /// This is a tri-state pin which can drive the signal, and never interprets it.
    tristate,

    /// Can this direction drive a signal?
    pub fn is_output(dir: Direction) bool {
        return switch (dir) {
            .in => false,
            .out => true,
            .inout => true,
            .tristate => true,
        };
    }

    /// Does this direction interpret a signal?
    pub fn is_input(dir: Direction) bool {
        return switch (dir) {
            .in => true,
            .out => false,
            .inout => true,
            .tristate => false,
        };
    }
};

const Expression = union(enum) {
    hardwired: Logic, // 'HL'
    resistors: Logic, // R'HL'
    reference: Reference, // FOO, FOO[0], FOO.BAR, FOO[*].BAR[3:0]

    concat: []Expression, // { … }

    joined: []Expression, // ~
    diode_or: []Expression, // |
    diode_and: []Expression, // &
    inverted: *Expression,
};

const Logic = struct {
    width: u32,
    bits: std.bit_set.Integer(64),

    pub fn parse(str: []const u8) !Logic {
        if (str.len > 64)
            return error.Overflow;

        var logic: Logic = .{
            .width = @intCast(str.len),
            .bits = .empty,
        };
        for (str, 0..) |c, i| {
            const level = Tokenizer.logic_to_bit(c) orelse return error.InvalidChar;
            logic.bits.setValue(logic.width - i - 1, level != 0);
        }
        return logic;
    }
};

const ConstMap = std.AutoArrayHashMapUnmanaged(String, u32);

const Index = union(enum) {
    numeric: u32,
    named: String,

    fn resolve(idx: Index, consts: *const ConstMap) !u32 {
        switch (idx) {
            .numeric => |i| return i,
            .named => |name| return consts.get(name) orelse {
                std.log.err("const {f} not found", .{name});
                return error.ConstNotFound;
            },
        }
    }
};

const BitRange = struct {
    low: u32,
    high: u32,

    pub fn width(r: BitRange) u32 {
        return r.high - r.low + 1;
    }

    pub fn is_valid_for_width(range: BitRange, w: u32) bool {
        return range.low < w and range.high < w;
    }
};

const Reference = union(enum) {
    wire: SignalRef,
    instance: struct { InstanceRef, SignalRef },
};

const InstanceRef = struct {
    name: String,
    access: union(enum) {
        singleton,
        indexed: Index,
        broadcast,
    },
};

const SignalRef = struct {
    name: String,
    access: union(enum) {
        full,
        index: Index,
        range: BitRange,
    },

    pub fn get_width(ref: SignalRef, port_width: u32) !u32 {
        return switch (ref.access) {
            .full => port_width,
            .index => return 1, // always a single bit wide
            .range => |r| return r.width(),
        };
    }

    pub fn is_valid_for_width(ref: SignalRef, consts: *const ConstMap, width: u32) !bool {
        return switch (ref.access) {
            .full => true,
            .index => |i| return (try i.resolve(consts)) < width,
            .range => |r| return r.is_valid_for_width(width),
        };
    }
};

const RangedRef = struct {
    name: String,
    access: union(enum) {
        full, // FOO
        index: Index, // FOO[<digits>]
        broadcast, // FOO[*]
        range: BitRange, // FOO[<digits>:<digits>]
    },

    fn to_instance_ref(rref: RangedRef) !InstanceRef {
        return .{
            .name = rref.name,
            .access = switch (rref.access) {
                .full => .singleton,
                .broadcast => .broadcast,
                .index => |i| .{ .indexed = i },
                .range => return error.InvalidRef,
            },
        };
    }
    fn to_signal_ref(rref: RangedRef) !SignalRef {
        return .{
            .name = rref.name,
            .access = switch (rref.access) {
                .full => .full,
                .broadcast => return error.InvalidRef,
                .index => |i| .{ .index = i },
                .range => |r| .{ .range = r },
            },
        };
    }
};

const Parser = struct {
    strings: *StringPool,
    source: *const SourceFile,
    pos: usize = 0,

    fn eof(parser: *const Parser) bool {
        return parser.pos >= parser.source.tokens.len;
    }

    fn peek(parser: *const Parser) ?Token {
        if (parser.eof())
            return null;
        return parser.source.tokens[parser.pos];
    }

    fn can_take(parser: *const Parser, kind: Token.Type) bool {
        const head = parser.peek() orelse return false;
        return head == kind;
    }

    fn try_take(parser: *Parser, kind: Token.Type) bool {
        const ok = parser.can_take(kind);
        if (ok) {
            parser.pos += 1;
        }
        return ok;
    }

    fn take(parser: *Parser, comptime kind: Token.Type) error{ EndOfFile, SyntaxError }!@FieldType(Token, @tagName(kind)) {
        const head = parser.peek() orelse return error.EndOfFile;

        switch (head) {
            kind => |body| {
                parser.pos += 1;
                return body;
            },
            else => return error.SyntaxError,
        }
    }

    fn take_ref(parser: *Parser) !Reference {
        const rref_head = try parser.take_rref();

        if (!parser.try_take(.@".")) {
            return .{ .wire = try rref_head.to_signal_ref() };
        }

        const rref_tail = try parser.take_rref();

        return .{
            .instance = .{
                try rref_head.to_instance_ref(),
                try rref_tail.to_signal_ref(),
            },
        };
    }

    fn take_rref(parser: *Parser) !RangedRef {
        const name = try parser.take(.identifier);
        var low: ?u32 = null;
        var high: ?u32 = null;
        var broadcast = false;
        var cref: ?String = null;

        if (parser.try_take(.@"[")) {
            if (parser.try_take(.@"*")) {
                broadcast = true;
            } else if (parser.can_take(.identifier)) {
                cref = try parser.take(.identifier);
            } else {
                high = try parser.take(.integer);

                if (parser.try_take(.@":")) {
                    low = try parser.take(.integer);
                }
            }

            try parser.take(.@"]");
        }

        return .{
            .name = name,
            .access = if (broadcast)
                .broadcast
            else if (cref) |ref|
                .{ .index = .{ .named = ref } }
            else if (low == null and high == null)
                .full
            else if (low == null and high != null)
                .{ .index = .{ .numeric = high.? } }
            else
                .{ .range = .{ .low = low.?, .high = high.? } },
        };
    }

    fn take_interface(parser: *Parser, gpa: std.mem.Allocator, kind: Interface.Kind) !Interface {
        const name = try parser.take(.identifier);

        var intf: Interface = .{
            .kind = kind,
            .name = name,
        };
        errdefer intf.ports.deinit(gpa);

        try parser.take(.@"{");
        while (!parser.try_take(.@"}")) {
            const dir: Direction = if (parser.try_take(.kw_input))
                .in
            else if (parser.try_take(.kw_output))
                .out
            else if (parser.try_take(.kw_inout))
                .inout
            else if (parser.try_take(.kw_tristate))
                .tristate
            else
                return error.SyntaxError;

            const rref = try parser.take_rref();

            const gop = try intf.ports.getOrPut(gpa, rref.name);
            if (gop.found_existing) {
                return error.DuplicateNet;
            }
            if (rref.access == .range and rref.access.range.low != 0) {
                return error.InvalidNet;
            }
            gop.value_ptr.* = .{
                .dir = dir,
                .name = rref.name,
                .width = switch (rref.access) {
                    .full => 1,
                    .range => |r| r.width(),
                    .index, .broadcast => return error.InvalidNet,
                },
            };
        }

        return intf;
    }

    fn parse_expr(parser: *Parser, arena: std.mem.Allocator) error{ OutOfMemory, SyntaxError, Overflow, EndOfFile, InvalidRef, InvalidChar }!*Expression {
        const atom = try parser.parse_atom_expr(arena);

        const sequence: Token.Type = if (parser.try_take(.@"|"))
            .@"|"
        else if (parser.try_take(.@"&"))
            .@"&"
        else if (parser.try_take(.@"~"))
            .@"~"
        else
            return atom;

        var list: std.ArrayList(Expression) = .empty;
        defer list.deinit(arena);

        try list.append(arena, atom.*);

        while (true) {
            const next = try parser.parse_atom_expr(arena);
            try list.append(arena, next.*);
            if (!parser.try_take(sequence))
                break;
        }

        const slice = try list.toOwnedSlice(arena);

        const expr = try arena.create(Expression);
        errdefer arena.destroy(expr);
        expr.* = switch (sequence) {
            .@"&" => .{ .diode_and = slice },
            .@"|" => .{ .diode_or = slice },
            .@"~" => .{ .joined = slice },
            else => unreachable,
        };
        return expr;
    }

    fn parse_atom_expr(parser: *Parser, arena: std.mem.Allocator) !*Expression {
        if (parser.try_take(.@"(")) {
            const expr = parser.parse_expr(arena);
            try parser.take(.@")");
            return expr;
        }
        if (parser.try_take(.@"{")) {
            var list: std.ArrayList(Expression) = .empty;
            defer list.deinit(arena);

            while (!parser.try_take(.@"}")) {
                if (list.items.len > 0)
                    try parser.take(.@",");
                const expr = try parser.parse_expr(arena);
                try list.append(arena, expr.*);
            }

            const slice = try list.toOwnedSlice(arena);

            const expr = try arena.create(Expression);
            expr.* = .{ .concat = slice };
            return expr;
        }

        const expr = try arena.create(Expression);
        errdefer arena.destroy(expr);

        if (parser.try_take(.@"!")) {
            const child = try parser.parse_atom_expr(arena);
            expr.* = .{ .inverted = child };
            return expr;
        }

        if (parser.can_take(.resistor)) {
            const res = try parser.take(.resistor);
            expr.* = .{ .resistors = try .parse(res) };
            return expr;
        }

        if (parser.can_take(.logic)) {
            const res = try parser.take(.logic);
            expr.* = .{ .hardwired = try .parse(res) };
            return expr;
        }

        const ref = try parser.take_ref();
        expr.* = .{ .reference = ref };
        return expr;
    }
};

const Tokenizer = struct {
    strings: *StringPool,
    code: []const u8,
    pos: usize = 0,

    fn run(allocator: std.mem.Allocator, code: []const u8, strings: *StringPool) error{ SyntaxError, InvalidNumber, OutOfMemory }!SourceFile {
        var tok: Tokenizer = .{ .code = code, .strings = strings };

        errdefer {
            const info = SourceFile.location_from_pos(code, tok.pos);
            std.debug.print("syntax error in {}:{}\n", .{ info.line, info.column });
        }

        var cnt: usize = 0;
        while (try tok.next()) |_| cnt += 1;

        tok.pos = 0;

        const stream = try allocator.alloc(Token, cnt);
        const offsets = try allocator.alloc(usize, cnt);
        for (offsets, stream) |*o, *t| {
            o.* = tok.pos;
            t.* = (tok.next() catch unreachable) orelse unreachable;
        }
        return .{
            .code = code,
            .tokens = stream,
            .offsets = offsets,
        };
    }

    pub fn next(tok: *Tokenizer) error{ SyntaxError, InvalidNumber, OutOfMemory }!?Token {
        try tok.skip_whitespace();
        if (tok.pos >= tok.code.len)
            return null;

        select: switch (tok.code[tok.pos]) {
            '.' => return tok.make_simple(.@"."),
            ',' => return tok.make_simple(.@","),
            '=' => return tok.make_simple(.@"="),
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
                var str = tok.slurp(is_digit);
                std.debug.assert(str.len >= 1);

                const suffix = tok.slurp(is_identifier);
                if (suffix.len > 0) {
                    // this isn't a number, but an identifier like "1A#", thanks 74xx
                    str.len += suffix.len;
                    std.debug.assert(str.ptr + str.len == suffix.ptr + suffix.len);
                    return .{ .identifier = try tok.strings.get_or_put(str) };
                }

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
            '-',
            '/',
            => {
                const str = tok.slurp(is_identifier);
                if (tok.peek() == ':') {
                    tok.pos += 1;

                    const Keyword = enum {
                        component,
                        port,
                        input,
                        output,
                        inout,
                        instance,
                        wire,
                        tristate,
                        @"const",
                    };

                    const kw = std.meta.stringToEnum(Keyword, str) orelse {
                        std.log.err("invalid keyword: {s}", .{str});
                        return error.SyntaxError;
                    };

                    return switch (kw) {
                        .wire => .kw_wire,
                        .component => .kw_component,
                        .input => .kw_input,
                        .output => .kw_output,
                        .inout => .kw_inout,
                        .tristate => .kw_tristate,
                        .instance => .kw_instance,
                        .port => .kw_port,
                        .@"const" => .kw_const,
                    };
                }

                return .{
                    .identifier = try tok.strings.get_or_put(str),
                };
            },

            'R', 'r' => {
                if (tok.pos + 1 >= tok.code.len)
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

            else => {
                std.log.err("unexpected char '{c}'", .{tok.code[tok.pos]});
                return error.SyntaxError;
            },
        }
    }

    fn peek(tok: *const Tokenizer) ?u8 {
        if (tok.pos >= tok.code.len)
            return null;
        return tok.code[tok.pos];
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
            '_', '#', '/', '-' => true,
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
    @"=",
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
    identifier: String,

    /// An integer value
    integer: u32,

    kw_component,
    kw_port,
    kw_input,
    kw_output,
    kw_inout,
    kw_tristate,
    kw_instance,
    kw_wire,
    kw_const,

    pub fn format(t: Token, writer: *std.Io.Writer) !void {
        switch (t) {
            .resistor => |data| try writer.print("Token(resistor=R'{s}')", .{data}),
            .logic => |data| try writer.print("Token(logic='{s}')", .{data}),
            .identifier => |data| try writer.print("Token(identifier={f})", .{data}),
            .integer => |data| try writer.print("Token(integer={d})", .{data}),
            .kw_component,
            .kw_port,
            .kw_input,
            .kw_output,
            .kw_inout,
            .kw_tristate,
            .kw_instance,
            .kw_wire,
            .kw_const,
            => try writer.print("Token({s}:)", .{@tagName(t)[3..]}),
            else => {
                try writer.print("Token({t})", .{t});
            },
        }
    }
};

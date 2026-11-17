const std = @import("std");

const putaco = @import("putaco");

pub fn main(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());

    if (argv.len < 2) {
        return error.NoArgs;
    }
    const filename = argv[1];

    const program = try std.Io.Dir.cwd().readFileAlloc(init.io, filename, init.arena.allocator(), .limited(1 << 20));

    var mem: Memory = .{};

    var sim: putaco.simulator.Simulator = .{};

    var stat_seeking: usize = 0;
    var stat_waiting: usize = 0;
    var stat_executing: usize = 0;

    main_loop: while (true) {
        for (program) |byte| {
            const result = sim.step(mem.interface(), @fromBackingInt(byte));
            switch (result) {
                .halt => break :main_loop,
                .seeking => stat_seeking +|= 1,
                .waiting => stat_waiting +|= 1,
                .executing => stat_executing +|= 1,
            }
        }
    }

    const total = stat_seeking +| stat_waiting +| stat_executing;
    std.log.info("seeking:   {d: >6}/{} ({d:3.1}%)", .{ stat_seeking, total, stat_perc(stat_seeking, total) });
    std.log.info("waiting:   {d: >6}/{} ({d:3.1}%)", .{ stat_waiting, total, stat_perc(stat_waiting, total) });
    std.log.info("executing: {d: >6}/{} ({d:3.1}%)", .{ stat_executing, total, stat_perc(stat_executing, total) });
}

fn stat_perc(rel: usize, total: usize) f64 {
    const permille: f64 = @floatFromInt(1000 *| rel / total);

    return permille / 10.0;
}

const MmioAddress = enum(u4) {
    data = 0,
    status = 1,
    physical = 2,
    segment = 3,
    bank0 = 4,
    bank1 = 5,
    _,
};

const Leds = packed struct(u8) {
    led0: u1,
    led1: u1,
    led2: u1,
    led3: u1,
    led4: u1,
    led5: u1,
    led6: u1,
    led7: u1,
};

const IoStatus = packed struct(u8) {
    rxf: bool, // data available if true
    txe: bool, // space available if true
    @"suspend": bool,
    configured: bool,
    _unused: u4 = 0,
};

const Memory = struct {
    ram: [16385]u8 = undefined,

    switches: u8 = 0,
    leds: Leds = @fromBackingInt(0),
    seg7: u8 = 0,

    bank0: u8 = 0,
    bank1: u8 = 0,

    fn interface(mem: *Memory) putaco.simulator.MemoryInterface {
        return .{
            .context = mem,
            .read_fn = intf_read,
            .write_fn = intf_write,
        };
    }

    fn read_mmio(mem: *Memory, addr: MmioAddress) u8 {
        return switch (addr) {
            .data => 0x00, // TODO
            .status => @backingInt(IoStatus{
                .rxf = false,
                .txe = true,
                .@"suspend" = false,
                .configured = true,
            }),
            .physical => mem.switches,
            .segment => mem.seg7,
            .bank0 => mem.bank0,
            .bank1 => mem.bank1,

            _ => {
                std.log.warn("read from unassigned mmio address {}", .{@backingInt(addr)});
                return 0;
            },
        };
    }

    fn write_mmio(mem: *Memory, addr: MmioAddress, value: u8) void {
        switch (addr) {
            .data => std.log.info("out: 0x{X:0>2} (\"{f}\")", .{ value, std.zig.fmtString(&.{value}) }),
            .status => std.log.info("send immediate", .{}), // TODO
            .physical => {
                mem.leds = @bitCast(value);
                std.log.info("LEDs: {} {} {} {} {} {} {} {}", .{
                    mem.leds.led0,
                    mem.leds.led1,
                    mem.leds.led2,
                    mem.leds.led3,
                    mem.leds.led4,
                    mem.leds.led5,
                    mem.leds.led6,
                    mem.leds.led7,
                });
            },
            .segment => {
                mem.seg7 = value;
                // TODO
            },
            .bank0 => mem.bank0 = value,
            .bank1 => mem.bank1 = value,

            _ => std.log.warn("write to unassigned mmio address {} = {}", .{ @backingInt(addr), value }),
        }
    }

    const Addr = union(enum) {
        mmio: MmioAddress,
        fixed: u7,
        bank0: u6,
        bank1: u6,
    };

    fn resolve(addr: u8) Addr {
        return switch (addr) {
            0...15 => .{ .mmio = @fromBackingInt(@truncate(addr)) },
            16...127 => .{ .fixed = @truncate(addr) },
            128...191 => .{ .bank0 = @truncate(addr) },
            192...255 => .{ .bank1 = @truncate(addr) },
        };
    }

    fn banked(bank: u8, offset: u6) u14 {
        const Chunk = packed struct(u14) {
            offset: u6,
            bank: u8,
        };
        return @bitCast(Chunk{
            .offset = offset,
            .bank = bank,
        });
    }

    pub fn intf_read(ctx: ?*anyopaque, raw_addr: u8) u8 {
        const mem: *Memory = @ptrCast(@alignCast(ctx.?));

        const addr = resolve(raw_addr);
        return switch (addr) {
            .mmio => |offset| mem.read_mmio(offset),
            .fixed => |offset| mem.ram[offset],
            .bank0 => |offset| mem.ram[banked(mem.bank0, offset)],
            .bank1 => |offset| mem.ram[banked(mem.bank1, offset)],
        };
    }

    pub fn intf_write(ctx: ?*anyopaque, raw_addr: u8, value: u8) void {
        const mem: *Memory = @ptrCast(@alignCast(ctx.?));

        const addr = resolve(raw_addr);
        switch (addr) {
            .mmio => |offset| mem.write_mmio(offset, value),
            .fixed => |offset| mem.ram[offset] = value,
            .bank0 => |offset| mem.ram[banked(mem.bank0, offset)] = value,
            .bank1 => |offset| mem.ram[banked(mem.bank1, offset)] = value,
        }
    }
};

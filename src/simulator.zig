const std = @import("std");

const putaco = @import("putaco");

pub fn main(init: std.process.Init) !void {
    _ = init;

    var sim: putaco.simulator.Simulator = .{};

    sim.step(undefined, undefined);
}

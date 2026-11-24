const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .safe });

    const aux_dir: std.Build.InstallDir = .{ .custom = "aux" };

    const shared_mod = b.createModule(.{
        .root_source_file = b.path("src/shared.zig"),
    });

    //
    // Generate the ALU look-up table and install it to aux.
    //

    const gen_alu_exe = b.addExecutable(.{
        .name = "gen-alu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen-alu.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_alu_gen = b.addRunArtifact(gen_alu_exe);

    const alu_blob_path = run_alu_gen.captureStdOut(.{ .basename = "alu.bin" });

    b.getInstallStep().dependOn(&b.addInstallFileWithDir(alu_blob_path, aux_dir, "alu.bin").step);

    //
    // Create the putaco module which needs the alu file.
    //

    const putaco_mod = b.addModule("putaco", .{
        .root_source_file = b.path("src/putaco.zig"),
        .imports = &.{
            .{ .name = "alu.bin", .module = b.createModule(.{
                .root_source_file = alu_blob_path,
            }) },
        },
    });

    //
    // Build the small putaco simulator
    //
    const sim_exe = b.addExecutable(.{
        .name = "simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simulator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "putaco", .module = putaco_mod },
            },
        }),
    });

    b.installArtifact(sim_exe);

    //
    // Build the putaco assembler
    //
    const asm_exe = b.addExecutable(.{
        .name = "assembler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/assembler.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "putaco", .module = putaco_mod },
                .{ .name = "shared", .module = shared_mod },
            },
        }),
    });

    b.installArtifact(asm_exe);

    //
    // Build our netlist compiler.
    //
    const netlist_exe = b.addExecutable(.{
        .name = "hwcomp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("utils/hwcomp.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared_mod },
            },
        }),
    });
    b.installArtifact(netlist_exe);
}

const std = @import("std");
const Target = std.Target;
const Build = std.Build;
const Compile = Build.Step.Compile;
const CrossTarget = std.zig.CrossTarget;
const Feature = Target.Cpu.Feature;
const InstallArtifact = Build.Step.InstallArtifact;

pub fn build(b: *std.Build) void {
    const features = Target.x86.Feature;

    var enabled_features = Feature.Set.empty;
    var disabled_features = Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(features.mmx));
    disabled_features.addFeature(@intFromEnum(features.sse));
    disabled_features.addFeature(@intFromEnum(features.sse2));
    disabled_features.addFeature(@intFromEnum(features.avx));
    disabled_features.addFeature(@intFromEnum(features.avx2));
    enabled_features.addFeature(@intFromEnum(features.soft_float));

    const query = CrossTarget{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    const target = b.resolveTargetQuery(query);
    const optimize = b.standardOptimizeOption(.{});
    const kernel = b.addExecutable(.{
        .name = "KovOS.elf",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });

    kernel.link_z_max_page_size = 0x1000;
    kernel.link_z_common_page_size = 0x1000;
    kernel.link_gc_sections = true;
    kernel.link_gc_sections = true;

    kernel.root_module.red_zone = false;
    kernel.setLinkerScript(.{ .path = "linker.ld" });

    const cwd = std.fs.cwd();

    const assembly_files = [_][]const u8{
        "boot",
        // "long",
    };

    const asm_dir = b.fmt("{s}/nasm-o", .{b.cache_root.path.?});
    cwd.deleteTree(asm_dir) catch {};
    cwd.makeDir(asm_dir) catch @panic("asm");
    inline for (assembly_files) |file| {
        const in = b.fmt("src/arch/x86_64/{s}.s", .{file});
        const out = b.fmt("{s}/{s}.o", .{ asm_dir, file });
        const nasm = b.addSystemCommand(&.{ "nasm", in, "-f", "elf64", "-o", out });
        kernel.addObjectFile(.{ .path = out });
        kernel.step.dependOn(&nasm.step);
    }

    var kernel_install = b.addInstallArtifact(kernel, .{});

    const iso_dir = b.fmt("{s}/iso_root", .{b.cache_root.path.?});
    const iso_dir_boot = b.fmt("{s}/iso_root/boot", .{b.cache_root.path.?});
    const iso_dir_boot_grub = b.fmt("{s}/iso_root/boot/grub", .{b.cache_root.path.?});
    const kernel_path = b.getInstallPath(kernel_install.dest_dir.?, kernel.out_filename);
    const iso_path = b.fmt("{s}/KovOS.iso", .{b.exe_dir});

    cwd.deleteTree("iso") catch {};

    const grub_dir = cwd.makeOpenPath(iso_dir_boot_grub, .{}) catch @panic("grub");

    const copy_kernel = b.addSystemCommand(&.{ "cp", kernel_path, iso_dir_boot });
    copy_kernel.step.dependOn(&kernel_install.step);

    cwd.copyFile("grub.cfg", grub_dir, "grub.cfg", .{}) catch @panic("grub");

    const iso_cmd = b.addSystemCommand(&.{ "grub-mkrescue", "-o", iso_path, iso_dir });
    iso_cmd.step.dependOn(&copy_kernel.step);

    const qemu_iso_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-cdrom",
        iso_path,
        // "-serial",
        // "stdio",
        // "-vga",
        // "virtio",
        // "-m",
        // "2G",
        "-no-reboot",
        "-no-shutdown",
    };
    const qemu_iso_cmd = b.addSystemCommand(qemu_iso_cmd_str);
    qemu_iso_cmd.step.dependOn(b.getInstallStep());

    const debug_cmd = b.addSystemCommand(qemu_iso_cmd_str ++ &[_][]const u8{ "-s", "-S" });
    debug_cmd.step.dependOn(b.getInstallStep());

    const qemu_kernel_cmd_str = &[_][]const u8{
        "qemu-system-x86_64",
        "-serial",
        "stdio",
        "-vga",
        "std",
        "-kernel",
        kernel_path,
    };

    const run_iso_step = b.step("run", "Run the iso");
    run_iso_step.dependOn(&qemu_iso_cmd.step);

    const debug_step = b.step("debug", "Debug the iso");
    debug_step.dependOn(&debug_cmd.step);

    const qemu_kernel_cmd = b.addSystemCommand(qemu_kernel_cmd_str);
    qemu_kernel_cmd.step.dependOn(&kernel_install.step);

    const run_kernel_step = b.step("run-kernel", "Run the kernel");
    run_kernel_step.dependOn(&qemu_kernel_cmd.step);

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&kernel_install.step);

    const iso_step = b.step("iso", "Build an ISO image");
    iso_step.dependOn(&iso_cmd.step);

    b.default_step.dependOn(iso_step);
}

// fn addBootloader(b: *Build, kernel: *Compile, target: Target)

// const iso_dir_modules = b.fmt("{s}/iso_root/modules", .{b.cache_root.path.?});
// const symbol_file_path = b.fmt("{s}/ZOS.map", .{b.exe_dir});

// const symbol_info_cmd_str = &[_][]const u8{
//     "/bin/sh", "-c", std.mem.concat(b.allocator, u8, &[_][]const u8{
//         "mkdir -p ",
//         iso_dir_modules,
//         "&&",
//         "readelf -s --wide ",
//         kernel_path,
//         "| grep -F \"FUNC\" | awk '{$1=$3=$4=$5=$6=$7=\"\"; print $0}' | sort -k 1 > ",
//         symbol_file_path,
//         " && ",
//         "echo \"\" >> ",
//         symbol_file_path,
//     }) catch unreachable,
// };
// const symbol_cmd = b.addSystemCommand(symbol_info_cmd_str);
// symbol_cmd.step.dependOn(&kernel_install.step);

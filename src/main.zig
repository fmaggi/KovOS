comptime {
    _ = @import("arch/x86_64/boot.zig");
}

const Multiboot = @import("arch/x86_64/multiboot2.zig");

const vga = @import("vga.zig");
const std = @import("std");

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    vga.set(0, 0);
    const red = vga.Color.init(.White, .Red);
    vga.write("Error: ", red);
    vga.write(msg, red);

    if (@import("builtin").mode == .Debug) {
        @breakpoint();
    }

    while (true) {
        asm volatile ("hlt");
    }
}

pub const std_options = struct {
    pub fn logFn(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = level;

        const black = vga.Color.init(.White, .Black);
        if (scope != std.log.default_log_scope) {
            vga.write(@tagName(scope), black);
        }

        var buf: [100]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, format, args) catch @panic("Format too long");
        vga.write(str, black);
        vga.putChar('\n', black);
    }
};

const Section = struct {
    address: u64,
    end: u64,
};

fn kernelSection(sections: *const Multiboot.ElfSections) Section {
    var start: usize = std.math.maxInt(u64);
    var end: usize = 0;
    var it = sections.iterator();
    while (it.next()) |section| {
        const s = section.address();
        const len = section.size();
        if (s < start) {
            start = s;
        }

        if (s + len > end) {
            end = s + len;
        }
    }

    return .{
        .address = start,
        .end = end,
    };
}

pub export fn kmain(magic: usize, address: usize) callconv(.C) void {
    if (magic != 0x36d76289) {
        @panic("No magic");
    }

    const boot_info = Multiboot.init(address) catch |e| {
        @panic(@errorName(e));
    };

    // if (boot_info.getTag(Multiboot.MemMap)) |memap| {
    //     const blue = vga.Color.init(.White, .Black);
    //     vga.write("Memory areas:\n", blue);
    //
    //     for (memap.areas()) |area| {
    //         if (area.type > 0) {
    //             var buf: [100]u8 = undefined;
    //             const str = std.fmt.bufPrint(&buf, "  start: 0x{x} len: 0x{x} ({})\n", .{
    //                 area.address,
    //                 area.len,
    //                 area.type,
    //             }) catch unreachable;
    //             vga.write(str, blue);
    //         }
    //     }
    // }

    if (boot_info.getTag(Multiboot.ElfSections)) |elf| {
        std.log.info("Elf Sections:", .{});

        var it = elf.iterator();
        while (it.next()) |section| {
            std.log.info("{s} 0x{x} 0x{x} ({})", .{
                section.name(),
                section.address(),
                section.size(),
                section.typ(),
            });
        }
    }
    vga.write("Ok", vga.Color.init(.White, .Green));
}

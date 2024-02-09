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

    while (true) {
        @breakpoint();
    }
}

pub export fn kmain(magic: usize, address: usize) callconv(.C) void {
    if (magic != 0x36d76289) {
        @panic("No magic");
    }

    if (address == 0) {
        @panic("No address");
    }

    const boot_info = Multiboot.init(address) catch |e| {
        @panic(@errorName(e));
    };

    if (boot_info.getTag(Multiboot.MemMap)) |memap| {
        const blue = vga.Color.init(.White, .Black);
        vga.write("Memory areas:\n", blue);

        for (memap.areas()) |area| {
            if (area.type > 0) {
                var buf: [100]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "  start: 0x{x} len: 0x{x} ({})\n", .{
                    area.address,
                    area.len,
                    area.type,
                }) catch unreachable;
                vga.write(str, blue);
            }
        }
    }

    vga.write("Ok", vga.Color.init(.White, .Green));
}

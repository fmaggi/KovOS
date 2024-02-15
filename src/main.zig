comptime {
    _ = @import("arch/x86_64/boot.zig");
}

const mem = @import("memory.zig");

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

pub export fn kmain(magic: usize, address: usize) callconv(.C) void {
    if (magic != 0x36d76289) {
        @panic("No magic");
    }

    const boot_info = Multiboot.init(address) catch |e| {
        @panic(@errorName(e));
    };

    var allocator = mem.FrameAllocator.init(boot_info) catch |e| {
        @panic(@errorName(e));
    };

    std.log.debug("kernel: {any}", .{allocator.kernel.start});
    std.log.debug("bootloader: {any}", .{allocator.bootloader.start});

    var frame: mem.Frame = allocator.allocate() orelse @panic("no frame");
    while (allocator.allocate()) |f| {
        frame = f;
    }

    std.log.debug("{any}", .{frame});

    vga.write("Ok", vga.Color.init(.White, .Green));
}

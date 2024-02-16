comptime {
    _ = @import("arch/x86_64/boot.zig");
}

const mem = @import("memory/memory.zig");
const paging = mem.paging;

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

    const u: u64 = 42 * 512 * 512 * 4096;
    const addr: paging.VirtualAddress = @bitCast(u); // 42th P3 entry
    const page = paging.Page.containingAddress(addr);
    const frame = allocator.allocate() catch @panic("no more frames");
    std.log.debug("None = {any}, map to {any}", .{ addr.translate(), frame });
    paging.mapTo(page, frame, .{}, &allocator);
    std.log.debug("Some = {any}", .{addr.translate()});
    std.log.debug("next free frame: {any}", .{allocator.allocate() catch @panic("oom")});

    // var entry: paging.Entry = @bitCast(@as(u64, 0));

    // entry.present = true;
    // entry.physical_address = 1;

    // std.log.debug("{} {any}", .{ entry.physical_address, entry.getFrame() });

    vga.write("Ok", vga.Color.init(.White, .Green));
}

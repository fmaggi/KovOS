const mem = @import("memory.zig");

const PAGE_SIZE = mem.PAGE_SIZE;

pub fn Table(comptime level: usize) type {
    return switch (level) {
        1 => struct {
            entries: [512]Entry = undefined,
        },
        2, 3, 4 => struct {
            const Self = @This();
            entries: [512]Entry,

            pub fn nextTable(self: *const Self, index: u32) ?*Table(level - 1) {
                return @ptrFromInt(nextTableAddress(self, self.entries[index], index));
            }
        },
        else => @compileError("Invalid table level"),
    };
}

fn nextTableAddress(self: *const anyopaque, entry: Entry, index: u32) usize {
    if (entry.present and !entry.huge) {
        const address: usize = @intFromPtr(self);
        return (address << 9) | (index << 12);
    }
    return 0;
}

pub const Entry = packed struct(u64) {
    const PhysicalAddressOffset = @bitOffsetOf(Entry, "physical_address");
    comptime {
        if (1 << PhysicalAddressOffset != PAGE_SIZE) @compileError("Invalid physical address offset");
    }

    present: bool,
    writable: bool,
    user_accesible: bool,
    write_through: bool,
    disable_cache: bool,
    accesed: bool,
    dirty: bool,
    huge: bool,
    global: bool,
    available0: u3,
    physical_address: u40,
    available1: u11,
    no_execute: bool,

    pub fn getFrame(self: Entry) ?mem.Frame {
        // frames are page aligned, and so is physical_address
        // so no need to convert anyhing
        return if (self.present)
            .{ .number = self.physical_address }
        else
            null;
    }
};

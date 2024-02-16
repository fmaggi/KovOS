const mem = @import("../memory.zig");

const PAGE_SIZE = mem.PAGE_SIZE;
const Frame = mem.Frame;
const FrameAllocator = mem.FrameAllocator;

pub fn Table(comptime level: usize) type {
    return switch (level) {
        1 => struct {
            const Self = @This();

            entries: [512]Entry = undefined,

            pub fn zero(self: *Self) void {
                for (&self.entries) |*entry| {
                    entry.* = Entry.init(.{ .number = 0 }, .{});
                }
            }
        },
        2, 3, 4 => struct {
            const Self = @This();
            entries: [512]Entry,

            pub fn nextTable(self: *const Self, index: u32) ?*Table(level - 1) {
                return @ptrFromInt(nextTableAddress(self, self.entries[index], index));
            }

            pub fn nextTableCreate(
                self: *Self,
                index: u32,
                allocator: *FrameAllocator,
            ) FrameAllocator.Error!*Table(level - 1) {
                if (self.nextTable(index)) |table| {
                    return table;
                }

                if (self.entries[index].huge) @panic("We do not handle huge pages");

                const frame = try allocator.allocate();
                const flags = .{ .present = true, .writable = true };
                self.entries[index] = Entry.init(frame, flags);
                const next = self.nextTable(index).?;
                next.zero();
                return next;
            }

            pub fn zero(self: *Self) void {
                for (&self.entries) |*entry| {
                    entry.* = Entry.init(.{ .number = 0 }, .{});
                }
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

    pub fn init(f: Frame, flags: Flags) Entry {
        var self: Entry = @bitCast(flags);
        self.physical_address = @truncate(f.number);
        return self;
    }

    pub fn isUnused(self: Entry) bool {
        return @as(u64, @bitCast(self)) == 0;
    }

    pub fn frame(self: Entry) ?Frame {
        // frames are page aligned, and so is physical_address
        // so no need to convert anything
        return if (self.present)
            .{ .number = self.physical_address }
        else
            null;
    }

    pub const Flags = packed struct(u64) {
        comptime {
            if (@sizeOf(Flags) != 8) @compileError("Invalid Flags");
            if (@bitOffsetOf(Flags, "no_execute") != 63) @compileError("Invalid Flags");
        }

        present: bool = false,
        writable: bool = false,
        user_accesible: bool = false,
        write_through: bool = false,
        disable_cache: bool = false,
        accesed: bool = false,
        dirty: bool = false,
        huge: bool = false,
        global: bool = false,
        _: u54 = 0,
        no_execute: bool = false,
    };
};

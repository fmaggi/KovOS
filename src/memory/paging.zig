const std = @import("std");

const mem = @import("memory.zig");

const PAGE_SIZE = mem.PAGE_SIZE;
const Frame = mem.Frame;
const FrameAllocator = mem.FrameAllocator;

const table = @import("paging/table.zig");
const Table = table.Table;

pub const P4: *Table(4) = @ptrFromInt(@as(u64, 0xffffffff_fffff000));

pub const PhysicalAddress = u64;

pub fn mapTo(page: Page, frame: Frame, allocator: *FrameAllocator) void {
    var P3 = P4.nextTableCreate(page.p4, allocator) catch @panic("OOM");
    var P2 = P3.nextTableCreate(page.p3, allocator) catch @panic("OOM");
    var P1 = P2.nextTableCreate(page.p2, allocator) catch @panic("OOM");

    if (!P1.entries[page.p1].isUnused()) @panic("Used page");
    P1.entries[page.p1] = table.Entry.init(frame, .{ .present = true });
}

pub const VirtualAddress = packed struct(u64) {
    offset: u12,
    p1: u9,
    p2: u9,
    p3: u9,
    p4: u9,
    sign: u16,

    pub fn toInt(self: VirtualAddress) u64 {
        return @bitCast(self);
    }

    pub fn isValid(self: VirtualAddress) bool {
        const i: u64 = @bitCast(self);
        return i < 0x0000_8000_0000_0000 or i >= 0xffff_8000_0000_0000;
    }

    pub fn translate(self: VirtualAddress) ?PhysicalAddress {
        const page = Page.containingAddress(self);
        const entry = page.entry() orelse return null;
        const frame = entry.frame() orelse return null;
        return frame.number * PAGE_SIZE + self.offset;
    }
};

pub const Page = packed struct(u64) {
    p1: u9,
    p2: u9,
    p3: u9,
    p4: u9,
    sign: u16,
    padding: u12,

    pub fn toInt(self: Page) u64 {
        return @bitCast(self);
    }

    pub fn entry(self: Page) ?*table.Entry {
        const Huge = struct {
            pub fn page() ?*table.Entry {
                return null;
            }
        };

        const P3 = P4.nextTable(self.p4) orelse return null;
        const P2 = P3.nextTable(self.p3) orelse return Huge.page();
        const P1 = P2.nextTable(self.p2) orelse return Huge.page();

        return &P1.entries[self.p1];
    }

    pub fn containingAddress(address: VirtualAddress) Page {
        if (!address.isValid()) std.debug.panic("Invalid addres 0x{x}", .{address.toInt()});
        return @bitCast(address.toInt() / PAGE_SIZE);
    }
};

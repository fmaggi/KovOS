const std = @import("std");

const Multiboot = @import("../arch/x86_64/multiboot2.zig");

pub const paging = @import("paging.zig");
pub const FrameAllocator = @import("FrameAllocator.zig");

pub const Area = Multiboot.MemMap.Entry;

pub const PAGE_SIZE = 4096;

pub const Frame = struct {
    number: usize,

    pub fn containingAddress(address: usize) Frame {
        return .{ .number = address / PAGE_SIZE };
    }

    pub fn containingAreaStart(area: Area) Frame {
        return containingAddress(area.address);
    }

    pub fn containingAreaEnd(area: Area) Frame {
        return containingAddress(area.address + area.len - 1);
    }

    pub fn next(self: Frame) Frame {
        return .{ .number = self.number + 1 };
    }
};

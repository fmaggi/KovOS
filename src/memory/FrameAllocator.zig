const mem = @import("memory.zig");
const Frame = mem.Frame;
const Area = mem.Area;
const PAGE_SIZE = mem.PAGE_SIZE;

const Multiboot = @import("../arch/x86_64/multiboot2.zig");

const FrameAllocator = @This();

pub const Error = error{ NoMemMap, NoElfSections, OutOfMemory };

const Reserved = struct {
    start: Frame,
    end: Frame,

    pub fn contains(self: Reserved, frame: Frame) bool {
        return frame.number >= self.start.number and frame.number <= self.end.number;
    }
};

next: Frame,
current_area: ?u32,
areas: []Area,
kernel: Reserved,
bootloader: Reserved,

pub fn init(info: *Multiboot.Info) Error!FrameAllocator {
    const mem_map = info.getTag(Multiboot.MemMap) orelse return Error.NoMemMap;
    const sections = info.getTag(Multiboot.ElfSections) orelse return Error.NoElfSections;

    const areas = mem_map.areas();
    const first_area = chooseAreaAboveFrame(areas, Frame.containingAddress(0)) orelse return Error.OutOfMemory;
    const first_frame = Frame.containingAreaStart(areas[first_area]);

    const kernel = try getKernelSection(sections);
    const bootloader = .{
        .start = Frame.containingAddress(@intFromPtr(info)),
        .end = Frame.containingAddress(@intFromPtr(info) + info.total_size),
    };

    return .{
        .next = first_frame,
        .current_area = first_area,
        .areas = areas,
        .kernel = kernel,
        .bootloader = bootloader,
    };
}

pub fn allocate(self: *FrameAllocator) !Frame {
    while (self.current_area) |i| {
        const current_area_last_frame = Frame.containingAreaEnd(self.areas[i]);
        const frame = self.next;

        if (frame.number > current_area_last_frame.number) {
            self.next = try self.advanceArea();
        } else if (self.kernel.contains(frame)) {
            self.next = self.kernel.end.next();
        } else if (self.bootloader.contains(frame)) {
            self.next = self.bootloader.end.next();
        } else {
            self.next = self.next.next();
            return frame;
        }
    }
    return Error.OutOfMemory;
}

// advances current area and return next frame
fn advanceArea(self: *FrameAllocator) !Frame {
    self.current_area = chooseAreaAboveFrame(self.areas, self.next);

    const i = self.current_area orelse return Error.OutOfMemory;
    const area = self.areas[i];
    const frame = Frame.containingAreaStart(area);
    self.current_area = i;

    return if (self.next.number < frame.number)
        frame
    else
        self.next;
}

fn chooseAreaAboveFrame(areas: []Area, frame: Frame) ?u32 {
    var min: ?u32 = null;
    for (areas, 0..) |area, i| {
        if (Frame.containingAreaEnd(area).number < frame.number) continue;

        if (min == null) {
            min = @truncate(i);
            continue;
        }

        if (area.address < areas[min.?].address) {
            min = @truncate(i);
        }
    }

    return min;
}

fn getKernelSection(sections: *const Multiboot.ElfSections) !Reserved {
    var it = sections.iterator();

    var reserved: Reserved = blk: {
        const first = it.next() orelse return Error.NoElfSections;
        const start = first.address();
        const len = first.size();
        break :blk .{
            .start = Frame.containingAddress(start),
            .end = Frame.containingAddress(start + len),
        };
    };

    while (it.next()) |section| {
        const s = section.address();
        const len = section.size();
        if (s < reserved.start.number) {
            reserved.start = Frame.containingAddress(s);
        }

        if (s + len > reserved.end.number) {
            reserved.end = Frame.containingAddress(s + len);
        }
    }

    return reserved;
}

pub fn deallocate(self: FrameAllocator, frame: Frame) void {
    _ = self;
    _ = frame;
}

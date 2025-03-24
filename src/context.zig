const std = @import("std");

const Atomic = std.atomic.Value;

const Context = @This();

const Size = struct {
    row: Atomic(u32) = .{ .raw = 0 },
    col: Atomic(u32) = .{ .raw = 0 },
    changed: Atomic(bool) = .{ .raw = true }, // Set to true so first start will clear screen
};

// Never accessed cross-thread
const Flags = struct {
    am_pm: bool = false,
    red_tint: bool = false,
    show_date: bool = false,
};

size: Size = .{},
flags: Flags = .{},
running: Atomic(bool) = .{ .raw = true },

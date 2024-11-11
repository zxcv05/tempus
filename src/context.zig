const std = @import("std");

const Atomic = std.atomic.Value;

const Size = struct {
    row: Atomic(u32),
    col: Atomic(u32),
    changed: Atomic(bool),
};

size: Size,
running: Atomic(bool),

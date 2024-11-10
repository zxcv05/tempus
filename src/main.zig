const std = @import("std");
const datetime = @import("datetime").datetime;

const tz = @import("tz.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();

    const hour_offset = tz.get_timezone_hour_offset();

    const now = datetime.Time.now();
    std.debug.print("{d:0>2}:{d:0>2}:{d:0>2}\n", .{ now.hour + hour_offset, now.minute, now.second });
}

const std = @import("std");
const builtin = @import("builtin");

const c = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("time.h");
    }),
    else => @compileError("Unsupported OS"),
};

/// In minutes
pub fn get_timezone_offset() i16 {
    c.tzset();
    const current_time = c.time(null);
    const timeinfo = c.localtime(&current_time);
    return @intCast(@divFloor(timeinfo.*.tm_gmtoff, std.time.s_per_min));
}

const std = @import("std");
const builtin = @import("builtin");

// const time = @import("time_h");

const time = @cImport({
    @cInclude("time.h");
});

/// In minutes
pub fn get_timezone_offset() i16 {
    time.tzset();
    const current_time = time.time(null);
    const timeinfo = time.localtime(&current_time);
    return @intCast(@divFloor(timeinfo.*.tm_gmtoff, std.time.s_per_min));
}

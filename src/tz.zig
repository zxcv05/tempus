const std = @import("std");
const builtin = @import("builtin");

const time = @cImport({
    @cInclude("time.h");
});

pub fn get_timezone_hour_offset() i32 {
    time.tzset();
    const current_time = time.time(null);
    const timeinfo = time.localtime(&current_time);
    return @intCast(@divFloor(timeinfo.*.tm_gmtoff, std.time.s_per_hour));
}

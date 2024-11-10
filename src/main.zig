const std = @import("std");
const datetime = @import("datetime").datetime;

const tz = @import("tz.zig");
const art = @import("number_art.zig").art;
const Termios = @import("termios.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

pub fn main() !void {
    defer _ = gpa.deinit();

    const stdout = std.io.getStdOut();
    defer stdout.close();

    const stdin = std.io.getStdIn();
    defer stdin.close();

    const tz_offset = tz.get_timezone_offset();
    const timezone = datetime.Timezone.create("Local", tz_offset);

    const termios = try Termios.init();

    // Raw mode
    try termios.set();
    defer termios.reset() catch {};

    // Cursor visiblity
    _ = try stdout.write("\x1b[?25l");
    defer _ = stdout.write("\x1b[?25h") catch {};

    // Alternate buffer
    _ = try stdout.write("\x1b[?1049h");
    defer _ = stdout.write("\x1b[?1049l") catch {};

    // TODO(correctness): Handle WINCH signal
    const size = try Termios.get_size();

    var buffer: [64]u8 = undefined;
    main: while (true) {
        const start = std.time.nanoTimestamp();

        // Input handling
        while (true) {
            const read = stdin.read(buffer[4..]) catch |e| switch (e) {
                error.WouldBlock => 0,
                else => return e,
            };

            for (0..read) |i| switch (buffer[4 + i]) {
                3, // ctrl+c
                27, // escape
                => break :main,
                else => {},
            };

            if (read < buffer.len - 4) break;
        }

        // Render
        const now = datetime.Datetime.now().shiftTimezone(&timezone);

        const numbers = try std.fmt.bufPrint(buffer[0..4], "{d:0>2}{d:0>2}", .{ now.time.hour, now.time.minute });

        const block_width = 3;
        const block_height = 5;

        const x_mid_offset = 2;
        const x_mid = @divFloor(size.ws_col, 2) + x_mid_offset;
        const y_mid = @divFloor(size.ws_row, 2) - 1;

        for (0..4) |i| {
            const num = numbers[i] - '0'; // all inputs are between ascii 0 and ascii 9
            const current_art = art[num];

            const x_step: i8 = 3;
            const x_spacing = 10;
            const x_offset = (-x_spacing * 2) +
                @as(isize, @intCast(x_spacing * i)) +
                @as(isize, if (i < 2) -2 else 2);

            // Draw block
            for (0..block_height) |y| for (0..block_width) |x| {
                const art_bit_0: u15 = 0x4000;
                const art_index: u4 = @intCast(y * block_width + x);
                const representation: u6 = @intCast((block_width * block_height * i) + (x * block_height + y));

                const attr = attr_csi_ending: {
                    break :attr_csi_ending //
                    if (representation == now.time.second) "48;5;8" // highlight
                    else if (current_art & (art_bit_0 >> art_index) != 0) "1" // bold
                    else "38;5;238"; //dim
                };

                _ = try stdout.writer().print("\x1b[{d};{d}H" ++ "\x1b[{s}m" ++ "{d:0>2}" ++ "\x1b[m", .{
                    y_mid + y,
                    x_mid + x_offset + @as(isize, @intCast(x)) * x_step,
                    attr,
                    representation,
                });
            };
        }

        // Middle column
        inline for ([2]usize{ 1, 3 }) |y| {
            _ = try stdout.writer().print("\x1b[{d};{d}H", .{ y_mid + y, x_mid - x_mid_offset });
            _ = try stdout.write(if (@mod(now.time.second, 2) == 0) "🬇🬃" else "  ");
        }

        const end = std.time.nanoTimestamp();
        if (start >= end) continue;

        std.time.sleep(std.time.ns_per_ms * 125 - @as(u64, @intCast(end - start)));
    }
}

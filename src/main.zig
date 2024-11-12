const std = @import("std");
const datetime = @import("datetime").datetime;

const tz = @import("tz.zig");
const art = @import("ascii-art.zig");
const Termios = @import("termios.zig");
const Context = @import("context.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

var ctx = Context{};

pub fn main() !void {
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const stdout = std.io.getStdOut();
    defer stdout.close();

    const stdin = std.io.getStdIn();
    defer stdin.close();

    const help_fmt =
        \\Usage: {s} [-cr]
        \\
        \\  -c | Enable 12-hour clock
        \\  -r | Enable red-color mode
        \\
    ;

    for (args[1..]) |arg| {
        if (arg[0] != '-') _ = return try stdout.writer().print(help_fmt, .{args[0]});

        for (arg[1..]) |c| switch (c) {
            'c' => ctx.flags.am_pm = true, // 12 hour
            'r' => ctx.flags.red_tint = true, // red
            else => {
                return try stdout.writer().print(help_fmt, .{args[0]});
            },
        };
    }

    const tz_offset = tz.get_timezone_offset();
    const timezone = datetime.Timezone.create("Local", tz_offset);

    const termios = try Termios.init();

    try termios.set();
    defer termios.reset() catch {};

    _ = try stdout.write("\x1b[?25l"); // Cursor visiblity
    defer _ = stdout.write("\x1b[?25h") catch {};

    _ = try stdout.write("\x1b[?1049h"); // Alternate buffer
    defer _ = stdout.write("\x1b[?1049l") catch {};

    {
        const size = try Termios.get_size();
        ctx.size.col.store(size.ws_col, .unordered);
        ctx.size.row.store(size.ws_row, .unordered);
    }

    const sigaction = std.posix.Sigaction{
        .handler = .{ .handler = sigaction_handler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    try std.posix.sigaction(std.posix.SIG.WINCH, &sigaction, null);

    var last_second: u8 = 0xff;
    var buffer: [64]u8 = undefined;

    main: while (ctx.running.load(.seq_cst)) {
        const start = std.time.nanoTimestamp();

        // Input handling
        while (true) {
            const read = stdin.read(buffer[0..]) catch |e| switch (e) {
                error.WouldBlock => 0,
                else => return e,
            };

            for (0..read) |i| switch (buffer[i]) {
                3, // ctrl+c
                27, // escape
                => break :main,
                else => {},
            };

            if (read < buffer.len) break;
        }

        // Update
        if (ctx.size.changed.swap(false, .seq_cst)) {
            _ = try stdout.writeAll("\x1b[2J");
        }

        const now = datetime.Datetime.now().shiftTimezone(&timezone);

        // Render
        if (last_second != now.time.second) {
            last_second = now.time.second;

            const second = now.time.second;
            const minute = now.time.minute;
            const is_am = now.time.hour <= 12;
            const hour = calculate_hour: {
                var hour = now.time.hour;
                if (ctx.flags.am_pm) {
                    if (is_am and hour == 0) hour = 12;
                    if (!is_am) hour -= 12;
                }
                break :calculate_hour hour;
            };

            const numbers = try std.fmt.bufPrint(buffer[0..4], "{d:0>2}{d:0>2}", .{ hour, minute });

            const block_width = 3;
            const block_height = 5;

            const x_mid_offset = 2;
            const x_mid = @divFloor(ctx.size.col.load(.seq_cst), 2) + x_mid_offset;
            const y_mid = @divFloor(ctx.size.row.load(.seq_cst), 2) - 1;

            const x_step: i8 = 3;
            const x_spacing = 10;

            const color_highlight = if (ctx.flags.red_tint) art.redtint_highlight else art.default_highlight;
            const color_bold = if (ctx.flags.red_tint) art.redtint_bold else art.default_bold;
            const color_dim = if (ctx.flags.red_tint) art.redtint_dim else art.default_dim;

            // Draw hour and minute blocks
            for (0..4) |i| {
                const num = numbers[i] - '0'; // all inputs are between ascii 0 and ascii 9
                const current_art = art.blocks[num];

                const x_offset = (-x_spacing * 2) +
                    @as(isize, @intCast(x_spacing * i)) +
                    @as(isize, if (i < 2) -2 else 2);

                // Draw block
                for (0..block_height) |y| for (0..block_width) |x| {
                    const art_bit_0: u15 = 0x4000;
                    const art_index: u4 = @intCast(y * block_width + x);
                    const representation: u6 = @intCast((block_width * block_height * i) + (x * block_height + y));

                    const highlight = if (representation == second) color_highlight else "";
                    const color = if (current_art & (art_bit_0 >> art_index) != 0) color_bold else color_dim;

                    _ = try stdout.writer().print("\x1b[{d};{d}H" ++ "{s}{s}" ++ "{d:0>2}" ++ "\x1b[m", .{
                        y_mid + y,
                        x_mid + x_offset + @as(isize, @intCast(x)) * x_step,
                        highlight,
                        color,
                        representation,
                    });
                };
            }

            // AM / PM indicator
            if (ctx.flags.am_pm) {
                const x_offset = 4 + x_spacing * 2;

                for (0..block_height) |y| for (0..block_width) |x| {
                    const art_bit_0: u15 = 0x4000;
                    const art_index: u4 = @intCast(y * block_width + x);

                    const current_art = art.blocks[if (is_am) 10 else 11];
                    const color = if (current_art & (art_bit_0 >> art_index) != 0) color_bold else color_dim;

                    _ = try stdout.writer().print("\x1b[{d};{d}H" ++ "{s}" ++ "{s}" ++ "\x1b[m", .{
                        y_mid + y,
                        x_mid + x_offset + x * x_step,
                        color,
                        if (is_am) "am" else "pm",
                    });
                };
            }

            // Middle column
            const is_shown = @mod(second, 2) == 0;
            inline for ([2]usize{ 1, 3 }) |y| {
                _ = try stdout.writer().print("\x1b[{d};{d}H", .{ y_mid + y, x_mid - x_mid_offset });
                _ = try stdout.writer().print(
                    "{s}{s}",
                    if (is_shown)
                        .{ color_bold, "🬇🬃" }
                    else
                        .{ "", "  " },
                );
            }
        }

        const end = std.time.nanoTimestamp();
        if (start >= end) continue;

        std.time.sleep(std.time.ns_per_ms * 125 - @as(u64, @intCast(end - start)));
    }
}

fn sigaction_handler(signal: i32) callconv(.C) void {
    switch (signal) {
        std.posix.SIG.WINCH => {
            const size = Termios.get_size() catch return;

            ctx.size.changed.store(true, .seq_cst);
            ctx.size.col.store(size.ws_col, .seq_cst);
            ctx.size.row.store(size.ws_row, .seq_cst);
        },
        else => unreachable,
    }
}

// SPDX-License-Identifier: MIT
// Copyright (c) 2024 - 2025 Michael Ortmann

// TODO: If EndOFStream show lag of temperature
// TODO: Fetch zenith and dusk once a day https://wttr.in/pdx?format=zenith%20%z%20dusk%20%d"

const builtin = @import("builtin");
const config = @import("config");
const std = @import("std");

pub fn main() !void {
    const argv = std.os.argv;
    const progname = std.fs.path.basename(std.mem.span(argv[0]));

    if (argv.len != 3) {
        std.log.debug(
            "{s}: error: Command-line options\nUsage: {s} <latitude> <longitude>",
            .{ progname, progname },
        );
        return;
    }

    var next_minute_30: i128 = 0;

    const second = 1_000_000_000; // 1 second in nanoseconds
    const minute_30 = 30 * 60; // 30 minutes in nanoseconds

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var client = std.http.Client{ .allocator = allocator };

    var url_buf: [128]u8 = undefined;
    // Alternative:
    // https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}&current_weather=true
    // temperature = data['current_weather']['temperature']
    const url = try std.fmt.bufPrint(
        &url_buf,
        "https://api.met.no/weatherapi/locationforecast/2.0/?lat={s}&lon={s}",
        .{ argv[1], argv[2] },
    );
    var response_buffer: [65536]u8 = undefined;
    var fetch_options = std.http.Client.FetchOptions{
        .headers = .{
            // https://api.met.no/doc/TermsOfService -> Legal stuff -> Identification
            .user_agent = .{ .override = "user-agent: zig/" ++ builtin.zig_version_string ++ " (std.http) github.com/michaelortmann/zstatus " ++ config.git_commit },
        },
        .keep_alive = false,
        .location = .{ .url = url },
    };

    var temperature: []u8 = undefined;

    const file = try std.fs.openFileAbsolute("/etc/localtime", .{});
    var file_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&file_buffer);
    const tz = try std.Tz.parse(allocator, &file_reader.interface);
    file.close();

    // Precompute current timezone offset and next transition
    var now = std.time.timestamp();
    var offset: i32 = 0;
    var next_transition: usize = undefined;
    for (tz.transitions, 0..) |transition, i| {
        if (now >= transition.ts) {
            offset = transition.timetype.offset;
        } else {
            next_transition = i;
            break;
        }
    }

    var stdout_buffer: [128]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // https://ziglang.org/documentation/master/#while-with-Error-Unions
    while (true) : (now = std.time.timestamp()) {
        if (now >= next_minute_30) {
            // Renew writer, do not append
            var response_writer = std.Io.Writer.fixed(&response_buffer);
            fetch_options.response_writer = &response_writer;
            // Combine the if and switch expression
            // https://ziglang.org/documentation/master/#try
            if (client.fetch(fetch_options)) |fetch_result| {
                if (fetch_result.status == .ok) {
                    var i = std.mem.indexOf(u8, response_buffer[438..], ",\"air_temperature\":");
                    const start = 438 + i.? + 19;
                    i = std.mem.indexOf(u8, response_buffer[start..], ",");
                    temperature = response_buffer[start .. start + i.?];
                }
            } else |err| switch (err) {
                error.ConnectionRefused, error.ConnectionTimedOut, error.TemporaryNameServerFailure => std.log.debug("{s}: error: {}", .{ progname, err }),
                else => return err,
            }
            next_minute_30 = @divFloor(now, minute_30) * minute_30 + minute_30;
        }

        // Next timezone transition?
        if (now >= tz.transitions[next_transition].ts) {
            offset = tz.transitions[next_transition].timetype.offset;
            next_transition += 1;
        }
        // Add timezone offset
        now += offset;

        // Rata Die
        // TODO: Precompute and increment daily
        const days_since_epoch = @divFloor(now, std.time.s_per_day);
        const z = days_since_epoch + 719468;
        const doe = @mod(z, 146097);
        const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
        const days = [_][]const u8{ "Th", "Fr", "Sa", "Su", "Mo", "Tu", "We" };
        const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
        const mp = @divFloor((5 * doy + 2), 153);
        const day_of_week = days[@intCast(@mod(@divFloor(now, std.time.s_per_day), 7))];
        const day = doy - @divFloor((153 * mp + 2), 5) + 1;
        const hour = @abs(@mod(@divFloor(now, std.time.s_per_hour), 24));
        const min = @abs(@mod(@divFloor(now, std.time.s_per_min), 60));
        const sec = @abs(@mod(now, 60));

        // sway-bar(5)
        //   status_command <status command>
        //     Each line of text printed to stdout from this command will be displayed
        // by "line" a write to stdout is meant, not \n buffered line reading
        try stdout.print("{s} °C {s} {d} {d:0>2}:{d:0>2}:{d:0>2}", .{ temperature, day_of_week, day, hour, min, sec });
        try stdout.flush();
        // sleep until next second
        std.Thread.sleep(@intCast(second - @mod(std.time.nanoTimestamp(), second)));
    }
}

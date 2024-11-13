// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Michael Ortmann

// TODO Weather URL should be command line arg
// TODO If EndOFStream show lag of temperature
// TODO Fetch zenith and dusk once a day https://wttr.in/pdx?format=zenith%20%z%20dusk%20%d"

const builtin = @import("builtin");
const std = @import("std");
const zeit = @import("zeit");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var storage = std.ArrayList(u8).init(allocator);
    var next_minute_30: i128 = 0;
    const second = 1_000_000_000; // 1 second in nanoseconds
    const minute_30 = 30 * 60 * second; // 30 minutes in nanoseconds
    var result_temperature: []u8 = "";
    var client = std.http.Client{ .allocator = allocator };
    const local = try zeit.local(allocator, null);
    var buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());

    const fetch_options = std.http.Client.FetchOptions{
        .response_storage = .{ .dynamic = &storage },
        // Hardcode never dies
        .location = .{ .url = "https://api.met.no/weatherapi/locationforecast/2.0/?lat=47.374&lon=8.531" },
        .keep_alive = false,
        .headers = .{
            // https://api.met.no/doc/TermsOfService -> Legal stuff -> Identification
            .user_agent = .{ .override = "user-agent: zig/" ++ builtin.zig_version_string ++ " (std.http) github.com/michaelortmann/zstatus" },
        },
    };
    // https://ziglang.org/documentation/master/#while-with-Error-Unions
    while (zeit.instant(.{})) |now| {
        if (now.timestamp >= next_minute_30) {
            // Combine the if and switch expression
            // https://ziglang.org/documentation/master/#try
            if (client.fetch(fetch_options)) |fetch_result| {
                if (fetch_result.status == .ok) {
                    // result_temperature = storage.items;
                    var i = std.mem.indexOf(u8, storage.items[438..], ",\"air_temperature\":");
                    const start = 438 + i.? + 19;
                    i = std.mem.indexOf(u8, storage.items[start..], ",");
                    result_temperature = storage.items[start .. start + i.?];
                    storage.clearRetainingCapacity();
                }
            } else |err| switch (err) {
                error.ConnectionRefused, error.ConnectionTimedOut, error.EndOfStream, error.TemporaryNameServerFailure => std.log.debug("err {}", .{err}),
                else => return err,
            }

            next_minute_30 = @divFloor(now.timestamp, minute_30) * minute_30 + minute_30;
        }

        const now_local = now.in(&local);
        const dt_zeit = now_local.time();
        // sway-bar(5)
        //   status_command <status command>
        //     Each line of text printed to stdout from this command will be displayed
        // by "line" a write to stdout is meant, not \n buffered line reading
        _ = try buffered_writer.write(result_temperature);
        try dt_zeit.strftime(buffered_writer.writer(), "°C %a %d %H:%M:%S");
        try buffered_writer.flush();

        // sleep until next second
        std.time.sleep(@intCast(second - @mod(now.timestamp, second)));
    } else |err| return err;
}

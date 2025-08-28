const std = @import("std");
//const default = @import("default");
const rl = @import("raylib");

fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

const RENDER_WIDTH = 480;
const RENDER_HEIGHT = 360;

const ZOOM = 2;

const WINDOW_WIDTH = RENDER_WIDTH * ZOOM;
const WINDOW_HEIGHT = RENDER_HEIGHT * ZOOM;

pub fn main() !void {
    println("Hello world!", .{});
    rl.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "shino");

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.gray);
    }
}

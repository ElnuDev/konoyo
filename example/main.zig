const std = @import("std");
const rl = @import("raylib");
const World = @import("world.zig").World;
const systems = @import("systems.zig");
const entities = @import("entities.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub const window_width = 960;
pub const window_height = 720;

pub fn main() !void {
    rl.initWindow(window_width, window_height, "konoyo demo");

    // rl.setWindowState(rl.ConfigFlags {
    //     .vsync_hint = true,
    //});

    var world = World.init(allocator);
    defer world.deinit();

    _ = entities.fumo(&world, rl.Vector2 {
        .x = window_width / 2,
        .y = window_height / 2,
    });

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.gray);

        systems.fumoMovement(&world);
        systems.drawSprites(&world);
        systems.spawnFumo(&world);
        systems.fumoCounter(&world);

        rl.drawFPS(0, 0);
        rl.drawText(
            \\click or Q to spawn fumo
            \\WASD/arrow keys to move fumo
            \\space to purge fumo
            , 0, 20, 20, rl.Color.white
        );
    }
}

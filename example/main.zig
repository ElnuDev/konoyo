const std = @import("std");
//const default = @import("default");
const rl = @import("raylib");
const ecs = @import("konoyo");
const World = @import("world.zig").World;
const systems = @import("systems.zig");
const entities = @import("entities.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub fn main() !void {
    rl.initWindow(960, 720, "konoyo demo");
    rl.setWindowState(rl.ConfigFlags {
        .vsync_hint = true,
    });

    var world = World.init(allocator);
    defer world.deinit();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.gray);

        systems.player_movement(&world);
        systems.draw_sprites(&world);
        systems.spawn_player(&world);

        rl.drawFPS(0, 0);
    }
}

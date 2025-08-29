const rl = @import("raylib");

pub const TransformComponent = struct {
    position: rl.Vector2 = rl.Vector2 { .x = 0, .y = 0 },
};
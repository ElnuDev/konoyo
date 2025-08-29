const rl = @import("raylib");
const ecs = @import("ecs.zig");
const graphics = @import("graphics.zig");

pub const World = ecs.World(&[_]type{
    TransformComponent,
    SpriteComponent,
});

pub const TransformComponent = struct {
    position: rl.Vector2 = rl.Vector2 { .x = 0, .y = 0 },
};

pub const SpriteComponent = struct {
    sprite: *const graphics.Sprite,
    sorting_layer: graphics.Layer = graphics.Layer.World,
    z_index: i32 = 0,

    pub fn draw(self: *const @This(), position: rl.Vector2) void {
        self.sprite.draw(position);
    }
};
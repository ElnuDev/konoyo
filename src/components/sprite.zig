const rl = @import("raylib");

const Sprite = @import("../graphics/sprite.zig").Sprite;
const sorting = @import("../graphics/sorting.zig");

pub const SpriteComponent = struct {
    sprite: *const Sprite,
    sorting_layer: sorting.Layer = sorting.Layer.World,
    z_index: i32 = 0,

    pub fn draw(self: *const @This(), position: rl.Vector2) void {
        self.sprite.draw(position);
    }
};
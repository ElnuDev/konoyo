const rl = @import("raylib");

pub const Layer = enum {
    Background,
    World,
    UI,
};

pub const Sort = struct {
    layer: Layer,
    z_index: i32,
    position: f32,

    fn under(self: *const Sort, other: *const Sort) bool {
        return @intFromEnum(self.layer) < @intFromEnum(other.layer)
            or self.z_index < other.z_index
            or self.position < other.position;
    }
};

pub const Sprite = struct {
    texture: rl.Texture2D,
    source: ?rl.Rectangle = null,
    draw_offset: rl.Vector2 = rl.Vector2 { .x = 0, .y = 0 },

    pub fn draw(self: *const Sprite, position: rl.Vector2) void {
        const draw_position = position.add(self.draw_offset);
        const tint = rl.Color.white;
        if (self.source) |source| {
            self.texture.drawRec(source, draw_position, tint);
        } else {
            self.texture.drawV(draw_position, tint);
        }
    }
};
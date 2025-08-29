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
const rl = @import("raylib");

const ecs = @import("ecs.zig");
const Sprite = @import("graphics.zig").Sprite;

const _world = @import("world.zig");
const World = _world.World;
const TransformComponent = _world.TransformComponent;
const SpriteComponent = _world.SpriteComponent;

const allactor = @import("main.zig").allocator;
var player_sprite: ?*Sprite = null;

pub fn player(world: *World, position: rl.Vector2) ecs.EntityId {
    const entity = world.createEntity();
    world.insert(entity, TransformComponent {
        .position = position,
    });
    world.insert(entity, SpriteComponent {
        .sprite = player_sprite orelse label: {
            const sprite = allactor.create(Sprite) catch unreachable;
            defer player_sprite = sprite;
            sprite.* = Sprite {
                .texture = rl.loadTexture("reimu.png") catch unreachable,
            };
            break :label sprite;
        },
    });
    return entity;
}
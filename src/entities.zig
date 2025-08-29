const rl = @import("raylib");

const World = @import("world.zig").World;
const Entity = @import("world.zig").Entity;
const Sprite = @import("graphics/sprite.zig").Sprite;

const TransformComponent = @import("components/transform.zig").TransformComponent;
const SpriteComponent = @import("components/sprite.zig").SpriteComponent;

const allactor = @import("main.zig").allocator;
var player_sprite: ?*Sprite = null;

pub fn player(world: *World, position: rl.Vector2) Entity {
    const entity = world.createEntity();
    world.transforms.put(entity, TransformComponent {
        .position = position,
    }) catch unreachable;
    world.sprites.put(entity, SpriteComponent {
        .sprite = player_sprite orelse label: {
            const sprite = allactor.create(Sprite) catch unreachable;
            defer player_sprite = sprite;
            sprite.* = Sprite {
                .texture = rl.loadTexture("reimu.png") catch unreachable,
            };
            break :label sprite;
        },
    }) catch unreachable;
    return entity;
}
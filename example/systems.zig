const std = @import("std");
const ecs = @import("konoyo");

const _world = @import("world.zig");
const World = _world.World;
const TransformComponent = _world.TransformComponent;
const SpriteComponent = _world.SpriteComponent;
const rl = @import("raylib");
const entities = @import("entities.zig");
const allocator = @import("main.zig").allocator;

pub fn drawSprites(world: *World) void {
    const Query = &[_]type{ ?TransformComponent, SpriteComponent };
    const Drawable = ecs.QueryResult(Query);
    const drawables = world.query(Query);
    defer world.allocator.free(drawables);

    const lessThanFn = struct {
        fn f(_: void, lhs: Drawable, rhs: Drawable) bool {
            return @intFromEnum(lhs.sprite.sorting_layer) < @intFromEnum(rhs.sprite.sorting_layer)
            or lhs.sprite.z_index < rhs.sprite.z_index
            or
                (if (lhs.transform) |transform| transform.position.y else 0) <
                (if (rhs.transform) |transform| transform.position.y else 0);
        }
    }.f;
    std.mem.sort(Drawable, drawables, {}, lessThanFn);
    for (drawables) |d| {
        d.sprite.draw(if (d.transform) |transform| transform.position else rl.Vector2.zero());
    }
}

pub fn fumoMovement(world: *World) void {
    const Query = &[_]type{ *TransformComponent };
    const players = world.query(Query);
    defer world.allocator.free(players);

    const delta = (rl.Vector2 {
        .x = @floatFromInt(
            @as(i2, @intFromBool(rl.isKeyDown(rl.KeyboardKey.right) or rl.isKeyDown(rl.KeyboardKey.d))) -
            @as(i2, @intFromBool(rl.isKeyDown(rl.KeyboardKey.left) or rl.isKeyDown(rl.KeyboardKey.a)))
        ),
        .y = @floatFromInt(
            @as(i2, @intFromBool(rl.isKeyDown(rl.KeyboardKey.down) or rl.isKeyDown(rl.KeyboardKey.s))) -
            @as(i2, @intFromBool(rl.isKeyDown(rl.KeyboardKey.up) or rl.isKeyDown(rl.KeyboardKey.w)))
        ),
    }).normalize().scale(rl.getFrameTime() * 250);
    for (players) |player| {
        if (rl.isKeyPressed(rl.KeyboardKey.space)) {
            _ = world.deleteEntity(player.entity);
        }
        player.transform.position = player.transform.position.add(delta);
    }
}

pub fn spawnFumo(world: *World) void {
    if (!rl.isMouseButtonPressed(rl.MouseButton.left)) {
        return;
    }
    _ = entities.fumo(world, rl.getMousePosition());
}

pub fn fumoCounter(world: *World) void {
    const count = world.components.sprites.count();
    const text: [:0]u8 = @ptrCast(std.fmt.allocPrint(allocator, "{} fumo" ++ [_]u8{0}, .{ count }) catch unreachable);
    rl.drawText(text, 0, 85, 20, rl.Color.red);
}
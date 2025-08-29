const std = @import("std");
const World = @import("world.zig").World;
const Entity = @import("world.zig").Entity;
const allocator = @import("main.zig").allocator;
const Transform = @import("components/transform.zig").TransformComponent;
const Sprite = @import("components/sprite.zig").SpriteComponent;
const rl = @import("raylib");
const entities = @import("entities.zig");

pub fn toEntityName(comptime input: []const u8) [:0]const u8 {
    // Find last '.' manually
    var last_dot: usize = 0;
    for (input, 0..) |c, i| {
        if (c == '.') last_dot = i;
    }
    const last = input[last_dot + 1 ..]; // slice after last '.'

    // Remove "Component" suffix if present
    const suffix = "Component";
    const base = last[0..(last.len - suffix.len)];

    // Make lowercase at comptime
    var buf: [64]u8 = undefined; // must be large enough
    var out_len: usize = 0;
    for (base) |c| {
        buf[out_len] = std.ascii.toLower(c);
        out_len += 1;
    }
    buf[out_len] = 0;
    return buf[0..out_len :0];
}

pub fn QueryResult(comptime Query: []const type) type {
    var fields: [Query.len + 1]std.builtin.Type.StructField = undefined;
    fields[0] = .{
        .name = "entity",
        .type = Entity,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 1,
    };
    for (Query, 1..) |Component, i| {
        fields[i] = .{
            .name = toEntityName(@typeName(Component)),
            .type = *Component,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 1,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn QueryResults(comptime Components: []const type) type {
    return std.ArrayList(QueryResult(Components));
}

// TODO: add support for optional components
fn query_world(world: *World, comptime Query: []const type) QueryResults(Query) {
    var results = QueryResults(Query)
        .initCapacity(allocator, world.entities.count()) catch unreachable;
    var iter = world.entities.keyIterator();
    outer: while (iter.next()) |entity| {
        var result = results.addOne(allocator) catch unreachable;
        result.entity = entity.*;
        inline for (std.meta.fields(QueryResult(Query))) |field| inner: {
            comptime if (std.mem.eql(u8, field.name, "entity")) break :inner;
            const plural = field.name ++ "s";
            @field(result, field.name) = @field(world, plural).getPtr(entity.*) orelse continue :outer;
        }
    }
    return results;
}

pub fn draw_sprites(world: *World) void {
    const Query = &[_]type{ Transform, Sprite };
    const Drawable = QueryResult(Query);
    const drawables = query_world(world, Query);
    const lessThanFn = struct {
        fn f(_: void, lhs: Drawable, rhs: Drawable) bool {
            return @intFromEnum(lhs.sprite.sorting_layer) < @intFromEnum(rhs.sprite.sorting_layer)
            or lhs.sprite.z_index < rhs.sprite.z_index
            or lhs.transform.position.y < rhs.transform.position.y;
        }
    }.f;
    std.mem.sort(Drawable, drawables.items, {}, lessThanFn);
    for (drawables.items) |d| {
        d.sprite.draw(d.transform.position);
    }
}

pub fn player_movement(world: *World) void {
    const Query = &[_]type{ Transform };
    const players = query_world(world, Query);
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
    for (players.items) |player| {
        if (rl.isKeyPressed(rl.KeyboardKey.space)) {
            world.deleteEntity(player.entity);
        }
        player.transform.position = player.transform.position.add(delta);
    }
}

pub fn spawn_player(world: *World) void {
    if (!rl.isMouseButtonPressed(rl.MouseButton.left)) {
        return;
    }
    _ = entities.player(world, rl.getMousePosition());
}
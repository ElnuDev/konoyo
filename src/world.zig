const std = @import("std");
const TransformComponent = @import("components/transform.zig").TransformComponent;
const SpriteComponent = @import("components/sprite.zig").SpriteComponent;

fn Set(T: type) type {
    return std.AutoHashMap(T, void);
}

fn Components(Component: type) type {
    return std.AutoHashMap(Entity, Component);
}

pub const Entity = struct {
    id: u32,
};

pub const World = struct {
    next_entity_id: u32 = 0,
    entities: Set(Entity) = undefined,
    transforms: Components(TransformComponent) = undefined,
    sprites: Components(SpriteComponent) = undefined,

    pub fn init(allocator: std.mem.Allocator) @This() {
        var self = @This() {};
        self.entities = Set(Entity).init(allocator);
        self.transforms = Components(TransformComponent).init(allocator);
        self.sprites = Components(SpriteComponent).init(allocator);
        return self;
    }

    pub fn existsEntity(self: *const @This(), entity: Entity) bool {
        return self.entities.contains(entity);
    }

    pub fn createEntity(self: *@This()) Entity {
        defer self.next_entity_id += 1;
        const entity = Entity { .id = self.next_entity_id };
        self.entities.put(entity, {}) catch unreachable;
        return entity;
    }

    pub fn deleteEntity(self: *@This(), entity: Entity) void {
        _ = self.entities.remove(entity);
        _ = self.transforms.remove(entity);
        _ = self.sprites.remove(entity);
    }
};
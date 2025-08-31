# konoyo

A very simple ECS implemented in Zig with heavy use of comptime.

To run the raylib exmaple, run `zig build -Dexample run`. You can click to spawn fumo, use WASD/arrow keys to move fumo, and press space to purge fumo.

## Getting started

To get started, import konoyo and initialize an ECS world type definition with a component list. Component types cannot be named "EntityComponent" and must end in "Component". This convention is enforced so it's clear what types in your project are queryable.

Once you have declared your world type, you can initialize it with an allocator. For each of the provided components, konoyo internally stores a hash table mapping from a `u32` entity ID to component instances.

Supposing you have already defined a `TransformComponent` and `SpriteComponent` (the ones used here are the same in the [example](example)), you can set up konoyo as follows.

```ZIG
const std = @import("std");
const ecs = @import("konoyo");

const World = ecs.World(&[_]type{
    TransformComponent,
    SpriteComponent,
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var world = World.init(allocator);
defer world.deinit();
```

### Spawning entities

To create an entity, call `world.createEntity`. This will return a unique ID for the created entity.

```ZIG
const entity = world.createEntity();
```

You can then add any component that was defined in the world definition.

```ZIG
world.insert(entity, TransformComponent {
    ...
});
world.insert(entity, SpriteComponent {
    ...
});
```

### Querying entities

To query the world, call `world.query`, passing in a query slice of types you want your query to return. The query will return an array list of `QueryResult(Query)`. Each query result will contain an `entity` field with the entity ID and one field for each type in your query, e.g. querying for a `TransformComponent` will give you a `transform` field in every query result.

```ZIG
const Query = &[_]type{ *TransformComponent, *const SpriteComponent };
const results = world.query(query);
defer world.allocator.free(results);
for (results) |e| {
    std.debug.print("Entity ID: {}\n", .{ e.entity });
    e.transform.position.x += 42;
    e.sprite.draw(e.transform.position);
}
```

Optional components are also supported.

```ZIG
const Query = &[_]type{ *TransformComponent, ?*const SpriteComponent };
```

Queried types are immutable by default: `Component` is a valid shorthand for `*const Component`.

```ZIG
const Query = &[_]type{ *TransformComponent, ?SpriteComponent };
```

### More utils

```ZIG
const entity = 0;
// deleteEntity returns whether or not the entity existed to begin with
_ = world.deleteEntity(entity);
// delete returns whether or not the component existed to begin with
_ = world.delete(entity, TransformComponent);
// check if entity exists
_ = world.entityExists(entity);
```

## Acknowledgements

Reimu fumo sprite by Jaysa under CC0 via [OpenGameArt.org](https://opengameart.org/content/touhou-fumo-factory)
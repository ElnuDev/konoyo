const std = @import("std");
const utils = @import("utils.zig");
const componentName = utils.componentName;
const componentNamePlural = utils.componentNamePlural;

/// Struct containing the individual result type for the given ECS query.
/// Contains an `entity: EntityId` and then one field for each component in the query.
pub fn QueryResult(comptime Query: []const type) type {
    var fields: [Query.len + 1]std.builtin.Type.StructField = undefined;
    fields[0] = .{
        .name = "entity",
        .type = EntityId,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 1,
    };
    var Components: [Query.len]type = undefined;
    for (Query, 0..) |QueryParam, i| {
        var Component: type = undefined;
        defer Components[i] = Component;
        fields[i + 1] = .{
            .name = componentName(QueryParam) catch unreachable,
            // immutability by default
            .type = inner: switch (@typeInfo(QueryParam)) {
                // *MyComponent => *MyComponent
                .pointer => {
                    Component = @typeInfo(QueryParam).pointer.child;
                    break :inner QueryParam;
                },
                .optional => |info| switch (@typeInfo(info.child)) {
                    // ?*MyComponent => ?*MyComponent
                    .pointer => {
                        Component = @typeInfo(info.child).pointer.child;
                        break :inner QueryParam;
                    },
                    // ?MyComponent => ?*const MyComponent
                    else => {
                        Component = info.child;
                        break :inner ?*info.child;
                    },
                },
                // MyComponent => *const MyComponent
                else => {
                    Component = QueryParam;
                    break :inner *const QueryParam;
                },
            },
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 1,
        };
        for (0..i) |j| {
            if (Component == Components[j]) {
                @compileError("Cannot query component " ++ @typeName(Component) ++ " twice");
            }
        }
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

/// ArrayList of results for the given ECS query.
fn QueryResults(comptime Query: []const type) type {
    return std.ArrayList(QueryResult(Query));
}

/// A HashSet.
fn Set(T: type) type {
    return std.AutoHashMap(T, void);
}

fn BiMap(K: type, V: type) type {
    return struct {
        values: std.AutoHashMap(K, V),
        keys: std.AutoHashMap(V, K),
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator) @This() {
            return @This() {
                .values = std.AutoHashMap(K, V).init(allocator),
                .keys = std.AutoHashMap(V, K).init(allocator),
                .allocator = allocator,
            };
        }

        fn getValue(self: *const @This(), key: K) ?V {
            return self.values.get(key);
        }

        fn getKey(self: *const @This(), value: V) ?K {
            return self.keys.get(value);
        }

        fn deinit(self: *@This()) void {
            self.values.deinit();
            self.keys.deinit();
        }

        fn put(self: *@This(), key: K, value: V) void {
            if (self.values.get(key)) |old_value| _ = self.keys.remove(old_value);
            if (self.keys.get(value)) |old_key| _ = self.values.remove(old_key);
            self.values.put(key, value) catch unreachable;
            self.keys.put(value, key) catch unreachable;
        }

        fn removeUnchecked(self: *@This(), key: K, value: V) void {
            self.values.remove(key);
            self.values.remove(value);
        }

        fn removeByKey(self: *@This(), key: K) bool {
            if (self.values.get(key)) |value| {
                _ = self.values.remove(key);
                _ = self.keys.remove(value);
                return true;
            }
            return false;
        }

        fn removeByValue(self: *@This(), value: V) bool {
            if (self.keys.get(value)) |key| {
                _ = self.values.remove(key);
                _ = self.keys.remove(value);
                return true;
            }
            return false;
        }
    };
}

/// A HashMap of `EntityId` to the given type.
fn EntityMap(V: type) type {
    return struct {
        dense: std.ArrayList(V),
        entities: BiMap(EntityId, usize),
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator) @This() {
            return @This() {
                .dense = std.ArrayList(V).initCapacity(allocator, 1) catch unreachable,
                .entities = BiMap(EntityId, usize).init(allocator),
                .allocator = allocator,
            };
        }

        fn deinit(self: *@This()) void {
            self.dense.deinit(self.allocator);
            self.entities.deinit();
        }

        fn count(self: *const @This()) usize {
            return self.dense.items.len;
        }

        fn get(self: *const @This(), entity: EntityId) ?*V {
            if (self.entities.getValue(entity)) |i| {
                return &self.dense.items[i];
            } else {
                return null;
            }
        }

        fn put(self: *@This(), entity: EntityId, value: V) void {
            if (self.entities.getValue(entity)) |i| {
                self.dense.items[i] = value;
            } else {
                self.entities.put(entity, self.dense.items.len);
                self.dense.append(self.allocator, value) catch unreachable;
            }
        }

        fn remove(self: *@This(), entity: EntityId) ?V {
            if (self.entities.getValue(entity)) |i| {
                const removed = self.dense.swapRemove(i);
                _ = self.entities.removeByKey(entity);
                if (i < self.dense.items.len) {
                    self.entities.put(self.entities.getKey(self.dense.items.len).?, i);
                }
                return removed;
            }
            return null;
        }
    };
}

/// A struct containing `EntityMap`s for all of the given component struct types.
///
///
/// For example,
///
/// ```ZIG
/// ComponentSet(&[_]type{
///     TransformComponent,
///     SpriteComponent,
/// }
/// ```
///
/// will contain the fields `transforms: EntityMap(TransformComponent)` and
/// `sprites: EntityMap(SpriteComponent)`.
fn ComponentSet(comptime Components: []const type) type {
    var fields: [Components.len]std.builtin.Type.StructField = undefined;
    for (Components, 0..) |Component, i| {
        switch (@typeInfo(Component)) {
            .@"struct" => {},
            else => @compileError("All components must be structs"),
        }
        if (@sizeOf(Component) == 0) {
            @compileError("Zero-sized components (tags) are currently not supported");
        }
        const name = componentName(Component)
            catch @compileError("Component name \"" ++ @typeName(Component) ++ "\" must end in \"Component\"");
        fields[i] = .{
            .name = if (name[name.len - 2] == 'y') name ++ "ies" else name ++ "s",
            .type = EntityMap(Component),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 8,
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        }
    });
}

// TODO: Let World take in an EntityId type
pub const EntityId = u32;

/// The ECS world.
///
/// ```ZIG
/// const std = @import("std");
/// const ecs = @import("konoyo");
///
/// const World = ecs.World(&[_]type{
///     TransformComponent,
///     SpriteComponent,
/// });
///
/// var gpa = std.heap.GeneralPurposeAllocator(.{}){};
/// const allocator = gpa.allocator();
///
/// var world = World.init(allocator);
/// ```
pub fn World(comptime Components: []const type) type {
    return struct {
        next_entity_id: EntityId = 0,
        entities: Set(EntityId),
        components: ComponentSet(Components),
        allocator: std.mem.Allocator,

        fn validateComponent(comptime Component: type) void {
            const maybe_name: ?[:0]const u8 = componentNamePlural(Component) catch null;
            if (maybe_name) |name| {
                inline for (std.meta.fields(ComponentSet(Components))) |field| {
                    if (std.mem.eql(u8, field.name, name)) {
                        return;
                    }
                }
            }
            @compileError("Component `" ++ @typeName(Component) ++ "` isn't registered on world");
        }

        pub fn init(allocator: std.mem.Allocator) @This() {
            var self = @This(){
                .entities = Set(EntityId).init(allocator),
                .components = undefined,
                .allocator = allocator,
            };
            inline for (std.meta.fields(@TypeOf(self.components))) |field| {
                @field(self.components, field.name) = @FieldType(@TypeOf(self.components), field.name).init(allocator);
            }
            return self;
        }

        pub fn deinit(self: *@This()) void {
            self.entities.deinit();
            inline for (std.meta.fields(@TypeOf(self.components))) |field| {
                @field(self.components, field.name).deinit();
            }
        }

        /// Query the ECS world.
        pub fn query(self: *const @This(), comptime Query: []const type) []QueryResult(Query) {
            // TODO: Currently the iteration loop goes over all entities in the world.
            // This is quite inefficient, since each component knows its own entity list --
            // a simple optimization to minimize the total number of accesses is to pick the
            // component set with the fewest elements and then only iterate over its elements instead.
            var results = QueryResults(Query)
                .initCapacity(self.allocator, self.entities.count()) catch unreachable;
            var iter = self.entities.keyIterator();
            outer: while (iter.next()) |entity| {
                var result = results.addOneAssumeCapacity();
                inline for (std.meta.fields(QueryResult(Query))) |field| inner: {
                    comptime if (std.mem.eql(u8, field.name, "entity")) break :inner;
                    @field(result, field.name) = @field(
                        self.components,
                        componentNamePlural(field.@"type") catch unreachable,
                    ).get(entity.*) orelse switch (@typeInfo(field.@"type")) {
                        .optional => null,
                        .pointer => {
                            results.shrinkRetainingCapacity(results.items.len - 1);
                            continue :outer;
                        },
                        else => unreachable,
                    };
                }
                result.entity = entity.*;
            }
            results.shrinkAndFree(self.allocator, results.items.len);
            return results.toOwnedSlice(self.allocator) catch unreachable;
        }

        pub fn count(self: *const @This(), comptime Component: type) usize {
            comptime @This().validateComponent(Component);
            return @field(self.components, componentNamePlural(Component) catch unreachable).dense.items.len;
        }

        pub fn get(self: *const @This(), entity: EntityId, comptime Component: type) ?*Component {
            comptime @This().validateComponent(Component);
            return @field(self.components, componentNamePlural(Component) catch unreachable).get(entity);
        }

        pub fn insert(self: *@This(), entity: EntityId, component: anytype) void {
            comptime @This().validateComponent(@TypeOf(component));
            std.debug.assert(self.entities.contains(entity));
            @field(
                self.components,
                componentNamePlural(@TypeOf(component)) catch unreachable,
            ).put(entity, component);
        }

        pub fn delete(self: *@This(), entity: EntityId, comptime Component: type) bool {
            comptime @This().validateComponent(Component);
            return @field(self.components, componentNamePlural(Component) catch unreachable).remove(entity);
        }

        pub fn existsEntity(self: *const @This(), entity: EntityId) bool {
            return self.entities.contains(entity);
        }

        pub fn createEntity(self: *@This()) EntityId {
            defer self.next_entity_id += 1;
            const entity = self.next_entity_id;
            self.entities.put(entity, {}) catch unreachable;
            return entity;
        }

        // Returns whether or not the given entity existed in the first place.
        pub fn deleteEntity(self: *@This(), entity: EntityId) bool {
            if (!self.entities.remove(entity)) return false;
            inline for (std.meta.fields(@TypeOf(self.components))) |field| {
                _ = @field(self.components, field.name).remove(entity);
            }
            return true;
        }
    };
}

const expect = std.testing.expect;

const TestAComponent = struct { foo: u8 = 42 };
const TestBComponent = struct { bar: u8 = 69 };
const TestWorld = World(&[_]type{
    TestAComponent,
    TestBComponent,
});

fn _createA(world: *TestWorld) void {
    const entity = world.createEntity();
    world.insert(entity, TestAComponent{});
}

test "refAllDeclsRecursive" {
    std.testing.refAllDeclsRecursive(@This());
    std.testing.refAllDeclsRecursive(TestWorld);
}

test "single" {
    var world = TestWorld.init(std.testing.allocator);
    defer world.deinit();

    _createA(&world);
    _createA(&world);
    try expect(world.entities.count() == 2);

    const results = world.query(&[_]type{TestAComponent});
    defer world.allocator.free(results);

    try expect(results.len == 2);
}

test "optional" {
    var world = TestWorld.init(std.testing.allocator);
    defer world.deinit();

    _createA(&world);
    try expect(world.entities.count() == 1);

    const results = world.query(&[_]type{ TestAComponent, ?TestBComponent });
    defer world.allocator.free(results);

    try expect(results.len == 1);
}

test "empty" {
    var world = TestWorld.init(std.testing.allocator);
    defer world.deinit();

    _createA(&world);
    try expect(world.entities.count() == 1);

    const results = world.query(&[_]type{ TestBComponent });
    defer world.allocator.free(results);

    try expect(results.len == 0);
}
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

/// A HashMap of `EntityId` to the given type.
fn EntityMap(V: type) type {
    return std.AutoHashMap(EntityId, V);
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
            var self = @This() {
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
            var results = QueryResults(Query)
                .initCapacity(self.allocator, self.entities.count()) catch unreachable;
            var iter = self.entities.keyIterator();
            outer: while (iter.next()) |entity| {
                var result = results.addOne(self.allocator) catch unreachable;
                result.entity = entity.*;
                inline for (std.meta.fields(QueryResult(Query))) |field| inner: {
                    comptime if (std.mem.eql(u8, field.name, "entity")) break :inner;
                    @field(result, field.name) = @field(
                        self.components,
                        componentNamePlural(field.@"type") catch unreachable,
                    ).getPtr(entity.*) orelse continue :outer;
                }
            }
            return results.toOwnedSlice(self.allocator) catch unreachable;
        }

        pub fn get(self: *const @This(), entity: EntityId, comptime Component: type) ?*Component {
            return @field(self.components, componentNamePlural(Component)).getPtr(entity);
        }

        pub fn insert(self: *@This(), entity: EntityId, component: anytype) void {
            comptime @This().validateComponent(@TypeOf(component));
            std.debug.assert(self.entities.contains(entity));
            @field(
                self.components,
                componentNamePlural(@TypeOf(component)) catch unreachable,
            ).put(entity, component) catch unreachable;
        }

        pub fn delete(self: *@This(), entity: EntityId, comptime Component: type) bool {
            comptime @This().validateComponent(Component);
            return @field(self.components, componentNamePlural(Component)).remove(entity);
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

const assert = std.debug.assert;

const TestAComponent = struct {};
const TestBComponent = struct {};
const TestWorld = World(&[_]type {
    TestAComponent,
    TestBComponent,
});

test "optional" {
    var world = TestWorld.init(std.testing.allocator);

    const entity = world.createEntity();
    world.insert(entity, TestAComponent {});

    const results = world.query(&[_]type { TestAComponent, ?TestBComponent });
    defer world.allocator.free(results);

    assert(results.len == 1);

    world.deinit();
}
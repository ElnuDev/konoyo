const std = @import("std");

/// Converts component type to its name in lowercase.
///
/// For example, \
/// `path.to.TransformComponent` → "transform", \
/// `path.to.VelocityComponent` → "velocity".
fn componentName(component: type) [:0]const u8 {
    const input = @typeName(component);

    // Find last '.' manually
    var last_dot: usize = 0;
    for (input, 0..) |c, i| {
        if (c == '.') last_dot = i;
    }
    const last = input[last_dot + 1 ..]; // slice after last '.'


    // Remove "Component" suffix if present
    const suffix = "Component";
    if (last.len < suffix.len or !std.mem.eql(u8, suffix, last[last.len - suffix.len..last.len])) {
        @compileError("Component name \"" ++ input ++ "\" must end in \"Component\"");
    }
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

/// Converts component type to its name in lowercase.
///
/// For example, \
/// `path.to.TransformComponent` → "transforms", \
/// `path.to.VelocityComponent` → "velocities".
fn componentNamePlural(component: type) [:0]const u8 {
    return plural(componentName(component));
}

/// Convert input string to its plural form.
fn plural(comptime input: [:0]const u8) [:0]const u8 {
    return if (input[input.len - 2] == 'y') input[0..input.len - 1] ++ "ies" else input ++ "s";
}

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
            .name = componentName(QueryParam),
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
pub fn QueryResults(comptime Query: []const type) type {
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
        const name = componentName(Component);
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

        /// Query the ECS world.
        /// 
        pub fn query(self: *const @This(), comptime Query: []const type) QueryResults(Query) {
            var results = QueryResults(Query)
                .initCapacity(self.allocator, self.entities.count()) catch unreachable;
            var iter = self.entities.keyIterator();
            outer: while (iter.next()) |entity| {
                var result = results.addOne(self.allocator) catch unreachable;
                result.entity = entity.*;
                inline for (std.meta.fields(QueryResult(Query))) |field| inner: {
                    comptime if (std.mem.eql(u8, field.name, "entity")) break :inner;
                    @field(result, field.name) = @field(self.components, componentNamePlural(field.@"type")).getPtr(entity.*) orelse continue :outer;
                }
            }
            return results;
        }

        pub fn get(self: *const @This(), entity: EntityId, comptime Component: type) ?*Component {
            return @field(self.components, componentNamePlural(Component)).getPtr(entity);
        }

        pub fn insert(self: *@This(), entity: EntityId, component: anytype) void {
            @field(self.components, componentNamePlural(@TypeOf(component))).put(entity, component) catch unreachable;
        }

        pub fn delete(self: *@This(), entity: EntityId, comptime Component: type) bool {
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
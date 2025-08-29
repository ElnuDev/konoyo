const std = @import("std");

fn toEntityName(component: type) [:0]const u8 {
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

fn toEntityNamePlural(component: type) [:0]const u8 {
    return plural(toEntityName(component));
}

fn plural(comptime input: [:0]const u8) [:0]const u8 {
    return if (input[input.len - 2] == 'y') input[0..input.len - 1] ++ "ies" else input ++ "s";
}

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
            .name = toEntityName(QueryParam),
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

pub fn QueryResults(comptime Components: []const type) type {
    return std.ArrayList(QueryResult(Components));
}

fn Set(T: type) type {
    return std.AutoHashMap(T, void);
}

fn EntityMap(V: type) type {
    return std.AutoHashMap(EntityId, V);
}

fn ComponentSet(comptime Components: []const type) type {
    var fields: [Components.len]std.builtin.Type.StructField = undefined;
    for (Components, 0..) |Component, i| {
        switch (@typeInfo(Component)) {
            .@"struct" => {},
            else => @compileError("All components must be structs"),
        }
        const name = toEntityName(Component);
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

pub const EntityId = u32;

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

        pub fn query(self: *const @This(), comptime Query: []const type) QueryResults(Query) {
            var results = QueryResults(Query)
                .initCapacity(self.allocator, self.entities.count()) catch unreachable;
            var iter = self.entities.keyIterator();
            outer: while (iter.next()) |entity| {
                var result = results.addOne(self.allocator) catch unreachable;
                result.entity = entity.*;
                inline for (std.meta.fields(QueryResult(Query))) |field| inner: {
                    comptime if (std.mem.eql(u8, field.name, "entity")) break :inner;
                    @field(result, field.name) = @field(self.components, toEntityNamePlural(field.@"type")).getPtr(entity.*) orelse continue :outer;
                }
            }
            return results;
        }

        pub fn get(self: *const @This(), entity: EntityId, comptime Component: type) ?*Component {
            return @field(self.components, toEntityNamePlural(Component)).getPtr(entity);
        }

        pub fn insert(self: *@This(), entity: EntityId, component: anytype) void {
            @field(self.components, toEntityNamePlural(@TypeOf(component))).put(entity, component) catch unreachable;
        }

        pub fn delete(self: *@This(), entity: EntityId, comptime Component: type) bool {
            return @field(self.components, toEntityNamePlural(Component)).remove(entity);
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

        pub fn deleteEntity(self: *@This(), entity: EntityId) bool {
            if (!self.entities.remove(entity)) return false;
            inline for (std.meta.fields(@TypeOf(self.components))) |field| {
                _ = @field(self.components, field.name).remove(entity);
            }
            return true;
        }
    };
}
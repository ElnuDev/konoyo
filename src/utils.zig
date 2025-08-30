const std = @import("std");

/// Converts component type to its name in lowercase.
///
/// For example, \
/// `path.to.TransformComponent` → "transform", \
/// `path.to.VelocityComponent` → "velocity".
pub fn componentName(component: type) [:0]const u8 {
    const input = @typeName(component);

    var last_dot: usize = 0;
    for (input, 0..) |c, i| {
        if (c == '.') last_dot = i;
    }
    const name = input[last_dot + 1 ..];

    const suffix = "Component";
    if (name.len < suffix.len or !std.mem.eql(u8, suffix, name[name.len - suffix.len..name.len])) {
        @compileError("Component name \"" ++ input ++ "\" must end in \"Component\"");
    }
    const base = name[0..(name.len - suffix.len)];

    var lowercase_buffer: [255]u8 = undefined;
    var out_len: usize = 0;
    for (base) |c| {
        lowercase_buffer[out_len] = std.ascii.toLower(c);
        out_len += 1;
    }
    lowercase_buffer[out_len] = 0;
    return lowercase_buffer[0..out_len :0];
}

/// Converts component type to its name in lowercase.
///
/// For example, \
/// `path.to.TransformComponent` → "transforms", \
/// `path.to.VelocityComponent` → "velocities".
pub fn componentNamePlural(component: type) [:0]const u8 {
    return plural(componentName(component));
}

/// Convert input string to its plural form.
fn plural(comptime input: [:0]const u8) [:0]const u8 {
    return if (input[input.len - 2] == 'y') input[0..input.len - 1] ++ "ies" else input ++ "s";
}
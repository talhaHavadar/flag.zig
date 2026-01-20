// Copyright 2026 Talha Can Havadar
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const logger = std.log.scoped(.__flag_zig);
const assert = std.debug.assert;

const Flags = @This();

pub const FlagsError = error{
    UnknownFlag,
    MissingRequiredFlag,
    InvalidValue,
    MissingValue,
    DuplicateFlagDefinition,
    EmptyFlagName,
    HelpRequested,
};

const FlagValue = union(enum) {
    int: ?i64,
    float: ?f64,
    string: ?[]const u8,
    boolean: bool,

    pub fn deinit(self: FlagValue, allocator: Allocator) void {
        switch (self) {
            .string => |value| {
                if (value) |v| allocator.free(v);
            },
            else => {}, // stack-allocated, nothing to free
        }
    }
};

const Flag = struct {
    name: []const u8,
    value: FlagValue,
    default: FlagValue,
    help: []const u8,
    was_set: bool = false,

    /// Returns true if this flag is required (default value is null)
    pub fn isRequired(self: Flag) bool {
        return switch (self.default) {
            .int => |v| v == null,
            .float => |v| v == null,
            .string => |v| v == null,
            .boolean => false, // booleans always have a default
        };
    }
};

debug: bool = false,
flags: std.ArrayList(Flag) = .empty,
command_name: []const u8 = "",
help_flag_added: bool = false,

pub fn init(o: struct {
    /// debug flag for contributors of flag.zig
    debug: bool = false,
}) Flags {
    return .{ .flags = .empty, .debug = o.debug };
}

pub fn deinit(self: *Flags, allocator: Allocator) void {
    for (self.flags.items) |f| {
        // Only free value.string if it was parsed (heap-allocated)
        // Don't free defaults - they are always compile-time literals
        if (f.was_set) {
            f.value.deinit(allocator);
        }
    }
    self.flags.deinit(allocator);
}

pub fn flag(
    self: *Flags,
    allocator: Allocator,
    name: []const u8,
    default: FlagValue,
    help: []const u8,
) (FlagsError || Allocator.Error)!void {
    // Validate empty flag name
    if (name.len == 0) {
        return FlagsError.EmptyFlagName;
    }

    // Reserve "h" and "help" for built-in help
    if (std.mem.eql(u8, name, "h") or std.mem.eql(u8, name, "help")) {
        return FlagsError.DuplicateFlagDefinition;
    }

    // Check for duplicate flag names
    for (self.flags.items) |existing| {
        if (std.mem.eql(u8, existing.name, name)) {
            return FlagsError.DuplicateFlagDefinition;
        }
    }

    try self.flags.append(allocator, .{
        .name = name,
        .value = default,
        .default = default,
        .help = help,
    });
}

fn ensureHelpFlags(self: *Flags, allocator: Allocator) Allocator.Error!void {
    if (self.help_flag_added) return;

    try self.flags.append(allocator, .{
        .name = "h",
        .value = .{ .boolean = false },
        .default = .{ .boolean = false },
        .help = "Print this help message and exit",
    });

    try self.flags.append(allocator, .{
        .name = "help",
        .value = .{ .boolean = false },
        .default = .{ .boolean = false },
        .help = "Print this help message and exit",
    });

    self.help_flag_added = true;
}

/// Returns the usage text based on given flag configuration so far.
///
/// Caller of this function should free the text returned.
pub fn usage(self: Flags, allocator: Allocator) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);
    const writer = buffer.writer(allocator);

    // Build command line summary
    const prog_name = if (self.command_name.len > 0) self.command_name else "command";
    try writer.print("Usage: {s}", .{prog_name});

    // Add flags to usage line
    for (self.flags.items) |f| {
        // Skip internal help flags in command line summary
        if (std.mem.eql(u8, f.name, "h") or std.mem.eql(u8, f.name, "help")) {
            continue;
        }

        const prefix: []const u8 = if (f.name.len == 1) "-" else "--";

        if (f.isRequired()) {
            try writer.print(" ({s}{s})", .{ prefix, f.name });
        } else {
            try writer.print(" [{s}{s}]", .{ prefix, f.name });
        }
    }

    try writer.writeAll("\n\nFlags:\n");

    // Detailed flag descriptions
    for (self.flags.items) |f| {
        const prefix: []const u8 = if (f.name.len == 1) "-" else "--";
        const required_marker: []const u8 = if (f.isRequired()) " (required)" else "";

        try writer.print("  {s}{s}{s}\n", .{ prefix, f.name, required_marker });
        try writer.print("        {s}\n", .{f.help});

        // Show default value if not required
        if (!f.isRequired()) {
            try self.writeDefaultValue(allocator, writer, f.default);
        }
    }

    return buffer.toOwnedSlice(allocator);
}

fn writeDefaultValue(self: Flags, allocator: Allocator, writer: anytype, default: FlagValue) !void {
    _ = self;
    _ = allocator;
    try writer.writeAll("        Default: ");
    switch (default) {
        .int => |v| try writer.print("{d}\n", .{v.?}),
        .float => |v| try writer.print("{d}\n", .{v.?}),
        .string => |v| try writer.print("\"{s}\"\n", .{v.?}),
        .boolean => |v| try writer.print("{}\n", .{v}),
    }
}

/// Prints the usage text to given file by default it uses `stdout`
pub fn printUsage(self: Flags, o: struct {
    file: std.fs.File = std.fs.File.stdout(),
}) !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    const usage_text = try self.usage(allocator);
    defer allocator.free(usage_text);
    _ = try o.file.write(usage_text);
}

/// Parses the args either fetched from std.process.args() or given `argIterator`
pub fn parse(
    self: *Flags,
    allocator: Allocator,
    o: struct {
        /// flag uses std.process.args by default providing custom iterator allows
        /// users to parse subsections of commandline
        argIterator: ?*ArgIterator = null,
    },
) (FlagsError || Allocator.Error)!void {
    // Add help flags before parsing
    try self.ensureHelpFlags(allocator);

    var aIterator: ArgIterator = undefined;
    if (o.argIterator) |iter| {
        aIterator = iter.*;
    } else {
        aIterator = std.process.args();
        // Get program name (first argument)
        if (aIterator.next()) |cmd| {
            self.command_name = std.fs.path.basename(cmd);
        }
    }

    self.log("parse:: process:{s}", .{self.command_name});

    // Parse remaining arguments
    while (aIterator.next()) |arg| {
        try self.parseArg(allocator, arg, &aIterator);
    }

    // Check for help request
    if (self.wasSet("h") or self.wasSet("help")) {
        return FlagsError.HelpRequested;
    }

    // Validate all required flags were provided
    try self.validateRequired();
}

fn findFlag(self: *Flags, name: []const u8) ?usize {
    for (self.flags.items, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) {
            return i;
        }
    }
    return null;
}

fn parseArg(
    self: *Flags,
    allocator: Allocator,
    arg: []const u8,
    iterator: *ArgIterator,
) (FlagsError || Allocator.Error)!void {
    // Must start with '-'
    if (arg.len == 0 or arg[0] != '-') {
        return FlagsError.UnknownFlag;
    }

    // Determine if short (-c) or long (--name) flag
    var flag_start: usize = 1;
    if (arg.len > 1 and arg[1] == '-') {
        flag_start = 2; // Long flag: --name
    }

    // Handle edge case: just "-" or "--"
    if (flag_start >= arg.len) {
        return FlagsError.UnknownFlag;
    }

    const remainder = arg[flag_start..];

    // Check for = in the argument (-c=5 or --name=foo)
    var flag_name: []const u8 = undefined;
    var inline_value: ?[]const u8 = null;

    if (std.mem.indexOf(u8, remainder, "=")) |eq_pos| {
        flag_name = remainder[0..eq_pos];
        inline_value = remainder[eq_pos + 1 ..];
    } else {
        flag_name = remainder;
    }

    // Find the flag
    const flag_index = self.findFlag(flag_name) orelse {
        self.log("Unknown flag: {s}", .{flag_name});
        return FlagsError.UnknownFlag;
    };

    var flag_ptr = &self.flags.items[flag_index];

    // Parse the value based on type
    try self.parseFlagValue(allocator, flag_ptr, inline_value, iterator);

    flag_ptr.was_set = true;
}

fn parseFlagValue(
    self: *Flags,
    allocator: Allocator,
    flag_ptr: *Flag,
    inline_value: ?[]const u8,
    iterator: *ArgIterator,
) (FlagsError || Allocator.Error)!void {
    _ = self;

    switch (flag_ptr.value) {
        .boolean => {
            // Boolean flags: presence means true, or explicit =true/=false
            if (inline_value) |val| {
                if (std.mem.eql(u8, val, "true")) {
                    flag_ptr.value = .{ .boolean = true };
                } else if (std.mem.eql(u8, val, "false")) {
                    flag_ptr.value = .{ .boolean = false };
                } else {
                    return FlagsError.InvalidValue;
                }
            } else {
                // No value means true
                flag_ptr.value = .{ .boolean = true };
            }
        },
        .int => {
            const value_str = inline_value orelse iterator.next() orelse {
                return FlagsError.MissingValue;
            };
            const parsed = std.fmt.parseInt(i64, value_str, 10) catch {
                return FlagsError.InvalidValue;
            };
            flag_ptr.value = .{ .int = parsed };
        },
        .float => {
            const value_str = inline_value orelse iterator.next() orelse {
                return FlagsError.MissingValue;
            };
            const parsed = std.fmt.parseFloat(f64, value_str) catch {
                return FlagsError.InvalidValue;
            };
            flag_ptr.value = .{ .float = parsed };
        },
        .string => {
            const value_str = inline_value orelse iterator.next() orelse {
                return FlagsError.MissingValue;
            };
            // Duplicate the string so it's owned
            const duped = try allocator.dupe(u8, value_str);
            // Free old string if it exists
            if (flag_ptr.value.string) |old| {
                allocator.free(old);
            }
            flag_ptr.value = .{ .string = duped };
        },
    }
}

fn validateRequired(self: *Flags) FlagsError!void {
    for (self.flags.items) |f| {
        if (f.isRequired() and !f.was_set) {
            self.log("Missing required flag: {s}", .{f.name});
            return FlagsError.MissingRequiredFlag;
        }
    }
}

fn log(
    self: Flags,
    comptime format: []const u8,
    args: anytype,
) void {
    if (self.debug) logger.debug(format, args);
}

/// Get a flag's value by name using comptime type
/// Returns null if flag not found or type doesn't match
pub fn get(self: *const Flags, comptime T: type, name: []const u8) ?T {
    for (self.flags.items) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return switch (T) {
                i64 => if (f.value == .int) f.value.int else null,
                f64 => if (f.value == .float) f.value.float else null,
                []const u8 => if (f.value == .string) f.value.string else null,
                bool => if (f.value == .boolean) f.value.boolean else null,
                else => @compileError("Unsupported type. Use i64, f64, []const u8, or bool"),
            };
        }
    }
    return null;
}

/// Check if a flag was explicitly set by the user
pub fn wasSet(self: *const Flags, name: []const u8) bool {
    for (self.flags.items) |f| {
        if (std.mem.eql(u8, f.name, name)) {
            return f.was_set;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "flag registration" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    try flags.flag(allocator, "test", .{ .int = 42 }, "Test flag");
    try std.testing.expectEqual(@as(usize, 1), flags.flags.items.len);
}

test "duplicate flag detection" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    try flags.flag(allocator, "test", .{ .int = 42 }, "Test flag");
    const result = flags.flag(allocator, "test", .{ .int = 10 }, "Duplicate");
    try std.testing.expectError(FlagsError.DuplicateFlagDefinition, result);
}

test "empty flag name" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    const result = flags.flag(allocator, "", .{ .int = 42 }, "Empty name");
    try std.testing.expectError(FlagsError.EmptyFlagName, result);
}

test "reserved help flag names" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    const result_h = flags.flag(allocator, "h", .{ .boolean = false }, "Custom h");
    try std.testing.expectError(FlagsError.DuplicateFlagDefinition, result_h);

    const result_help = flags.flag(allocator, "help", .{ .boolean = false }, "Custom help");
    try std.testing.expectError(FlagsError.DuplicateFlagDefinition, result_help);
}

test "required flag detection" {
    const f1 = Flag{
        .name = "required",
        .value = .{ .string = null },
        .default = .{ .string = null },
        .help = "Required flag",
    };
    try std.testing.expect(f1.isRequired());

    const f2 = Flag{
        .name = "optional",
        .value = .{ .string = "default" },
        .default = .{ .string = "default" },
        .help = "Optional flag",
    };
    try std.testing.expect(!f2.isRequired());

    const f3 = Flag{
        .name = "bool_optional",
        .value = .{ .boolean = false },
        .default = .{ .boolean = false },
        .help = "Boolean is never required",
    };
    try std.testing.expect(!f3.isRequired());
}

test "getters return correct values" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    try flags.flag(allocator, "count", .{ .int = 42 }, "Count");
    try flags.flag(allocator, "rate", .{ .float = 3.14 }, "Rate");
    try flags.flag(allocator, "name", .{ .string = "test" }, "Name");
    try flags.flag(allocator, "verbose", .{ .boolean = true }, "Verbose");

    try std.testing.expectEqual(@as(?i64, 42), flags.get(i64, "count"));
    try std.testing.expectEqual(@as(?f64, 3.14), flags.get(f64, "rate"));
    try std.testing.expectEqualStrings("test", flags.get([]const u8, "name").?);
    try std.testing.expectEqual(@as(?bool, true), flags.get(bool, "verbose"));
}

test "get returns null for unknown flag" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    try std.testing.expectEqual(@as(?i64, null), flags.get(i64, "unknown"));
}

test "usage text generation" {
    const allocator = std.testing.allocator;
    var flags = Flags.init(.{});
    defer flags.deinit(allocator);

    try flags.flag(allocator, "c", .{ .int = 1 }, "Count");
    try flags.flag(allocator, "name", .{ .string = null }, "Name (required)");

    const usage_text = try flags.usage(allocator);
    defer allocator.free(usage_text);

    // Verify usage contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "[-c]") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "(--name)") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "(required)") != null);
}

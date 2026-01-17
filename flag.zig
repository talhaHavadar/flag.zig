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

const FlagValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    boolean: bool,

    pub fn deinit(self: FlagValue, allocator: Allocator) void {
        switch (self) {
            .string => |v| allocator.free(v),
            else => {}, // stack-allocated, nothing to free
        }
    }
};

const Flag = struct {
    name: []const u8,
    value: FlagValue,
    default: FlagValue,
    help: []const u8,
};

debug: bool = false,
flags: std.ArrayList(Flag) = .empty,

pub fn init(o: struct {
    /// debug flag for contributors of flag.zig
    debug: bool = false,
}) Flags {
    return .{ .flags = .empty, .debug = o.debug };
}

pub fn deinit(self: *Flags, allocator: Allocator) void {
    for (self.flags.items) |f| {
        f.value.deinit(allocator);
        f.default.deinit(allocator);
    }
    self.flags.deinit(allocator);
}

pub fn flag(
    self: *Flags,
    allocator: Allocator,
    name: []const u8,
    default: FlagValue,
    help: []const u8,
) !void {
    try self.flags.append(allocator, .{
        .name = name,
        .value = default,
        .default = default,
        .help = help,
    });
}

/// Returns the usage text based on given flag configuration so far.
///
/// Caller of this function should free the text returned.
pub fn usage(self: Flags, allocator: Allocator) ![]const u8 {
    _ = self;
    return try std.fmt.allocPrint(allocator,
        \\Usage:
        \\
    , .{});
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
pub fn parse(self: *Flags, o: struct {
    /// flag uses std.process.args by default providing custom iterator allows
    /// users to parse subsections of commandline
    argIterator: ?ArgIterator = null,
}) !void {
    var aIterator = std.process.args();
    var process: ?[]const u8 = null;
    if (o.argIterator) |iter| {
        aIterator = iter;
    } else {
        process = aIterator.next();
    }
    self.log(
        "parse:: process:{s}",
        .{std.fs.path.basename(process orelse "null")},
    );
}
pub fn log(
    self: Flags,
    comptime format: []const u8,
    args: anytype,
) void {
    if (self.debug) logger.debug(format, args);
}

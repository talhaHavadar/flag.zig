# flag.zig - Lightweight Commandline Flag/Option Parser

A simple, type-safe command-line argument parser for Zig with automatic help generation.

## Features

- Type-safe flag definitions (integers, floats, strings, booleans)
- Automatic `-h`/`--help` flag handling
- Required vs optional flags with defaults
- Short (`-c`) and long (`--config`) flag formats
- Inline value syntax (`-c=5`, `--name=foo`)
- Auto-generated usage text

## Installation

```bash
zig fetch --save git+https://github.com/talhaHavadar/flag.zig
```

## Installation as Module

Add the dependency in your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flag_dep = b.dependency("flag", .{
        .target = target,
        .optimize = optimize,
    });
    const flag = flag_dep.module("flag");

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "flag", .module = flag_dep.module("flag") },
            },
        }),
    });

    b.installArtifact(exe);
}
```

## Examples

### Basic Usage

```zig
const std = @import("std");
const flag = @import("flag");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var flags = flag.init(.{});
    defer flags.deinit(allocator);

    // Integer flag with default (optional)
    try flags.flag(allocator, "c", .{ .int = 1 }, "Number of iterations");

    // String flag without default (required)
    try flags.flag(allocator, "name", .{ .string = null }, "Input file name");

    // Float flag with default
    try flags.flag(allocator, "threshold", .{ .float = 0.5 }, "Threshold value");

    // Boolean flag
    try flags.flag(allocator, "verbose", .{ .boolean = false }, "Enable verbose output");

    // Parse arguments
    flags.parse(allocator, .{}) catch |err| switch (err) {
        error.HelpRequested => {
            try flags.printUsage(.{});
            return;
        },
        error.MissingRequiredFlag => {
            std.debug.print("Error: Missing required flag\n\n", .{});
            try flags.printUsage(.{});
            std.process.exit(1);
        },
        else => return err,
    };

    // Access values
    const count = flags.get(i64, "c") orelse 1;
    const name = flags.get([]const u8, "name") orelse unreachable;
    const verbose = flags.get(bool, "verbose") orelse false;

    std.debug.print("Count: {d}, Name: {s}, Verbose: {}\n", .{ count, name, verbose });
}
```

### Supported Types

| Type    | Zig Type     | Example                                                        |
| ------- | ------------ | -------------------------------------------------------------- |
| Integer | `i64`        | `.{ .int = 42 }` or `.{ .int = null }` (required)              |
| Float   | `f64`        | `.{ .float = 3.14 }` or `.{ .float = null }` (required)        |
| String  | `[]const u8` | `.{ .string = "default" }` or `.{ .string = null }` (required) |
| Boolean | `bool`       | `.{ .boolean = false }` (always optional)                      |

### Command Line Syntax

```bash
# Short flags
./myapp -c 5 -v

# Long flags
./myapp --name=input.txt --verbose

# Mixed
./myapp -c=10 --name file.txt --threshold 0.75

# Help
./myapp -h
./myapp --help
```

### Checking if Flag was Set

```zig
if (flags.wasSet("threshold")) {
    std.debug.print("Threshold was explicitly provided\n", .{});
}
```

## License

Apache License 2.0

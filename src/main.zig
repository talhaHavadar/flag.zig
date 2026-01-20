const std = @import("std");
const flag = @import("flag");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var flags = flag.init(.{ .debug = false });
    defer flags.deinit(allocator);

    // Integer flag with default (optional)
    try flags.flag(allocator, "c", .{ .int = 1 }, "Number of iterations to run");

    // String flag without default (required) - null means required
    try flags.flag(allocator, "name", .{ .string = null }, "Name of the input file");

    // Float flag with default (optional)
    try flags.flag(allocator, "threshold", .{ .float = 0.5 }, "Threshold value for processing");

    // Boolean flags (optional, defaults to false)
    try flags.flag(allocator, "verbose", .{ .boolean = false }, "Enable verbose output");
    try flags.flag(allocator, "v", .{ .boolean = false }, "Short form of verbose");

    // Parse command line arguments
    flags.parse(allocator, .{}) catch |err| switch (err) {
        error.HelpRequested => {
            // User asked for help - print usage and exit cleanly
            try flags.printUsage(.{});
            return;
        },
        error.MissingRequiredFlag => {
            std.debug.print("Error: Missing required flag\n\n", .{});
            try flags.printUsage(.{});
            std.process.exit(1);
        },
        error.UnknownFlag => {
            std.debug.print("Error: Unknown flag provided\n\n", .{});
            try flags.printUsage(.{});
            std.process.exit(1);
        },
        error.InvalidValue => {
            std.debug.print("Error: Invalid value for flag\n\n", .{});
            try flags.printUsage(.{});
            std.process.exit(1);
        },
        error.MissingValue => {
            std.debug.print("Error: Flag requires a value\n\n", .{});
            try flags.printUsage(.{});
            std.process.exit(1);
        },
        else => return err,
    };

    // Access parsed values using the generic get() function
    const count = flags.get(i64, "c") orelse 1;
    const name = flags.get([]const u8, "name") orelse unreachable; // Required, so always present
    const threshold = flags.get(f64, "threshold") orelse 0.5;
    const verbose = flags.get(bool, "verbose") orelse false;
    const v = flags.get(bool, "v") orelse false;

    // Check if flags were explicitly set
    if (flags.wasSet("threshold")) {
        std.debug.print("Threshold was explicitly set by user\n", .{});
    }

    // Use the parsed values
    std.debug.print("\nConfiguration:\n", .{});
    std.debug.print("  Count: {d}\n", .{count});
    std.debug.print("  Name: {s}\n", .{name});
    std.debug.print("  Threshold: {d}\n", .{threshold});
    std.debug.print("  Verbose: {}\n", .{verbose or v});
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

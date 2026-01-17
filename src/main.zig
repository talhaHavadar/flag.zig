const std = @import("std");
const flag = @import("flag");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    var flags = flag.init(.{ .debug = true });
    defer flags.deinit(allocator);

    _ = try flags.flag(allocator, "c", .{ .int = 1 }, "count");
    try flags.parse(.{});

    const usage = try flags.usage(allocator);
    defer allocator.free(usage);
    _ = try std.fs.File.stdout().write(usage);

    std.debug.print("Or print directly with managed allocation\n", .{});
    try flags.printUsage(.{});
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

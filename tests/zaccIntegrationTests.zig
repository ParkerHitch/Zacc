const std = @import("std");

test "Straight Line Lang" {
    std.testing.refAllDecls(@import("straightLine/main.zig"));
}

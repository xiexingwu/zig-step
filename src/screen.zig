const std = @import("std");
const rl = @import("raylib");

pub const ARR_LNG = 0.15; // Side length of arrow, normalised by lane height

pub fn getArrSzPx() i32 {
    return toPx(ARR_LNG);
}

pub const Dims = struct {
    width: i32,
    height: i32,
};

pub var dims: Dims = .{ .width = 0, .height = 0 };

/// Screen pixel coordinate
pub const Px = struct {
    x: i32,
    y: i32,
    pub fn toPt(self: Px) Pt {
        const x: f32 = @floatFromInt(self.x);
        const y: f32 = @floatFromInt(self.y);
        return .{
            .x = x / @as(@TypeOf(x), @floatFromInt(dims.width)),
            .y = y / @as(@TypeOf(y), @floatFromInt(dims.height)),
        };
    }
    pub fn fromPt(pt: Pt) Px {
        const width: f32 = @floatFromInt(dims.width);
        const height: f32 = @floatFromInt(dims.height);
        return .{
            .x = @intFromFloat(pt.x * width),
            .y = @intFromFloat(pt.y * height),
        };
    }
};

/// Get pix length relative to screen height
pub fn toPx(scalar: f32) i32 {
    const height: f32 = @floatFromInt(dims.height);
    return @intFromFloat(scalar * height);
}

/// Screen normalised coordinate
pub const Pt = struct {
    x: f32,
    y: f32,
    pub fn toPx(self: Pt) Px {
        const width: f32 = @floatFromInt(dims.width);
        const height: f32 = @floatFromInt(dims.height);
        return .{
            .x = @intFromFloat(self.x * width),
            .y = @intFromFloat(self.y * height),
        };
    }
};

const LANE_AR: f32 = 2.0 / 3.0;

pub fn init() void {
    const heightDefault = 600;
    const widthDefault = LANE_AR * heightDefault;
    dims.width = widthDefault;
    dims.height = heightDefault;
}

pub fn deinit() void {}

pub fn drawDebug(appState: anytype) void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;

    const fps = rl.getFPS();
    const mousePx = Px{
        .x = rl.getMouseX(),
        .y = rl.getMouseY(),
    };
    const mousePt = mousePx.toPt();
    const volume = appState.masterVolume;
    const mod = @tagName(appState.playMode.mod);
    const modValue = appState.playMode.modValue;

    // FPS
    len += (std.fmt.bufPrintZ(buf[len..], "FPS: {d: >3.0}\n", .{fps}) catch "FPS:  0\n").len;

    // Mouse loc
    len += (std.fmt.bufPrintZ(
        buf[len..],
        "X:{d: >4.0}, Y:{d: >4.0}\n" ++ "X:{d: >4.2}, Y:{d: >4.2}\n",
        .{ mousePx.x, mousePx.y, mousePt.x, mousePt.y },
    ) catch "X:+  0, Y:+   0\nX:+0.00, Y:+0.00").len;

    // Volume
    len += (std.fmt.bufPrintZ(
        buf[len..],
        "Volume: {d: >3.0}%\n",
        .{volume * 100},
    ) catch "   ").len;

    // Mod
    len += (std.fmt.bufPrintZ(
        buf[len..],
        "{s}: {d: >4.2}\n",
        .{ mod, modValue },
    ) catch "   ").len;

    rl.drawText(buf[0..len :0], 10, 10, 14, rl.Color.green);
}

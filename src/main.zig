const std = @import("std");
const rl = @import("raylib");
const audio = @import("audio.zig");

const KeyColors = enum {
    white,
    black,
};

pub fn main() !void {
    const screen_width: i32 = 1280;
    const screen_height: i32 = 720;

    rl.initWindow(screen_width, screen_height, "PD Piano");

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    const sample_rate: u32 = 44100;
    var sine_gen = audio.ADSRSineGen{};
    var square_gen = audio.ADSRSquareGen{};
    var triangle_gen = audio.ADSRTriangleGen{};
    var synth = audio.Synth.init(audio.SynthGen.from(&sine_gen), sample_rate);
    synth.volume = 0.2;

    const buffer_size = 1024;
    rl.setAudioStreamBufferSizeDefault(buffer_size);
    const stream = try rl.loadAudioStream(sample_rate, 32, 1);
    defer rl.unloadAudioStream(stream);
    rl.playAudioStream(stream);

    const white_key_width: f32 = screen_width / 7;
    const black_key_width_frac: f32 = 0.5;
    const black_key_width: f32 = white_key_width * black_key_width_frac;
    const black_key_length: f32 = screen_height / 2;
    const margins: i32 = 3;
    const top_shift: i32 = screen_height / 30;

    const white_keys = [_]i32{ 0, 2, 4, 5, 7, 9, 11 };
    const black_keys = [_]i32{ 1, 3, -1, 6, 8, 10 };
    var pressed_keys: u16 = 0;
    var buf: [buffer_size]f32 = undefined;
    while (!rl.windowShouldClose()) {
        const prev_keys = pressed_keys;

        if (rl.isAudioStreamProcessed(stream)) {
            synth.fill(&buf);
            rl.updateAudioStream(stream, &buf, buffer_size);
        }

        if (rl.isKeyPressed(.one)) synth.gen = audio.SynthGen.from(&sine_gen);
        if (rl.isKeyPressed(.two)) synth.gen = audio.SynthGen.from(&square_gen);
        if (rl.isKeyPressed(.three)) synth.gen = audio.SynthGen.from(&triangle_gen);

        if (rl.isMouseButtonDown(.left)) input: {
            const mouse_pos = rl.getMousePosition();
            if (mouse_pos.x < 0) {
                pressed_keys = 0;
                break :input;
            }
            const white_key_rel_pos = @mod(mouse_pos.x / white_key_width, 1.0);
            const key_idx: usize = @intFromFloat(@min(mouse_pos.x / white_key_width, 6.0));
            const half_black = 0.5 * black_key_width_frac;

            var key = white_keys[key_idx];
            if (mouse_pos.y <= black_key_length) {
                if (white_key_rel_pos >= 1.0 - half_black and key_idx <= 5 and black_keys[key_idx] >= 0) key = black_keys[key_idx] else if (white_key_rel_pos <= half_black and key_idx >= 1 and black_keys[key_idx - 1] >= 0) key = black_keys[key_idx - 1];
            }
            pressed_keys = @as(u16, 1) << @as(u4, @intCast(key));
        }
        if (rl.isMouseButtonReleased(.left)) {
            pressed_keys = 0;
        }

        if (pressed_keys != prev_keys) {
            if (pressed_keys == 0) {
                synth.noteOff();
            } else {
                const played_key: i32 = @ctz(pressed_keys);
                const freq = 440.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(played_key - 9)) / 12.0);
                if (prev_keys == 0) synth.noteOn(freq) else synth.freq = freq;
            }
        }

        rl.beginDrawing();
        rl.clearBackground(.{ .r = 22, .g = 22, .b = 29, .a = 255 });

        for (0..7) |i| {
            const color: rl.Color = if (pressed_keys & @as(u16, 1) << @intCast(white_keys[i]) > 0) .yellow else .white;
            const rect = rl.Rectangle.init(white_key_width * @as(f32, @floatFromInt(i)) + margins, -top_shift, white_key_width - @as(f32, @floatFromInt(margins * 2)), screen_height + top_shift);
            rl.drawRectangleRounded(rect, 0.25, 64, color);
        }

        for (0..6) |i| {
            if (black_keys[i] < 0) continue;
            const color: rl.Color = if (pressed_keys & @as(u16, 1) << @intCast(black_keys[i]) > 0) .yellow else .black;
            const rect = rl.Rectangle.init(white_key_width * @as(f32, @floatFromInt(i)) + black_key_width * (1 + black_key_width_frac), -top_shift, black_key_width, black_key_length + top_shift);
            rl.drawRectangleRounded(rect, 0.25, 64, color);
        }
        rl.endDrawing();
    }
}

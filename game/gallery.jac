"""Asset gallery: every model in a grid, normalised to the same size.

    ./gallery            orbit the grid (Esc quits)
    ./gallery --shot     write gallery.png after a few frames and exit
"""

import math;
import sys;
import from rl {
    Camera3D, SetConfigFlags, SetTraceLogLevel, InitWindow, CloseWindow,
    WindowShouldClose, SetTargetFPS, BeginDrawing, EndDrawing, ClearBackground,
    BeginMode3D, EndMode3D, DrawText, TakeScreenshot, GetWorldToScreen
}
import from gfx {
    Env, Gfx, MODEL_NAMES, FIRST_SKY, M_SKY_SHOAL, vec3, rgba, gfx_load,
    apply_env, set_view, draw, draw_sky
}

with entry {
    shot = "--shot" in sys.argv;
    SetConfigFlags(u32(0x20));
    SetTraceLogLevel(i32(4));
    InitWindow(i32(1600), i32(900), "EMBERWAKE gallery");
    SetTargetFPS(i32(60));
    g = gfx_load("assets");
    env = Env(
        sky=M_SKY_SHOAL, lx=-0.5, ly=-0.6, lz=-0.6, lr=1.0, lg=0.95, lb=0.88,
        ar=0.30, ag=0.32, ab=0.38, fr=0.05, fg=0.08, fb=0.12, fog_near=400.0, fog_far=900.0
    );
    apply_env(g, env);
    cols = 8;
    frame = 0;
    while not WindowShouldClose() {
        t = float(frame) / 60.0;
        eye = vec3(0.0, 3.0, 26.0);
        cam = Camera3D(position=eye, target=vec3(0.0, -0.8, 0.0), up=vec3(0.0, 1.0, 0.0), fovy=f32(45.0), projection=i32(0));
        set_view(g, 0.0, 3.0, 26.0);
        BeginDrawing();
        ClearBackground(rgba(10, 12, 20, 255));
        BeginMode3D(cam);
        draw_sky(g, env.sky, 0.0, 3.0, 26.0, 0.0, 255);
        for i in range(FIRST_SKY) {
            col = i % cols;
            row = i // cols;
            x = (float(col) - 3.5) * 4.2;
            y = 7.5 - float(row) * 3.6;
            s = 1.5 / g.radius[i];
            draw(g, i, x, y, 0.0, 0.6 + 0.4 * t, 0.35, 0.0, s);
        }
        EndMode3D();
        for i in range(FIRST_SKY) {
            col = i % cols;
            row = i // cols;
            p = GetWorldToScreen(vec3((float(col) - 3.5) * 4.2 - 1.6, 7.5 - float(row) * 3.6 - 1.7, 0.0), cam);
            DrawText(MODEL_NAMES[i], i32(int(p.x)), i32(int(p.y)), i32(14), rgba(220, 225, 235, 255));
        }
        EndDrawing();
        frame += 1;
        if shot and frame == 20 {
            TakeScreenshot("gallery.png");
            break;
        }
    }
    CloseWindow();
}

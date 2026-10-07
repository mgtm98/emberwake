"""EMBERWAKE: a low-poly on-rails space shooter in Jac native + raylib.

    ./emberwake                     play
    ./emberwake --chapter 3         jump straight into a chapter
    ./emberwake --chapter 5 --at 0.1 --demo --frames 900 --shot-every 150
                                    test run: start at 10 %, autopilot,
                                    screenshot every 150 frames, exit after 900
"""

import math;
import sys;
import from rl {
    SetConfigFlags, SetTraceLogLevel, InitWindow, CloseWindow, WindowShouldClose,
    SetTargetFPS, SetExitKey, ToggleFullscreen, GetFrameTime, GetTime, GetScreenWidth,
    GetScreenHeight, BeginDrawing,
    EndDrawing, ClearBackground, TakeScreenshot, IsKeyPressed, FileExists,
    LoadFileText, SaveFileText, IsGamepadAvailable, IsGamepadButtonPressed,
    KEY_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_P, KEY_M, KEY_UP, KEY_DOWN, KEY_W,
    KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D,
    KEY_S, KEY_F11, PAD_A, PAD_START, PAD_UP, PAD_DOWN
}
import from gfx { gfx_load, apply_env, rgba }
import from audio {
    audio_load, audio_update, music, play, toggle_mute, chapter_track,
    S_UI_MOVE, S_UI_SELECT, MU_TITLE, MU_ENDING
}
import from state {
    Game, ST_TITLE, ST_PROLOGUE, ST_BRIEFING, ST_PLAY, ST_PAUSE, ST_DEAD,
    ST_COMPLETE, ST_ENDING, ST_CONTROLS, ST_SELECT, ST_REFIT, ST_DIFFICULTY
}
import from world { chapter_env }
import from logic {
    start_chapter, update_play, skip_to, set_difficulty, refit_choices, retry_checkpoint
}
import from render { make_camera, draw_scene, draw_title_scene, draw_ending_scene }
import from post { Post, post_load, post_resize, scene_begin, scene_end, post_apply, post_draw }
import from hud {
    draw_hud, draw_title, draw_controls, draw_select, draw_prologue, draw_briefing,
    draw_pause, draw_dead, draw_complete, draw_ending, draw_white, load_fonts,
    draw_difficulty, draw_refit
}

glob SAVE_FILE: str = "save.txt",
     INPUT_LOCKED: bool = False;

def load_save(g: Game) {
    if not FileExists(SAVE_FILE) {
        return;
    }
    txt: str = LoadFileText(SAVE_FILE);
    rows = txt.split("\n");
    parts = rows[0].split(" ");
    if len(parts) >= 6 {
        g.unlocked = max(1, min(5, int(parts[0])));
        for k in range(1, 6) {
            g.best[k] = int(parts[k]);
        }
    }
    if len(parts) >= 12 {
        set_difficulty(g, max(0, min(2, int(parts[6]))));
        for k in range(1, 6) {
            g.medals[k] = int(parts[6 + k]);
        }
    }
    if len(rows) >= 2 {
        for u in rows[1].split(" ") {
            if u != "" {
                g.saved_upgrades.append(int(u));
            }
        }
    }
}

def write_save(g: Game) {
    if g.demo {
        return;
    }
    s = str(g.unlocked);
    for k in range(1, 6) {
        s = s + " " + str(g.best[k]);
    }
    s = s + " " + str(g.difficulty);
    for k in range(1, 6) {
        s = s + " " + str(g.medals[k]);
    }
    s = s + "\n";
    for k in range(len(g.saved_upgrades)) {
        s = s + ("" if k == 0 else " ") + str(g.saved_upgrades[k]);
    }
    SaveFileText(SAVE_FILE, s);
}

def confirm() -> bool {
    if INPUT_LOCKED {
        return False;
    }
    if IsKeyPressed(i32(KEY_ENTER)) or IsKeyPressed(i32(KEY_SPACE)) {
        return True;
    }
    return IsGamepadAvailable(i32(0)) and IsGamepadButtonPressed(i32(0), i32(PAD_A));
}

def back() -> bool {
    if INPUT_LOCKED {
        return False;
    }
    if IsKeyPressed(i32(KEY_ESCAPE)) or IsKeyPressed(i32(KEY_P)) {
        return True;
    }
    return IsGamepadAvailable(i32(0)) and IsGamepadButtonPressed(i32(0), i32(PAD_START));
}

"""Menu navigation; returns the chosen index or -1."""
def menu_input(g: Game, n: int) -> int {
    if INPUT_LOCKED {
        return -1;
    }
    up = IsKeyPressed(i32(KEY_UP)) or IsKeyPressed(i32(KEY_W));
    down = IsKeyPressed(i32(KEY_DOWN)) or IsKeyPressed(i32(KEY_S));
    if IsGamepadAvailable(i32(0)) {
        up = up or IsGamepadButtonPressed(i32(0), i32(PAD_UP));
        down = down or IsGamepadButtonPressed(i32(0), i32(PAD_DOWN));
    }
    if up {
        g.menu = (g.menu + n - 1) % n;
        play(g.audio, S_UI_MOVE);
    }
    if down {
        g.menu = (g.menu + 1) % n;
        play(g.audio, S_UI_MOVE);
    }
    if confirm() and g.state_t > 0.25 {
        play(g.audio, S_UI_SELECT);
        return g.menu;
    }
    return -1;
}

"""Left/right selection (refit cards); returns the chosen index or -1."""
def menu_input_h(g: Game, n: int) -> int {
    if INPUT_LOCKED {
        return -1;
    }
    left = IsKeyPressed(i32(KEY_LEFT)) or IsKeyPressed(i32(KEY_A)) or IsKeyPressed(i32(KEY_UP)) or IsKeyPressed(i32(KEY_W));
    right = IsKeyPressed(i32(KEY_RIGHT)) or IsKeyPressed(i32(KEY_D)) or IsKeyPressed(i32(KEY_DOWN)) or IsKeyPressed(i32(KEY_S));
    if IsGamepadAvailable(i32(0)) {
        left = left or IsGamepadButtonPressed(i32(0), i32(4)) or IsGamepadButtonPressed(i32(0), i32(PAD_UP));
        right = right or IsGamepadButtonPressed(i32(0), i32(2)) or IsGamepadButtonPressed(i32(0), i32(PAD_DOWN));
    }
    if left {
        g.menu = (g.menu + n - 1) % n;
        play(g.audio, S_UI_MOVE);
    }
    if right {
        g.menu = (g.menu + 1) % n;
        play(g.audio, S_UI_MOVE);
    }
    if confirm() and g.state_t > 0.6 {
        play(g.audio, S_UI_SELECT);
        return g.menu;
    }
    return -1;
}

def death_items(g: Game) -> list[str] {
    if g.cp_active {
        return ["RETRY FROM CHECKPOINT", "RETRY CHAPTER", "QUIT TO TITLE"];
    }
    return ["RETRY CHAPTER", "QUIT TO TITLE"];
}

def go(g: Game, state: int) {
    g.state = state;
    g.state_t = 0.0;
    g.menu = 0;
}

def to_title(g: Game) {
    g.chapter = 0;
    g.env = chapter_env(0);
    apply_env(g.gfx, g.env);
    music(g.audio, MU_TITLE);
    go(g, ST_TITLE);
}

def to_briefing(g: Game, ch: int) {
    g.chapter = ch;
    g.upgrades = [];
    for k in range(min(ch - 1, len(g.saved_upgrades))) {
        g.upgrades.append(g.saved_upgrades[k]);
    }
    g.env = chapter_env(ch);
    apply_env(g.gfx, g.env);
    music(g.audio, chapter_track(ch));
    go(g, ST_BRIEFING);
}

def arg_value(name: str, fallback: str) -> str {
    for k in range(len(sys.argv) - 1) {
        if sys.argv[k] == name {
            return sys.argv[k + 1];
        }
    }
    return fallback;
}

with entry {
    testing = int(arg_value("--frames", "0")) > 0;
    # Test runs neither take focus nor read input, so typing elsewhere cannot steer them.
    INPUT_LOCKED = testing;
    SetConfigFlags(u32(0x800 if testing else 0x40));
    SetTraceLogLevel(i32(4));
    InitWindow(i32(1280), i32(720), "EMBERWAKE");
    SetTargetFPS(i32(0 if testing else 60));
    SetExitKey(i32(0));

    g = Game(gfx=gfx_load("assets"), audio=audio_load("assets"), env=chapter_env(0));
    load_fonts("assets");
    post = post_load("assets", int(GetScreenWidth()), int(GetScreenHeight()), float(arg_value("--ss", "1.5")));
    load_save(g);
    if "--mute" in sys.argv {
        toggle_mute(g.audio);
    }
    start_ch = int(arg_value("--chapter", "0"));
    start_at = float(arg_value("--at", "0"));
    max_frames = int(arg_value("--frames", "0"));
    shot_every = int(arg_value("--shot-every", "0"));
    g.demo = "--demo" in sys.argv;
    g.pin_y = float(arg_value("--pin-y", "99"));
    g.shot_mode = max_frames > 0;

    if start_ch > 0 {
        g.unlocked = max(g.unlocked, start_ch);
        start_chapter(g, start_ch);
        if start_at > 0.0 {
            skip_to(g, start_at);
        }
        go(g, ST_PLAY);
    } else {
        to_title(g);
        screen = arg_value("--screen", "");
        if screen == "prologue" {
            go(g, ST_PROLOGUE);
        } elif screen == "difficulty" {
            go(g, ST_DIFFICULTY);
            g.menu = 1;
        } elif screen.startswith("refit") {
            g.chapter = int(screen[5:]);
            g.refit_options = refit_choices(g, g.chapter);
            go(g, ST_REFIT);
            g.menu = 1;
        } elif screen == "controls" {
            go(g, ST_CONTROLS);
        } elif screen == "select" {
            g.unlocked = 5;
            go(g, ST_SELECT);
        } elif screen.startswith("briefing") {
            to_briefing(g, int(screen[8:]));
        }
    }

    t = 0.0;
    quit = False;
    last_state = g.state;
    wall0 = float(GetTime());
    while not WindowShouldClose() and not quit {
        dt = 1.0 / 60.0 if g.shot_mode else min(float(GetFrameTime()), 0.05);
        t += dt;
        g.frame += 1;
        g.state_t += dt;
        audio_update(g.audio);
        if not INPUT_LOCKED and IsKeyPressed(i32(KEY_F11)) {
            ToggleFullscreen();
        }
        if not INPUT_LOCKED and IsKeyPressed(i32(KEY_M)) {
            toggle_mute(g.audio);
        }

        # ---------------------------------------------------------- update
        st = g.state;
        if st == ST_TITLE {
            sel = menu_input(g, 4);
            if sel == 0 {
                go(g, ST_DIFFICULTY);
                g.menu = g.difficulty;
            } elif sel == 1 {
                go(g, ST_SELECT);
            } elif sel == 2 {
                go(g, ST_CONTROLS);
            } elif sel == 3 {
                quit = True;
            }
        } elif st == ST_DIFFICULTY {
            sel = menu_input(g, 4);
            if sel == 3 or back() {
                go(g, ST_TITLE);
            } elif sel >= 0 {
                set_difficulty(g, sel);
                g.saved_upgrades = [];
                g.score = 0;
                write_save(g);
                go(g, ST_PROLOGUE);
            }
        } elif st == ST_REFIT {
            sel = menu_input_h(g, len(g.refit_options));
            if sel >= 0 {
                g.upgrades.append(g.refit_options[sel]);
                g.saved_upgrades = [];
                for u in g.upgrades {
                    g.saved_upgrades.append(u);
                }
                write_save(g);
                to_briefing(g, g.chapter + 1);
            }
        } elif st == ST_CONTROLS {
            if g.state_t > 0.3 and (confirm() or back()) {
                go(g, ST_TITLE);
            }
        } elif st == ST_SELECT {
            sel = menu_input(g, g.unlocked + 1);
            if sel == g.unlocked or back() {
                go(g, ST_TITLE);
            } elif sel >= 0 {
                g.score = 0;
                to_briefing(g, sel + 1);
            }
        } elif st == ST_PROLOGUE {
            if g.state_t > 0.5 and confirm() {
                to_briefing(g, 1);
            }
        } elif st == ST_BRIEFING {
            if g.state_t > 1.0 and confirm() {
                start_chapter(g, g.chapter);
                go(g, ST_PLAY);
            }
        } elif st == ST_PLAY {
            if back() and g.player.alive {
                go(g, ST_PAUSE);
            } else {
                update_play(g, dt);
                if g.state == ST_ENDING {
                    g.best[5] = max(g.best[5], g.chapter_score);
                    write_save(g);
                    g.chapter = 6;
                    g.env = chapter_env(6);
                    apply_env(g.gfx, g.env);
                    music(g.audio, MU_ENDING);
                }
            }
        } elif st == ST_PAUSE {
            sel = menu_input(g, 3);
            if back() and g.state_t > 0.2 {
                g.state = ST_PLAY;
            } elif sel == 0 {
                g.state = ST_PLAY;
            } elif sel == 1 {
                g.score = g.chapter_start_score;
                start_chapter(g, g.chapter);
                go(g, ST_PLAY);
            } elif sel == 2 {
                to_title(g);
            }
        } elif st == ST_DEAD {
            items = death_items(g);
            sel = menu_input(g, len(items));
            if sel >= 0 {
                choice = items[sel];
                if choice == "RETRY FROM CHECKPOINT" {
                    retry_checkpoint(g);
                    go(g, ST_PLAY);
                } elif choice == "RETRY CHAPTER" {
                    g.score = g.chapter_start_score;
                    start_chapter(g, g.chapter);
                    go(g, ST_PLAY);
                } else {
                    to_title(g);
                }
            }
        } elif st == ST_COMPLETE {
            if g.state_t > 2.2 and confirm() {
                g.best[g.chapter] = max(g.best[g.chapter], g.chapter_score);
                g.unlocked = max(g.unlocked, min(5, g.chapter + 1));
                write_save(g);
                g.refit_options = refit_choices(g, g.chapter);
                go(g, ST_REFIT);
                g.menu = 1;
            }
        } elif st == ST_ENDING {
            g.white_fx = max(0.0, g.white_fx - dt * 0.4);
            if g.state_t > 30.0 and confirm() {
                to_title(g);
            }
        }

        # ---------------------------------------------------------- draw
        post_resize(post, int(GetScreenWidth()), int(GetScreenHeight()));
        st = g.state;
        in_flight = st == ST_PLAY or st == ST_PAUSE or st == ST_DEAD or st == ST_COMPLETE or st == ST_REFIT;
        cam = make_camera(g);
        scene_begin(post);
        if in_flight {
            draw_scene(g, cam, t);
        } elif st == ST_ENDING {
            draw_ending_scene(g, g.state_t);
        } else {
            draw_title_scene(g, t, st == ST_TITLE);
        }
        scene_end(post);
        post_apply(post);

        BeginDrawing();
        ClearBackground(rgba(0, 0, 0, 255));
        post_draw(post);
        if in_flight {
            if st == ST_PLAY {
                draw_hud(g, cam);
            } elif st == ST_PAUSE {
                draw_pause(g, ["RESUME", "RESTART CHAPTER", "QUIT TO TITLE"]);
            } elif st == ST_DEAD {
                draw_dead(g, death_items(g));
            } elif st == ST_REFIT {
                draw_refit(g, g.state_t);
            } else {
                draw_complete(g, g.state_t);
            }
        } elif st == ST_ENDING {
            draw_ending(g.state_t, g.score);
        } elif st == ST_TITLE {
            draw_title(g, t, ["NEW GAME", "CHAPTER SELECT", "CONTROLS", "QUIT"]);
        } elif st == ST_DIFFICULTY {
            draw_difficulty(g);
        } elif st == ST_CONTROLS {
            draw_controls();
        } elif st == ST_SELECT {
            draw_select(g);
        } elif st == ST_PROLOGUE {
            draw_prologue(g.state_t);
        } elif st == ST_BRIEFING {
            draw_briefing(g, g.state_t);
        }
        draw_white(g.white_fx);
        EndDrawing();

        if testing and g.state != last_state {
            print(f"frame {g.frame}: state {last_state} -> {g.state} chapter {g.chapter} score {g.score} kills {g.kills} dmg {int(g.damage)} lantern {int(g.lantern_hp)}");
            last_state = g.state;
        }
        if shot_every > 0 and g.frame % shot_every == 0 {
            TakeScreenshot("shot_c" + str(g.chapter) + "_" + str(g.frame) + ".png");
        }
        if max_frames > 0 and g.frame >= max_frames {
            quit = True;
        }
    }
    if testing {
        wall = float(GetTime()) - wall0;
        print(f"frames {g.frame} in {wall:.1f}s = {float(g.frame) / wall:.0f} fps; progress {g.dist / g.length:.2f} boss {g.boss_active} enemies {len(g.enemies)} shots {len(g.shots)} particles {len(g.particles)} props {len(g.props)} prop_hits {g.prop_hits} shield {int(g.player.shield)} alive {g.player.alive}");
    }
    CloseWindow();
}

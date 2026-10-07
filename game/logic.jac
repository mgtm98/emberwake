"""Per-frame gameplay: input, the player, enemies, bosses, collisions, radio
and chapter flow."""

import math;
import random;
import from rl {
    IsKeyDown, IsKeyPressed, IsGamepadAvailable, IsGamepadButtonDown,
    IsGamepadButtonPressed, GetGamepadAxisMovement, KEY_SPACE, KEY_A, KEY_B,
    KEY_D, KEY_E, KEY_J, KEY_K, KEY_Q, KEY_S, KEY_W, KEY_LEFT, KEY_RIGHT,
    KEY_UP, KEY_DOWN, KEY_LEFT_SHIFT, KEY_RIGHT_SHIFT, PAD_A, PAD_X, PAD_LB,
    PAD_RB, PAD_RT, PAD_AXIS_X, PAD_AXIS_Y
}
import from state {
    Game, Player, Enemy, Shot, Boss, Line, Particle, Pickup, Prop, ST_PLAY, ST_DEAD, ST_COMPLETE,
    ST_ENDING, K_MOTE, K_LANCE, K_WARDEN, K_TURRET, K_MINE, K_EMITTER, K_POD,
    K_CORE, K_BODY, K_NODE, K_CACHE, K_ICE, P_STREAM, P_V, P_RING, P_SWARM,
    P_FLANK, P_HOVER, P_FIXED, P_LANTERN, P_DIVE, P_PART, U_SHIELD, U_CANNON,
    U_BOMB, B_NONE, B_VAULT, B_CARRIER, B_CONDUCTOR, E_WAVE, E_ENEMY, E_PICKUP,
    E_BOSS, E_FLAG, CHUNK
}
import from gfx { apply_env, M_CARRIER, M_COND_CORE, M_CORE_ORB }
import from audio {
    play, play_pitch, music, chapter_track, S_LASER, S_HURT, S_ROLL, S_BOOST,
    S_BOMB, S_ALARM, S_RADIO, S_ENEMY_SHOT, S_WARNING, S_EXPLODE_BOSS, S_EXPLODE_BIG, MU_BOSS,
    MU_CH5
}
import from spawn {
    rnd, chance, make_enemy, spawn_wave, spawn_fixed, spawn_pickup, player_bolt,
    enemy_orb, enemy_orb_dir, aim_at_player, burst, explosion, damage_enemy,
    kill_enemy, collect, trigger, particle
}
import from world { chapter_env, build_chapter, gen_chunk, CHAPTER_LENGTHS }

# ------------------------------------------------------------------ input

def pad() -> bool {
    return IsGamepadAvailable(i32(0));
}

def axis_x() -> float {
    v = 0.0;
    if IsKeyDown(i32(KEY_A)) or IsKeyDown(i32(KEY_LEFT)) {
        v -= 1.0;
    }
    if IsKeyDown(i32(KEY_D)) or IsKeyDown(i32(KEY_RIGHT)) {
        v += 1.0;
    }
    if pad() {
        a = float(GetGamepadAxisMovement(i32(0), i32(PAD_AXIS_X)));
        if abs(a) > 0.2 {
            v = a;
        }
    }
    return v;
}

def axis_y() -> float {
    v = 0.0;
    if IsKeyDown(i32(KEY_S)) or IsKeyDown(i32(KEY_DOWN)) {
        v -= 1.0;
    }
    if IsKeyDown(i32(KEY_W)) or IsKeyDown(i32(KEY_UP)) {
        v += 1.0;
    }
    if pad() {
        a = float(GetGamepadAxisMovement(i32(0), i32(PAD_AXIS_Y)));
        if abs(a) > 0.2 {
            v = -a;
        }
    }
    return v;
}

def key_or_pad(key: int, key2: int, button: int) -> bool {
    if IsKeyDown(i32(key)) or IsKeyDown(i32(key2)) {
        return True;
    }
    return pad() and IsGamepadButtonDown(i32(0), i32(button));
}

def pressed_or_pad(key: int, key2: int, button: int) -> bool {
    if IsKeyPressed(i32(key)) or IsKeyPressed(i32(key2)) {
        return True;
    }
    return pad() and IsGamepadButtonPressed(i32(0), i32(button));
}

# ------------------------------------------------------------------ chapter setup

def start_chapter(g: Game, ch: int) {
    g.chapter = ch;
    g.env = chapter_env(ch);
    apply_env(g.gfx, g.env);
    g.player = Player();
    g.player.weapon = 1 if ch >= 3 else 0;
    g.enemies = [];
    g.shots = [];
    g.particles = [];
    g.pickups = [];
    g.props = [];
    g.queue = [];
    g.group_left = [];
    g.radio_t = 0.0;
    g.radio_text = "";
    g.scroll = 0.0;
    g.dist = 0.0;
    g.pz = 0.0;
    g.length = CHAPTER_LENGTHS[ch];
    g.speed = 28.0;
    g.hold = False;
    g.chunk_next = 0;
    g.boss = Boss();
    g.boss_active = False;
    g.escort = False;
    g.lantern_hp = 100.0;
    g.lantern_x = -80.0;
    g.lantern_y = -25.0;
    g.lantern_dz = 2000.0;
    g.halo = 0;
    g.trench = False;
    g.finish_t = 0.0;
    g.gate_t = 0.0;
    g.cache_done = False;
    g.fail = "";
    g.combo = 0;
    g.combo_t = 0.0;
    g.kills = 0;
    g.fired = 0;
    g.hits = 0;
    g.damage = 0.0;
    g.chapter_start_score = g.score;
    g.cam_x = 0.0;
    g.cam_y = 2.6;
    g.cam_z = 10.5;
    g.white_fx = 0.6;
    random.seed(1000 + ch);
    build_chapter(g, ch);
    stream_chunks(g);
    music(g.audio, chapter_track(ch));
}

def stream_chunks(g: Game) {
    while -float(g.chunk_next) * CHUNK > g.pz - 380.0 {
        gen_chunk(g, g.chunk_next);
        g.chunk_next += 1;
    }
}

"""Jump to progress p (testing): earlier events are skipped, flags still apply."""
def skip_to(g: Game, p: float) {
    for ev in g.events {
        if ev.at < p {
            ev.done = True;
            if ev.kind == E_FLAG {
                run_flag(g, ev.s);
            }
        }
    }
    for ln in g.lines {
        if ln.at >= 0.0 and ln.at < p {
            ln.done = True;
        }
    }
    g.dist = p * g.length;
    g.scroll = g.dist;
    g.pz = -g.scroll;
    g.props = [];
    g.enemies = [];
    g.chunk_next = int(g.scroll / CHUNK);
    stream_chunks(g);
}

def progress(g: Game) -> float {
    return g.dist / g.length;
}

# ------------------------------------------------------------------ events + radio

def run_events(g: Game) {
    p = progress(g);
    for ev in g.events {
        if ev.done or ev.at > p {
            continue;
        }
        ev.done = True;
        if ev.kind == E_WAVE {
            first = len(g.enemies);
            spawn_wave(g, ev.i, int(ev.a), int(ev.b), ev.c, ev.d);
            if ev.s == "hold" {
                for k in range(first, len(g.enemies)) {
                    g.enemies[k].holds = True;
                }
            }
        } elif ev.kind == E_ENEMY {
            e = spawn_fixed(g, ev.i, ev.c, ev.d, ev.a);
            if ev.i == K_CACHE {
                e.drop = U_CANNON;
            }
        } elif ev.kind == E_PICKUP {
            spawn_pickup(g, ev.i, ev.c, ev.d, g.pz - 160.0);
        } elif ev.kind == E_BOSS {
            start_boss(g, ev.i);
        } else {
            run_flag(g, ev.s);
        }
    }
}

def run_flag(g: Game, name: str) {
    if name == "halo_on" {
        g.halo = 1;
        g.halo_x = 6.0;
        g.halo_y = 1.5;
        g.halo_dz = 6.0;
    } elif name == "halo_leave" {
        g.halo = 2;
    } elif name == "halo_lost" {
        explosion(g, -140.0, -30.0, g.pz - 320.0, 4.0, 1);
    } elif name == "lantern_side" {
        g.lantern_x = -125.0;
        g.lantern_y = -46.0;
        g.lantern_dz = 110.0;
    } elif name == "lantern_away" {
        g.gate_t = 0.01;
    } elif name == "escort_on" {
        g.escort = True;
        g.lantern_x = -72.0;
        g.lantern_y = -30.0;
        g.lantern_dz = 75.0;
    } elif name == "lantern_ahead" {
        g.lantern_x = -75.0;
        g.lantern_y = -30.0;
        g.lantern_dz = 230.0;
    } elif name == "trench_on" {
        g.trench = True;
    } elif name == "trench_off" {
        g.trench = False;
    } elif name == "cache_check" {
        if g.player.weapon == 0 {
            spawn_pickup(g, U_CANNON, g.player.x, g.player.y + 2.0, g.pz - 60.0);
        }
    }
}

def radio_update(g: Game, dt: float) {
    p = progress(g);
    for ln in g.lines {
        if not ln.done and ln.at >= 0.0 and ln.at <= p {
            ln.done = True;
            g.queue.append(ln);
        }
    }
    g.radio_t -= dt;
    if g.radio_t <= 0.0 and len(g.queue) > 0 {
        ln = g.queue[0];
        rest: list[Line] = [];
        for k in range(1, len(g.queue)) {
            rest.append(g.queue[k]);
        }
        g.queue = rest;
        g.radio_who = ln.who;
        g.radio_text = ln.text;
        g.radio_t = 2.2 + float(len(ln.text)) * 0.05;
        play(g.audio, S_RADIO);
    }
}

# ------------------------------------------------------------------ player

def hurt(g: Game, dmg: float) {
    p = g.player;
    if not p.alive or p.invuln > 0.0 or g.demo {
        return;
    }
    p.shield -= dmg;
    p.invuln = 1.0;
    g.damage += dmg;
    g.hurt_fx = 1.0;
    g.shake = max(g.shake, 0.6);
    g.combo = 0;
    g.combo_t = 0.0;
    play(g.audio, S_HURT);
    burst(g, p.x, p.y, g.pz, 16, 7.0, 0.3, 3);
    if p.shield <= 0.0 {
        p.shield = 0.0;
        kill_player(g, "THE KESTREL IS DOWN");
    }
}

def kill_player(g: Game, why: str) {
    p = g.player;
    if not p.alive {
        return;
    }
    p.alive = False;
    p.dead_t = 0.0;
    g.fail = why;
    explosion(g, p.x, p.y, g.pz, 5.0, 1);
    play(g.audio, S_EXPLODE_BOSS);
    g.white_fx = 0.7;
}

def update_player(g: Game, dt: float) {
    p = g.player;
    if not p.alive {
        p.dead_t += dt;
        return;
    }
    ax = axis_x();
    ay = axis_y();
    if g.demo {
        ax = math.sin(g.demo_t * 0.7) * 0.8;
        ay = math.sin(g.demo_t * 0.53) * 0.6;
        best = 1.0e9;
        for e in g.enemies {
            rz = g.pz - e.z;
            if e.alive and not e.invuln and e.delay <= 0.0 and rz > 8.0 and rz < 160.0 and rz < best {
                best = rz;
                tx = max(-g.max_x, min(g.max_x, e.x));
                ty = max(g.min_y, min(g.max_y, e.y));
                ax = max(-1.0, min(1.0, (tx - p.x) * 0.6));
                ay = max(-1.0, min(1.0, (ty - p.y) * 0.6));
            }
        }
    }
    k = min(1.0, dt * 8.0);
    p.vx += (ax * 15.0 - p.vx) * k;
    p.vy += (ay * 11.0 - p.vy) * k;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    if p.x > g.max_x {
        p.x = g.max_x;
        p.vx = 0.0;
    } elif p.x < -g.max_x {
        p.x = -g.max_x;
        p.vx = 0.0;
    }
    if p.y > g.max_y {
        p.y = g.max_y;
        p.vy = 0.0;
    } elif p.y < g.min_y {
        p.y = g.min_y;
        p.vy = 0.0;
    }
    p.bank += (-p.vx * 0.06 - p.bank) * k;
    p.pitch += (p.vy * 0.04 - p.pitch) * k;
    p.invuln = max(0.0, p.invuln - dt);
    p.roll_cd = max(0.0, p.roll_cd - dt);
    if p.roll_t > 0.0 {
        p.roll_t = max(0.0, p.roll_t - dt);
    }

    # boost
    want = not g.demo and key_or_pad(KEY_LEFT_SHIFT, KEY_RIGHT_SHIFT, PAD_RT);
    if want and p.boost > 4.0 and g.gate_t <= 0.0 {
        if not p.boosting {
            play(g.audio, S_BOOST);
        }
        p.boosting = True;
        p.boost = max(0.0, p.boost - 40.0 * dt);
    } else {
        p.boosting = False;
        p.boost = min(100.0, p.boost + 20.0 * dt);
    }

    # roll
    if p.roll_cd <= 0.0 and not g.demo {
        left = pressed_or_pad(KEY_Q, KEY_Q, PAD_LB);
        right = pressed_or_pad(KEY_E, KEY_E, PAD_RB);
        if left or right {
            p.roll_t = 0.5;
            p.roll_dir = 1.0 if left else -1.0;
            p.roll_cd = 0.8;
            p.vx += -8.0 if left else 8.0;
            play(g.audio, S_ROLL);
        }
    }

    # fire
    p.fire_cd -= dt;
    firing = key_or_pad(KEY_SPACE, KEY_J, PAD_A) or g.demo;
    if firing and p.fire_cd <= 0.0 {
        p.fire_cd = 0.125;
        dmg = 2.0 if p.weapon >= 2 else 1.0;
        if p.weapon == 0 {
            player_bolt(g, p.x, p.y - 0.1, dmg);
            g.fired += 1;
        } else {
            c = math.cos(p.bank);
            s = math.sin(p.bank);
            player_bolt(g, p.x + 2.3 * c, p.y + 2.3 * s - 0.07, dmg);
            player_bolt(g, p.x - 2.3 * c, p.y - 2.3 * s - 0.07, dmg);
            g.fired += 2;
        }
        play_pitch(g.audio, S_LASER, rnd(0.95, 1.05) if p.weapon < 2 else 0.85);
    }

    # bomb
    if not g.demo and pressed_or_pad(KEY_B, KEY_K, PAD_X) and p.bombs > 0 {
        p.bombs -= 1;
        detonate_bomb(g);
    }

    # engine trail (the ember wake)
    p.trail_t -= dt;
    if p.trail_t <= 0.0 {
        p.trail_t = 0.008;
        c = math.cos(p.bank);
        s = math.sin(p.bank);
        boost = 1.6 if p.boosting else 1.0;
        for side in [-1.0, 1.0] {
            ex = p.x + side * 0.62 * c + 0.06 * s;
            ey = p.y + side * 0.62 * s - 0.06 * c;
            particle(g, ex, ey, g.pz + 2.1, rnd(-0.3, 0.3), rnd(-0.3, 0.3), -g.speed + 9.0, 0.22 * boost, 0.12 * boost, 255, 150, 50);
        }
    }

    # low-shield alarm
    if p.shield < 30.0 {
        g.alarm_t -= dt;
        if g.alarm_t <= 0.0 {
            g.alarm_t = 0.9;
            play(g.audio, S_ALARM);
        }
    }
}

def detonate_bomb(g: Game) {
    play(g.audio, S_BOMB);
    g.white_fx = 0.8;
    g.shake = 1.0;
    p = g.player;
    for s in g.shots {
        if s.hostile and s.alive {
            s.alive = False;
            particle(g, s.x, s.y, s.z, 0.0, 0.0, -g.speed, 0.3, 0.3, 200, 120, 255);
        }
    }
    for e in g.enemies {
        rz = g.pz - e.z;
        if e.alive and e.delay <= 0.0 and rz > -5.0 and rz < 90.0 and e.kind != K_ICE {
            damage_enemy(g, e, 20.0);
        }
    }
    for k in range(4) {
        burst(g, p.x + rnd(-6.0, 6.0), p.y + rnd(-3.0, 3.0), g.pz - 25.0 - float(k) * 10.0, 30, 18.0, 0.5, 1);
    }
}

# ------------------------------------------------------------------ enemies

def update_enemy(g: Game, e: Enemy, dt: float) {
    p = g.player;
    if e.delay > 0.0 {
        e.delay -= dt;
        if e.pat != P_FIXED and e.pat != P_PART {
            e.z -= g.speed * dt;
        }
        return;
    }
    e.t += dt;
    e.flash = max(0.0, e.flash - dt * 6.0);
    e.roll += e.spin * dt;
    rz = g.pz - e.z;
    approach = -g.speed + e.a;
    if e.pat == P_STREAM {
        e.z += approach * dt;
        e.x = e.ox + e.b * math.sin(e.t * 1.6 + e.c);
        e.y = e.oy + e.b * 0.5 * math.cos(e.t * 1.3 + e.c);
        e.yaw = math.pi;
    } elif e.pat == P_V {
        e.z += approach * dt;
        e.ox += (p.x - e.ox) * 0.15 * dt;
        e.oy += (p.y - e.oy) * 0.15 * dt;
        e.x = e.ox;
        e.y = e.oy;
        e.yaw = math.pi;
    } elif e.pat == P_RING {
        e.z += approach * dt;
        ang = e.c + e.t * 1.4;
        e.x = e.ox + e.b * math.cos(ang);
        e.y = e.oy + e.b * math.sin(ang);
        e.yaw = math.pi;
    } elif e.pat == P_SWARM {
        e.z += approach * dt;
        if rz > 12.0 {
            e.x += max(-1.0, min(1.0, p.x - e.x)) * 4.0 * dt;
            e.y += max(-1.0, min(1.0, p.y - e.y)) * 3.0 * dt;
        }
        e.yaw = math.pi;
    } elif e.pat == P_DIVE {
        e.z += approach * dt;
        e.x += e.b * dt;
        e.y += (-7.0 + 4.0 * e.t) * dt;
        e.yaw = math.pi;
    } elif e.pat == P_FLANK {
        update_lance(g, e, dt, rz);
    } elif e.pat == P_HOVER {
        update_warden(g, e, dt, rz);
    } elif e.pat == P_LANTERN {
        # Dive through the left of the flight box (interceptable), then strike the ark.
        tx = e.ox;
        ty = e.oy;
        tz = g.pz - 20.0;
        sp = e.a;
        if e.state == 1 {
            tx = g.lantern_x;
            ty = g.lantern_y;
            tz = g.pz - g.lantern_dz;
            sp = 45.0;
        }
        dx = tx - e.x;
        dy = ty - e.y;
        dz = tz - e.z;
        n = math.sqrt(dx * dx + dy * dy + dz * dz);
        if e.state == 0 and (n < 3.0 or rz < 21.0) {
            e.state = 1;
        } elif e.state == 1 and n < 9.0 {
            e.alive = False;
            g.lantern_hp -= 4.0;
            explosion(g, e.x, e.y, e.z, 2.5, 1);
            break_group(g, e);
            return;
        }
        n = max(n, 0.01);
        e.x += dx / n * sp * dt;
        e.y += dy / n * sp * dt;
        e.z += (dz / n * sp - g.speed) * dt;
        e.yaw = math.atan2(-dx, -dz);
    } elif e.pat == P_FIXED {
        update_fixed(g, e, dt, rz);
    }

    if e.shoots and e.pat != P_FLANK and e.pat != P_HOVER and e.pat != P_PART {
        if rz > 30.0 and rz < 110.0 and p.alive {
            e.fire_t -= dt;
            if e.fire_t <= 0.0 {
                e.fire_t = rnd(2.5, 4.5) if e.kind != K_TURRET else rnd(1.6, 2.6);
                aim_at_player(g, e, 24.0 if e.kind == K_MOTE else 30.0);
            }
        }
    }

    if e.pat != P_PART and (rz < -25.0 or abs(e.x) > 120.0 or abs(e.y) > 90.0 or rz > 600.0) {
        e.alive = False;
        break_group(g, e);
    }
}

def break_group(g: Game, e: Enemy) {
    if e.group >= 0 {
        g.group_left[e.group] = -1000;
    }
}

def update_lance(g: Game, e: Enemy, dt: float, rz: float) {
    e.state_t += dt;
    if e.state == 0 {
        e.z += (-g.speed - 34.0) * dt;
        e.x += (e.ox - e.x) * 1.5 * dt;
        e.yaw = 0.0;
        e.roll = -(e.ox - e.x) * 0.1;
        if rz > 34.0 {
            e.state = 1;
            e.state_t = 0.0;
            e.c = 0.0;
        }
    } elif e.state == 1 {
        e.z = g.pz - 34.0;
        e.yaw += (math.pi - e.yaw) * min(1.0, dt * 6.0);
        e.roll *= 0.9;
        if e.state_t > 0.55 and e.c < 3.0 and g.player.alive {
            e.fire_t -= dt;
            if e.fire_t <= 0.0 {
                e.fire_t = 0.16;
                e.c += 1.0;
                aim_at_player(g, e, 34.0);
            }
        }
        if e.state_t > 2.4 {
            e.state = 2;
        }
    } else {
        side = 1.0 if e.x >= 0.0 else -1.0;
        e.x += side * 22.0 * dt;
        e.y += 7.0 * dt;
        e.z += (-g.speed + 20.0) * dt;
        e.roll += side * 3.0 * dt;
    }
}

def update_warden(g: Game, e: Enemy, dt: float, rz: float) {
    e.state_t += dt;
    e.yaw = math.pi;
    if e.state == 0 {
        e.z += (-g.speed + 32.0) * dt;
        e.x += (e.ox - e.x) * dt;
        if rz <= e.dz {
            e.state = 1;
            e.state_t = 0.0;
        }
    } elif e.state == 1 {
        e.z = g.pz - e.dz;
        e.x = e.ox + 5.0 * math.sin(e.state_t * 0.7);
        e.y = e.oy + 1.5 * math.sin(e.state_t * 1.1);
        e.roll = 0.15 * math.sin(e.state_t * 0.7);
        e.fire_t -= dt;
        if e.fire_t <= 0.0 and g.player.alive {
            e.fire_t = 2.2;
            spread(g, e, 5, 0.18, 26.0);
        }
        if e.state_t > (40.0 if e.holds else 16.0) {
            e.state = 2;
        }
    } else {
        e.y += 10.0 * dt;
        e.z += (-g.speed - 25.0) * dt;
    }
}

"""Fan of n orbs aimed at the player, `step` radians apart horizontally."""
def spread(g: Game, e: Enemy, n: int, step: float, speed: float) {
    p = g.player;
    dx = p.x - e.x;
    dy = p.y - e.y;
    dz = g.pz - e.z;
    base = math.atan2(dx, dz);
    flat = math.sqrt(dx * dx + dz * dz);
    for k in range(n) {
        a = base + (float(k) - float(n - 1) * 0.5) * step;
        tx = e.x + math.sin(a) * flat;
        tz = e.z + math.cos(a) * flat;
        enemy_orb(g, e.x, e.y, e.z + 1.5, tx, p.y, tz, speed);
    }
    play_pitch(g.audio, S_ENEMY_SHOT, 0.8);
}

def update_fixed(g: Game, e: Enemy, dt: float, rz: float) {
    p = g.player;
    if e.kind == K_TURRET {
        e.yaw = math.pi;
        e.spin = 0.0;
    } elif e.kind == K_MINE {
        if rz < 45.0 and rz > -2.0 {
            e.x += max(-1.0, min(1.0, p.x - e.x)) * 3.0 * dt;
            e.y += max(-1.0, min(1.0, p.y - e.y)) * 3.0 * dt;
        }
        dx = p.x - e.x;
        dy = p.y - e.y;
        if abs(rz) < 3.0 and dx * dx + dy * dy < 12.0 and p.alive {
            kill_enemy(g, e);
            hurt(g, 15.0);
        }
    } elif e.kind == K_CACHE {
        e.spin = 0.4;
    }
}

# ------------------------------------------------------------------ bosses

def boss_part(g: Game, kind: int, slot: int) -> Enemy {
    e = make_enemy(g, kind, 0.0, 0.0, g.pz - 300.0);
    e.pat = P_PART;
    e.holds = True;
    e.slot = slot;
    e.fire_t = 1.5 + float(slot) * 0.7;
    g.boss.parts.append(e);
    return e;
}

def start_boss(g: Game, kind: int) {
    g.boss = Boss(kind=kind, parts=[], core=[], body=[]);
    g.boss_active = True;
    b = g.boss;
    play(g.audio, S_WARNING);
    music(g.audio, MU_BOSS);
    if kind == B_VAULT {
        b.name = "HESPER LATTICE";
        for k in range(4) {
            boss_part(g, K_EMITTER, k);
        }
    } elif kind == B_CARRIER {
        b.name = "CHOIR CARRIER";
        b.z = g.pz - 300.0;
        body = make_enemy(g, K_BODY, 0.0, 1.0, b.z);
        body.model = M_CARRIER;
        body.invuln = True;
        body.pat = P_PART;
        body.scale = 0.65;
        body.radius = 6.5;
        body.holds = True;
        b.body.append(body);
        for k in range(4) {
            boss_part(g, K_POD, k);
        }
    } else {
        b.name = "THE CONDUCTOR";
        b.z = g.pz - 420.0;
        body = make_enemy(g, K_BODY, 0.0, 0.5, b.z);
        body.model = M_COND_CORE;
        body.invuln = True;
        body.pat = P_PART;
        body.scale = 0.55;
        body.radius = 5.5;
        body.holds = True;
        body.hp = 120.0;
        body.max_hp = 120.0;
        body.score = 20000;
        b.body.append(body);
        b.ring_dist = 0.0;
        b.count = 4;
        for k in range(4) {
            boss_part(g, K_NODE, k);
        }
    }
}

def alive_parts(b: Boss) -> int {
    n = 0;
    for e in b.parts {
        if e.alive {
            n += 1;
        }
    }
    return n;
}

"""Boss health 0..1 for the HUD bar."""
def boss_health(g: Game) -> float {
    b = g.boss;
    total = 0.0;
    left = 0.0;
    for e in b.parts {
        total += e.max_hp;
        if e.alive {
            left += max(0.0, e.hp);
        }
    }
    for e in b.core {
        total += e.max_hp;
        if e.alive {
            left += max(0.0, e.hp);
        }
    }
    if b.kind == B_CARRIER and len(b.core) == 0 {
        total += 60.0;
        left += 60.0;
    }
    if b.kind == B_CONDUCTOR {
        body = b.body[0];
        total += body.max_hp;
        left += max(0.0, body.hp) if body.alive else 0.0;
    }
    if total <= 0.0 {
        return 0.0;
    }
    return left / total;
}

def update_boss(g: Game, dt: float) {
    b = g.boss;
    b.t += dt;
    if b.kind == B_VAULT {
        update_vault(g, b, dt);
    } elif b.kind == B_CARRIER {
        update_carrier(g, b, dt);
    } else {
        update_conductor(g, b, dt);
    }
}

def end_boss(g: Game) {
    b = g.boss;
    g.boss_active = False;
    for e in b.body {
        e.alive = False;
    }
    g.score += 10000 if b.kind == B_CONDUCTOR else 3000;
    trigger(g, "boss_dead");
    music(g.audio, chapter_track(g.chapter));
}

def boss_dying(g: Game, b: Boss, dt: float, x: float, y: float, z: float, r: float, dur: float) {
    b.dying += dt;
    if random.random() < dt * 12.0 {
        explosion(g, x + rnd(-r, r), y + rnd(-r, r), z + rnd(-r, r), 3.0, 0 if chance(0.6) else 1);
    }
    if b.dying >= dur {
        explosion(g, x, y, z, 8.0, 0);
        play(g.audio, S_EXPLODE_BOSS);
        g.white_fx = 1.0;
        g.shake = 1.5;
        end_boss(g);
    }
}

def update_vault(g: Game, b: Boss, dt: float) {
    b.z = g.pz - 105.0;
    slots_x = [-9.0, 9.0, -6.0, 6.0];
    slots_y = [3.5, 3.5, -3.5, -3.5];
    enter = min(1.0, b.t / 3.0);
    for e in b.parts {
        if not e.alive {
            continue;
        }
        k = e.slot;
        e.x = slots_x[k] + math.sin(b.t * 0.8 + float(k)) * 1.2;
        e.y = slots_y[k] + math.cos(b.t * 0.6 + float(k)) * 0.8;
        e.z = g.pz - (240.0 - 180.0 * enter);
        e.yaw = b.t * 0.5 + float(k);
        if enter >= 1.0 and g.player.alive {
            e.fire_t -= dt;
            if e.fire_t <= 0.0 {
                e.fire_t = 3.4;
                n = 10;
                for i in range(n) {
                    a = 2.0 * math.pi * float(i) / float(n) + b.t;
                    enemy_orb_dir(g, e.x, e.y, e.z + 2.0, math.cos(a) * 4.0, math.sin(a) * 4.0, 22.0);
                }
                aim_at_player(g, e, 30.0);
            }
        }
    }
    if alive_parts(b) == 0 {
        if b.dying == 0.0 {
            trigger(g, "emitters_down");
        }
        boss_dying(g, b, dt, 0.0, 0.0, b.z + 30.0, 6.0, 1.2);
    }
}

def update_carrier(g: Game, b: Boss, dt: float) {
    body = b.body[0];
    if b.phase == 0 {
        enter = min(1.0, b.t / 4.0);
        b.z = g.pz - (300.0 - 200.0 * enter);
        if enter >= 1.0 {
            b.phase = 1;
        }
    } else {
        b.z = g.pz - 100.0;
    }
    b.x = 4.0 * math.sin(b.t * 0.3);
    b.y = 1.0 + 1.5 * math.sin(b.t * 0.45);
    body.x = b.x;
    body.y = b.y;
    body.z = b.z;
    body.yaw = math.pi;
    body.roll = 0.06 * math.sin(b.t * 0.45);
    offs_x = [9.4, -9.4, 9.4, -9.4];
    offs_y = [3.25, 3.25, -3.25, -3.25];
    for e in b.parts {
        if not e.alive {
            continue;
        }
        e.x = b.x + offs_x[e.slot];
        e.y = b.y + offs_y[e.slot];
        e.z = b.z - 2.6;
        e.scale = 1.1;
        e.yaw = math.pi;
        e.roll += dt * 0.8;
        if b.phase >= 1 and g.player.alive {
            e.fire_t -= dt;
            if e.fire_t <= 0.0 {
                e.fire_t = 2.8;
                spread(g, e, 3, 0.2, 28.0);
            }
        }
    }
    if b.phase >= 1 {
        b.launch_t -= dt;
        if b.launch_t <= 0.0 {
            b.launch_t = 4.8 if b.phase == 1 else 4.0;
            for k in range(3) {
                m = make_enemy(g, K_MOTE, b.x + rnd(-3.0, 3.0), b.y + rnd(-2.0, 2.0), b.z + 15.0);
                m.pat = P_LANTERN;
                m.a = 20.0;
                m.ox = rnd(-8.0, -1.0);
                m.oy = rnd(-4.0, 2.0);
                m.delay = float(k) * 0.3;
            }
        }
    }
    if b.phase == 1 and alive_parts(b) == 0 {
        b.phase = 2;
        trigger(g, "pods_down");
        core = make_enemy(g, K_CORE, b.x, b.y, b.z + 12.0);
        core.pat = P_PART;
        core.holds = True;
        core.hp = 60.0;
        core.max_hp = 60.0;
        b.core.append(core);
    }
    if b.phase == 2 {
        core = b.core[0];
        if core.alive {
            core.x = b.x;
            core.y = b.y;
            core.z = b.z + 12.0;
            core.roll += dt * 2.0;
            b.attack_t -= dt;
            if b.attack_t <= 0.0 and g.player.alive {
                b.attack_t = 1.7;
                spread(g, core, 5, 0.12, 30.0);
            }
        } else {
            boss_dying(g, b, dt, b.x, b.y, b.z, 8.0, 2.5);
        }
    }
}

def update_conductor(g: Game, b: Boss, dt: float) {
    body = b.body[0];
    if b.phase == 0 {
        enter = min(1.0, b.t / 5.0);
        b.z = g.pz - (420.0 - 290.0 * enter);
        if enter >= 1.0 {
            b.phase = 1;
            trigger(g, "boss_intro");
        }
    } else {
        b.z = g.pz - 130.0;
    }
    b.x = 2.0 * math.sin(b.t * 0.25);
    b.y = 0.5 + 1.5 * math.sin(b.t * 0.4);
    body.x = b.x;
    body.y = b.y;
    body.z = b.z;
    body.yaw = math.pi;
    body.roll = b.t * 0.05;
    b.ring_roll += dt * (0.35 if b.phase <= 1 else 1.6);
    if b.phase >= 2 {
        b.ring_dist += dt * 60.0;
    }
    alive_n = 0;
    for e in b.parts {
        if not e.alive {
            continue;
        }
        alive_n += 1;
        a = b.ring_roll + float(e.slot) * math.pi * 0.5;
        e.x = b.x + 12.0 * math.cos(a);
        e.y = b.y + 12.0 * math.sin(a);
        e.z = b.z;
        e.roll = a;
        e.yaw = math.pi;
        if b.phase == 1 and g.player.alive {
            e.fire_t -= dt;
            if e.fire_t <= 0.0 {
                e.fire_t = 0.24;
                sa = b.t * 2.4 + float(e.slot) * 1.3;
                enemy_orb_dir(g, e.x, e.y, e.z + 2.0, math.cos(sa) * 3.0 - e.x * 0.12, math.sin(sa) * 3.0 - (e.y - 1.0) * 0.12, 26.0);
            }
        }
    }
    if b.phase == 1 {
        if alive_n < b.count {
            if alive_n == 3 {
                trigger(g, "nodes_3");
            } elif alive_n == 2 {
                trigger(g, "nodes_2");
            } elif alive_n == 1 {
                trigger(g, "nodes_1");
            }
            b.count = alive_n;
        }
        b.attack_t -= dt;
        if b.attack_t <= 0.0 and g.player.alive {
            b.attack_t = 3.0;
            aim_at_player(g, body, 30.0);
        }
        if alive_n == 0 {
            b.phase = 2;
            body.invuln = False;
            b.core.append(body);
            trigger(g, "core_exposed");
            play(g.audio, S_EXPLODE_BIG);
        }
    } elif b.phase == 2 or b.phase == 3 {
        if body.alive and body.hp < 40.0 and b.phase == 2 {
            b.phase = 3;
            trigger(g, "boss_phase3");
            g.gate_t = 0.01;
        }
        if body.alive and g.player.alive {
            b.attack_t -= dt;
            b.launch_t -= dt;
            if b.phase == 2 {
                if b.attack_t <= 0.0 {
                    b.attack_t = 2.2;
                    spread(g, body, 5, 0.1, 32.0);
                    for i in range(14) {
                        a = 2.0 * math.pi * float(i) / 14.0 + b.t * 0.7;
                        enemy_orb_dir(g, body.x, body.y, body.z + 5.0, math.cos(a) * 5.0, math.sin(a) * 5.0, 22.0);
                    }
                }
                if b.launch_t <= 0.0 {
                    b.launch_t = 6.0;
                    spawn_wave(g, K_MOTE, P_SWARM, 4, 0.0, 0.0);
                }
            } else {
                if b.attack_t <= 0.0 {
                    b.attack_t = 0.11;
                    for arm in range(2) {
                        a = b.t * 3.1 + float(arm) * math.pi;
                        enemy_orb_dir(g, body.x, body.y, body.z + 5.0, math.cos(a) * 4.5, math.sin(a) * 4.5, 24.0);
                    }
                }
                if b.launch_t <= 0.0 {
                    b.launch_t = 2.6;
                    aim_at_player(g, body, 34.0);
                }
            }
        }
        if not body.alive {
            boss_dying(g, b, dt, b.x, b.y, b.z, 7.0, 3.5);
        }
    }
}

# ------------------------------------------------------------------ collisions

def collide(g: Game) {
    p = g.player;
    rolling = p.roll_t > 0.0;
    for s in g.shots {
        if not s.alive {
            continue;
        }
        if s.hostile {
            if p.alive {
                dx = s.x - p.x;
                dy = s.y - p.y;
                dz = s.z - g.pz;
                if dx * dx + dy * dy + dz * dz < 1.5 {
                    s.alive = False;
                    if rolling {
                        burst(g, s.x, s.y, s.z, 8, 6.0, 0.18, 3);
                    } else {
                        hurt(g, 10.0);
                    }
                }
            }
            continue;
        }
        for e in g.enemies {
            if not e.alive or e.delay > 0.0 {
                continue;
            }
            dz = s.z - e.z;
            r = e.radius + 0.5;
            if dz > r + 3.0 or dz < -r - 3.0 {
                continue;
            }
            dx = s.x - e.x;
            dy = s.y - e.y;
            if dx * dx + dy * dy + dz * dz < r * r {
                s.alive = False;
                g.hits += 1;
                if e.invuln {
                    burst(g, s.x, s.y, s.z, 4, 5.0, 0.15, 0);
                } else {
                    damage_enemy(g, e, s.dmg);
                    burst(g, s.x, s.y, s.z, 3, 4.0, 0.14, 1);
                }
                break;
            }
        }
        if s.alive {
            for pr in g.props {
                if not pr.solid or not pr.alive {
                    continue;
                }
                if prop_hit(pr, s.x, s.y, s.z, 0.2) {
                    s.alive = False;
                    burst(g, s.x, s.y, s.z, 3, 4.0, 0.14, 1);
                    break;
                }
            }
        }
    }
    if not p.alive {
        return;
    }
    for e in g.enemies {
        if not e.alive or e.delay > 0.0 or e.pat == P_PART {
            continue;
        }
        dz = e.z - g.pz;
        r = e.radius * 0.8 + 0.9;
        if abs(dz) > r {
            continue;
        }
        dx = e.x - p.x;
        dy = e.y - p.y;
        if dx * dx + dy * dy + dz * dz < r * r {
            if e.kind == K_MOTE or e.kind == K_LANCE or e.kind == K_ICE or e.kind == K_MINE {
                kill_enemy(g, e);
                hurt(g, 15.0);
            } elif e.kind == K_CACHE {
                kill_enemy(g, e);
            } else {
                hurt(g, 20.0);
            }
        }
    }
    for pr in g.props {
        if pr.solid and pr.alive and prop_hit(pr, p.x, p.y, g.pz, 0.8) {
            if p.invuln <= 0.0 {
                hurt(g, 20.0);
                burst(g, p.x, p.y, g.pz - 1.0, 20, 8.0, 0.3, 1);
            }
            if pr.box {
                p.vy += 14.0 if p.y > pr.y else -14.0;
            } else {
                dx = p.x - pr.x;
                dy = p.y - pr.y;
                n = max(0.1, math.sqrt(dx * dx + dy * dy));
                p.vx += dx / n * 14.0;
                p.vy += dy / n * 14.0;
            }
        }
    }
    for u in g.pickups {
        if not u.alive {
            continue;
        }
        dx = u.x - p.x;
        dy = u.y - p.y;
        dz = u.z - g.pz;
        if dx * dx + dy * dy + dz * dz < 6.0 {
            collect(g, u);
        }
    }
}

def prop_hit(pr: Prop, x: float, y: float, z: float, pad: float) -> bool {
    if pr.box {
        return abs(x - pr.x) < pr.hx + pad and abs(y - pr.y) < pr.hy + pad and abs(z - pr.z) < pr.hz + pad;
    }
    dz = z - pr.z;
    r = pr.radius + pad;
    if abs(dz) > r {
        return False;
    }
    dx = x - pr.x;
    dy = y - pr.y;
    return dx * dx + dy * dy + dz * dz < r * r;
}

# ------------------------------------------------------------------ frame

def update_play(g: Game, dt: float) {
    p = g.player;
    if g.demo {
        g.demo_t += dt;
    }
    update_player(g, dt);

    # rail
    target = 28.0;
    if p.boosting {
        target = 44.0;
    }
    if g.chapter == 5 and not g.boss_active and g.boss.kind == B_CONDUCTOR {
        target = 64.0;
    }
    g.speed += (target - g.speed) * min(1.0, dt * 3.0);
    g.scroll += g.speed * dt;
    g.pz = -g.scroll;
    g.hold = g.boss_active;
    if not g.hold {
        for e in g.enemies {
            if e.alive and e.holds {
                g.hold = True;
                break;
            }
        }
    }
    if not g.hold {
        g.dist = min(g.length, g.dist + g.speed * dt);
    }
    stream_chunks(g);
    run_events(g);
    radio_update(g, dt);

    # companions
    if g.halo == 1 {
        g.halo_x += (min(8.5, p.x + 6.0) - g.halo_x) * min(1.0, dt * 1.5);
        g.halo_y += (p.y + 1.6 - g.halo_y) * min(1.0, dt * 1.5);
        g.halo_dz = 6.0;
        if random.random() < dt * 3.0 {
            g.shots.append(Shot(x=g.halo_x, y=g.halo_y, z=g.pz - g.halo_dz - 2.5, vx=0.0, vy=0.0, vz=-(g.speed + 170.0), life=1.4));
        }
    } elif g.halo == 2 {
        g.halo_x -= 26.0 * dt;
        g.halo_y += 3.0 * dt;
        g.halo_dz -= 18.0 * dt;
        if g.halo_dz < -60.0 {
            g.halo = 3;
        }
    }
    if g.gate_t > 0.0 {
        g.gate_t += dt;
        g.lantern_dz += (40.0 + g.gate_t * 120.0) * dt;
    }
    if g.escort and g.lantern_hp <= 0.0 and p.alive {
        g.lantern_hp = 0.0;
        explosion(g, g.lantern_x, g.lantern_y, g.pz - g.lantern_dz, 8.0, 1);
        kill_player(g, "THE LANTERN IS LOST");
    }

    if g.boss_active {
        update_boss(g, dt);
    }
    for e in g.enemies {
        if e.alive {
            update_enemy(g, e, dt);
        }
    }
    for s in g.shots {
        if s.alive {
            s.x += s.vx * dt;
            s.y += s.vy * dt;
            s.z += s.vz * dt;
            s.life -= dt;
            if s.life <= 0.0 or s.z > g.pz + 15.0 {
                s.alive = False;
            }
        }
    }
    for u in g.pickups {
        if u.alive {
            u.t += dt;
            rz = g.pz - u.z;
            if rz < 45.0 and p.alive {
                u.x += max(-1.0, min(1.0, p.x - u.x)) * 9.0 * dt;
                u.y += max(-1.0, min(1.0, p.y - u.y)) * 9.0 * dt;
            }
            if rz < -15.0 {
                u.alive = False;
            }
        }
    }
    for pr in g.props {
        pr.yaw += pr.spin_yaw * dt;
        pr.pitch += pr.spin_pitch * dt;
        if pr.z > g.pz + 40.0 {
            pr.alive = False;
        }
    }
    for q in g.particles {
        q.x += q.vx * dt;
        q.y += q.vy * dt;
        q.z += q.vz * dt;
        q.life -= dt;
        if q.life <= 0.0 {
            q.alive = False;
        }
    }
    collide(g);
    compact(g);

    g.combo_t = max(0.0, g.combo_t - dt);
    if g.combo_t <= 0.0 {
        g.combo = 0;
    }
    update_camera(g, dt);
    g.hurt_fx = max(0.0, g.hurt_fx - dt * 2.0);
    g.white_fx = max(0.0, g.white_fx - dt * 1.2);

    # chapter end
    if g.dist >= g.length and not g.hold and p.alive {
        g.finish_t += dt;
        if g.chapter == 5 {
            if g.finish_t > 3.2 {
                g.white_fx = 1.0;
                g.state = ST_ENDING;
                g.state_t = 0.0;
            }
        } elif g.finish_t > 2.5 {
            g.state = ST_COMPLETE;
            g.state_t = 0.0;
            g.menu = 0;
        }
    }
    if not p.alive and p.dead_t > 2.8 {
        g.state = ST_DEAD;
        g.state_t = 0.0;
        g.menu = 0;
    }
}

def update_camera(g: Game, dt: float) {
    p = g.player;
    k = min(1.0, dt * 4.0);
    g.cam_x += (p.x * 0.72 - g.cam_x) * k;
    g.cam_y += (p.y * 0.68 + 2.4 - g.cam_y) * k;
    g.cam_roll += (p.bank * 0.25 - g.cam_roll) * k;
    g.shake = max(0.0, g.shake - dt * 1.8);
}

def compact(g: Game) {
    es: list[Enemy] = [];
    for e in g.enemies {
        if e.alive {
            es.append(e);
        }
    }
    g.enemies = es;
    ss: list[Shot] = [];
    for s in g.shots {
        if s.alive {
            ss.append(s);
        }
    }
    g.shots = ss;
    ps: list[Particle] = [];
    for q in g.particles {
        if q.alive {
            ps.append(q);
        }
    }
    g.particles = ps;
    us: list[Pickup] = [];
    for u in g.pickups {
        if u.alive {
            us.append(u);
        }
    }
    g.pickups = us;
    rs: list[Prop] = [];
    for pr in g.props {
        if pr.alive {
            rs.append(pr);
        }
    }
    g.props = rs;
}

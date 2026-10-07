"""3D scene drawing: sky, chapter backdrops, scenery, ships, bosses, shots and
particles."""

import math;
import from rl {
    Camera3D, Color, BeginMode3D, EndMode3D, BeginBlendMode, EndBlendMode,
    DrawCube, DrawSphereEx, DrawLine3D, rlDrawRenderBatchActive,
    rlDisableDepthMask, rlEnableDepthMask
}
import from gfx {
    Gfx, vec3, rgba, clamp, set_view, draw, draw_flash, draw_alpha, draw_sky,
    draw_backdrop, M_KESTREL, M_HALO, M_LANTERN, M_TARSIS, M_MARETH, M_SUN,
    M_SUN_BLUE, M_APERTURE, M_APERTURE_FIELD, M_CORE_ORB, M_SHIELD, M_COND_RING, M_COND_CORE,
    M_VAULT, M_PICK_SHIELD, M_PICK_CANNON, M_PICK_BOMB, M_PRISM_HALF, M_RING_FX
}
import from state {
    Game, Enemy, K_CORE, K_BODY, K_PRISM, K_WEAVER, U_SHIELD, U_CANNON, B_VAULT,
    B_CARRIER, B_CONDUCTOR
}

def make_camera(g: Game) -> Camera3D {
    sx = 0.0;
    sy = 0.0;
    if g.shake > 0.0 {
        sx = math.sin(float(g.frame) * 1.7) * g.shake * 0.35;
        sy = math.cos(float(g.frame) * 2.3) * g.shake * 0.35;
    }
    return Camera3D(
        position=vec3(g.cam_x + sx, g.cam_y + sy, g.pz + 10.5),
        target=vec3(g.cam_x * 1.1, g.cam_y - 1.5, g.pz - 30.0),
        up=vec3(math.sin(g.cam_roll), math.cos(g.cam_roll), 0.0),
        fovy=f32(62.0 + max(0.0, g.speed - 28.0) * 0.4),
        projection=i32(0)
    );
}

def hash01(i: int, salt: float) -> float {
    v = math.sin(float(i) * 12.9898 + salt) * 43758.5453;
    return v - math.floor(v);
}

"""Space dust: world-fixed points that wrap around the camera and streak with speed."""
def draw_dust(g: Game) {
    streak = g.speed * 0.035;
    r = 190;
    gr = 200;
    b = 225;
    if g.chapter == 2 {
        r = 170;
        gr = 225;
        b = 245;
    } elif g.chapter == 4 {
        r = 220;
        gr = 150;
        b = 250;
    }
    for i in range(140) {
        x = (hash01(i, 1.3) - 0.5) * 70.0;
        y = (hash01(i, 7.1) - 0.5) * 44.0;
        z0 = hash01(i, 3.7) * 140.0;
        m = (g.pz + 12.0 - z0) % 140.0;
        if m < 0.0 {
            m += 140.0;
        }
        z = g.pz + 12.0 - m;
        f = 1.0 - m / 140.0;
        DrawLine3D(vec3(x, y, z), vec3(x, y, z + streak), rgba(int(float(r) * f), int(float(gr) * f), int(float(b) * f), 255));
    }
}

"""Distance from the player to the Aperture in chapter 5."""
def gate_distance(g: Game) -> float {
    if g.finish_t > 0.0 {
        return 300.0 - g.finish_t * 110.0;
    }
    return min(1300.0, 300.0 + (g.length - g.dist) * 0.45);
}

def draw_backdrops(g: Game, cx: float, cy: float, cz: float, t: float) {
    gx = g.gfx;
    ch = g.chapter;
    if ch == 1 {
        draw_backdrop(gx, M_TARSIS, cx - 900.0, cy - 560.0, cz - 820.0, t * 0.01, 0.3, 0.2, 720.0);
        draw_backdrop(gx, M_SUN, cx + 520.0, cy + 330.0, cz - 1250.0, t * 0.05, 0.2, 0.0, 70.0);
    } elif ch == 2 {
        draw_backdrop(gx, M_MARETH, cx + 560.0, cy - 140.0, cz - 1150.0, t * 0.01, 0.25, 0.35, 430.0);
        draw_backdrop(gx, M_SUN, cx - 650.0, cy + 650.0, cz - 1000.0, t * 0.05, 0.0, 0.0, 35.0);
    } elif ch == 3 {
        draw_backdrop(gx, M_MARETH, cx - 900.0, cy + 280.0, cz - 900.0, t * 0.01, 0.3, -0.3, 140.0);
        draw_backdrop(gx, M_SUN, cx + 700.0, cy + 900.0, cz + 300.0, t * 0.05, 0.0, 0.0, 45.0);
    } elif ch == 4 {
        draw_backdrop(gx, M_CORE_ORB, cx + 520.0, cy + 260.0, cz - 1350.0, t * 0.03, 0.4, 0.0, 80.0);
    } elif ch == 5 {
        gd = gate_distance(g);
        draw_backdrop(gx, M_APERTURE, 0.0, 6.0, g.pz - gd, 0.0, 0.0, t * 0.04, 150.0);
    } elif ch == 6 {
        draw_backdrop(gx, M_SUN_BLUE, cx + 160.0, cy + 120.0, cz - 1200.0, t * 0.03, 0.0, 0.0, 110.0);
    } else {
        draw_backdrop(gx, M_TARSIS, cx - 700.0, cy - 420.0, cz - 900.0, t * 0.01, 0.3, 0.2, 650.0);
        draw_backdrop(gx, M_SUN, cx + 520.0, cy + 330.0, cz - 1250.0, t * 0.05, 0.2, 0.0, 70.0);
    }
}

def draw_enemy(g: Game, e: Enemy, t: float) {
    if e.kind == K_PRISM {
        draw_prism(g, e, t);
        return;
    }
    s = e.scale;
    if e.kind == K_CORE {
        s = e.scale * (1.0 + 0.08 * math.sin(t * 7.0));
    }
    draw_flash(g.gfx, e.model, e.x, e.y, e.z, e.yaw, e.pitch, e.roll, s, e.flash, 1.0, 1.0, 1.0);
}

"""Two armour halves that slide apart along the prism's rolled X axis."""
def draw_prism(g: Game, e: Enemy, t: float) {
    gx = g.gfx;
    sc = e.scale;
    sep = e.b * 1.7 * sc;
    c = math.cos(e.roll);
    sn = math.sin(e.roll);
    draw_flash(gx, M_PRISM_HALF, e.x + c * sep, e.y + sn * sep, e.z, 0.0, 0.0, e.roll, sc, e.flash, 1.0, 1.0, 1.0);
    draw_flash(gx, M_PRISM_HALF, e.x - c * sep, e.y - sn * sep, e.z, 0.0, 0.0, e.roll + math.pi, sc, e.flash, 1.0, 1.0, 1.0);
    glow = (0.8 + 0.7 * e.b + 0.08 * math.sin(t * 9.0)) * sc;
    draw_flash(gx, M_CORE_ORB, e.x, e.y, e.z, t, 0.0, 0.0, glow, e.flash, 1.0, 1.0, 1.0);
}

def draw_scene(g: Game, cam: Camera3D, t: float) {
    gx = g.gfx;
    p = g.player;
    cx = float(cam.position.x);
    cy = float(cam.position.y);
    cz = float(cam.position.z);
    set_view(gx, cx, cy, cz);
    BeginMode3D(cam);
    draw_sky(gx, g.env.sky, cx, cy, cz, t * 0.004, 255);
    draw_backdrops(g, cx, cy, cz, t);

    far = g.pz - 460.0;
    near = g.pz + 20.0;
    for pr in g.props {
        if pr.z < near and pr.z > far {
            draw(gx, pr.model, pr.x, pr.y, pr.z, pr.yaw, pr.pitch, pr.roll, pr.scale);
        }
    }
    if g.lantern_dz < 1400.0 {
        draw(gx, M_LANTERN, g.lantern_x, g.lantern_y, g.pz - g.lantern_dz, 0.0, 0.0, 0.0, 0.8);
    }
    if g.halo == 1 or g.halo == 2 {
        roll = -0.15 if g.halo == 1 else 0.7;
        draw(gx, M_HALO, g.halo_x, g.halo_y, g.pz - g.halo_dz, 0.25 if g.halo == 2 else 0.0, 0.0, roll, 1.0);
    }
    if g.boss_active {
        draw_boss_extras(g, t);
    }
    for e in g.enemies {
        if e.delay <= 0.0 and e.z < near and e.z > far {
            draw_enemy(g, e, t);
        }
    }
    for q in g.debris {
        f = clamp(q.life / q.max_life, 0.0, 1.0);
        draw(gx, q.model, q.x, q.y, q.z, q.yaw, q.pitch, q.roll, q.scale * (0.3 + 0.7 * f));
    }
    for u in g.pickups {
        m = M_PICK_SHIELD if u.kind == U_SHIELD else (M_PICK_CANNON if u.kind == U_CANNON else M_PICK_BOMB);
        draw_flash(gx, m, u.x, u.y + 0.3 * math.sin(u.t * 3.0), u.z, u.t * 2.0, 0.3, 0.0, 1.2, 0.25 + 0.2 * math.sin(u.t * 8.0), 1.0, 1.0, 1.0);
    }
    if p.alive and (p.invuln <= 0.0 or g.frame % 6 < 4) {
        barrel = 0.0;
        if p.roll_t > 0.0 {
            barrel = p.roll_dir * 2.0 * math.pi * (1.0 - p.roll_t / p.roll_len);
        }
        draw(gx, M_KESTREL, p.x, p.y, g.pz, -p.vx * 0.012, p.pitch, p.bank + barrel, 1.0);
    }
    if g.chapter == 5 {
        gd = gate_distance(g);
        flicker = 0.22 + 0.06 * math.sin(t * 9.0);
        if g.gate_t > 0.0 {
            flicker = 0.25 + 0.2 * math.sin(t * 23.0);
        }
        draw_alpha(gx, M_APERTURE_FIELD, 0.0, 6.0, g.pz - gd, 0.0, 0.0, 0.0, 150.0, flicker);
    }
    for e in g.enemies {
        if e.shielded and e.delay <= 0.0 {
            draw_alpha(gx, M_SHIELD, e.x, e.y, e.z, t * 0.7, 0.0, 0.0, e.radius * 1.35 + 0.6, 0.2 + 0.06 * math.sin(t * 6.0 + float(e.uid)));
        }
    }
    for r in g.rings {
        f = clamp(r.t / r.dur, 0.0, 1.0);
        draw_alpha(gx, M_RING_FX, r.x, r.y, r.z, 0.0, 0.0, 0.0, r.size * (0.25 + 0.75 * f), 0.9 * (1.0 - f));
    }
    draw_effects(g, t);
    EndMode3D();
}

def draw_boss_extras(g: Game, t: float) {
    gx = g.gfx;
    b = g.boss;
    if b.kind == B_VAULT {
        draw(gx, M_VAULT, 0.0, -4.0, b.z, t * 0.1, 0.0, 0.0, 1.0);
        if b.dying == 0.0 {
            draw_alpha(gx, M_SHIELD, 0.0, -4.0, b.z, t * 0.2, 0.0, 0.0, 15.0, 0.16 + 0.04 * math.sin(t * 5.0));
        }
    } elif b.kind == B_CONDUCTOR {
        if b.ring_dist < 300.0 {
            draw(gx, M_COND_RING, b.x, b.y, b.z - b.ring_dist, 0.0, 0.0, b.ring_roll, 0.5 * (1.0 + b.ring_dist * 0.01));
        }
        if b.phase <= 1 {
            draw_alpha(gx, M_SHIELD, b.x, b.y, b.z, t * 0.3, 0.0, 0.0, 8.5, 0.14 + 0.04 * math.sin(t * 4.0));
        }
        if b.dying > 0.0 {
            draw_flash(gx, M_COND_CORE, b.x, b.y, b.z, math.pi, 0.0, b.t * 0.05, 0.55 * (1.0 + b.dying * 0.05), 0.5 + 0.5 * math.sin(t * 25.0), 1.0, 0.85, 1.0);
        }
    }
}

def draw_effects(g: Game, t: float) {
    rlDrawRenderBatchActive();
    rlDisableDepthMask();
    BeginBlendMode(i32(1));
    draw_dust(g);
    b = g.boss;
    if g.boss_active and b.kind == B_VAULT and b.dying == 0.0 {
        for e in b.parts {
            if e.alive {
                DrawLine3D(vec3(e.x, e.y, e.z), vec3(0.0, -4.0 + e.y * 0.3, b.z), rgba(170, 90, 255, 255));
            }
        }
    }
    for e in g.enemies {
        if e.link >= 0 {
            for w in g.enemies {
                if w.uid == e.link {
                    DrawLine3D(vec3(w.x, w.y, w.z), vec3(e.x, e.y, e.z), rgba(200, 110, 255, 255));
                }
            }
        }
    }
    for s in g.shots {
        if s.charged {
            DrawSphereEx(vec3(s.x, s.y, s.z), f32(0.95), i32(5), i32(8), rgba(255, 140, 50, 255));
            DrawSphereEx(vec3(s.x, s.y, s.z), f32(0.5), i32(4), i32(6), rgba(255, 240, 210, 255));
        } elif s.hostile {
            DrawSphereEx(vec3(s.x, s.y, s.z), f32(0.45), i32(4), i32(6), rgba(150, 60, 230, 255));
            DrawSphereEx(vec3(s.x, s.y, s.z), f32(0.22), i32(3), i32(5), rgba(255, 210, 255, 255));
        } elif s.dmg >= 2.0 {
            DrawCube(vec3(s.x, s.y, s.z), f32(0.16), f32(0.16), f32(3.0), rgba(120, 220, 255, 255));
        } else {
            DrawCube(vec3(s.x, s.y, s.z), f32(0.12), f32(0.12), f32(2.6), rgba(255, 170, 70, 255));
        }
    }
    for q in g.particles {
        f = clamp(q.life / q.max_life, 0.0, 1.0);
        sz = q.size * (0.4 + 0.6 * f);
        DrawCube(vec3(q.x, q.y, q.z), f32(sz), f32(sz), f32(sz), rgba(int(float(q.r) * f), int(float(q.g) * f), int(float(q.b) * f), 255));
    }
    EndBlendMode();
    rlEnableDepthMask();
}

"""Title backdrop: the Kestrel on a slow turntable above Tarsis."""
def draw_title_scene(g: Game, t: float, ship: bool) {
    gx = g.gfx;
    cam = Camera3D(position=vec3(0.0, 1.4, 13.5), target=vec3(0.0, -0.3, 0.0), up=vec3(0.0, 1.0, 0.0), fovy=f32(45.0), projection=i32(0));
    set_view(gx, 0.0, 1.4, 13.5);
    BeginMode3D(cam);
    draw_sky(gx, g.env.sky, 0.0, 1.4, 11.5, t * 0.004, 255);
    if g.chapter == 0 {
        draw_backdrop(gx, M_TARSIS, -760.0, -430.0, -900.0, t * 0.01, 0.3, 0.2, 430.0);
        draw_backdrop(gx, M_SUN, 520.0, 330.0, -1250.0, t * 0.05, 0.2, 0.0, 60.0);
    } else {
        draw_backdrops(g, 0.0, 1.4, 11.5, t);
    }
    if ship {
        draw(gx, M_KESTREL, 0.0, 0.25 * math.sin(t * 0.8), 0.0, 0.6 + t * 0.25, 0.08 * math.sin(t * 0.6), 0.2 * math.sin(t * 0.5), 1.0);
    }
    EndMode3D();
}

"""Epilogue: the Lantern drifting toward a young blue star, the Kestrel alongside."""
def draw_ending_scene(g: Game, t: float) {
    gx = g.gfx;
    lz = -40.0 - t * 3.0;
    cam = Camera3D(position=vec3(95.0 - t * 0.8, 22.0, lz + 70.0), target=vec3(-10.0, -4.0, lz - 25.0), up=vec3(0.0, 1.0, 0.0), fovy=f32(50.0), projection=i32(0));
    cx = float(cam.position.x);
    cy = float(cam.position.y);
    cz = float(cam.position.z);
    set_view(gx, cx, cy, cz);
    BeginMode3D(cam);
    draw_sky(gx, g.env.sky, cx, cy, cz, t * 0.003, 255);
    draw_backdrops(g, cx, cy, cz, t);
    draw(gx, M_LANTERN, -20.0, -6.0, lz, 0.0, 0.0, 0.02 * math.sin(t * 0.3), 0.8);
    draw(gx, M_KESTREL, 30.0 + math.sin(t * 0.5), 6.0 + 0.5 * math.sin(t * 0.7), lz + 30.0, 0.0, 0.0, -0.2 + 0.1 * math.sin(t * 0.4), 1.6);
    EndMode3D();
}

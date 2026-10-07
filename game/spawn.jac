"""Creating things: enemies, formations, shots, pickups, particles, explosions,
and the bookkeeping of a kill (score, combo, formation drops)."""

import math;
import random;
import from state {
    Game, Enemy, Shot, Particle, Pickup, Popup, Debris, Ring, K_MOTE, K_LANCE,
    K_WARDEN, K_TURRET, K_MINE, K_EMITTER, K_POD, K_CORE, K_BODY, K_NODE, K_CACHE,
    K_ICE, K_SEEKER, K_MISSILE, K_PRISM, K_WEAVER, P_STREAM, P_V, P_RING, P_SWARM,
    P_FLANK, P_HOVER, P_FIXED, P_LANTERN, P_DIVE, U_SHIELD, U_CANNON, U_BOMB
}
import from gfx {
    M_MOTE, M_LANCE, M_WARDEN, M_TURRET, M_MINE, M_EMITTER, M_POD, M_CORE_ORB,
    M_CARRIER, M_COND_NODE, M_CACHE, M_ICE_A, M_ICE_B, M_ICE_C, M_SEEKER,
    M_MISSILE, M_PRISM_HALF, M_WEAVER, M_SHARD, M_SCRAP
}
import from audio {
    play, play_pitch, S_EXPLODE_SMALL, S_EXPLODE_BIG, S_HIT, S_ENEMY_SHOT, S_PICKUP,
    S_UI_MOVE
}

def rnd(lo: float, hi: float) -> float {
    return lo + (hi - lo) * random.random();
}

def chance(p: float) -> bool {
    return random.random() < p;
}

def make_enemy(g: Game, kind: int, x: float, y: float, z: float) -> Enemy {
    model = M_MOTE;
    hp = 1.0;
    score = 100;
    scale = 1.0;
    if kind == K_LANCE {
        model = M_LANCE;
        hp = 3.0;
        score = 250;
    } elif kind == K_WARDEN {
        model = M_WARDEN;
        hp = 25.0;
        score = 1000;
        scale = 1.35;
    } elif kind == K_TURRET {
        model = M_TURRET;
        hp = 6.0;
        score = 300;
        scale = 1.3;
    } elif kind == K_MINE {
        model = M_MINE;
        hp = 2.0;
        score = 150;
        scale = 1.1;
    } elif kind == K_EMITTER {
        model = M_EMITTER;
        hp = 20.0;
        score = 800;
        scale = 1.3;
    } elif kind == K_POD {
        model = M_POD;
        hp = 15.0;
        score = 1200;
        scale = 1.4;
    } elif kind == K_CORE {
        model = M_CORE_ORB;
        hp = 60.0;
        score = 5000;
        scale = 3.0;
    } elif kind == K_BODY {
        model = M_CARRIER;
        hp = 1.0;
        score = 0;
    } elif kind == K_NODE {
        model = M_COND_NODE;
        hp = 20.0;
        score = 1500;
        scale = 1.3;
    } elif kind == K_CACHE {
        model = M_CACHE;
        hp = 4.0;
        score = 200;
        scale = 1.3;
    } elif kind == K_ICE {
        r = random.random();
        model = M_ICE_A if r < 0.4 else (M_ICE_B if r < 0.75 else M_ICE_C);
        hp = 3.0;
        score = 50;
        scale = rnd(1.1, 1.8);
    } elif kind == K_SEEKER {
        model = M_SEEKER;
        hp = 6.0;
        score = 600;
        scale = 1.3;
    } elif kind == K_MISSILE {
        model = M_MISSILE;
        hp = 1.0;
        score = 50;
        scale = 1.2;
    } elif kind == K_PRISM {
        model = M_PRISM_HALF;
        hp = 14.0;
        score = 1200;
        scale = 1.35;
    } elif kind == K_WEAVER {
        model = M_WEAVER;
        hp = 8.0;
        score = 900;
        scale = 1.6;
    }
    e = Enemy(kind=kind, model=model, x=x, y=y, z=z, hp=hp, max_hp=hp, score=score, scale=scale);
    e.uid = g.uid_next;
    g.uid_next += 1;
    e.radius = g.gfx.radius[model] * scale * 0.8;
    if kind == K_PRISM {
        e.radius = 3.4;
    } elif kind == K_MISSILE {
        e.radius = 0.9;
    }
    e.spin = rnd(-1.5, 1.5);
    e.fire_t = rnd(1.0, 3.0);
    g.enemies.append(e);
    return e;
}

def new_group(g: Game, n: int) -> int {
    g.group_left.append(n);
    return len(g.group_left) - 1;
}

"""Spawn a formation of `n` enemies of `kind` moving in pattern `pat` around (x, y)."""
def spawn_wave(g: Game, kind: int, pat: int, n: int, x: float, y: float) {
    grp = new_group(g, n);
    for i in range(n) {
        e = make_enemy(g, kind, x, y, g.pz - 170.0);
        e.pat = pat;
        e.group = grp;
        e.ox = x;
        e.oy = y;
        e.a = 26.0;
        e.shoots = g.chapter >= 2 and chance(0.35);
        if pat == P_STREAM {
            e.delay = float(i) * 0.32;
            e.b = 3.5;
            e.c = float(i) * 0.6;
        } elif pat == P_V {
            k = float(i - n // 2);
            e.ox = x + k * 2.4;
            e.oy = y + abs(k) * 1.2;
            e.delay = abs(k) * 0.15;
            e.a = 24.0;
        } elif pat == P_RING {
            e.b = 3.6;
            e.c = 2.0 * math.pi * float(i) / float(n);
            e.a = 22.0;
        } elif pat == P_SWARM {
            e.ox = rnd(-8.0, 8.0);
            e.oy = rnd(-4.5, 4.5);
            e.z = g.pz - rnd(150.0, 200.0);
            e.delay = float(i) * 0.12;
            e.a = 30.0;
        } elif pat == P_DIVE {
            e.delay = float(i) * 0.25;
            e.ox = x;
            e.oy = y + 9.0;
            e.b = -x * 0.25;
            e.a = 30.0;
        } elif pat == P_FLANK {
            side = 1.0 if x >= 0.0 else -1.0;
            e.z = g.pz + 18.0 + float(i) * 4.0;
            e.x = 13.0 * side;
            e.y = y + float(i) * 1.6 - float(n - 1) * 0.8;
            e.ox = side * rnd(2.5, 7.0);
            e.oy = e.y;
            e.delay = float(i) * 0.45;
            e.shoots = True;
        } elif pat == P_LANTERN {
            e.x = x + rnd(-6.0, 6.0);
            e.y = y + rnd(-3.0, 3.0);
            e.ox = rnd(-8.0, -1.0);
            e.oy = rnd(-4.0, 2.0);
            e.delay = float(i) * 0.35;
            e.a = 22.0;
        } elif pat == P_HOVER {
            e.z = g.pz - 160.0;
            e.ox = x;
            e.oy = y;
            e.dz = 48.0 + float(i) * 8.0;
            if kind == K_SEEKER {
                e.dz = 66.0 + float(i) * 8.0;
            } elif kind == K_PRISM {
                e.dz = 56.0 + float(i) * 10.0;
            } elif kind == K_WEAVER {
                e.dz = 72.0 + float(i) * 6.0;
            }
            e.shoots = True;
            e.fire_t = 2.0 + float(i);
        }
        if pat != P_FLANK and pat != P_LANTERN {
            e.x = e.ox;
            e.y = e.oy;
        }
    }
}

"""A single enemy fixed in the world (turrets, mines, caches) `ahead` units in front."""
def spawn_fixed(g: Game, kind: int, x: float, y: float, ahead: float) -> Enemy {
    e = make_enemy(g, kind, x, y, g.pz - ahead);
    e.pat = P_FIXED;
    e.shoots = kind == K_TURRET;
    return e;
}

def spawn_pickup(g: Game, kind: int, x: float, y: float, z: float) {
    g.pickups.append(Pickup(kind=kind, x=x, y=y, z=z));
}

# ------------------------------------------------------------------ shots

def player_bolt(g: Game, x: float, y: float, dmg: float) {
    g.shots.append(Shot(x=x, y=y, z=g.pz - 2.6, vx=0.0, vy=0.0, vz=-(g.speed + 170.0), life=1.4, dmg=dmg));
}

"""Charged plasma: slower, homing on `target` (an enemy uid, -1 for none)."""
def plasma_bolt(g: Game, x: float, y: float, target: int) {
    g.shots.append(Shot(x=x, y=y, z=g.pz - 3.0, vx=0.0, vy=0.0, vz=-(g.speed + 95.0), life=2.4, dmg=10.0, charged=True, target=target));
}

"""Enemy orb from (x,y,z) toward world point (tx,ty,tz) at `speed` relative to the rail."""
def enemy_orb(g: Game, x: float, y: float, z: float, tx: float, ty: float, tz: float, speed: float) {
    dx = tx - x;
    dy = ty - y;
    dz = tz - z;
    n = math.sqrt(dx * dx + dy * dy + dz * dz);
    if n < 0.01 {
        return;
    }
    sp = speed * g.orb_speed;
    g.shots.append(Shot(x=x, y=y, z=z, vx=dx / n * sp, vy=dy / n * sp, vz=dz / n * sp - g.speed, life=6.0, hostile=True));
}

"""Orb with an explicit direction (spirals, rings): lateral (dx,dy) plus approach speed."""
def enemy_orb_dir(g: Game, x: float, y: float, z: float, dx: float, dy: float, approach: float) {
    k = g.orb_speed;
    g.shots.append(Shot(x=x, y=y, z=z, vx=dx * k, vy=dy * k, vz=approach * k - g.speed, life=6.0, hostile=True));
}

def aim_at_player(g: Game, e: Enemy, speed: float) {
    p = g.player;
    enemy_orb(g, e.x, e.y, e.z + e.radius * 0.6, p.x, p.y, g.pz, speed);
    play_pitch(g.audio, S_ENEMY_SHOT, rnd(0.9, 1.15));
}

# ------------------------------------------------------------------ particles

def particle(g: Game, x: float, y: float, z: float, vx: float, vy: float, vz: float, life: float, size: float, r: int, gr: int, b: int) {
    if len(g.particles) < 1400 {
        g.particles.append(Particle(x=x, y=y, z=z, vx=vx, vy=vy, vz=vz, life=life, max_life=life, size=size, r=r, g=gr, b=b));
    }
}

"""Burst of particles. palette 0 = Choir violet, 1 = fire, 2 = ice, 3 = shield cyan."""
def burst(g: Game, x: float, y: float, z: float, n: int, speed: float, size: float, palette: int) {
    for i in range(n) {
        th = rnd(0.0, 2.0 * math.pi);
        u = rnd(-1.0, 1.0);
        s = math.sqrt(1.0 - u * u);
        v = speed * rnd(0.3, 1.0);
        r = 255;
        gr = 160;
        b = 60;
        k = random.random();
        if palette == 0 {
            if k < 0.5 {
                r = 190;
                gr = 90;
                b = 255;
            } elif k < 0.8 {
                r = 255;
                gr = 80;
                b = 200;
            } else {
                r = 255;
                gr = 240;
                b = 255;
            }
        } elif palette == 1 {
            if k < 0.4 {
                r = 255;
                gr = 200;
                b = 90;
            } elif k < 0.8 {
                r = 255;
                gr = 110;
                b = 30;
            } else {
                r = 255;
                gr = 250;
                b = 220;
            }
        } elif palette == 2 {
            r = 190;
            gr = 230;
            b = 255;
        } else {
            r = 120;
            gr = 220;
            b = 255;
        }
        particle(g, x, y, z, s * math.cos(th) * v, s * math.sin(th) * v, u * v - g.speed * 0.85, rnd(0.35, 0.9), size * rnd(0.5, 1.2), r, gr, b);
    }
}

def debris_piece(g: Game, model: int, x: float, y: float, z: float, speed: float, scale: float) {
    if len(g.debris) >= 160 {
        return;
    }
    th = rnd(0.0, 2.0 * math.pi);
    u = rnd(-1.0, 1.0);
    s = math.sqrt(1.0 - u * u);
    v = speed * rnd(0.4, 1.0);
    life = rnd(0.7, 1.4);
    g.debris.append(Debris(
        model=model, x=x, y=y, z=z, vx=s * math.cos(th) * v, vy=s * math.sin(th) * v,
        vz=u * v - g.speed * 0.8, yaw=rnd(0.0, 6.28), pitch=rnd(0.0, 6.28),
        roll=rnd(0.0, 6.28), spin=rnd(-9.0, 9.0), life=life, max_life=life, scale=scale * rnd(0.6, 1.3)
    ));
}

def shockwave(g: Game, x: float, y: float, z: float, size: float, dur: float) {
    g.rings.append(Ring(x=x, y=y, z=z, size=size, dur=dur));
}

def popup(g: Game, text: str, x: float, y: float, z: float, big: bool) {
    if len(g.popups) < 24 {
        g.popups.append(Popup(text=text, x=x, y=y, z=z, big=big));
    }
}

def explosion(g: Game, x: float, y: float, z: float, size: float, palette: int) {
    burst(g, x, y, z, int(14.0 + size * 10.0), 6.0 + size * 5.0, 0.25 + size * 0.12, palette);
    burst(g, x, y, z, int(6.0 + size * 4.0), 2.0 + size * 2.0, 0.6 + size * 0.3, 1);
    shard = M_SHARD if palette == 0 else (M_ICE_B if palette == 2 else M_SCRAP);
    shard_scale = 1.0 if palette != 2 else 0.35;
    for i in range(min(18, int(3.0 + size * 2.5))) {
        debris_piece(g, shard, x, y, z, 7.0 + size * 3.0, shard_scale * (0.8 + size * 0.15));
    }
    if size >= 1.5 {
        shockwave(g, x, y, z, 2.5 + size * 2.2, 0.35 + size * 0.06);
    }
    if size >= 2.5 {
        play(g.audio, S_EXPLODE_BIG);
        g.shake = max(g.shake, 0.5 + size * 0.1);
    } else {
        play_pitch(g.audio, S_EXPLODE_SMALL, rnd(0.85, 1.2));
        g.shake = max(g.shake, 0.18);
    }
}

# ------------------------------------------------------------------ kills

def add_score(g: Game, base: int) -> int {
    p = g.player;
    if g.combo_t > 0.0 {
        g.combo = min(g.combo + 1, p.combo_max);
    } else {
        g.combo = 1;
    }
    g.combo_t = p.combo_window;
    gained = base * g.combo;
    g.score += gained;
    return gained;
}

def kill_enemy(g: Game, e: Enemy) {
    e.alive = False;
    palette = 2 if e.kind == K_ICE else (1 if e.kind == K_CACHE else 0);
    size = 1.0;
    if e.kind == K_WARDEN or e.kind == K_EMITTER or e.kind == K_POD or e.kind == K_NODE {
        size = 3.0;
    } elif e.kind == K_CORE {
        size = 5.0;
    } elif e.kind == K_LANCE or e.kind == K_TURRET {
        size = 1.6;
    } elif e.kind == K_SEEKER or e.kind == K_PRISM or e.kind == K_WEAVER {
        size = 2.4;
    } elif e.kind == K_MISSILE {
        size = 0.6;
    }
    explosion(g, e.x, e.y, e.z, size, palette);
    if e.score > 0 {
        gained = add_score(g, e.score);
        g.kills += 1;
        label = "+" + str(gained);
        if g.combo > 1 {
            label = label + "  x" + str(g.combo);
        }
        popup(g, label, e.x, e.y + e.radius * 0.6, e.z, gained >= 1000);
    }
    if e.drop >= 0 {
        spawn_pickup(g, e.drop, e.x, e.y, e.z);
    }
    if e.group >= 0 and g.group_left[e.group] > 0 {
        g.group_left[e.group] -= 1;
        if g.group_left[e.group] == 0 {
            r = random.random();
            if r < 0.45 {
                spawn_pickup(g, U_SHIELD, e.x, e.y, e.z);
            } elif r < 0.6 {
                spawn_pickup(g, U_BOMB, e.x, e.y, e.z);
            }
        }
    }
}

"""Prism armour is closed (state 0) except while open (state 2)."""
def armoured(e: Enemy) -> bool {
    return e.shielded or (e.kind == K_PRISM and e.state != 2);
}

"""Damage an enemy; returns True when it dies. Without `pierce`, Weaver
shields and closed Prism armour turn the hit away."""
def damage_enemy(g: Game, e: Enemy, dmg: float, pierce: bool) -> bool {
    if e.invuln or not e.alive or e.delay > 0.0 {
        return False;
    }
    if not pierce and armoured(e) {
        burst(g, e.x, e.y, e.z + e.radius * 0.5, 4, 6.0, 0.18, 3);
        play_pitch(g.audio, S_UI_MOVE, rnd(1.6, 2.0));
        return False;
    }
    e.hp -= dmg;
    e.flash = 1.0;
    if e.hp <= 0.0 {
        kill_enemy(g, e);
        return True;
    }
    play_pitch(g.audio, S_HIT, rnd(0.9, 1.2));
    return False;
}

"""Queue the radio lines bound to a named story event."""
def trigger(g: Game, name: str) {
    for ln in g.lines {
        if not ln.done and ln.ev == name {
            ln.done = True;
            g.queue.append(ln);
        }
    }
}

def collect(g: Game, u: Pickup) {
    u.alive = False;
    p = g.player;
    play(g.audio, S_PICKUP);
    burst(g, u.x, u.y, u.z, 18, 5.0, 0.25, 3);
    bonus = int(250.0 * p.pickup_bonus);
    g.score += bonus;
    popup(g, "+" + str(bonus), u.x, u.y + 1.0, u.z, False);
    if u.kind == U_SHIELD {
        p.shield = min(p.max_shield, p.shield + 30.0);
    } elif u.kind == U_CANNON {
        p.weapon = min(2, p.weapon + 1);
        trigger(g, "got_cannon");
    } else {
        p.bombs = min(p.max_bombs, p.bombs + 1);
    }
}

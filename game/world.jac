"""The five chapters as data: environment, radio script, event timeline, and
streamed scenery. See docs/STORY.md for the narrative these encode."""

import math;
import random;
import from state {
    Game, Event, Line, Prop, CHUNK, E_WAVE, E_ENEMY, E_PICKUP, E_BOSS, E_FLAG,
    K_MOTE, K_LANCE, K_WARDEN, K_TURRET, K_MINE, K_CACHE, K_ICE, P_STREAM, P_V,
    P_RING, P_SWARM, P_FLANK, P_HOVER, P_LANTERN, P_DIVE, U_SHIELD, U_CANNON,
    U_BOMB, B_VAULT, B_CARRIER, B_CONDUCTOR, W_WREN, W_SATO, W_HALO, W_LIND, W_LOG
}
import from gfx {
    Env, M_SKY_TARSIS, M_SKY_SHOAL, M_SKY_HESPER, M_SKY_REACH, M_SKY_APERTURE,
    M_SKY_EPILOGUE, M_ROCK_A, M_ROCK_B, M_ROCK_C, M_ICE_A, M_ICE_B, M_ICE_C,
    M_DEBRIS_PLATE, M_DEBRIS_GIRDER, M_GANTRY, M_TRENCH_WALL, M_TRENCH_FLOOR,
    M_GIRDER, M_TURRET
}
import from spawn { rnd, chance, spawn_fixed }

glob CHAPTER_NAMES: list[str] = ["", "LAST LIGHT", "THE SHOAL", "RELAY SILENCE", "CHOIR'S WAKE", "THE APERTURE"];
glob CHAPTER_PLACES: list[str] = ["", "Tarsis orbit", "Mareth's ice ring", "Hesper Relay", "The Violet Reach", "The system's edge"];
glob CHAPTER_LENGTHS: list[float] = [0.0, 3600.0, 4000.0, 4000.0, 4200.0, 3000.0];
glob SPEAKERS: list[str] = ["WREN", "CAPT. SATO", "HALO", "DR. LIND", "HESPER LOG"];

"""Lighting per chapter; 0 is the title screen and 6 the epilogue."""
def chapter_env(ch: int) -> Env {
    if ch == 1 {
        return Env(sky=M_SKY_TARSIS, lx=-0.45, ly=-0.75, lz=0.35, lr=1.0, lg=0.78, lb=0.55, ar=0.30, ag=0.24, ab=0.24, fr=0.16, fg=0.08, fb=0.06, fog_near=90.0, fog_far=330.0);
    } elif ch == 2 {
        return Env(sky=M_SKY_SHOAL, lx=0.4, ly=-0.75, lz=0.3, lr=0.95, lg=0.95, lb=0.9, ar=0.22, ag=0.30, ab=0.36, fr=0.04, fg=0.10, fb=0.14, fog_near=80.0, fog_far=300.0);
    } elif ch == 3 {
        return Env(sky=M_SKY_HESPER, lx=-0.4, ly=-0.85, lz=-0.3, lr=0.95, lg=0.85, lb=0.75, ar=0.22, ag=0.24, ab=0.32, fr=0.04, fg=0.05, fb=0.09, fog_near=80.0, fog_far=300.0);
    } elif ch == 4 {
        return Env(sky=M_SKY_REACH, lx=-0.2, ly=-0.8, lz=-0.4, lr=0.85, lg=0.6, lb=1.0, ar=0.28, ag=0.18, ab=0.32, fr=0.15, fg=0.05, fb=0.20, fog_near=60.0, fog_far=240.0);
    } elif ch == 5 {
        return Env(sky=M_SKY_APERTURE, lx=0.3, ly=-0.5, lz=-0.8, lr=1.0, lg=0.8, lb=0.6, ar=0.2, ag=0.2, ab=0.28, fr=0.02, fg=0.02, fb=0.05, fog_near=110.0, fog_far=380.0);
    } elif ch == 6 {
        return Env(sky=M_SKY_EPILOGUE, lx=0.5, ly=-0.6, lz=-0.6, lr=0.8, lg=0.9, lb=1.0, ar=0.3, ag=0.34, ab=0.42, fr=0.06, fg=0.12, fb=0.22, fog_near=200.0, fog_far=800.0);
    }
    return Env(sky=M_SKY_TARSIS, lx=-0.45, ly=-0.65, lz=-0.6, lr=1.0, lg=0.82, lb=0.62, ar=0.3, ag=0.26, ab=0.26, fr=0.16, fg=0.08, fb=0.06, fog_near=200.0, fog_far=800.0);
}

# ------------------------------------------------------------------ script helpers

def wave(g: Game, at: float, kind: int, pat: int, n: int, x: float, y: float) {
    g.events.append(Event(at=at, kind=E_WAVE, i=kind, a=float(pat), b=float(n), c=x, d=y));
}

def hold_wave(g: Game, at: float, kind: int, pat: int, n: int, x: float, y: float) {
    g.events.append(Event(at=at, kind=E_WAVE, i=kind, a=float(pat), b=float(n), c=x, d=y, s="hold"));
}

def enemy(g: Game, at: float, kind: int, x: float, y: float, ahead: float) {
    g.events.append(Event(at=at, kind=E_ENEMY, i=kind, a=ahead, c=x, d=y));
}

def pickup(g: Game, at: float, kind: int, x: float, y: float) {
    g.events.append(Event(at=at, kind=E_PICKUP, i=kind, c=x, d=y));
}

def boss(g: Game, at: float, kind: int) {
    g.events.append(Event(at=at, kind=E_BOSS, i=kind));
}

def flag(g: Game, at: float, name: str) {
    g.events.append(Event(at=at, kind=E_FLAG, s=name));
}

def say(g: Game, at: float, who: int, text: str) {
    g.lines.append(Line(at=at, who=who, text=text));
}

def say_on(g: Game, ev: str, who: int, text: str) {
    g.lines.append(Line(at=-1.0, who=who, text=text, ev=ev));
}

# ------------------------------------------------------------------ chapters

def build_chapter(g: Game, ch: int) {
    g.events = [];
    g.lines = [];
    if ch == 1 {
        chapter_1(g);
    } elif ch == 2 {
        chapter_2(g);
    } elif ch == 3 {
        chapter_3(g);
    } elif ch == 4 {
        chapter_4(g);
    } else {
        chapter_5(g);
    }
}

def chapter_1(g: Game) {
    say(g, 0.0, W_SATO, "Lantern is clear of the dock clamps. All Guard flights, form on the ark.");
    say(g, 0.02, W_HALO, "Ember, you're on my wing. Just like the ore runs. Stay close.");
    say(g, 0.045, W_WREN, "Steer with WASD or the arrow keys. Hold SPACE to fire.");
    say(g, 0.12, W_WREN, "Contacts. Choir Motes. Individually weak. Collectively, not.");
    say(g, 0.21, W_WREN, "Tap Q or E to roll. Rolling deflects incoming fire.");
    say(g, 0.28, W_WREN, "SHIFT boosts. B drops a bomb when things get crowded.");
    say(g, 0.34, W_HALO, "They're going for the gantries. I'll hold the dock. You stay on the Lantern.");
    say(g, 0.38, W_WREN, "Halo is breaking formation.");
    say(g, 0.50, W_HALO, "Ember, whatever happens, you get them to that ga-");
    say(g, 0.53, W_WREN, "... Halo's transponder is offline. I am sorry.");
    say(g, 0.59, W_WREN, "Silver rings restore shields. Fly through them.");
    say(g, 0.81, W_SATO, "Two heavy signatures closing. Wardens. Keep them off my hull.");
    say(g, 0.95, W_SATO, "We're clear of orbit. Good flying, Ember. Halo would have said so.");

    flag(g, 0.0, "halo_on");
    flag(g, 0.0, "lantern_side");
    wave(g, 0.06, K_MOTE, P_STREAM, 5, 5.0, 2.0);
    wave(g, 0.10, K_MOTE, P_STREAM, 5, -5.0, -1.0);
    wave(g, 0.14, K_MOTE, P_V, 5, 0.0, 1.0);
    wave(g, 0.18, K_MOTE, P_STREAM, 6, 4.0, -2.0);
    wave(g, 0.22, K_MOTE, P_RING, 6, 0.0, 0.0);
    wave(g, 0.26, K_MOTE, P_DIVE, 5, 6.0, 0.0);
    wave(g, 0.30, K_MOTE, P_V, 7, 0.0, -1.0);
    flag(g, 0.34, "halo_leave");
    wave(g, 0.37, K_MOTE, P_SWARM, 8, 0.0, 0.0);
    wave(g, 0.41, K_MOTE, P_STREAM, 6, -5.0, 2.0);
    wave(g, 0.42, K_MOTE, P_STREAM, 6, 5.0, -2.0);
    enemy(g, 0.44, K_MINE, -4.0, 1.0, 200.0);
    enemy(g, 0.445, K_MINE, 3.0, -2.0, 200.0);
    enemy(g, 0.45, K_MINE, 6.0, 3.0, 200.0);
    wave(g, 0.47, K_MOTE, P_RING, 8, 0.0, 1.0);
    flag(g, 0.50, "halo_lost");
    wave(g, 0.54, K_MOTE, P_V, 7, 0.0, 0.0);
    pickup(g, 0.58, U_SHIELD, 0.0, 0.0);
    wave(g, 0.60, K_MOTE, P_SWARM, 10, 0.0, 0.0);
    wave(g, 0.64, K_MOTE, P_DIVE, 6, -6.0, 0.0);
    wave(g, 0.67, K_MOTE, P_STREAM, 6, 5.0, 1.0);
    wave(g, 0.68, K_MOTE, P_STREAM, 6, -5.0, -1.0);
    pickup(g, 0.70, U_BOMB, 3.0, 1.0);
    wave(g, 0.72, K_MOTE, P_RING, 8, -3.0, 0.0);
    wave(g, 0.76, K_MOTE, P_SWARM, 12, 0.0, 0.0);
    hold_wave(g, 0.82, K_WARDEN, P_HOVER, 1, -5.0, 1.0);
    hold_wave(g, 0.82, K_WARDEN, P_HOVER, 1, 5.0, -1.0);
    wave(g, 0.84, K_MOTE, P_STREAM, 5, 0.0, 3.0);
    flag(g, 0.9, "lantern_away");
}

def chapter_2(g: Game) {
    say(g, 0.0, W_SATO, "Mareth's ring scatters their song. We go the long way, through the Shoal.");
    say(g, 0.04, W_WREN, "Ice density is high. Recommend not hitting it.");
    say(g, 0.18, W_WREN, "Lances. Fast. They attack from the flanks.");
    say(g, 0.38, W_WREN, "Guard supply beacon ahead. Someone left us a present.");
    say_on(g, "got_cannon", W_WREN, "Twin cannons online. I feel much better about this.");
    say(g, 0.70, W_SATO, "Ember, you're flying lead now. Act like it.");
    say(g, 0.85, W_WREN, "Wardens moving to intercept the exit.");
    say(g, 0.96, W_SATO, "Lantern is through the Shoal. Next stop: Hesper.");

    wave(g, 0.06, K_MOTE, P_STREAM, 6, 4.0, 2.0);
    wave(g, 0.10, K_MOTE, P_V, 7, 0.0, 0.0);
    wave(g, 0.14, K_MOTE, P_STREAM, 6, -4.0, -2.0);
    wave(g, 0.19, K_LANCE, P_FLANK, 3, -1.0, 0.0);
    wave(g, 0.23, K_LANCE, P_FLANK, 3, 1.0, 1.0);
    wave(g, 0.27, K_MOTE, P_SWARM, 10, 0.0, 0.0);
    wave(g, 0.31, K_MOTE, P_RING, 8, 0.0, 0.0);
    wave(g, 0.34, K_LANCE, P_FLANK, 2, -1.0, 2.0);
    wave(g, 0.345, K_LANCE, P_FLANK, 2, 1.0, -2.0);
    enemy(g, 0.40, K_CACHE, 0.0, 0.0, 170.0);
    flag(g, 0.47, "cache_check");
    wave(g, 0.47, K_MOTE, P_DIVE, 6, -6.0, 1.0);
    wave(g, 0.50, K_LANCE, P_FLANK, 4, 1.0, 0.0);
    enemy(g, 0.55, K_MINE, -5.0, 2.0, 200.0);
    enemy(g, 0.552, K_MINE, 0.0, -3.0, 200.0);
    enemy(g, 0.554, K_MINE, 5.0, 1.0, 200.0);
    enemy(g, 0.556, K_MINE, -2.0, 4.0, 200.0);
    wave(g, 0.58, K_MOTE, P_STREAM, 7, 0.0, 3.0);
    wave(g, 0.62, K_MOTE, P_V, 7, 0.0, -2.0);
    pickup(g, 0.64, U_SHIELD, 0.0, 0.0);
    wave(g, 0.68, K_LANCE, P_FLANK, 3, -1.0, 0.0);
    wave(g, 0.69, K_LANCE, P_FLANK, 3, 1.0, 0.0);
    wave(g, 0.72, K_MOTE, P_SWARM, 14, 0.0, 0.0);
    wave(g, 0.76, K_MOTE, P_RING, 10, 0.0, 0.0);
    pickup(g, 0.78, U_BOMB, -3.0, 0.0);
    wave(g, 0.80, K_LANCE, P_FLANK, 4, -1.0, 1.0);
    hold_wave(g, 0.86, K_WARDEN, P_HOVER, 1, -6.0, 1.0);
    hold_wave(g, 0.86, K_WARDEN, P_HOVER, 1, 6.0, -1.0);
    wave(g, 0.87, K_LANCE, P_FLANK, 3, 1.0, 0.0);
}

def chapter_3(g: Game) {
    say(g, 0.0, W_LIND, "The command keys are in Hesper's core. I need forty seconds on its data spine.");
    say(g, 0.04, W_WREN, "The station is infested. Turrets are now Choir property.");
    say(g, 0.11, W_WREN, "Girders in the trench. Fly over or under. Not through.");
    say(g, 0.53, W_LIND, "The vault has a shield lattice. Four emitters. Break them.");
    say_on(g, "boss_dead", W_LIND, "Lattice down! Pulling the keys now...");
    say(g, 0.60, W_LIND, "There's a log here. \"The gate is not broken. We closed it.\"");
    say(g, 0.63, W_LOG, "\"They are on the other side. They are listening.\"");
    say(g, 0.68, W_SATO, "Lind, Ember. Get out of there. Now.");

    flag(g, 0.03, "trench_on");
    wave(g, 0.12, K_MOTE, P_STREAM, 5, 0.0, 2.0);
    wave(g, 0.18, K_MOTE, P_V, 5, 0.0, 0.0);
    wave(g, 0.24, K_LANCE, P_FLANK, 2, -1.0, 0.0);
    wave(g, 0.30, K_MOTE, P_STREAM, 6, -3.0, 3.0);
    pickup(g, 0.33, U_SHIELD, 0.0, 1.0);
    wave(g, 0.36, K_MOTE, P_RING, 6, 0.0, 1.0);
    wave(g, 0.42, K_LANCE, P_FLANK, 3, 1.0, 2.0);
    wave(g, 0.46, K_MOTE, P_SWARM, 8, 0.0, 0.0);
    flag(g, 0.43, "trench_off");
    pickup(g, 0.50, U_BOMB, 0.0, 0.0);
    boss(g, 0.55, B_VAULT);
    flag(g, 0.62, "trench_on");
    pickup(g, 0.64, U_SHIELD, 0.0, 0.0);
    wave(g, 0.72, K_LANCE, P_FLANK, 3, -1.0, 1.0);
    wave(g, 0.78, K_LANCE, P_FLANK, 3, 1.0, -1.0);
    wave(g, 0.84, K_MOTE, P_SWARM, 10, 0.0, 0.0);
    flag(g, 0.88, "trench_off");
}

def chapter_4(g: Game) {
    say(g, 0.0, W_SATO, "The Violet Reach. Shortest path to the gate. Stay tight.");
    say(g, 0.06, W_WREN, "Spectrograph: iron, carbon, stellar ash. Ember... this nebula used to be a star.");
    say(g, 0.13, W_SATO, "That's what they'll do to Vesper.");
    say(g, 0.27, W_WREN, "Carrier signature. It is launching at the Lantern, not at us.");
    say(g, 0.29, W_SATO, "Hull plating won't take much of that. Keep them off us!");
    say_on(g, "pods_down", W_WREN, "Pods down. The core is open.");
    say_on(g, "boss_dead", W_SATO, "Carrier down! Lantern is still flying. Barely.");
    say(g, 0.93, W_SATO, "Gate in sight. Lind, wake it up.");

    flag(g, 0.0, "escort_on");
    wave(g, 0.05, K_MOTE, P_STREAM, 6, 3.0, 1.0);
    wave(g, 0.09, K_MOTE, P_LANTERN, 6, 0.0, 0.0);
    wave(g, 0.13, K_MOTE, P_V, 7, 0.0, 0.0);
    pickup(g, 0.15, U_SHIELD, 0.0, 0.0);
    wave(g, 0.17, K_LANCE, P_FLANK, 3, -1.0, 0.0);
    wave(g, 0.20, K_MOTE, P_LANTERN, 8, 0.0, 0.0);
    wave(g, 0.24, K_MOTE, P_SWARM, 10, 0.0, 0.0);
    pickup(g, 0.28, U_BOMB, 0.0, 0.0);
    boss(g, 0.30, B_CARRIER);
    wave(g, 0.82, K_MOTE, P_STREAM, 6, -3.0, 1.0);
    pickup(g, 0.84, U_SHIELD, 0.0, 0.0);
    wave(g, 0.86, K_LANCE, P_FLANK, 3, 1.0, 0.0);
    wave(g, 0.90, K_MOTE, P_LANTERN, 6, 0.0, 0.0);
}

def chapter_5(g: Game) {
    say(g, 0.0, W_LIND, "Keys accepted. The Aperture is spinning up.");
    say(g, 0.05, W_WREN, "Ember. Something is coming through from the other side.");
    say(g, 0.08, W_SATO, "...The Conductor.");
    say(g, 0.10, W_LIND, "Its resonance holds the gate open. Break its core while the gate is lit, and the gate collapses behind us. Forever.");
    say_on(g, "boss_intro", W_WREN, "Resonator nodes on the outer ring. Four. I will count them for you.");
    say_on(g, "nodes_3", W_WREN, "Three.");
    say_on(g, "nodes_2", W_WREN, "Two.");
    say_on(g, "nodes_1", W_WREN, "One.");
    say_on(g, "core_exposed", W_WREN, "Core exposed.");
    say_on(g, "boss_phase3", W_LIND, "The gate is folding! Lantern, jump NOW!");
    say_on(g, "boss_dead", W_SATO, "Lantern is through. Ember, come home.");
    say(g, 0.30, W_WREN, "Choir remnants pursuing. They are... angry. Is that a thing they can be?");
    say(g, 0.55, W_LIND, "Gate stability at forty percent. Thirty. Ember, it's now or never!");
    say(g, 0.78, W_SATO, "We're holding the aperture open for you. Ten seconds.");
    say(g, 0.93, W_WREN, "Full burn. Do not look back. (I am looking back. It is very large.)");

    flag(g, 0.0, "lantern_ahead");
    wave(g, 0.03, K_MOTE, P_STREAM, 6, 0.0, 2.0);
    wave(g, 0.06, K_LANCE, P_FLANK, 3, -1.0, 0.0);
    wave(g, 0.08, K_MOTE, P_V, 7, 0.0, 0.0);
    pickup(g, 0.11, U_SHIELD, 0.0, 0.0);
    boss(g, 0.12, B_CONDUCTOR);
    wave(g, 0.28, K_LANCE, P_FLANK, 3, -1.0, 1.0);
    wave(g, 0.33, K_LANCE, P_FLANK, 3, 1.0, -1.0);
    wave(g, 0.40, K_MOTE, P_SWARM, 12, 0.0, 0.0);
    enemy(g, 0.46, K_MINE, -4.0, 2.0, 220.0);
    enemy(g, 0.465, K_MINE, 4.0, -2.0, 220.0);
    enemy(g, 0.47, K_MINE, 0.0, 3.0, 220.0);
    wave(g, 0.52, K_LANCE, P_FLANK, 4, -1.0, 0.0);
    wave(g, 0.60, K_MOTE, P_RING, 10, 0.0, 0.0);
    pickup(g, 0.64, U_SHIELD, 0.0, 0.0);
    wave(g, 0.68, K_LANCE, P_FLANK, 4, 1.0, 0.0);
    wave(g, 0.74, K_MOTE, P_SWARM, 14, 0.0, 0.0);
    wave(g, 0.82, K_LANCE, P_FLANK, 3, -1.0, 2.0);
    wave(g, 0.83, K_LANCE, P_FLANK, 3, 1.0, -2.0);
}

# ------------------------------------------------------------------ scenery

def prop(g: Game, model: int, x: float, y: float, z: float, scale: float, solid: bool) -> Prop {
    p = Prop(model=model, x=x, y=y, z=z, scale=scale, solid=solid);
    p.radius = g.gfx.radius[model] * scale * 0.72;
    p.yaw = rnd(0.0, 6.28);
    p.pitch = rnd(0.0, 6.28);
    p.roll = rnd(0.0, 6.28);
    g.props.append(p);
    return p;
}

def spinning(p: Prop, amount: float) {
    p.spin_yaw = rnd(-amount, amount);
    p.spin_pitch = rnd(-amount, amount);
}

"""A point well outside the flight box (|x| > 13 or |y| > 8)."""
def outside(spread: float) -> list[float] {
    if chance(0.5) {
        side = 1.0 if chance(0.5) else -1.0;
        return [side * rnd(14.0, spread), rnd(-spread * 0.6, spread * 0.6)];
    }
    side = 1.0 if chance(0.5) else -1.0;
    return [rnd(-spread, spread), side * rnd(9.0, spread * 0.6)];
}

def rock_model() -> int {
    r = random.random();
    if r < 0.33 {
        return M_ROCK_A;
    }
    return M_ROCK_B if r < 0.66 else M_ROCK_C;
}

def ice_model() -> int {
    r = random.random();
    if r < 0.4 {
        return M_ICE_A;
    }
    return M_ICE_B if r < 0.75 else M_ICE_C;
}

"""Populate scenery chunk `idx` (world z from -idx*CHUNK down to -(idx+1)*CHUNK)."""
def gen_chunk(g: Game, idx: int) {
    z0 = -float(idx) * CHUNK;
    ch = g.chapter;
    if ch == 1 {
        if idx >= 1 and idx <= 9 and idx % 3 == 1 {
            p = prop(g, M_GANTRY, 0.0, -1.0, z0 - 20.0, 1.0, False);
            p.yaw = 0.0;
            p.pitch = 0.0;
            p.roll = 0.0;
        }
        for k in range(5 if idx < 12 else 3) {
            o = outside(60.0);
            p = prop(g, M_DEBRIS_PLATE if chance(0.6) else M_DEBRIS_GIRDER, o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(1.0, 2.5), False);
            spinning(p, 0.6);
        }
        if idx > 4 and chance(0.35) {
            p = prop(g, M_DEBRIS_PLATE, rnd(-7.0, 7.0), rnd(-4.0, 4.0), z0 - rnd(0.0, CHUNK), rnd(0.8, 1.1), True);
            spinning(p, 0.8);
        }
        for k in range(2) {
            o = outside(90.0);
            p = prop(g, rock_model(), o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(2.0, 6.0), False);
            spinning(p, 0.2);
        }
    } elif ch == 2 {
        for k in range(6) {
            o = outside(70.0);
            p = prop(g, ice_model(), o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(4.0, 11.0), False);
            spinning(p, 0.15);
        }
        for k in range(2) {
            o = outside(160.0);
            p = prop(g, ice_model(), o[0] * 1.4, o[1], z0 - rnd(0.0, CHUNK), rnd(12.0, 26.0), False);
            spinning(p, 0.05);
        }
        if idx > 3 and chance(0.55) {
            p = prop(g, ice_model(), rnd(-8.0, 8.0), rnd(-4.5, 4.5), z0 - rnd(0.0, CHUNK), rnd(2.2, 3.6), True);
            spinning(p, 0.3);
        }
        if idx > 3 {
            for k in range(2) {
                if chance(0.6) {
                    e = spawn_fixed(g, K_ICE, rnd(-8.0, 8.0), rnd(-4.5, 4.5), 0.0);
                    e.z = z0 - rnd(0.0, CHUNK);
                }
            }
        }
    } elif ch == 3 {
        if g.trench {
            pl = prop(g, M_TRENCH_WALL, 0.0, 0.0, z0 - 20.0, 1.0, False);
            pl.yaw = 0.0;
            pl.pitch = 0.0;
            pl.roll = 0.0;
            pr = prop(g, M_TRENCH_WALL, 0.0, 0.0, z0 - 20.0, 1.0, False);
            pr.yaw = 3.14159;
            pr.pitch = 0.0;
            pr.roll = 0.0;
            pf = prop(g, M_TRENCH_FLOOR, 0.0, 0.0, z0 - 20.0, 1.0, False);
            pf.yaw = 0.0;
            pf.pitch = 0.0;
            pf.roll = 0.0;
            if idx % 2 == 1 and idx > 2 {
                low = chance(0.5);
                gy = -3.4 if low else 3.4;
                for k in range(2) {
                    gp = prop(g, M_GIRDER, 0.0, gy + (0.8 if low else -0.8) * float(k), z0 - 20.0, 1.0, True);
                    gp.yaw = 0.0;
                    gp.pitch = 0.0;
                    gp.roll = 0.0;
                    gp.box = True;
                    gp.hx = 12.0;
                    gp.hy = 0.9;
                    gp.hz = 0.8;
                }
            }
            if idx > 2 {
                for k in range(2) {
                    if chance(0.55) {
                        side = 1.0 if chance(0.5) else -1.0;
                        e = spawn_fixed(g, K_TURRET, side * 11.0, rnd(-4.0, 7.0), 0.0);
                        e.z = z0 - rnd(4.0, CHUNK - 4.0);
                        e.roll = -1.5708 * side;
                    }
                }
                if chance(0.35) {
                    e = spawn_fixed(g, K_TURRET, rnd(-6.0, 6.0), -7.4, 0.0);
                    e.z = z0 - rnd(4.0, CHUNK - 4.0);
                }
            }
        } else {
            for k in range(4) {
                o = outside(80.0);
                p = prop(g, M_DEBRIS_GIRDER if chance(0.5) else M_DEBRIS_PLATE, o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(2.0, 5.0), False);
                spinning(p, 0.3);
            }
            if chance(0.5) {
                o = outside(120.0);
                p = prop(g, rock_model(), o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(6.0, 14.0), False);
                spinning(p, 0.1);
            }
        }
    } elif ch == 4 {
        for k in range(4) {
            o = outside(70.0);
            p = prop(g, rock_model(), o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(3.0, 9.0), False);
            spinning(p, 0.2);
        }
        if idx > 3 and chance(0.4) {
            p = prop(g, rock_model(), rnd(-8.0, 8.0), rnd(-4.0, 4.0), z0 - rnd(0.0, CHUNK), rnd(1.6, 2.6), True);
            spinning(p, 0.4);
        }
    } else {
        for k in range(2) {
            o = outside(90.0);
            p = prop(g, rock_model() if chance(0.6) else M_DEBRIS_PLATE, o[0], o[1], z0 - rnd(0.0, CHUNK), rnd(2.0, 7.0), False);
            spinning(p, 0.2);
        }
    }
}

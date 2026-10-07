"""Shared game state: entity types, the Game aggregate and constants.

World axes: forward is -Z, +Y up, +X right. The player rides the rail at
z = -scroll; "ahead" distances are pz - z.
"""

import from gfx { Gfx, Env }
import from audio { Audio }

# game states
glob ST_TITLE: int = 0,
     ST_PROLOGUE: int = 1,
     ST_BRIEFING: int = 2,
     ST_PLAY: int = 3,
     ST_PAUSE: int = 4,
     ST_DEAD: int = 5,
     ST_COMPLETE: int = 6,
     ST_ENDING: int = 7,
     ST_CONTROLS: int = 8,
     ST_SELECT: int = 9,
     ST_REFIT: int = 10,
     ST_DIFFICULTY: int = 11;

# enemy kinds
glob K_MOTE: int = 0,
     K_LANCE: int = 1,
     K_WARDEN: int = 2,
     K_TURRET: int = 3,
     K_MINE: int = 4,
     K_EMITTER: int = 5,
     K_POD: int = 6,
     K_CORE: int = 7,
     K_BODY: int = 8,
     K_NODE: int = 9,
     K_CACHE: int = 10,
     K_ICE: int = 11,
     K_SEEKER: int = 12,
     K_MISSILE: int = 13,
     K_PRISM: int = 14,
     K_WEAVER: int = 15;

# movement patterns
glob P_STREAM: int = 0,
     P_V: int = 1,
     P_RING: int = 2,
     P_SWARM: int = 3,
     P_FLANK: int = 4,
     P_HOVER: int = 5,
     P_FIXED: int = 6,
     P_LANTERN: int = 7,
     P_DIVE: int = 8,
     P_PART: int = 9,
     P_HOMING: int = 10;

# pickups
glob U_SHIELD: int = 0,
     U_CANNON: int = 1,
     U_BOMB: int = 2;

# bosses
glob B_NONE: int = 0,
     B_VAULT: int = 1,
     B_CARRIER: int = 2,
     B_CONDUCTOR: int = 3;

# radio speakers
glob W_WREN: int = 0,
     W_SATO: int = 1,
     W_HALO: int = 2,
     W_LIND: int = 3,
     W_LOG: int = 4;

# event kinds
glob E_WAVE: int = 0,
     E_ENEMY: int = 1,
     E_PICKUP: int = 2,
     E_BOSS: int = 3,
     E_FLAG: int = 4;

glob CHUNK: float = 40.0;

# Refit upgrades offered between chapters (see logic.apply_upgrades).
glob UPGRADE_NAMES: list[str] = [
    "REINFORCED PLATING", "CAPACITOR BANK", "ORDNANCE RACK", "AFTERBURNER COILS",
    "DEFLECTOR TUNING", "TWIN-LINKED CANNONS", "SALVAGE MAGNET", "EMBER CORE"
];
glob UPGRADE_TEXT: list[str] = [
    "Shield capacity +25.",
    "Charged shots build 40% faster.",
    "Carry two more bombs and start each chapter with one extra.",
    "Boost and brake drain 35% slower and refill 60% faster.",
    "Rolls recharge 40% faster and deflect for longer.",
    "Cannons start one level higher in every chapter.",
    "Pickups home in from twice as far and score 50% more.",
    "Combos last a second longer and climb to x10."
];

glob DIFFICULTY_NAMES: list[str] = ["RECRUIT", "GUARD", "ACE"];
glob DIFFICULTY_TEXT: list[str] = [
    "Gentler fire and lighter hits. For learning the routes.",
    "The intended balance.",
    "Faster, denser fire and harder hits."
];

# Chapter score (points earned in that chapter) that wins its medal.
glob MEDAL_SCORE: list[int] = [0, 35000, 60000, 80000, 40000, 80000];

obj Player {
    has x: float = 0.0,
        y: float = 0.0,
        vx: float = 0.0,
        vy: float = 0.0,
        shield: float = 100.0,
        bombs: int = 3,
        weapon: int = 0,
        boost: float = 100.0,
        boosting: bool = False,
        roll_t: float = 0.0,
        roll_dir: float = 1.0,
        roll_cd: float = 0.0,
        fire_cd: float = 0.0,
        invuln: float = 0.0,
        bank: float = 0.0,
        pitch: float = 0.0,
        alive: bool = True,
        dead_t: float = 0.0,
        trail_t: float = 0.0,
        charge: float = 0.0,
        was_firing: bool = False,
        braking: bool = False,
        max_shield: float = 100.0,
        max_bombs: int = 5,
        charge_time: float = 1.0,
        boost_drain: float = 40.0,
        boost_regen: float = 20.0,
        roll_cd_max: float = 0.8,
        roll_len: float = 0.5,
        magnet: float = 45.0,
        pickup_bonus: float = 1.0,
        combo_window: float = 2.0,
        combo_max: int = 8;
}

obj Enemy {
    has kind: int,
        model: int,
        x: float = 0.0,
        y: float = 0.0,
        z: float = 0.0,
        vx: float = 0.0,
        vy: float = 0.0,
        hp: float = 1.0,
        max_hp: float = 1.0,
        radius: float = 1.0,
        scale: float = 1.0,
        score: int = 100,
        t: float = 0.0,
        delay: float = 0.0,
        pat: int = 0,
        ox: float = 0.0,
        oy: float = 0.0,
        a: float = 0.0,
        b: float = 0.0,
        c: float = 0.0,
        dz: float = 60.0,
        fire_t: float = 2.0,
        state: int = 0,
        state_t: float = 0.0,
        yaw: float = 0.0,
        pitch: float = 0.0,
        roll: float = 0.0,
        spin: float = 0.0,
        flash: float = 0.0,
        alive: bool = True,
        invuln: bool = False,
        holds: bool = False,
        shoots: bool = False,
        group: int = -1,
        drop: int = -1,
        slot: int = 0,
        uid: int = 0,
        link: int = -1,
        shielded: bool = False,
        vz: float = 0.0;
}

obj Shot {
    has x: float,
        y: float,
        z: float,
        vx: float,
        vy: float,
        vz: float,
        life: float,
        dmg: float = 1.0,
        hostile: bool = False,
        charged: bool = False,
        target: int = -1,
        alive: bool = True;
}

"""Floating score text at a world position."""
obj Popup {
    has text: str,
        x: float,
        y: float,
        z: float,
        t: float = 0.0,
        big: bool = False,
        alive: bool = True;
}

"""A tumbling fragment from an explosion."""
obj Debris {
    has model: int,
        x: float,
        y: float,
        z: float,
        vx: float,
        vy: float,
        vz: float,
        yaw: float,
        pitch: float,
        roll: float,
        spin: float,
        life: float,
        max_life: float,
        scale: float,
        alive: bool = True;
}

"""An expanding shockwave ring."""
obj Ring {
    has x: float,
        y: float,
        z: float,
        size: float,
        dur: float,
        t: float = 0.0,
        alive: bool = True;
}

obj Particle {
    has x: float,
        y: float,
        z: float,
        vx: float,
        vy: float,
        vz: float,
        life: float,
        max_life: float,
        size: float,
        r: int,
        g: int,
        b: int,
        alive: bool = True;
}

obj Pickup {
    has kind: int,
        x: float,
        y: float,
        z: float,
        t: float = 0.0,
        alive: bool = True;
}

"""Streamed scenery. `box` props collide as an axis-aligned box (hx, hy, hz)."""
obj Prop {
    has model: int,
        x: float,
        y: float,
        z: float,
        yaw: float = 0.0,
        pitch: float = 0.0,
        roll: float = 0.0,
        spin_yaw: float = 0.0,
        spin_pitch: float = 0.0,
        scale: float = 1.0,
        radius: float = 0.0,
        solid: bool = False,
        box: bool = False,
        hx: float = 0.0,
        hy: float = 0.0,
        hz: float = 0.0,
        alive: bool = True;
}

obj Line {
    has at: float,
        who: int,
        text: str,
        ev: str = "",
        done: bool = False;
}

obj Event {
    has at: float,
        kind: int,
        i: int = 0,
        a: float = 0.0,
        b: float = 0.0,
        c: float = 0.0,
        d: float = 0.0,
        s: str = "",
        done: bool = False;
}

obj Boss {
    has kind: int = 0,
        name: str = "",
        phase: int = 0,
        t: float = 0.0,
        x: float = 0.0,
        y: float = 0.0,
        z: float = 0.0,
        ring_roll: float = 0.0,
        ring_dist: float = 0.0,
        launch_t: float = 3.0,
        attack_t: float = 2.0,
        dying: float = 0.0,
        count: int = 0,
        parts: list[Enemy] = [],
        core: list[Enemy] = [],
        body: list[Enemy] = [];
}

obj Game {
    has gfx: Gfx,
        audio: Audio,
        env: Env,
        state: int = 0,
        state_t: float = 0.0,
        menu: int = 0,
        chapter: int = 1,
        unlocked: int = 1,
        best: list[int] = [0, 0, 0, 0, 0, 0],
        score: int = 0,
        chapter_start_score: int = 0,
        combo: int = 0,
        combo_t: float = 0.0,
        kills: int = 0,
        fired: int = 0,
        hits: int = 0,
        damage: float = 0.0,
        player: Player = Player(),
        enemies: list[Enemy] = [],
        shots: list[Shot] = [],
        particles: list[Particle] = [],
        pickups: list[Pickup] = [],
        props: list[Prop] = [],
        events: list[Event] = [],
        lines: list[Line] = [],
        queue: list[Line] = [],
        radio_who: int = 0,
        radio_text: str = "",
        radio_t: float = 0.0,
        scroll: float = 0.0,
        dist: float = 0.0,
        length: float = 3600.0,
        speed: float = 28.0,
        pz: float = 0.0,
        hold: bool = False,
        chunk_next: int = 0,
        cam_x: float = 0.0,
        cam_y: float = 2.5,
        cam_z: float = 10.0,
        cam_roll: float = 0.0,
        shake: float = 0.0,
        hurt_fx: float = 0.0,
        white_fx: float = 0.0,
        boss: Boss = Boss(),
        boss_active: bool = False,
        escort: bool = False,
        lantern_hp: float = 100.0,
        lantern_x: float = -40.0,
        lantern_y: float = -12.0,
        lantern_dz: float = 40.0,
        halo: int = 0,
        halo_x: float = 6.0,
        halo_y: float = 1.5,
        halo_dz: float = -4.0,
        trench: bool = False,
        min_y: float = -5.0,
        max_y: float = 5.0,
        max_x: float = 9.0,
        group_next: int = 0,
        group_left: list[int] = [],
        alarm_t: float = 0.0,
        finish_t: float = 0.0,
        gate_t: float = 0.0,
        cache_done: bool = False,
        muted: bool = False,
        fail: str = "",
        popups: list[Popup] = [],
        debris: list[Debris] = [],
        rings: list[Ring] = [],
        uid_next: int = 1,
        lock_uid: int = -1,
        hit_t: float = 0.0,
        intro_t: float = 0.0,
        warn_t: float = 0.0,
        difficulty: int = 1,
        fire_rate: float = 1.0,
        orb_speed: float = 1.0,
        dmg_scale: float = 1.0,
        upgrades: list[int] = [],
        saved_upgrades: list[int] = [],
        refit_options: list[int] = [],
        cp_active: bool = False,
        cp_at: float = 0.0,
        cp_score: int = 0,
        cp_start_score: int = 0,
        cp_weapon: int = 0,
        cp_bombs: int = 0,
        cp_shield: float = 100.0,
        medals: list[int] = [0, 0, 0, 0, 0, 0],
        medal_new: bool = False,
        chapter_score: int = 0,
        prop_hits: int = 0,
        pin_y: float = 99.0,
        frame: int = 0,
        shot_mode: bool = False,
        demo: bool = False,
        demo_t: float = 0.0;
}

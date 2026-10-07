"""Model registry, lighting environment and draw helpers.

Models are addressed by the integer ids below (the order of MODEL_NAMES).
Every model except the skies gets the lit shader (assets/shaders/lit.*);
skies keep raylib's default shader, which multiplies their true-colour vertex
colours by the tint.
"""

import math;
import from rl {
    Vector3, Vector4, Matrix, Color, Model, Shader, BoundingBox,
    LoadModel, GetModelBoundingBox, DrawModel, LoadShader, IsShaderValid,
    GetShaderLocation, SetShaderValue, rlEnableDepthMask, rlDisableDepthMask,
    rlEnableBackfaceCulling, rlDisableBackfaceCulling
}

glob MODEL_NAMES: list[str] = [
    "kestrel", "kestrel_halo", "lantern", "mote", "lance", "warden", "turret",
    "mine", "emitter", "carrier", "carrier_pod", "conductor_core",
    "conductor_ring", "conductor_node", "core_orb", "shield_bubble", "rock_a",
    "rock_b", "rock_c", "ice_a", "ice_b", "ice_c", "debris_plate",
    "debris_girder", "dock_gantry", "trench_wall", "trench_floor", "girder",
    "vault_spine", "cache", "pickup_shield", "pickup_cannon", "pickup_bomb",
    "planet_tarsis", "planet_mareth", "sun", "sun_blue", "aperture",
    "aperture_field", "seeker", "missile", "prism_half", "weaver", "shard",
    "scrap", "ring_fx", "sky_tarsis", "sky_shoal", "sky_hesper", "sky_reach",
    "sky_aperture", "sky_epilogue"
];

glob M_KESTREL: int = 0,
     M_HALO: int = 1,
     M_LANTERN: int = 2,
     M_MOTE: int = 3,
     M_LANCE: int = 4,
     M_WARDEN: int = 5,
     M_TURRET: int = 6,
     M_MINE: int = 7,
     M_EMITTER: int = 8,
     M_CARRIER: int = 9,
     M_POD: int = 10,
     M_COND_CORE: int = 11,
     M_COND_RING: int = 12,
     M_COND_NODE: int = 13,
     M_CORE_ORB: int = 14,
     M_SHIELD: int = 15,
     M_ROCK_A: int = 16,
     M_ROCK_B: int = 17,
     M_ROCK_C: int = 18,
     M_ICE_A: int = 19,
     M_ICE_B: int = 20,
     M_ICE_C: int = 21,
     M_DEBRIS_PLATE: int = 22,
     M_DEBRIS_GIRDER: int = 23,
     M_GANTRY: int = 24,
     M_TRENCH_WALL: int = 25,
     M_TRENCH_FLOOR: int = 26,
     M_GIRDER: int = 27,
     M_VAULT: int = 28,
     M_CACHE: int = 29,
     M_PICK_SHIELD: int = 30,
     M_PICK_CANNON: int = 31,
     M_PICK_BOMB: int = 32,
     M_TARSIS: int = 33,
     M_MARETH: int = 34,
     M_SUN: int = 35,
     M_SUN_BLUE: int = 36,
     M_APERTURE: int = 37,
     M_APERTURE_FIELD: int = 38,
     M_SEEKER: int = 39,
     M_MISSILE: int = 40,
     M_PRISM_HALF: int = 41,
     M_WEAVER: int = 42,
     M_SHARD: int = 43,
     M_SCRAP: int = 44,
     M_RING_FX: int = 45,
     M_SKY_TARSIS: int = 46,
     M_SKY_SHOAL: int = 47,
     M_SKY_HESPER: int = 48,
     M_SKY_REACH: int = 49,
     M_SKY_APERTURE: int = 50,
     M_SKY_EPILOGUE: int = 51,
     FIRST_SKY: int = 46;

"""Lighting environment of a scene (all colours 0..1)."""
obj Env {
    has sky: int,
        lx: float, ly: float, lz: float,
        lr: float, lg: float, lb: float,
        ar: float, ag: float, ab: float,
        fr: float, fg: float, fb: float,
        fog_near: float, fog_far: float;
}

obj Gfx {
    has models: list[Model],
        radius: list[float],
        lit: Shader,
        loc_light: int = -1,
        loc_light_color: int = -1,
        loc_ambient: int = -1,
        loc_fog_color: int = -1,
        loc_fog: int = -1,
        loc_view: int = -1,
        loc_flash: int = -1,
        fog_near: float = 60.0,
        fog_far: float = 300.0,
        flash_on: bool = False;
}

def vec3(x: float, y: float, z: float) -> Vector3 {
    return Vector3(x=f32(x), y=f32(y), z=f32(z));
}

def rgba(r: int, g: int, b: int, a: int) -> Color {
    return Color(r=u8(r), g=u8(g), b=u8(b), a=u8(a));
}

def clamp(v: float, lo: float, hi: float) -> float {
    if v < lo {
        return lo;
    }
    if v > hi {
        return hi;
    }
    return v;
}

def lerp(a: float, b: float, t: float) -> float {
    return a + (b - a) * t;
}

"""Model matrix: uniform scale s, rotation Ry(yaw) Rx(pitch) Rz(roll), then translation."""
def trs(
    tx: float, ty: float, tz: float, yaw: float, pitch: float, roll: float, s: float
) -> Matrix {
    cy = math.cos(yaw);
    sy = math.sin(yaw);
    cp = math.cos(pitch);
    sp = math.sin(pitch);
    cr = math.cos(roll);
    sr = math.sin(roll);
    return Matrix(
        m0=f32((cy * cr + sy * sp * sr) * s), m4=f32((-cy * sr + sy * sp * cr) * s), m8=f32(sy * cp * s), m12=f32(tx),
        m1=f32(cp * sr * s), m5=f32(cp * cr * s), m9=f32(-sp * s), m13=f32(ty),
        m2=f32((-sy * cr + cy * sp * sr) * s), m6=f32((sy * sr + cy * sp * cr) * s), m10=f32(cy * cp * s), m14=f32(tz),
        m3=f32(0.0), m7=f32(0.0), m11=f32(0.0), m15=f32(1.0)
    );
}

def set_uniform(g: Gfx, loc: int, x: float, y: float, z: float, w: float) {
    v = Vector4(x=f32(x), y=f32(y), z=f32(z), w=f32(w));
    SetShaderValue(g.lit, i32(loc), &v, i32(3));
}

def gfx_load(base: str) -> Gfx {
    sh = LoadShader(base + "/shaders/lit.vs", base + "/shaders/lit.fs");
    g = Gfx(models=[], radius=[], lit=sh);
    g.loc_light = int(GetShaderLocation(sh, "lightDir"));
    g.loc_light_color = int(GetShaderLocation(sh, "lightColor"));
    g.loc_ambient = int(GetShaderLocation(sh, "ambient"));
    g.loc_fog_color = int(GetShaderLocation(sh, "fogColor"));
    g.loc_fog = int(GetShaderLocation(sh, "fogParams"));
    g.loc_view = int(GetShaderLocation(sh, "viewPos"));
    g.loc_flash = int(GetShaderLocation(sh, "flash"));
    for i in range(len(MODEL_NAMES)) {
        m = LoadModel(base + "/models/" + MODEL_NAMES[i] + ".glb");
        if i < FIRST_SKY {
            mats = m.materials.view(int(m.materialCount));
            for k in range(len(mats)) {
                mats[k].shader = sh;
            }
        }
        box = GetModelBoundingBox(m);
        hx = float(box.max.x - box.min.x);
        hy = float(box.max.y - box.min.y);
        hz = float(box.max.z - box.min.z);
        g.models.append(m);
        g.radius.append(0.5 * max(hx, max(hy, hz)));
    }
    set_uniform(g, g.loc_flash, 1.0, 1.0, 1.0, 0.0);
    return g;
}

def shader_ok(g: Gfx) -> bool {
    return IsShaderValid(g.lit);
}

def apply_env(g: Gfx, e: Env) {
    n = math.sqrt(e.lx * e.lx + e.ly * e.ly + e.lz * e.lz);
    set_uniform(g, g.loc_light, e.lx / n, e.ly / n, e.lz / n, 0.0);
    set_uniform(g, g.loc_light_color, e.lr, e.lg, e.lb, 1.0);
    set_uniform(g, g.loc_ambient, e.ar, e.ag, e.ab, 1.0);
    set_uniform(g, g.loc_fog_color, e.fr, e.fg, e.fb, 1.0);
    g.fog_near = e.fog_near;
    g.fog_far = e.fog_far;
    fog(g, True);
}

def fog(g: Gfx, on: bool) {
    set_uniform(g, g.loc_fog, g.fog_near, g.fog_far, 1.0 if on else 0.0, 0.0);
}

def set_view(g: Gfx, x: float, y: float, z: float) {
    set_uniform(g, g.loc_view, x, y, z, 1.0);
}

def draw(g: Gfx, id: int, x: float, y: float, z: float, yaw: float, pitch: float, roll: float, s: float) {
    m = g.models[id];
    m.transform = trs(x, y, z, yaw, pitch, roll, s);
    DrawModel(m, vec3(0.0, 0.0, 0.0), f32(1.0), rgba(255, 255, 255, 255));
}

"""Draw with a hit flash (amount 0..1 toward r,g,b)."""
def draw_flash(
    g: Gfx, id: int, x: float, y: float, z: float, yaw: float, pitch: float,
    roll: float, s: float, amount: float, r: float, gr: float, b: float
) {
    if amount <= 0.0 {
        draw(g, id, x, y, z, yaw, pitch, roll, s);
        return;
    }
    set_uniform(g, g.loc_flash, r, gr, b, clamp(amount, 0.0, 1.0));
    draw(g, id, x, y, z, yaw, pitch, roll, s);
    set_uniform(g, g.loc_flash, 1.0, 1.0, 1.0, 0.0);
}

"""Draw tinted with alpha (shield bubbles, the gate field)."""
def draw_alpha(g: Gfx, id: int, x: float, y: float, z: float, yaw: float, pitch: float, roll: float, s: float, alpha: float) {
    m = g.models[id];
    m.transform = trs(x, y, z, yaw, pitch, roll, s);
    rlDisableDepthMask();
    DrawModel(m, vec3(0.0, 0.0, 0.0), f32(1.0), rgba(255, 255, 255, int(clamp(alpha, 0.0, 1.0) * 255.0)));
    rlEnableDepthMask();
}

"""Sky dome centred on the camera, behind everything."""
def draw_sky(g: Gfx, id: int, cx: float, cy: float, cz: float, yaw: float, bright: int) {
    m = g.models[id];
    m.transform = trs(cx, cy, cz, yaw, 0.0, 0.0, 1500.0);
    rlDisableDepthMask();
    rlDisableBackfaceCulling();
    DrawModel(m, vec3(0.0, 0.0, 0.0), f32(1.0), rgba(bright, bright, bright, 255));
    rlEnableBackfaceCulling();
    rlEnableDepthMask();
}

"""Far scenery (planets, suns, the gate): unfogged, placed inside the sky dome."""
def draw_backdrop(g: Gfx, id: int, x: float, y: float, z: float, yaw: float, pitch: float, roll: float, s: float) {
    fog(g, False);
    draw(g, id, x, y, z, yaw, pitch, roll, s);
    fog(g, True);
}

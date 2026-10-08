"""Build every EMBERWAKE model procedurally and export it to assets/models/.

    blender -b --factory-startup -P blender/assets.py -- [name ...]

With no names, every asset is rebuilt. Units are game units (the Kestrel is
about 4.6 long). Blender +Y is the model's forward and +Z is up; the glTF
exporter turns that into the game's -Z forward, +Y up.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lowpoly import (  # noqa: E402
    Asset, R, S, T, align_y, annulus, beam, bipyramid, box, disc, fbm, hull, ico, mix, prism,
    ring, rock, smoothstep, torus, uvsphere, xform,
)
from mathutils import Vector  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "assets" / "models"

# Palette (display colours; see docs/DESIGN.md "Art direction").
HULL = (0.86, 0.88, 0.92)
EMBER = (0.95, 0.40, 0.10)
GOLD = (0.95, 0.74, 0.26)
CANOPY = (0.25, 0.80, 1.00)
ENGINE = (0.26, 0.27, 0.30)
GLOW = (1.00, 0.60, 0.18)
OBSIDIAN = (0.14, 0.12, 0.21)
OBSIDIAN_HI = (0.24, 0.20, 0.34)
VIOLET = (0.72, 0.32, 1.00)
MAGENTA = (1.00, 0.28, 0.78)
STEEL = (0.52, 0.55, 0.59)
STEEL_D = (0.30, 0.32, 0.36)
GRAPHITE = (0.30, 0.31, 0.34)
AMBER = (1.00, 0.68, 0.22)
CYAN = (0.35, 0.90, 1.00)

ASSETS = {}


def asset(fn):
    ASSETS[fn.__name__] = fn
    return fn


def up(shape):
    """Turn a Y-axis shape so its axis points up (+Z)."""
    return xform(shape, R("X", 90))


def choir_mats(a):
    a.mat("shell", OBSIDIAN)
    a.mat("shell_hi", OBSIDIAN_HI)
    a.mat("core", VIOLET, emissive=1.0)
    a.mat("tip", MAGENTA, emissive=1.0)


# ===================================================================== player

def build_kestrel(name, accent):
    a = Asset(name, seed=11)
    a.mat("hull", HULL)
    a.mat("accent", accent)
    a.mat("glass", CANOPY, emissive=0.35)
    a.mat("engine", ENGINE)
    a.mat("dark", (0.14, 0.15, 0.18))
    a.mat("glow", GLOW, emissive=1.0)

    a.add(hull([(0, 2.6, -0.02)] + ring(1.3, 0.30, 0.22) + ring(-0.2, 0.48, 0.32) + ring(-1.6, 0.40, 0.28) + ring(-1.95, 0.30, 0.20)), "hull")
    a.add(hull([(0, 2.66, -0.02)] + ring(2.05, 0.14, 0.11)), "accent")
    a.add(hull([(0, 1.75, 0.10)] + ring(1.1, 0.19, 0.11, cz=0.24) + ring(0.1, 0.21, 0.13, cz=0.27) + [(0, -0.6, 0.22)]), "glass")

    wing = [(0.35, 0.5, 0.06), (0.35, 0.5, -0.08), (0.35, -1.5, 0.06), (0.35, -1.5, -0.08),
            (2.3, -1.0, -0.04), (2.3, -1.0, -0.09), (2.3, -1.65, -0.04), (2.3, -1.65, -0.09)]
    a.add(hull(wing), "accent", mirror_x=True)
    a.add(prism(0.075, 1.8), "dark", T(2.3, -0.75, -0.065), mirror_x=True)
    a.add(prism(0.05, 0.12), "glow", T(2.3, 0.2, -0.065), mirror_x=True)

    a.add(hull(ring(0.5, 0.20, sides=8, cx=0.62, cz=-0.06) + ring(-1.9, 0.26, sides=8, cx=0.62, cz=-0.06)), "engine", mirror_x=True)
    a.add(hull(ring(0.52, 0.15, sides=8, cx=0.62, cz=-0.06) + ring(0.56, 0.15, sides=8, cx=0.62, cz=-0.06)), "dark", mirror_x=True)
    a.add(hull(ring(-1.92, 0.20, sides=8, cx=0.62, cz=-0.06) + ring(-2.02, 0.17, sides=8, cx=0.62, cz=-0.06)), "glow", mirror_x=True)

    fin = [(0.55, -0.9, 0.15), (0.62, -1.9, 0.18), (0.88, -1.78, 0.95), (0.82, -1.38, 0.95)]
    fin = [(x + dx, y, z) for (x, y, z) in fin for dx in (-0.035, 0.035)]
    a.add(hull(fin), "accent", mirror_x=True)
    return a


@asset
def kestrel():
    return build_kestrel("kestrel", EMBER)


@asset
def kestrel_halo():
    return build_kestrel("kestrel_halo", GOLD)


# ===================================================================== allies

@asset
def lantern():
    a = Asset("lantern", seed=21, jitter=0.08)
    a.mat("hull", (0.36, 0.37, 0.40))
    a.mat("plate", (0.46, 0.47, 0.50))
    a.mat("dark", (0.20, 0.21, 0.23))
    a.mat("accent", EMBER)
    a.mat("window", AMBER, emissive=1.0)
    a.mat("core", (1.0, 0.76, 0.36), emissive=1.0)
    a.mat("thrust", (0.62, 0.86, 1.0), emissive=1.0)
    rng = a.rng

    a.add(prism(3.2, 122), "hull", T(0, -5, 0))
    for y in range(-50, 36, 9):
        for ang in (0, 90, 180, 270):
            if rng.random() < 0.82:
                w, h, ln = rng.uniform(5, 8), rng.uniform(4, 7), rng.uniform(6.5, 8.2)
                m = R("Y", ang) @ T(0, y, 3.0 + h / 2)
                a.add(box(w, ln, h), "accent" if rng.random() < 0.12 else "plate", m)
                for k in range(rng.randint(1, 3)):
                    a.add(box(w * 0.75, 0.35, 0.2), "window", m @ T(0, -ln / 2 + 1.5 + k * 1.6, h / 2 + 0.06))

    a.add(torus(24, 2.2, segs=36, sides=6), "plate", T(0, 12, 0))
    for i in range(36):
        a.add(box(1.4, 1.8, 0.4), "window", R("Y", i * 10) @ T(0, 12, 26.25))
    for ang in (45, 135, 225, 315):
        a.add(beam((0, 12, 0), (0, 12, 22.5), 1.3), "hull", R("Y", ang))

    a.add(box(16, 14, 14), "dark", T(0, -72, 0))
    for sx in (-4, 4):
        for sz in (-4, 4):
            a.add(prism(3.0, 5, sides=8, r2=2.4), "hull", T(sx, -80.5, sz))
            a.add(prism(2.5, 0.6, sides=8), "thrust", T(sx, -83.2, sz))

    a.add(torus(9, 0.6, segs=24, sides=6), "plate", T(0, 58, 0))
    for i in range(6):
        ang = math.radians(i * 60)
        a.add(beam((9 * math.cos(ang), 58, 9 * math.sin(ang)), (0, 78, 0), 0.8), "plate")
        a.add(beam((3.2 * math.cos(ang), 54, 3.2 * math.sin(ang)), (9 * math.cos(ang), 58, 9 * math.sin(ang)), 0.7), "hull")
    a.add(ico(6.5, 2), "core", T(0, 66, 0))
    return a


# ===================================================================== choir

@asset
def mote():
    a = Asset("mote", seed=31)
    choir_mats(a)
    a.add(ico(0.40, 1), "core")
    dirs = [(0, 1, 0.35), (0.9, -0.45, 0.35), (-0.9, -0.45, 0.35), (0, 0, -1)]
    for i, d in enumerate(dirs):
        m = align_y(d)
        a.add(bipyramid(0.27, 1.0, 0.25, sides=3), "shell_hi" if i == 0 else "shell", m @ T(0, 0.35, 0))
        a.add(bipyramid(0.08, 0.28, 0.04, sides=3), "tip", m @ T(0, 1.32, 0))
    return a


@asset
def lance():
    a = Asset("lance", seed=32)
    choir_mats(a)
    nose, tail = (0, 2.4, 0), (0, -1.8, 0)
    mid = ring(0.3, 0.44, 0.30, sides=4)
    a.add(hull([nose, tail] + mid), "shell")
    for p in mid:
        a.add(beam(nose, p, 0.06), "core")
    for ang in (90, 210, 330):
        d = Vector((math.cos(math.radians(ang)), -1.2, math.sin(math.radians(ang))))
        a.add(bipyramid(0.13, 1.1, 0.1, sides=3), "shell_hi", T(0, -1.0, 0) @ align_y(d))
        a.add(bipyramid(0.05, 0.25, 0.02, sides=3), "tip", T(0, -1.0, 0) @ align_y(d) @ T(0, 1.15, 0))
    a.add(ico(0.17, 1), "tip", T(0, 1.0, 0.2))
    return a


@asset
def warden():
    a = Asset("warden", seed=33)
    choir_mats(a)
    a.add(hull([(0, 2.3, 0), (0, -1.7, 0)] + ring(0.4, 1.8, 1.3, sides=8, phase=math.pi / 8)), "shell")
    a.add(torus(1.72, 0.11, segs=24, sides=4), "core", T(0, 0.4, 0))
    a.add(ico(0.42, 1), "core", T(0, 2.0, 0))
    for sx in (-1, 1):
        a.add(bipyramid(0.5, 1.6, 1.2, sides=5), "shell_hi", T(2.7 * sx, -0.2, 0))
        a.add(ico(0.18, 1), "tip", T(2.7 * sx, 1.45, 0))
        a.add(beam((1.5 * sx, 0.2, 0), (2.5 * sx, -0.2, 0), 0.25), "shell")
    for sz in (-1, 1):
        a.add(bipyramid(0.22, 1.3, 0.1, sides=4), "shell_hi", T(0, -0.1, 1.0 * sz) @ align_y((0, -0.3, sz)))
    return a


@asset
def turret():
    a = Asset("turret", seed=34)
    choir_mats(a)
    a.mat("steel", STEEL)
    a.mat("steel_d", STEEL_D)
    a.add(up(prism(1.25, 0.6)), "steel", T(0, 0, 0.3))
    a.add(hull([(x, y, z) for (x, y, z) in [(v[0] * 0.9, v[1] * 0.9, abs(v[2]) * 0.9) for v in ico(1, 1)[0]]]), "shell", T(0, 0, 0.55))
    a.add(prism(0.14, 1.7), "steel_d", T(0, 1.0, 1.0))
    a.add(prism(0.2, 0.3), "steel_d", T(0, 0.35, 1.0))
    a.add(ico(0.24, 1), "core", T(0, 0.62, 1.12))
    for ang in (30, 150, 270):
        d = (math.cos(math.radians(ang)), math.sin(math.radians(ang)), 1.1)
        a.add(bipyramid(0.13, 0.7, 0.05, sides=4), "tip", T(0.95 * d[0], 0.95 * d[1], 0.5) @ align_y(d))
    return a


@asset
def mine():
    a = Asset("mine", seed=35)
    choir_mats(a)
    a.add(ico(0.55, 1), "shell")
    for v in ico(1.0, 0)[0]:
        a.add(bipyramid(0.11, 0.7, 0.0, sides=4), "core", align_y(v) @ T(0, 0.42, 0))
    return a


@asset
def emitter():
    a = Asset("emitter", seed=36)
    choir_mats(a)
    a.mat("steel", STEEL)
    a.mat("steel_d", STEEL_D)
    a.add(up(prism(1.6, 1.0)), "steel", T(0, 0, -3.5))
    a.add(up(prism(0.55, 5.0)), "steel_d", T(0, 0, -0.5))
    a.add(up(bipyramid(1.0, 1.9, 1.3, sides=6)), "core", T(0, 0, 3.3))
    for ang in (0, 120, 240):
        a.add(box(0.15, 1.3, 4.2), "shell", R("Z", ang) @ T(0, 0.8, -0.6))
        a.add(bipyramid(0.12, 0.6, 0.0, sides=3), "tip", R("Z", ang) @ T(0, 1.4, 1.6) @ align_y((0, 0.4, 1)))
    return a


@asset
def carrier():
    a = Asset("carrier", seed=37, jitter=0.08)
    choir_mats(a)
    a.add(rock(a.rng, r=1.0, n=44, stretch=(12, 21, 7.5), jitter=(0.88, 1.04)), "shell")
    a.add(prism(4.6, 6, sides=6, r2=5.4), "shell_hi", T(0, 19.5, 0))
    a.add(prism(4.3, 0.3, sides=6), "core", T(0, 22.6, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            a.add(beam((6 * sx, -2, 2 * sz), (14.5 * sx, -4, 5 * sz), 1.2), "shell_hi")
    for i in range(9):
        y = -14 + i * 3.6
        a.add(bipyramid(0.5, 2.4 + (i % 3), 0.2, sides=4), "core", T(0, y, 6.4 + 0.6 * math.cos(i)) @ align_y((0, 0.25, 1)))
    a.add(torus(3.6, 0.35, segs=20, sides=4, axis="Z"), "core", T(0, -6, 6.9))
    return a


@asset
def carrier_pod():
    a = Asset("carrier_pod", seed=38)
    choir_mats(a)
    a.add(bipyramid(2.0, 3.6, 3.0, sides=6), "shell")
    a.add(torus(1.85, 0.16, segs=18, sides=4), "core", T(0, 0.3, 0))
    a.add(prism(0.7, 0.4, sides=6), "tip", T(0, 3.3, 0))
    return a


@asset
def conductor_core():
    a = Asset("conductor_core", seed=39, jitter=0.07)
    choir_mats(a)
    a.add(rock(a.rng, r=10.0, n=64, jitter=(0.9, 1.04)), "shell")
    a.add(ico(3.4, 2), "core", T(0, 9.0, 0))
    a.add(torus(4.2, 0.45, segs=24, sides=4), "tip", T(0, 8.6, 0))
    for _ in range(14):
        d = Vector((a.rng.gauss(0, 1), a.rng.gauss(0, 1), a.rng.gauss(0, 1))).normalized()
        if d.y > 0.75:
            continue
        a.add(bipyramid(0.9, a.rng.uniform(4, 7), 0.5, sides=4), "core" if a.rng.random() < 0.5 else "shell_hi", align_y(d) @ T(0, 9.0, 0))
    return a


@asset
def conductor_ring():
    a = Asset("conductor_ring", seed=40)
    choir_mats(a)
    n = 16
    for i in range(n):
        ang = 2 * math.pi * (i + 0.5) / n
        pos = (24 * math.cos(ang), 0, 24 * math.sin(ang))
        tangent = (-math.sin(ang), 0, math.cos(ang))
        a.add(bipyramid(1.7, 3.6, 3.6, sides=4), "shell" if i % 2 else "shell_hi", T(*pos) @ align_y(tangent))
        a.add(bipyramid(0.35, 1.6, 0.0, sides=4), "tip", T(*pos) @ align_y((pos[0], 0, pos[2])) @ T(0, 1.4, 0))
    a.add(torus(24, 0.3, segs=48, sides=4), "core")
    return a


@asset
def conductor_node():
    a = Asset("conductor_node", seed=41)
    choir_mats(a)
    a.add(ico(1.4, 1), "tip")
    for d in [(0, 1, 0), (1, 0.3, 0.4), (-1, 0.3, 0.4), (0.3, 0.2, -1), (-0.3, 0.2, 1)]:
        a.add(bipyramid(0.7, 3.2, 0.4, sides=4), "shell", align_y(d) @ T(0, 0.8, 0))
    return a


@asset
def core_orb():
    a = Asset("core_orb", seed=42)
    a.mat("core", VIOLET, emissive=1.0)
    a.add(ico(1.0, 2), "core")
    return a


@asset
def shield_bubble():
    a = Asset("shield_bubble", seed=43, jitter=0.15)
    a.mat("shield", (0.55, 0.75, 1.0), emissive=1.0)
    a.add(ico(1.0, 2), "shield")
    return a


# ===================================================================== choir, wave 2

@asset
def seeker():
    """Missile drone: a flat crystal hull with two launch tubes."""
    a = Asset("seeker", seed=44)
    choir_mats(a)
    a.add(hull([(0, 1.9, 0), (0, -1.4, 0)] + ring(0.2, 1.3, 0.55, sides=6)), "shell")
    a.add(ico(0.32, 1), "core", T(0, 1.55, 0.12))
    for sx in (-1, 1):
        a.add(prism(0.32, 2.2, sides=6), "shell_hi", T(1.45 * sx, 0.1, -0.05))
        a.add(prism(0.24, 0.12, sides=6), "tip", T(1.45 * sx, 1.24, -0.05))
        a.add(bipyramid(0.12, 0.9, 0.1, sides=3), "core", T(1.45 * sx, -1.1, 0.25) @ align_y((0.3 * sx, -1.0, 0.6)))
    return a


@asset
def missile():
    """Homing crystal dart fired by Seekers (can be shot down)."""
    a = Asset("missile", seed=45)
    choir_mats(a)
    a.add(bipyramid(0.22, 1.0, 0.5, sides=4), "shell_hi")
    a.add(bipyramid(0.1, 0.45, 0.0, sides=4), "tip", T(0, 0.9, 0))
    for ang in (0, 120, 240):
        a.add(bipyramid(0.06, 0.45, 0.0, sides=3), "core", T(0, -0.35, 0) @ R("Y", ang) @ align_y((0.6, -1.0, 0)))
    return a


@asset
def prism_half():
    """One armour half of a Prism; the game draws two, split apart when it opens."""
    a = Asset("prism_half", seed=46, jitter=0.1)
    choir_mats(a)
    a.mat("mirror", (0.62, 0.66, 0.82))
    pts = [(0, 2.6, 0), (0, -2.6, 0), (0, 0, 2.0), (0, 0, -2.0), (2.1, 0.3, 0.0), (1.6, 1.2, 1.1), (1.6, -1.1, -1.0), (1.4, 1.1, -1.2), (1.5, -1.2, 1.2)]
    a.add(hull(pts), "mirror")
    a.add(beam((0.05, 2.5, 0), (2.0, 0.3, 0.0), 0.08), "core")
    a.add(beam((0.05, -2.5, 0), (2.0, 0.3, 0.0), 0.08), "core")
    a.add(beam((0.05, 0, 1.95), (2.0, 0.3, 0.0), 0.08), "tip")
    return a


@asset
def weaver():
    """Shield projector: a bright core caged by three crystal rings."""
    a = Asset("weaver", seed=47)
    choir_mats(a)
    a.add(ico(0.55, 2), "tip")
    a.add(torus(1.3, 0.09, segs=20, sides=4), "core")
    a.add(torus(1.55, 0.08, segs=20, sides=4), "shell_hi", R("X", 70))
    a.add(torus(1.8, 0.08, segs=22, sides=4), "core", R("Z", 60) @ R("X", 35))
    for d in [(0, 1, 0), (0, -1, 0), (1, 0, 0.2), (-1, 0, 0.2), (0, 0.2, 1), (0, 0.2, -1)]:
        a.add(bipyramid(0.12, 1.5, 0.0, sides=3), "shell", align_y(d) @ T(0, 0.5, 0))
    return a


# ===================================================================== effects

@asset
def shard():
    """Choir debris fragment."""
    a = Asset("shard", seed=48, jitter=0.12)
    choir_mats(a)
    a.add(hull([(0, 0.55, 0), (0.22, -0.2, 0.05), (-0.18, -0.25, 0.1), (0.02, -0.1, -0.2)]), "shell_hi")
    a.add(hull([(0, 0.6, 0), (0.06, 0.25, 0.03), (-0.05, 0.25, 0.04), (0, 0.27, -0.05)]), "tip")
    return a


@asset
def scrap():
    """Metal debris fragment (station, Guard ships)."""
    a = Asset("scrap", seed=49, jitter=0.12)
    a.mat("steel", STEEL)
    a.mat("hot", (1.0, 0.55, 0.2), emissive=1.0)
    a.add(box(0.7, 0.45, 0.08), "steel")
    a.add(box(0.1, 0.45, 0.1), "hot", T(0.33, 0, 0))
    return a


@asset
def ring_fx():
    """Shockwave ring, drawn additively and scaled up over time."""
    a = Asset("ring_fx", seed=50, jitter=0.0)
    a.mat("glow", (1.0, 0.92, 0.85), emissive=1.0)
    a.add(torus(1.0, 0.035, segs=48, sides=4), "glow")
    return a


# ===================================================================== environment

def rock_asset(name, seed, stretch, color, n=36):
    a = Asset(name, seed=seed, jitter=0.09)
    a.mat("rock", color)
    a.add(rock(a.rng, r=1.0, n=n, stretch=stretch), "rock")
    return a


@asset
def rock_a():
    return rock_asset("rock_a", 51, (1.0, 1.0, 0.9), (0.46, 0.41, 0.37))


@asset
def rock_b():
    return rock_asset("rock_b", 52, (1.3, 0.9, 0.8), (0.38, 0.36, 0.35), n=28)


@asset
def rock_c():
    return rock_asset("rock_c", 53, (0.9, 1.4, 1.0), (0.52, 0.45, 0.39), n=44)


def ice_asset(name, seed, stretch, color, n=14):
    a = Asset(name, seed=seed, jitter=0.1)
    a.mat("ice", color, emissive=0.12)
    a.add(rock(a.rng, r=1.0, n=n, stretch=stretch, jitter=(0.7, 1.2)), "ice")
    return a


@asset
def ice_a():
    return ice_asset("ice_a", 61, (0.8, 1.5, 0.9), (0.74, 0.88, 0.96))


@asset
def ice_b():
    return ice_asset("ice_b", 62, (1.2, 1.0, 0.7), (0.62, 0.79, 0.93), n=11)


@asset
def ice_c():
    a = Asset("ice_c", seed=63, jitter=0.1)
    a.mat("ice", (0.80, 0.92, 0.98), emissive=0.12)
    a.mat("ice2", (0.55, 0.74, 0.90), emissive=0.12)
    for d, s in [((0, 0, 1), 1.0), ((0.6, 0.2, 0.5), 0.7), ((-0.5, -0.3, 0.6), 0.8), ((0.1, 0.6, -0.4), 0.6)]:
        a.add(bipyramid(0.35 * s, 1.6 * s, 0.6 * s, sides=5), "ice" if s > 0.75 else "ice2", align_y(d))
    return a


@asset
def debris_plate():
    a = Asset("debris_plate", seed=71)
    a.mat("steel", STEEL)
    a.mat("accent", EMBER)
    a.mat("dark", STEEL_D)
    a.add(box(3.4, 2.4, 0.18), "steel")
    a.add(box(2.2, 2.4, 0.18), "dark", T(2.6, 0, 0.45) @ R("Y", -25))
    a.add(box(3.45, 0.35, 0.22), "accent", T(0, 0.6, 0))
    a.add(beam((-1.6, -1.1, 0.1), (1.4, 1.1, 0.1), 0.2), "dark")
    return a


@asset
def debris_girder():
    a = Asset("debris_girder", seed=72)
    a.mat("steel", STEEL)
    a.mat("dark", STEEL_D)
    for sx in (-0.5, 0.5):
        a.add(box(0.28, 8.0, 0.28), "steel", T(sx, 0, 0))
    for i in range(5):
        y = -3.6 + i * 1.8
        a.add(box(1.0, 0.2, 0.2), "dark", T(0, y, 0))
        if i < 4:
            a.add(beam((-0.5, y, 0), (0.5, y + 1.8, 0), 0.14), "dark")
    return a


@asset
def dock_gantry():
    a = Asset("dock_gantry", seed=73, jitter=0.07)
    a.mat("steel", STEEL)
    a.mat("dark", STEEL_D)
    a.mat("accent", EMBER)
    a.mat("light", AMBER, emissive=1.0)
    for sx in (-18, 18):
        for cx in (-1.5, 1.5):
            for cy in (-1.5, 1.5):
                a.add(box(0.8, 0.8, 30), "steel", T(sx + cx, cy, 0))
        for k in range(8):
            z = -13 + k * 3.8
            a.add(box(3.8, 0.5, 0.5), "dark", T(sx, -1.5, z))
            a.add(box(3.8, 0.5, 0.5), "dark", T(sx, 1.5, z))
            a.add(beam((sx - 1.5, -1.5, z), (sx + 1.5, -1.5, z + 3.8), 0.3), "dark")
        a.add(box(4.6, 4.6, 1.2), "accent", T(sx, 0, 15.2))
        a.add(box(0.8, 0.8, 0.8), "light", T(sx, 0, 16.2))
    for cy in (-1.2, 1.2):
        for cz in (14.2, 16.6):
            a.add(box(36, 0.7, 0.7), "steel", T(0, cy, cz))
    for k in range(12):
        x = -16.5 + k * 3.0
        a.add(beam((x, -1.2, 14.2), (x + 3.0, -1.2, 16.6), 0.3), "dark")
        a.add(box(0.5, 0.5, 0.3), "light", T(x + 1.5, -1.6, 14.0))
    for sx in (-1, 1):
        a.add(beam((6 * sx, 0, 14), (9 * sx, 0, 8), 0.9), "accent")
        a.add(box(2.2, 1.4, 0.8), "dark", T(9 * sx, 0, 7.6))
    return a


@asset
def trench_wall():
    """Left trench wall segment: face at x=-12 looking +X, 40 long, floor at z=-8."""
    a = Asset("trench_wall", seed=74, jitter=0.07)
    a.mat("steel", STEEL)
    a.mat("dark", STEEL_D)
    a.mat("light", AMBER, emissive=1.0)
    a.mat("cyan", CYAN, emissive=1.0)
    a.mat("crystal", VIOLET, emissive=1.0)
    rng = a.rng
    a.add(box(2, 40, 22), "dark", T(-13, 0, 2))
    a.add(box(3.2, 40, 1.0), "steel", T(-12.4, 0, 13.4))
    for _ in range(16):
        d, ln, h = rng.uniform(0.3, 1.4), rng.uniform(2, 8), rng.uniform(1, 4)
        a.add(box(d, ln, h), "steel" if rng.random() < 0.6 else "dark", T(-12 + d / 2, rng.uniform(-17, 17), rng.uniform(-6, 11)))
    for z in (rng.uniform(-6, -3), rng.uniform(4, 9)):
        a.add(prism(0.35, 40, sides=6), "steel", T(-11.6, 0, z))
    for k in range(4):
        a.add(box(0.12, 2.8, 0.25), "light" if k % 2 else "cyan", T(-11.85, -15 + k * 10, rng.uniform(-5, 10)))
    for _ in range(2):
        y, z = rng.uniform(-15, 15), rng.uniform(-6, 9)
        for d in [(1, 0.2, 0.3), (1, -0.3, -0.2), (0.8, 0.1, -0.5)]:
            a.add(bipyramid(0.35, rng.uniform(1.4, 2.4), 0.2, sides=4), "crystal", T(-12, y, z) @ align_y(d))
    return a


@asset
def trench_floor():
    a = Asset("trench_floor", seed=75, jitter=0.05)
    a.mat("steel", STEEL)
    a.mat("dark", STEEL_D)
    a.mat("cyan", CYAN, emissive=1.0)
    a.add(box(24, 40, 1.0), "dark", T(0, 0, -8.5))
    for i in range(4):
        for j in range(4):
            a.add(box(5.6, 9.6, 0.2), "steel" if (i + j) % 2 else "dark", T(-8.4 + i * 5.6, -15 + j * 10, -7.95))
    for k in range(8):
        for sx in (-3, 3):
            a.add(box(0.3, 1.2, 0.12), "cyan", T(sx, -17.5 + k * 5, -7.8))
    return a


@asset
def girder():
    """Hazard beam spanning the trench (24 wide)."""
    a = Asset("girder", seed=76)
    a.mat("hazard", AMBER, emissive=0.55)
    a.mat("dark", (0.12, 0.12, 0.14))
    a.mat("steel", STEEL)
    for i in range(12):
        a.add(box(2.0, 1.6, 1.8), "hazard" if i % 2 else "dark", T(-11 + i * 2, 0, 0))
    for sx in (-1, 1):
        a.add(box(1.0, 2.6, 2.8), "steel", T(12.3 * sx, 0, 0))
    return a


@asset
def vault_spine():
    a = Asset("vault_spine", seed=77, jitter=0.06)
    a.mat("dark", STEEL_D)
    a.mat("data", CYAN, emissive=1.0)
    a.mat("crystal", VIOLET, emissive=1.0)
    a.add(up(prism(5, 70, sides=8)), "dark")
    for k in range(9):
        a.add(torus(5.25, 0.28, segs=32, sides=4, axis="Z"), "data", T(0, 0, -28 + k * 7))
    rng = a.rng
    for _ in range(12):
        ang = rng.uniform(0, 2 * math.pi)
        d = (math.cos(ang), math.sin(ang), rng.uniform(-0.3, 0.5))
        a.add(bipyramid(0.6, rng.uniform(2.5, 4.5), 0.3, sides=4), "crystal", T(4.6 * d[0], 4.6 * d[1], rng.uniform(-25, 25)) @ align_y(d))
    return a


@asset
def cache():
    a = Asset("cache", seed=78)
    a.mat("hull", GRAPHITE)
    a.mat("accent", EMBER)
    a.mat("light", AMBER, emissive=1.0)
    a.add(box(2.4, 2.4, 2.4), "hull")
    for y in (-0.7, 0.7):
        a.add(box(2.46, 0.4, 2.46), "accent", T(0, y, 0))
    a.add(box(0.5, 0.5, 0.6), "light", T(0, 0, 1.45))
    return a


# ===================================================================== pickups

@asset
def pickup_shield():
    a = Asset("pickup_shield", seed=81)
    a.mat("silver", (0.86, 0.9, 0.97), emissive=0.45)
    a.mat("cyan", CYAN, emissive=1.0)
    a.add(torus(0.9, 0.17, segs=24, sides=6), "silver")
    a.add(torus(0.62, 0.06, segs=24, sides=4), "cyan")
    return a


@asset
def pickup_cannon():
    a = Asset("pickup_cannon", seed=82)
    a.mat("ember", EMBER, emissive=0.85)
    a.mat("gold", GOLD, emissive=0.6)
    a.add(bipyramid(0.45, 0.95, 0.95, sides=4), "ember")
    a.add(torus(0.75, 0.07, segs=20, sides=4, axis="Z"), "gold")
    return a


@asset
def pickup_bomb():
    a = Asset("pickup_bomb", seed=83)
    a.mat("red", (1.0, 0.22, 0.16), emissive=0.6)
    a.mat("dark", (0.15, 0.15, 0.17))
    a.add(bipyramid(0.62, 0.62, 0.62, sides=4), "red")
    a.add(torus(0.7, 0.08, segs=20, sides=4, axis="Z"), "dark")
    return a


# ===================================================================== backdrops

@asset
def planet_tarsis():
    a = Asset("planet_tarsis", seed=91, jitter=0.04)
    a.mat("ocean", (0.16, 0.30, 0.44))
    a.mat("land", (0.42, 0.35, 0.26))
    a.mat("high", (0.52, 0.46, 0.38))
    a.mat("ash", (0.60, 0.55, 0.50))
    a.mat("fire", (1.0, 0.42, 0.10), emissive=1.0)
    a.mat("ice", (0.86, 0.90, 0.95))
    verts, faces = ico(1.0, 4)
    for f in faces:
        c = sum((Vector(verts[i]) for i in f), Vector()) / len(f)
        land = fbm(c, 1.6)
        cloud = fbm(c + Vector((7, 3, 1)), 2.6)
        if abs(c.z) > 0.86:
            key = "ice"
        elif cloud > 0.34:
            key = "ash"
        elif land > 0.18:
            key = "fire" if fbm(c + Vector((2, 5, 9)), 7.0) > 0.5 else ("high" if land > 0.32 else "land")
        else:
            key = "ocean"
        a.add(([verts[i] for i in f], [tuple(range(len(f)))]), key)
    return a


@asset
def planet_mareth():
    a = Asset("planet_mareth", seed=92, jitter=0.03)
    bands = [("cream", (0.86, 0.79, 0.63)), ("ochre", (0.76, 0.56, 0.33)), ("rust", (0.62, 0.38, 0.25)), ("pale", (0.92, 0.88, 0.80))]
    for k, c in bands:
        a.mat(k, c)
    a.mat("ring_a", (0.80, 0.75, 0.64), emissive=0.15)
    a.mat("ring_b", (0.60, 0.56, 0.48), emissive=0.15)
    verts, faces = uvsphere(1.0, 32, 18)
    for f in faces:
        c = sum((Vector(verts[i]) for i in f), Vector()) / len(f)
        t = c.z * 4.0 + 0.6 * fbm(c, 3.0)
        key = bands[int(math.floor(t * 1.3)) % 4][0]
        a.add(([verts[i] for i in f], [tuple(range(len(f)))]), key)
    for i, (r0, r1) in enumerate([(1.45, 1.7), (1.74, 1.95), (2.02, 2.3)]):
        a.add(annulus(r0, r1, segs=72, thickness=0.004), "ring_a" if i % 2 == 0 else "ring_b")
    return a


def sun_asset(name, core, corona, thread=None):
    a = Asset(name, seed=93, jitter=0.03)
    a.mat("core", core, emissive=1.0)
    a.mat("corona", corona, emissive=1.0)
    if thread:
        a.mat("thread", thread, emissive=1.0)
    a.add(ico(1.0, 2), "core")
    rng = a.rng
    for _ in range(26):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        a.add(bipyramid(rng.uniform(0.06, 0.12), rng.uniform(0.35, 0.8), 0.0, sides=3), "corona", align_y(d) @ T(0, 0.95, 0))
    if thread:
        for _ in range(8):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
            a.add(bipyramid(0.025, rng.uniform(0.9, 1.6), 0.0, sides=3), "thread", align_y(d) @ T(0, 0.9, 0))
    return a


@asset
def sun():
    return sun_asset("sun", (1.0, 0.66, 0.30), (1.0, 0.48, 0.16), thread=VIOLET)


@asset
def sun_blue():
    return sun_asset("sun_blue", (0.70, 0.88, 1.0), (0.42, 0.70, 1.0))


@asset
def aperture():
    a = Asset("aperture", seed=94, jitter=0.05)
    a.mat("bronze", (0.64, 0.50, 0.32))
    a.mat("dark", (0.22, 0.20, 0.18))
    a.mat("cyan", CYAN, emissive=1.0)
    a.add(torus(1.0, 0.055, segs=72, sides=6), "bronze")
    a.add(torus(0.935, 0.012, segs=72, sides=4), "cyan")
    for i in range(18):
        m = R("Y", i * 20)
        a.add(box(0.06, 0.09, 0.18), "dark", m @ T(0, 0, 1.08))
        a.add(box(0.035, 0.035, 0.05), "cyan", m @ T(0, 0, 1.19))
    for i in range(3):
        m = R("Y", 30 + i * 120)
        a.add(box(0.22, 0.2, 0.3), "bronze", m @ T(0, 0, 1.12))
        a.add(box(0.12, 0.26, 0.12), "dark", m @ T(0, 0, 1.3))
    return a


@asset
def aperture_field():
    a = Asset("aperture_field", seed=95, jitter=0.12)
    a.mat("field", (0.70, 0.92, 1.0), emissive=1.0)
    a.add(disc(0.93, segs=48, thickness=0.004), "field", R("X", 90))
    return a


# ===================================================================== skies

SKIES = {
    #             low            high           neb_a           neb_b          sun dir (Blender)      sun glow
    "tarsis": ((0.10, 0.05, 0.04), (0.20, 0.10, 0.07), (0.55, 0.24, 0.10), (0.30, 0.12, 0.18), (0.55, 0.75, 0.35), (1.0, 0.55, 0.22), 300),
    "shoal": ((0.02, 0.05, 0.08), (0.04, 0.12, 0.16), (0.10, 0.38, 0.45), (0.12, 0.18, 0.40), (-0.5, 0.6, 0.6), (0.9, 0.8, 0.6), 550),
    "hesper": ((0.02, 0.03, 0.05), (0.05, 0.07, 0.11), (0.14, 0.22, 0.36), (0.28, 0.14, 0.36), (0.4, -0.3, 0.85), (0.9, 0.7, 0.5), 650),
    "reach": ((0.06, 0.02, 0.09), (0.13, 0.04, 0.18), (0.42, 0.14, 0.52), (0.55, 0.18, 0.32), (0.2, 0.8, -0.3), (0.55, 0.3, 0.62), 180),
    "aperture": ((0.01, 0.01, 0.03), (0.03, 0.04, 0.08), (0.16, 0.10, 0.30), (0.06, 0.20, 0.30), (-0.3, -0.8, 0.5), (1.0, 0.6, 0.3), 800),
    "epilogue": ((0.03, 0.06, 0.12), (0.08, 0.16, 0.28), (0.20, 0.40, 0.60), (0.36, 0.52, 0.68), (0.0, 1.0, 0.2), (0.40, 0.50, 0.65), 600),
}


def make_sky(key):
    low, high, neb_a, neb_b, sun_dir, sun_col, n_stars = SKIES[key]
    a = Asset(f"sky_{key}", seed=100 + len(key))
    a.mat("dome", (1, 1, 1))
    a.mat("star", (1, 1, 1))
    sun_dir = Vector(sun_dir).normalized()
    offset = Vector((len(key) * 3.1, 1.7, 4.2))

    def color(d, mat):
        if mat == "star":
            h = (math.sin(d.dot(Vector((12.9898, 78.233, 37.719))) * 43758.5453) % 1.0)
            b = 0.55 + 0.45 * h
            tint = mix((1.0, 0.92, 0.8), (0.75, 0.88, 1.0), (h * 7.0) % 1.0)
            return tuple(b * c for c in tint)
        c = mix(low, high, smoothstep(-0.6, 0.8, d.z))
        n1 = fbm(d + offset, 2.2)
        n2 = fbm(d * 1.7 + offset * 2.0, 3.1)
        c = mix(c, neb_a, smoothstep(0.0, 0.55, n1) * 0.85)
        c = mix(c, neb_b, smoothstep(0.05, 0.6, n2) * 0.6)
        glow = max(0.0, d.dot(sun_dir)) ** 6
        return tuple(min(1.0, x + glow * 0.75 * s) for x, s in zip(c, sun_col))

    a.sky_fn = color
    a.add(ico(1.0, 4), "dome")
    rng = a.rng
    stars_v, stars_f = [], []
    for _ in range(n_stars):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        t1 = d.orthogonal().normalized()
        t2 = d.cross(t1)
        s = rng.uniform(0.0009, 0.0022)
        base = len(stars_v)
        p = d * 0.985
        stars_v += [tuple(p + t1 * s), tuple(p - t1 * s * 0.5 + t2 * s * 0.87), tuple(p - t1 * s * 0.5 - t2 * s * 0.87)]
        stars_f.append((base, base + 1, base + 2))
    a.add((stars_v, stars_f), "star")
    return a


for _sky in SKIES:
    ASSETS[f"sky_{_sky}"] = (lambda k: (lambda: make_sky(k)))(_sky)


# ===================================================================== main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(ASSETS)
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"building {len(names)} assets -> {OUT}")
    for name in names:
        ASSETS[name]().export(OUT)


main()

# EMBERWAKE — game design

The story is in [STORY.md](STORY.md). This document is the implementation spec.

## Genre and camera

EMBERWAKE is an on-rails 3D space shooter in the style of Star Fox 64 and
Panzer Dragoon. The ship flies forward automatically; the player steers inside
a screen-sized box, shoots, rolls and boosts. The camera sits behind and above
the Kestrel, trails it with some lag, and leans into turns.

- World axes: **forward is −Z**, +Y is up, +X is screen-right. Every model is
  authored with its nose along Blender **+Y**, which the glTF exporter maps to
  −Z.
- The player box is x ∈ [−9, 9], y ∈ [−5, 5] around the rail. Chapter 3's trench
  narrows it.
- Rail speed is 28 u/s when cruising and 44 u/s when boosting.

## Player — the Kestrel

| Action | Keys | Pad | Notes |
|---|---|---|---|
| Steer | WASD / arrows | left stick | The ship banks and pitches into its motion. |
| Fire | Space / J | A | 8 shots/s; held fire repeats |
| Roll | Q / E | LB / RB | 0.5 s, deflects enemy shots; 0.8 s cooldown |
| Boost | Shift | RT | Drains 40/s from a 100 meter; refills 20/s |
| Bomb | B / K | X | Clears enemy shots, deals 20 damage within 90 u ahead; starts with 3, holds up to 5 |
| Pause | Esc / P | Start | |

- Shields start at 100. An enemy shot deals 10, ramming a Mote 15, an
  asteroid or wall 20. Each hit gives 1 s of invulnerability with blinking.
- Weapon levels: **single** (1 damage), **twin** (2 bolts; unlocked in Chapter
  2), **hyper** (2 bolts, 2 damage, from a cannon pickup while twin).
- When shields hit 0 the ship explodes and the game offers *Retry chapter* or
  *Quit to title*. Score rolls back to the chapter's starting value.

## Scoring

- Each kill scores the enemy's base value × the combo multiplier. A kill within
  2 s of the previous one raises the multiplier, up to ×8; it resets after 2 s
  without a kill or when the player takes a hit.
- After-action card: kills, shot accuracy, shield lost, and a rank (S/A/B/C)
  derived from these against the chapter's par.
- Progress (highest unlocked chapter, best score per chapter) is saved in
  `save.txt`.

## Enemies — the Choir

All Choir units are obsidian shells with violet cores. Shots are violet orbs
with a chime.

| Unit | HP | Score | Behaviour |
|---|---|---|---|
| Mote | 1 | 100 | Small tetrahedral drone. Flies in formations (stream, V, ring, swarm) along sine paths; fires slow orbs from Chapter 2 on. |
| Lance | 3 | 250 | Needle interceptor. Enters from behind or the flanks, overtakes, turns, fires a 3-shot burst, then dashes off. |
| Warden | 25 | 1000 | Octahedral gunship. Holds 45–60 u ahead, strafes, fires a 5-way spread every 2 s, leaves after 15 s. |
| Turret | 6 | 300 | Fixed to station walls; fires aimed shots while 30–140 u ahead. |
| Mine | 2 | 150 | Spiked seed; drifts toward the player and bursts at 4 u. |
| Emitter | 20 | 800 | Chapter 3 vault: four pylons that hold station ahead and fire rings of orbs. |
| Carrier | pods 4×15, core 60 | 5000 | Chapter 4 boss. Launches Mote swarms at the Lantern; the core is shielded until all pods are destroyed. |
| Conductor | nodes 4×20, core 120 | 20000 | Chapter 5 boss. Phase 1: a rotating ring with four nodes firing spirals. Phase 2: exposed core firing aimed bursts plus Motes. Phase 3: a death song of radial spirals while the gate folds. |

Bosses "hold" the rail: the world keeps scrolling, but level progress stops
at the boss's hold point until it dies.

## Pickups

| Pickup | Look | Effect |
|---|---|---|
| Shield ring | silver torus | +30 shield |
| Cannon | ember-orange crystal | weapon level +1 |
| Bomb | red octahedron | +1 bomb |

Some pickups are scripted; destroying a whole formation also drops one.

## Chapters (level data)

Each level is a script of events triggered by progress, plus streamed scenery.

| # | Name | Length | Scenery | Sky / fog | Key events |
|---|---|---|---|---|---|
| 1 | Last Light | 3600 u | dock gantries, debris, Tarsis, Vesper | ash orange | Mote formations; the Lantern alongside at first; Warden pair at the end |
| 2 | The Shoal | 4000 u | ice asteroids (some destructible), Mareth | cold teal | Lances on the flanks, twin cannon pickup at 42 %, Wardens at the exit |
| 3 | Relay Silence | 4000 u | trench walls and floor, girders, turrets | steel blue | Trench at 3–43 %, vault at 55 % (four emitters, hold), escape trench at 62–88 % |
| 4 | Choir's Wake | 4200 u | nebula, rocks, the Lantern escorted | violet | Lantern hull bar; Carrier boss at 30 % (hold until dead) |
| 5 | The Aperture | 3000 u | the gate, Vesper, rocks | black-blue | Conductor at 12 % (hold); escape at 64 u/s with remnants pursuing; fly through the folding gate; ending |

## Art direction

- Low poly, flat-shaded faceted solids, with a ±6 % random brightness change
  per face so planes read as panels.
- The custom lit shader does lambert lighting from a per-chapter sun, ambient
  light, distance fog to the sky colour, and a hit flash.
- **Vertex-color convention** (every lit model): `R` = face brightness, `G` =
  emissive amount, `B` = 0, `A` = 1. Emissive faces ignore lighting and fog
  less. Skies use true RGB vertex colours and the unlit shader.
- Palette:
  - Kestrel: silver-white hull, ember-orange wings, cyan canopy, orange
    engines. Halo's ship has gold accents.
  - Lantern: graphite hull, warm amber windows, a large glowing amber lantern
    core in a cage at the bow.
  - Choir: obsidian (0.07, 0.06, 0.11), violet core (0.72, 0.32, 1.0), magenta
    seams.
  - Station: steel grey, amber hazard lights.

## Audio

| SFX (`assets/sfx/*.wav`) | Use |
|---|---|
| `laser` | player shot |
| `enemy_shot` | Choir orb (a short glassy chime) |
| `hit` | player bolt hits an enemy |
| `hurt` | player takes damage |
| `explode_small` | Mote, Lance, turret |
| `explode_big` | Warden, emitter, pod |
| `explode_boss` | boss death |
| `roll` | barrel roll whoosh |
| `boost` | boost start |
| `bomb` | bomb detonation |
| `pickup` | pickup collected |
| `alarm` | low shields (looping beep) |
| `ui_move`, `ui_select` | menu navigation |
| `radio` | radio line starts (static blip) |
| `warning` | boss incoming klaxon |

| Music (`assets/music/*`) | Mood |
|---|---|
| `title` | slow, melancholic: a dying sun |
| `ch1` | urgent and hopeful: departure |
| `ch2` | cold and tense: ice |
| `ch3` | mechanical and claustrophobic |
| `ch4` | eerie and sad: inside a dead star |
| `boss` | driving; the Choir's chord on top |
| `ch5` | epic and final |
| `ending` | warm and resolved: a new star |

## Tech architecture

```
jblender/
  docs/              story + design
  blender/           lowpoly.py (helpers) + assets.py (every model) → assets/models/*.glb
  tools/gen_audio.py numpy synth → assets/sfx, assets/music
  assets/shaders/    lit.vs/.fs, sky.vs/.fs
  game/
    rl.jac           raylib 6.0 bindings (structs, externs, constants)
    gfx.jac          model registry, shaders, transforms, drawing helpers
    audio.jac        sound bank + music
    world.jac        chapter definitions: environment, scenery streams, event scripts, radio lines
    entities.jac     player, enemies, bosses, shots, pickups, particles
    hud.jac          HUD, radio box, menus, cards
    main.jac         window, state machine, game loop
  build.sh           assets + audio + native build
```

Native constraints to design around: no lambdas, decorators, generators or
walkers. Import names explicitly (`import from rl { * }` loses extern return
types).

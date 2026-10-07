"""Sound bank and music.

Each effect gets a few raylib sound aliases so rapid repeats overlap instead of
restarting. Missing files are skipped, so the game runs silently without them.
"""

import from rl {
    Sound, Music, FileExists, InitAudioDevice, IsAudioDeviceReady, SetMasterVolume,
    LoadSound, LoadSoundAlias, PlaySound, StopSound, IsSoundPlaying, SetSoundVolume,
    SetSoundPitch, LoadMusicStream, PlayMusicStream, StopMusicStream,
    UpdateMusicStream, SetMusicVolume
}

glob SFX_NAMES: list[str] = [
    "laser", "enemy_shot", "hit", "hurt", "explode_small", "explode_big",
    "explode_boss", "roll", "boost", "bomb", "pickup", "alarm", "ui_move",
    "ui_select", "radio", "warning"
];

glob S_LASER: int = 0,
     S_ENEMY_SHOT: int = 1,
     S_HIT: int = 2,
     S_HURT: int = 3,
     S_EXPLODE_SMALL: int = 4,
     S_EXPLODE_BIG: int = 5,
     S_EXPLODE_BOSS: int = 6,
     S_ROLL: int = 7,
     S_BOOST: int = 8,
     S_BOMB: int = 9,
     S_PICKUP: int = 10,
     S_ALARM: int = 11,
     S_UI_MOVE: int = 12,
     S_UI_SELECT: int = 13,
     S_RADIO: int = 14,
     S_WARNING: int = 15;

glob MUSIC_NAMES: list[str] = ["title", "ch1", "ch2", "ch3", "ch4", "boss", "ch5", "ending"];

glob MU_TITLE: int = 0,
     MU_BOSS: int = 5,
     MU_CH5: int = 6,
     MU_ENDING: int = 7,
     VOICES: int = 4;

obj Audio {
    has ok: bool = False,
        sounds: list[Sound] = [],
        has_sound: list[bool] = [],
        next_voice: list[int] = [],
        music: list[Music] = [],
        has_music: list[bool] = [],
        current: int = -1,
        music_volume: float = 0.55,
        muted: bool = False;
}

"""Music track for a chapter (1..5)."""
def chapter_track(ch: int) -> int {
    if ch == 5 {
        return MU_CH5;
    }
    return ch;
}

def audio_load(base: str) -> Audio {
    a = Audio();
    InitAudioDevice();
    a.ok = IsAudioDeviceReady();
    if not a.ok {
        return a;
    }
    SetMasterVolume(f32(0.9));
    for i in range(len(SFX_NAMES)) {
        path = base + "/sfx/" + SFX_NAMES[i] + ".wav";
        found = FileExists(path);
        for v in range(VOICES) {
            if found {
                if v == 0 {
                    a.sounds.append(LoadSound(path));
                } else {
                    a.sounds.append(LoadSoundAlias(a.sounds[i * VOICES]));
                }
            } else {
                a.sounds.append(Sound());
            }
        }
        a.has_sound.append(found);
        a.next_voice.append(0);
    }
    for i in range(len(MUSIC_NAMES)) {
        path = base + "/music/" + MUSIC_NAMES[i] + ".ogg";
        if not FileExists(path) {
            path = base + "/music/" + MUSIC_NAMES[i] + ".wav";
        }
        found = FileExists(path);
        if found {
            m = LoadMusicStream(path);
            m.looping = True;
            a.music.append(m);
        } else {
            a.music.append(Music());
        }
        a.has_music.append(found);
    }
    set_sfx_volume(a, S_LASER, 0.35);
    set_sfx_volume(a, S_ENEMY_SHOT, 0.45);
    set_sfx_volume(a, S_HIT, 0.5);
    set_sfx_volume(a, S_ALARM, 0.5);
    set_sfx_volume(a, S_UI_MOVE, 0.6);
    return a;
}

def set_sfx_volume(a: Audio, id: int, vol: float) {
    if not a.ok or not a.has_sound[id] {
        return;
    }
    for v in range(VOICES) {
        SetSoundVolume(a.sounds[id * VOICES + v], f32(vol));
    }
}

def play(a: Audio, id: int) {
    play_pitch(a, id, 1.0);
}

def play_pitch(a: Audio, id: int, pitch: float) {
    if not a.ok or a.muted or not a.has_sound[id] {
        return;
    }
    v = a.next_voice[id];
    a.next_voice[id] = (v + 1) % VOICES;
    s = a.sounds[id * VOICES + v];
    SetSoundPitch(s, f32(pitch));
    PlaySound(s);
}

"""Switch the music track; -1 stops music."""
def music(a: Audio, id: int) {
    if not a.ok or id == a.current {
        return;
    }
    if a.current >= 0 and a.has_music[a.current] {
        StopMusicStream(a.music[a.current]);
    }
    a.current = id;
    if id >= 0 and a.has_music[id] {
        SetMusicVolume(a.music[id], f32(0.0 if a.muted else a.music_volume));
        PlayMusicStream(a.music[id]);
    }
}

def audio_update(a: Audio) {
    if a.ok and a.current >= 0 and a.has_music[a.current] {
        UpdateMusicStream(a.music[a.current]);
    }
}

def toggle_mute(a: Audio) {
    a.muted = not a.muted;
    if a.ok and a.current >= 0 and a.has_music[a.current] {
        SetMusicVolume(a.music[a.current], f32(0.0 if a.muted else a.music_volume));
    }
}

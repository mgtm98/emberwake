#!/usr/bin/env bash
# Build EMBERWAKE: fetch raylib, generate models (Blender) and audio (numpy),
# compile the game to a native binary, then run it.
#   ./build.sh             build what is missing, then play
#   ./build.sh --assets    regenerate every model and sound first
#   ./build.sh --no-run    build only
#   ./build.sh --gallery   build and open the model gallery
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

RAYLIB_VERSION=6.0
# The fork's dev launcher; the venv `jac` points at another checkout and lacks --native.
export PATH="$HOME/forks/native/jac/jac/zig-out/bin:$PATH"

force_assets=0; run=1; gallery=0
for arg in "$@"; do
  case "$arg" in
    --assets) force_assets=1 ;;
    --no-run) run=0 ;;
    --gallery) gallery=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ ! -e libraylib.so ]; then
  mkdir -p .build
  asset="raylib-${RAYLIB_VERSION}_linux_amd64"
  echo ">> fetching raylib $RAYLIB_VERSION"
  curl -fsSL --retry 3 -o ".build/$asset.tar.gz" \
    "https://github.com/raysan5/raylib/releases/download/${RAYLIB_VERSION}/$asset.tar.gz"
  tar xzf ".build/$asset.tar.gz" -C .build
  cp -P ".build/$asset/lib/"libraylib.so* .
fi

if [ "$force_assets" = 1 ] || [ ! -e assets/models/kestrel.glb ]; then
  echo ">> generating models (Blender)"
  blender -b --factory-startup -P blender/assets.py 2>&1 | grep -E '^  |^building|Error|Traceback' || true
fi

if [ "$force_assets" = 1 ] || [ ! -e assets/sfx/laser.wav ]; then
  echo ">> synthesizing audio"
  python3 tools/gen_audio.py
fi

echo ">> compiling (jac native)"
jac build --native game/main.jac -o emberwake | grep -E 'Binary written|rror' || true
if [ "$gallery" = 1 ]; then
  jac build --native game/gallery.jac -o gallery | grep -E 'Binary written|rror' || true
  exec ./gallery
fi

if [ "$run" = 1 ]; then
  exec ./emberwake
fi

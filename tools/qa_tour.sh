#!/usr/bin/env bash
# Visual QA tour: boot a server with bots, walk every player-facing state,
# save a still and a measurement for each, and build a contact sheet.
#
# Needs a real framebuffer. On Windows run it from Git Bash and it uses the
# console binary directly. On Linux it wraps the run in Xvfb, because bare
# --headless has no framebuffer and every still comes back empty. Without Xvfb,
# FRAGR_QA_DISPLAY names an existing 1280x720 X display instead (for example a
# nested rootful Xwayland on :97), rendered on the GPU.
#
# Usage: tools/qa_tour.sh [--publish] [output directory]
#   --publish also runs a short team deathmatch pass, copies the approved
#   stills into docs/screenshots/ (what the README shows) and removes any
#   published tour_* still this run did not produce. Run it after any change a
#   player would see.
# Default output: .agents/qa/<stamp>/ (gitignored), with a `latest` copy.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
PUBLISH=0
if [ "${1:-}" = "--publish" ]; then
  PUBLISH=1
  shift
fi
OUT_DIR="${1:-$ROOT/.agents/qa/$STAMP}"
SERVER_PORT="${FRAGR_PORT:-6767}"
SERVER_URL="${FRAGR_SERVER:-127.0.0.1:$SERVER_PORT}"
BOTS="${FRAGR_QA_BOTS:-5}"

# An unrelated listener can satisfy the readiness probe while this server
# fails to bind. Refuse that port before building or launching the tour.
if (exec 3<>"/dev/tcp/127.0.0.1/$SERVER_PORT") 2>/dev/null; then
  echo "qa_tour: port $SERVER_PORT is already in use; choose FRAGR_PORT" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# Godot changes its working directory to the project. A relative path otherwise
# saves the images in a different directory from the wrapper's logs and publish.
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
# The boot menu previews the local campaign run. Give this tour its own
# absolute save directory so captures never depend on a player's real run.
if command -v cygpath >/dev/null 2>&1; then
  export FRAGR_RUN_DIR="$(cygpath -w "$OUT_DIR/run")"
else
  export FRAGR_RUN_DIR="$OUT_DIR/run"
fi

# Godot 4.7.2. FRAGR_GODOT wins; then the console binary on Windows; then PATH.
GODOT_BIN="${FRAGR_GODOT:-${GODOT_BIN:-}}"
if [ -z "$GODOT_BIN" ]; then
  for candidate in \
    "/c/GitHub/_toolchains/godot/Godot_v4.7.2-stable_win64_console.exe" \
    "/c/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" \
    "$HOME/godot/Godot_v4.7.2-stable_win64_console.exe"; do
    [ -x "$candidate" ] && GODOT_BIN="$candidate" && break
  done
fi
if [ -z "$GODOT_BIN" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif command -v Godot_v4.7.2-stable_linux.x86_64 >/dev/null 2>&1; then
    GODOT_BIN="$(command -v Godot_v4.7.2-stable_linux.x86_64)"
  fi
fi
if [ -z "$GODOT_BIN" ]; then
  echo "qa_tour: no Godot 4.7.2 found. Set FRAGR_GODOT to the binary." >&2
  exit 1
fi

echo "qa_tour: godot   $GODOT_BIN"
echo "qa_tour: output  $OUT_DIR"

# A server with bots, so the tour has a match to photograph.
cargo build -p fragr-server --release --locked >"$OUT_DIR/build.log" 2>&1 || {
  echo "qa_tour: server build failed" >&2; exit 1; }
SERVER_ARGS=(--bind "127.0.0.1:$SERVER_PORT" --bots "$BOTS")
if [ -n "${FRAGR_QA_MAP_FILE:-}" ]; then
  SERVER_ARGS+=(--map-file "$FRAGR_QA_MAP_FILE")
else
  SERVER_ARGS+=(--map "${FRAGR_QA_MAP:-1}")
fi
if [ -n "${FRAGR_QA_DIFFICULTY:-}" ]; then
  SERVER_ARGS+=(--difficulty "$FRAGR_QA_DIFFICULTY")
fi
if [ "${FRAGR_QA_CAMPAIGN_RUN:-0}" = "1" ]; then
  SERVER_ARGS+=(--campaign-run)
fi
if [ "${FRAGR_QA_SOLO_BROADCAST:-0}" = "1" ]; then
  SERVER_ARGS+=(--solo-broadcast)
fi
if [ "${FRAGR_QA_NO_ROUND_EVENTS:-0}" = "1" ]; then
  SERVER_ARGS+=(--no-round-events)
fi
# A rule set for the tour server: FRAGR_QA_MODE=tdm, FRAGR_QA_MUTATORS="rail-only two-lives".
if [ -n "${FRAGR_QA_MODE:-}" ]; then
  SERVER_ARGS+=(--mode "$FRAGR_QA_MODE")
fi
if [ -n "${FRAGR_QA_CAPTURE_LIMIT:-}" ]; then
  SERVER_ARGS+=(--capture-limit "$FRAGR_QA_CAPTURE_LIMIT")
fi
if [ -n "${FRAGR_QA_SEED:-}" ]; then
  SERVER_ARGS+=(--seed "$FRAGR_QA_SEED")
fi
for mutator in ${FRAGR_QA_MUTATORS:-}; do
  SERVER_ARGS+=(--mutator "$mutator")
done
SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" >/dev/null 2>&1
  [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT

# Start a tour server with the given arguments and wait for its port.
# A tour against a server that never started photographs an empty grey room
# and calls it a game, which is exactly what happened the first time this ran.
start_server() {
  local log="$1"
  shift
  "$ROOT/target/release/fragr-server" "$@" >"$log" 2>&1 &
  SERVER_PID=$!
  local up=0
  for _ in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    if (exec 3<>"/dev/tcp/127.0.0.1/$SERVER_PORT") 2>/dev/null; then exec 3>&- 3<&-; up=1; break; fi
    sleep 0.2
  done
  if [ "$up" -ne 1 ]; then
    echo "qa_tour: server never came up on port $SERVER_PORT" >&2
    tail -5 "$log" >&2
    exit 1
  fi
}

stop_server() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" >/dev/null 2>&1
  wait "$SERVER_PID" 2>/dev/null
  SERVER_PID=""
  # The next pass binds the same port; wait until this one has let it go.
  for _ in $(seq 1 50); do
    (exec 3<>"/dev/tcp/127.0.0.1/$SERVER_PORT") 2>/dev/null || return 0
    sleep 0.2
  done
}

# Run the tour client once into a directory, with an optional manifest.
run_client() {
  local dir="$1" manifest="${2:-}"
  local run=("$GODOT_BIN" --path "$ROOT/client" --rendering-driver "${FRAGR_RENDER_DRIVER:-opengl3}"
       --windowed --resolution 1280x720 --script res://scripts/qa_tour.gd)
  if [ -n "${FRAGR_QA_POSITION:-}" ]; then
    run+=(--position "$FRAGR_QA_POSITION")
  fi
  # A shared host can keep the tour off its sound card (FRAGR_QA_AUDIO_DRIVER=Dummy).
  if [ -n "${FRAGR_QA_AUDIO_DRIVER:-}" ]; then
    run+=(--audio-driver "$FRAGR_QA_AUDIO_DRIVER")
  fi
  local status
  if [ "$(uname -s)" != "Linux" ]; then
    FRAGR_QA_DIR="$dir" FRAGR_QA_MANIFEST="$manifest" "${run[@]}" >"$dir/client.log" 2>&1
    status=$?
  elif [ -n "${FRAGR_QA_DISPLAY:-}" ]; then
    env -u WAYLAND_DISPLAY DISPLAY="$FRAGR_QA_DISPLAY" \
      FRAGR_QA_DIR="$dir" FRAGR_QA_MANIFEST="$manifest" "${run[@]}" >"$dir/client.log" 2>&1
    status=$?
  else
    env -u WAYLAND_DISPLAY DISPLAY=":$DISPLAY_NUM" LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
      FRAGR_QA_DIR="$dir" FRAGR_QA_MANIFEST="$manifest" "${run[@]}" >"$dir/client.log" 2>&1
    status=$?
  fi
  cat "$dir/client.log"
  if [ "$status" -ne 0 ] || grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$dir/client.log"; then
    echo "qa_tour: the tour failed (exit $status). Server log: $dir/server.log" >&2
    exit 1
  fi
  if [ ! -s "$dir/contact.png" ] || [ ! -s "$dir/manifest.json" ]; then
    echo "qa_tour: missing capture artifacts in $dir" >&2
    exit 1
  fi
}

export FRAGR_SERVER="$SERVER_URL"

# Import the project first. Running a script against a project Godot has never
# imported gives a client with no textures: every scene that references one
# fails to parse, and the tour photographs an empty grey room with a working
# HUD over it. Incremental, so it costs nothing once warm.
echo "qa_tour: importing assets"
"$GODOT_BIN" --path "$ROOT/client" --headless --import >"$OUT_DIR/import.log" 2>&1 || {
  echo "qa_tour: asset import failed; see $OUT_DIR/import.log" >&2
  exit 1
}
if grep -qiE 'SCRIPT ERROR|Parse Error|(^|[[:space:]])ERROR:' "$OUT_DIR/import.log"; then
  echo "qa_tour: import reported errors; see $OUT_DIR/import.log" >&2
  exit 1
fi

if [ "$(uname -s)" = "Linux" ] && [ -z "${FRAGR_QA_DISPLAY:-}" ]; then
  command -v Xvfb >/dev/null 2>&1 || {
    echo "qa_tour: Xvfb needed on Linux for a framebuffer" >&2; exit 1; }
  DISPLAY_NUM="${DISPLAY_NUM:-99}"
  Xvfb ":$DISPLAY_NUM" -screen 0 1280x720x24 >/dev/null 2>&1 &
  XVFB_PID=$!
  sleep 1
fi

start_server "$OUT_DIR/server.log" "${SERVER_ARGS[@]}"
run_client "$OUT_DIR" "${FRAGR_QA_MANIFEST:-}"
stop_server

# A `latest` pointer so the critique step never has to know the stamp.
# Remove only previous tour files, never recursively delete a computed path.
mkdir -p "$ROOT/.agents/qa/latest"
if [ "$OUT_DIR" != "$ROOT/.agents/qa/latest" ]; then
  rm -f "$ROOT/.agents/qa/latest/"*.png "$ROOT/.agents/qa/latest/manifest.json"
  cp "$OUT_DIR"/*.png "$OUT_DIR"/manifest.json "$ROOT/.agents/qa/latest/" || exit 1
fi

# `--publish` copies the approved tour into docs/screenshots/. The README
# embeds four of those files. Do not add the rest back to the README.
if [ "${PUBLISH:-0}" = "1" ]; then
  # Team stills come from their own pass against a team deathmatch server, so
  # they are regenerated with every publish instead of going stale.
  TEAM_DIR="$OUT_DIR/team"
  mkdir -p "$TEAM_DIR"
  start_server "$TEAM_DIR/server.log" --bind "127.0.0.1:$SERVER_PORT" --bots "$BOTS" --map 1 --mode tdm
  run_client "$TEAM_DIR" "res://qa/team_tour.json"
  stop_server

  published=0
  kept=()
  shopt -s nullglob
  while IFS='|' read -r pass state dest; do
    [ -z "$state" ] && continue
    source_dir="$OUT_DIR"
    [ "$pass" = "team" ] && source_dir="$TEAM_DIR"
    # State names survive additions to the tour; ordinal filenames do not.
    matches=("$source_dir/"*"_${state}.png")
    if [ "${#matches[@]}" -eq 1 ]; then
      cp "${matches[0]}" "$ROOT/docs/screenshots/$dest" || exit 1
      kept+=("$dest")
      published=$((published + 1))
    else
      echo "qa_tour: expected one capture for $state, found ${#matches[@]}" >&2
      exit 1
    fi
  done <<'SHOTS'
main|hud_first_person|tour_first_person_16x9.png
main|combat_follow|tour_combat_follow_16x9.png
main|body_human|tour_body_human_16x9.png
main|body_synthetic|tour_body_synthetic_16x9.png
main|arena_overview|tour_arena_overview_16x9.png
main|shot_effects_strip|tour_shot_strip.png
main|rail_impact_strip|tour_rail_impact_strip.png
main|boot_menu|tour_menu_16x9.png
main|multiplayer_menu|tour_multiplayer_16x9.png
main|spectator_chase|tour_spectator_16x9.png
main|profile_menu|tour_profile_16x9.png
main|settings_menu|tour_settings_16x9.png
main|campaign_difficulty|tour_difficulty_16x9.png
main|service_record|tour_records_16x9.png
team|team_first_person|tour_team_first_person_16x9.png
team|team_spectator|tour_team_spectator_16x9.png
SHOTS
  # Every published tour still is one this run produced. A tour_* file the
  # tour no longer makes is removed, so a stale capture cannot ship again.
  for existing in "$ROOT/docs/screenshots/"tour_*.png; do
    name="$(basename "$existing")"
    if [[ " ${kept[*]} " != *" $name "* ]]; then
      rm -f "$existing"
      echo "qa_tour: removed stale $name (no tour state produces it)"
    fi
  done
  echo "qa_tour: published $published stills into docs/screenshots/"
fi

echo "qa_tour: done. Contact sheet: $OUT_DIR/contact.png"

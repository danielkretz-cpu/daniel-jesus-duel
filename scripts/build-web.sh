#!/usr/bin/env bash
# The same checked build runs locally, in GitHub Actions, and on Vercel.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export XDG_CACHE_HOME="$ROOT/.cache/runtime/cache"
export XDG_CONFIG_HOME="$ROOT/.cache/runtime/config"
export XDG_DATA_HOME="$ROOT/.cache/runtime/data"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$ROOT/.cache/logs" "$ROOT/build/web"

GODOT="$(bash "$ROOT/scripts/install-godot.sh")"
"$GODOT" --version
run_godot() {
  local stage="$1"
  shift
  local log="$ROOT/.cache/logs/$stage.log"
  "$GODOT" --headless --path "$ROOT" "$@" 2>&1 | tee "$log"
  # Godot can return zero even after a script parse/runtime error.
  if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)|Parse Error:' "$log"; then
    echo "Godot reported an error during $stage; refusing to deploy." >&2
    exit 1
  fi
}

run_godot import --editor --import
run_godot smoke --quit-after 10
run_godot tests --script res://tests/test_game.gd
run_godot network-tests --script res://tests/test_network.gd
run_godot expansion-tests --script res://tests/test_expansion.gd
run_godot 3d-tests --script res://tests/test_3d.gd
run_godot six-player-tests --script res://tests/test_multiplayer_six.gd
run_godot menu-tests --script res://tests/test_menu.gd
run_godot animation-tests --script res://tests/test_animation.gd
run_godot export --export-release Web "$ROOT/build/web/index.html"
touch "$ROOT/build/web/.nojekyll"
python3 "$ROOT/scripts/validate-web.py" "$ROOT/build/web"

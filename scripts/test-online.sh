#!/usr/bin/env bash
# End-to-end test: two- and six-player real Godot matches against the actual Worker runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export XDG_CACHE_HOME="$ROOT/.cache/runtime/cache"
export XDG_CONFIG_HOME="$ROOT/.cache/runtime/config"
export XDG_DATA_HOME="$ROOT/.cache/runtime/data"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$ROOT/.cache/logs"
GODOT="${GODOT:-$(bash "$ROOT/scripts/install-godot.sh")}"
PORT="${PORT:-18787}"
if [[ ! -d online-server/node_modules ]]; then
  echo 'Install the pinned local test server first: (cd online-server && npm ci)' >&2
  exit 1
fi
PORT="$PORT" node online-server/dev.js > .cache/logs/online-server.log 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true' EXIT
ready=false
for n in $(seq 1 60); do
  if ! kill -0 "$server" 2>/dev/null; then cat .cache/logs/online-server.log; exit 1; fi
  if curl --fail --silent "http://127.0.0.1:$PORT/health" > /dev/null; then ready=true; break; fi
  sleep 0.25
done
if [[ "$ready" != true ]]; then cat .cache/logs/online-server.log; exit 1; fi
timeout "${ONLINE_TEST_TIMEOUT:-240}" "$GODOT" --headless --path "$ROOT" --script res://tests/test_online_live.gd -- "--server-url=ws://127.0.0.1:$PORT" 2>&1 | tee .cache/logs/online-live.log
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)|Parse Error:' .cache/logs/online-live.log; then
  echo 'Online integration failed; refusing to deploy.' >&2
  exit 1
fi
grep -Eq 'RESULT: [0-9]+ real-WebSocket checks, 0 failures' .cache/logs/online-live.log

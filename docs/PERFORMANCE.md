# Performance and multiplayer stability

## Strategy

Keep the host authoritative, make expensive presentation work proportional to what changed, and bound queued work. The server is a relay for accepted host state, not the game's physics engine. Visual client prediction reduces perceived input latency; it does not repair a slow rendering thread or a disconnected socket.

### Terrain

- Gameplay collision changes immediately. The full 1280×470 RGBA texture is uploaded at most once per rendered frame, even when five banana fragments or reconnect replay carve many holes.
- Empty/repeated blasts do not consume history entries or trigger mesh rebuilds. Legacy snapshot histories retain all entries during replay so protocol 3 stays compatible. Known cosmetic limitation: guests currently infer blast particles/audio from crater updates, so a blast that changes no terrain may omit that guest-only audiovisual effect; damage and damage labels remain authoritative and correct. A separate bounded blast-event channel can address this without reintroducing terrain work.
- Carving uses native horizontal image fills for the interior, retaining per-pixel checks only around the scorched rim. A randomized reference-kernel test checks exact collision bitmap equality.
- Only dirty chunks rebuild. Native bitmap thresholding and row/column searches replace interpreted pixel walks; exact facet waves are cached. The geometry, normals, UVs, colors and indices are unchanged.
- Protocol 3 accepts at most 500 craters. The game now enforces that same limit instead of sending states every guest rejects. A one-time Swedish notice explains that terrain cutting has reached its limit; shots still deal damage. Restart resets the limit. A future protocol can replace this safety limit with compact terrain checkpoints.

### Rendering

The 3D viewport starts at 80% resolution on web. Sustained slow foreground frames reduce it gradually to 50%; sustained fast frames restore quality gradually. UI text, input coordinates, physics and collision remain full precision. An isolated suspension gap is ignored, while repeated very slow frames still lower quality. Particles have a fixed cap of 128. Hidden lobby controls are not relaid out at every state update.

### Network

Queued full state snapshots are coalesced without crossing control-message boundaries. The latest snapshot retains the entire canonical terrain history. Transport buffers and outbound pending states are bounded; periodic held inputs do not accumulate behind congestion. Server rate limiting tolerates short TCP bursts while still limiting sustained floods.

### Local visual prediction

Guest movement and keyboard aim/power are previewed locally with a short bounded horizon, then reconciled to authoritative snapshots. Opposing visual correction cannot overpower a newly accepted local movement or keyboard-aim step. Only grounded horizontal movement is predicted; jumping, projectiles, hits, HP and terrain remain host-confirmed. Prediction clears when the turn, phase, terrain, connection or control eligibility changes, and stops on stale state. No new protocol fields or authoritative input replay are introduced.

## Reproducible checks

Run the full checked export with `bash scripts/build-web.sh`, the real socket suite with `bash scripts/test-online.sh`, and server tests with `(cd online-server && npm test)`.

Additional CPU profiling:

- `godot --headless --path . --script tests/benchmark_terrain.gd`
- `godot --headless --path . --script tests/performance_review.gd -- --mesh`

Set XDG cache/config/data paths to writable directories when needed. The benchmark's optional baseline verification requires a separately saved original Terrain3D.gd, as documented in that script.

## Measured terrain CPU result, 2026-10-05

Median milliseconds, 15 samples across five maps, same native headless runtime:

| Rebuild | Before | After |
| --- | ---: | ---: |
| Initial terrain | 68.15 | 29.30 |
| Small crater | 9.83 | 2.94 |
| Large crater | 17.73 | 6.40 |
| Five-crater batch | 22.50 | 7.57 |

The original and optimized complete mesh buffers matched in 24 comparisons. Five same-frame terrain modifications now use one full-image upload instead of five. These are CPU measurements and verified transfer counts, not browser FPS claims. Headless tests do not measure WebGL upload cost, real-device frame pacing, Safari behavior or residential-network latency.

## Final verification

The checked web export passed gameplay (37), network state (64), transport (7), prediction (33), performance guards (27), independent real-Game/3D prediction (9), expansion (128), 3D geometry (82), six-player (354), menus (99) and animation (438) assertions. The separate real-WebSocket suite passed 180 checks, including a two-second guest receive stall and reconnects. A twenty-restart soak retained the same node/mesh/surface counts.

An independent native Compatibility/software-renderer comparison ran each of the five maps for 30 seconds with six fighters and real combat: 44 shots across each complete 150-second run, with no freeze. Fixed-resolution map setup was faster after the patch. Frame times remained software-rasterizer-bound and varied by map (baseline median 79–91 ms, patched 78–86 ms), so this does not establish smooth real-browser performance. The adaptive-resolution run completed separately. Testing on the players' actual browsers and GPUs remains necessary.

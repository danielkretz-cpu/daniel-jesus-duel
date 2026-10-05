extends SceneTree
const Predictor = preload("res://ClientPrediction.gd")
class DummyNet:
	var seat := 1
class DummyGame:
	const WW := 1280
	var online := true
	var net = DummyNet.new()
	var active := 1
	var turn := 2
	var phase := "aim"
	var map_id := 0
	var craters: Array = []
	var angle := 46.0
	var power := 70.0
	var _charge_active := false
	var _charge_power := 12.0
	var _released_context := ""
	var move_left := 170.0
	var _state_age := 0.0
	var _host_focused := true
	var _pending_aim: Array = []
	var help_open := false
	var connected := true
	var wall := false
	var ledge := false
	var held := {}
	var fighters := [{"pos": Vector2(50, 300), "face": 1.0, "ground": true, "hp": 100, "vel": Vector2.ZERO}, {"pos": Vector2(100, 300), "face": 1.0, "ground": true, "hp": 100, "vel": Vector2.ZERO}]
	func _charge_key() -> String:
		return "%d/%d/%s" % [turn, active, phase]
	func _can_control() -> bool:
		return connected and not help_open and phase == "aim" and active == net.seat
	func _held_value(action: String, _key1: int, _key2: int) -> float:
		return float(held.get(action, 0.0))
	func _solid(p: Vector2) -> bool:
		return (wall and p.x >= 130 and p.y >= 0) or (p.y >= 300 and not (ledge and p.x > 115))
	func _is_grounded(p: Vector2) -> bool:
		return _solid(p + Vector2(0, 2))
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func run() -> void:
	var game = DummyGame.new()
	var prediction = Predictor.new()
	var pristine: Array = game.fighters.duplicate(true)
	game.held = {"right": 1.0, "angle_up": 1.0, "power_up": 1.0}
	prediction.update(game, 0.1)
	check(prediction.position_for(game, 1).x > 109 and prediction.angle_for(game) > 50 and prediction.power_for(game) > 74, "Movement and keyboard aim respond before a round trip")
	check(game.fighters == pristine and game.angle == 46 and game.power == 70 and game.move_left == 170, "Prediction never mutates authoritative position, health, velocity, aim or movement budget")
	check(prediction.position_for(game, 0) == game.fighters[0].pos, "Other fighters remain fully authoritative")
	var forward: Vector2 = prediction.position_for(game, 1)
	game.held = {"left": 1.0}
	prediction.update(game, 0.05)
	check(prediction.position_for(game, 1).x < forward.x and prediction.face_for(game, 1) == -1, "Input reversal changes predicted motion and facing immediately")
	prediction.reset()
	game.held = {"right": 1.0}
	prediction.update(game, 1.0)
	check(prediction.position_for(game, 1).x <= 126.251, "One-second stalled frame cannot exceed the 250 ms prediction horizon")
	prediction.update(game, 1.0)
	check(prediction.position_for(game, 1).x <= 126.251, "Repeated frames without snapshots cannot extrapolate indefinitely")
	game._state_age = 0.6
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Stale authority immediately disables speculative pose")
	game._state_age = 0.0
	prediction.reset()
	game.wall = true
	prediction.update(game, 0.25)
	check(prediction.position_for(game, 1).x < 122, "Collision microsteps cannot walk through a wall even on a slow frame")
	game.wall = false
	game.ledge = true
	prediction.reset()
	prediction.update(game, 0.25)
	check(prediction.position_for(game, 1).x <= 115, "Ground prediction stops at a ledge instead of inventing fall physics")
	game.ledge = false
	game.move_left = 3
	prediction.reset()
	prediction.update(game, 0.25)
	check(prediction.position_for(game, 1).x <= 103.001 and game.move_left == 3, "Prediction respects remaining movement without spending canonical budget")
	game.move_left = 170
	game.angle = 84
	game.power = 99
	game.held = {"angle_up": 1.0, "power_up": 1.0}
	prediction.reset()
	prediction.update(game, 0.1)
	check(prediction.angle_for(game) == 85 and prediction.power_for(game) == 100, "Local aim and power obey canonical limits")
	game._pending_aim = [-1.0, 33.0]
	prediction.update(game, 0.01)
	check(prediction.angle_for(game) == 33 and prediction.face_for(game, 1) == -1, "Pending pointer aim wins over keyboard prediction")
	game._pending_aim.clear()
	game.held = {"right": 1.0}
	prediction.reset()
	prediction.update(game, 0.1)
	game.craters.append([100, 300, 30])
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Terrain version change cancels stale collision prediction before rendering")
	prediction.reconcile(game)
	game.fighters[1].ground = false
	game.fighters[1].pos = Vector2(102, 280)
	prediction.reconcile(game)
	prediction.update(game, 0.1)
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Jump and airborne trajectories remain authoritative")
	game.fighters[1].ground = true
	game.fighters[1].pos = Vector2(100, 300)
	prediction.reset()
	prediction.update(game, 0.1)
	game.help_open = true
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Help or cancellation immediately removes local prediction")
	game.help_open = false
	game.connected = false
	prediction.update(game, 0.1)
	check(not prediction._active, "Disconnect clears pending presentation state")
	game.connected = true
	prediction.reconcile(game)
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Reconnect seeds canonical state without replaying held movement")
	prediction.update(game, 0.1)
	game.turn += 1
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Turn changes discard previous turn prediction")
	prediction.reconcile(game)
	game.fighters[1].pos = Vector2(700, 300)
	prediction.reconcile(game)
	check(prediction.position_for(game, 1) == game.fighters[1].pos, "Large authoritative corrections snap safely instead of sliding across terrain")
	game.angle = 46
	game.power = 70
	game.held = {"angle_up": 1.0, "power_up": 1.0}
	prediction.reset()
	prediction.update(game, 0.1)
	var preview_angle: float = prediction.angle_for(game)
	var preview_power: float = prediction.power_for(game)
	prediction.reconcile(game)
	check(is_equal_approx(prediction.angle_for(game), preview_angle) and is_equal_approx(prediction.power_for(game), preview_power), "Fresh snapshot preserves aim/power preview for smooth correction")
	game.held.clear()
	for _i in range(60):
		prediction.update(game, 1.0 / 120.0)
	check(absf(prediction.angle_for(game) - game.angle) < 0.01 and absf(prediction.power_for(game) - game.power) < 0.01, "Aim/power correction converges to authority after controls release")
	game.held = {"right": 1.0}
	game.fighters[1].pos = Vector2(100, 300)
	game.angle = 46
	game.power = 70
	game.held.clear()
	prediction.reset()
	prediction.update(game, 0.0)
	game.fighters[1].pos = Vector2(120, 300)
	game.angle = 56
	game.power = 80
	prediction.reconcile(game)
	var corrected_position: Vector2 = prediction.position_for(game, 1)
	var corrected_angle: float = prediction.angle_for(game)
	var corrected_power: float = prediction.power_for(game)
	game.held = {"left": 1.0, "angle_down": 1.0, "power_down": 1.0}
	prediction.update(game, 1.0 / 60.0)
	check(prediction.position_for(game, 1).x < corrected_position.x, "A 20-pixel correction cannot push the actor right on fresh left input")
	check(prediction.angle_for(game) < corrected_angle and prediction.power_for(game) < corrected_power, "Angular/power correction cannot overpower fresh reversed keyboard input")
	check(game.fighters[1].pos == Vector2(120, 300) and game.angle == 56 and game.power == 80, "Direction-aware reconciliation still leaves authority untouched")
	game.held.clear()
	for _i in range(90):
		prediction.update(game, 1.0 / 120.0)
	check(prediction.position_for(game, 1).distance_to(Vector2(118.25, 300)) < 0.02 and absf(prediction._correction.x) < 0.02, "Correction resumes normal convergence when reversal input is released")
	game.held = {"right": 1.0}
	for latency in [0.05, 0.1, 0.25, 0.45]:
		game.fighters[1].pos = Vector2(100, 300)
		game._state_age = 0
		prediction.reset()
		var elapsed := 0.0
		while elapsed < latency:
			prediction.update(game, 1.0 / 120.0)
			elapsed += 1.0 / 120.0
			game._state_age = elapsed
		var before: Vector2 = prediction.position_for(game, 1)
		check(before.x >= 100 and before.x <= 126.251, "Prediction remains bounded at %.0f ms snapshot delay" % (latency * 1000))
		game.fighters[1].pos = Vector2(110, 300)
		game._state_age = 0
		prediction.reconcile(game)
		game.held.clear()
		for _i in range(60):
			prediction.update(game, 1.0 / 120.0)
		check(prediction.position_for(game, 1).distance_to(game.fighters[1].pos) < 0.02, "Visual correction converges after %.0f ms delay without authority mutation" % (latency * 1000))
		game.held = {"right": 1.0}
	print("RESULT: %d prediction checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

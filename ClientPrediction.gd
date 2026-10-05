extends RefCounted
## Presentation-only guest prediction. Never writes fighters, gameplay or input.
## No rollback/ack replay: the host alone owns damage, jumps and terrain.
const HORIZON := 0.25
const STALE_AFTER := 0.5
const SPEED := 105.0
const AIM_SPEED := 44.0
const CORRECTION_RATE := 18.0
const TELEPORT_DISTANCE := 48.0
var _active := false
var _seat := -1
var _key := ""
var _age := 0.0
var _position := Vector2.ZERO
var _correction := Vector2.ZERO
var _angle := 46.0
var _power := 70.0
var _face := 1.0
var _angle_correction := 0.0
var _power_correction := 0.0
var _budget := 0.0

func reset() -> void:
	_active = false
	_seat = -1
	_key = ""
	_age = 0.0
	_correction = Vector2.ZERO
	_angle_correction = 0.0
	_power_correction = 0.0

func _eligible(game) -> bool:
	return game.online and game._host_focused and game.net != null and game.net.seat > 0 and game.net.seat == game.active and game._can_control() and game._state_age < STALE_AFTER and game.fighters[game.active].hp > 0

func _context(game) -> String:
	return "%d/%d/%s/%d/%d/%s" % [game.turn, game.active, game.phase, game.map_id, game.craters.size(), str(game.fighters[game.active].ground)]

func _seed(game) -> void:
	_active = true
	_seat = game.active
	_key = _context(game)
	_age = 0.0
	_position = game.fighters[_seat].pos
	_correction = Vector2.ZERO
	_angle_correction = 0.0
	_power_correction = 0.0
	_angle = game.angle
	_power = game.power
	_face = game.fighters[_seat].face
	_budget = game.move_left

func reconcile(game) -> void:
	if not _eligible(game):
		reset()
		return
	var position: Vector2 = game.fighters[game.active].pos
	var previous_angle := _angle + _angle_correction
	var previous_power := _power + _power_correction
	var previous := _position + _correction
	var smooth := _active and _key == _context(game) and previous.distance_to(position) < TELEPORT_DISTANCE
	_seed(game)
	if smooth:
		_correction = (previous - position).limit_length(SPEED * HORIZON)
		_angle_correction = clampf(previous_angle - _angle, -AIM_SPEED * HORIZON, AIM_SPEED * HORIZON)
		_power_correction = clampf(previous_power - _power, -AIM_SPEED * HORIZON, AIM_SPEED * HORIZON)

func update(game, delta: float) -> void:
	if not _eligible(game):
		reset()
		return
	if not _active or _key != _context(game):
		_seed(game)
	# A slow frame must not extrapolate a large leap or cut through a wall.
	var dt := minf(maxf(delta, 0.0), maxf(0.0, HORIZON - _age))
	_age += maxf(delta, 0.0)
	var blend := exp(-CORRECTION_RATE * maxf(delta, 0.0))
	var before_x := _position.x
	var before_angle := _angle
	var before_power := _power
	var direction: float = game._held_value("right", KEY_D, KEY_RIGHT) - game._held_value("left", KEY_A, KEY_LEFT)
	if bool(game.fighters[_seat].ground) and direction != 0 and _budget > 0:
		_face = direction
		# Match host collision/step-up tests at small steps even under low FPS.
		var steps := maxi(1, ceili(SPEED * dt / 2.0))
		for _i in range(steps):
			var distance := minf(SPEED * dt / steps, _budget)
			var target := _position + Vector2(direction * distance, 0)
			target.x = clampf(target.x, 20, game.WW - 20)
			var rise := 0
			while (game._solid(target + Vector2(0, -1)) or game._solid(target + Vector2(direction * 9, -9))) and rise < 10:
				target.y -= 1
				rise += 1
			# Do not predict falling/jumps. Wait for canonical air physics.
			if rise >= 10 or not game._is_grounded(target):
				break
			_position = target
			_budget = maxf(0, _budget - distance)
	else:
		if not bool(game.fighters[_seat].ground):
			_position = game.fighters[_seat].pos
			_correction = Vector2.ZERO
	_angle = clampf(_angle + (game._held_value("angle_up", KEY_W, KEY_UP) - game._held_value("angle_down", KEY_S, KEY_DOWN)) * AIM_SPEED * dt, 5, 85)
	_power = clampf(_power + (game._held_value("power_up", KEY_E, KEY_EQUAL) - game._held_value("power_down", KEY_Q, KEY_MINUS)) * AIM_SPEED * dt, 12, 100)
	# Reconciliation may correct stale visuals, but cannot overpower a fresh
	# accepted local step in the opposite direction. Collision-blocked movement
	# (zero accepted step) still converges to authority normally.
	_correction.x = _decay_correction(_correction.x, blend, _position.x - before_x)
	_correction.y *= blend
	_angle_correction = _decay_correction(_angle_correction, blend, _angle - before_angle)
	_power_correction = _decay_correction(_power_correction, blend, _power - before_power)
	if not game._pending_aim.is_empty():
		_face = float(game._pending_aim[0])
		_angle = clampf(float(game._pending_aim[1]), 5, 85)
		_angle_correction = 0.0

static func _decay_correction(error: float, blend: float, local_step: float) -> float:
	var corrected := error * blend
	if local_step != 0.0 and (corrected - error) * local_step < 0.0:
		return move_toward(error, corrected, absf(local_step) * 0.5)
	return corrected

func _show(game) -> bool:
	return _active and _eligible(game) and _key == _context(game)

func position_for(game, index: int) -> Vector2:
	if not _show(game) or index != _seat:
		return game.fighters[index].pos
	var visual := _position + _correction
	# Reconciliation must never smooth the actor into newly authoritative terrain.
	if game._solid(visual + Vector2(0, -1)) or game._solid(visual + Vector2(_face * 9, -9)):
		return _position
	return visual

func angle_for(game) -> float:
	return clampf(_angle + _angle_correction, 5, 85) if _show(game) else game.angle

func power_for(game) -> float:
	if game._charge_active or game._released_context == game._charge_key():
		return game._charge_power
	return clampf(_power + _power_correction, 12, 100) if _show(game) else game.power

func face_for(game, index: int) -> float:
	return _face if _show(game) and index == _seat else game.fighters[index].face

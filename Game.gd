extends Control
## Kraterkompisar: original terrain-bitmap artillery, built entirely in Godot.
const WW := 1280
const WH := 470
const WATER := 442.0
const GRAVITY := 470.0
const INK := Color("171a2d")
const CREAM := Color("fff3db")
const GOLD := Color("f9c95e")
const MINT := Color("91d2b0")
const PURPLE := Color("b6a4ef")
const MUTED := Color("a4a5b8")
const FONT = preload("res://assets/Regular.ttf")
const BOLD = preload("res://assets/Bold.ttf")
const NetSessionScript = preload("res://NetSession.gd")
const OnlineLobbyScript = preload("res://OnlineLobby.gd")

var terrain: Image
var terrain_texture: ImageTexture
var fighters: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var projectile: Dictionary = {}
var trail: Array[Vector2] = []
var phase := "title"
var active := 0
var turn := 1
var angle := 46.0
var power := 70.0
var weapon := 0
var wind := 0.0
var move_left := 170.0
var turn_clock := 40.0
var settle_clock := 0.0
var banner_clock := 0.0
var banner := ""
var winner := -1
var elapsed := 0.0
var shake := 0.0
var toast := ""
var toast_clock := 0.0
var hits := 0
var shots := 0
var help_open := false
var sound_on := true
var buttons: Dictionary = {}
var pointers: Dictionary = {}
var held: Dictionary = {}
var ui_scale := 1.0
var ui_origin := Vector2.ZERO
var layout_h := 800.0
var portrait := false
var world_top := 128.0
var panel_y := 620.0
var last_size := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var audio: AudioStreamPlayer
var audio_data: Dictionary = {}
var debug_enabled := false
var online := false
var net
var lobby
var craters: Array = []
var _last_received_seq := -1
var _remote_input_seq := -1
var _remote_held: Dictionary = {}
var _remote_input_age := 1.0
var _applying_remote := false
var _state_clock := 0.0
var _input_clock := 0.0
var _last_commit_key := ""
var _pending_aim: Array = []
var _online_started := false
var _host_focused := true
var _host_paused := false
var _state_age := 0.0

func _ready() -> void:
	rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	_generate_terrain()
	_spawn_fighters()
	_make_audio()
	debug_enabled = OS.get_cmdline_user_args().has("--test")
	net = NetSessionScript.new()
	add_child(net)
	lobby = OnlineLobbyScript.new()
	add_child(lobby)
	lobby.create_requested.connect(func(): net.create_room())
	lobby.join_requested.connect(func(code: String): net.join_room(code))
	lobby.leave_requested.connect(_leave_online)
	lobby.reconnect_requested.connect(func(): net.reconnect())
	lobby.copy_requested.connect(_copy_room)
	net.changed.connect(_network_changed)
	net.welcomed.connect(_network_welcome)
	net.received.connect(_network_received)
	_layout()
	if OS.has_feature("web"):
		var room_code = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
		if room_code is String and not room_code.is_empty():
			_open_online()
			lobby.code.text = room_code.to_upper()
	queue_redraw()

func _layout(view: Vector2 = Vector2.ZERO) -> void:
	if view == Vector2.ZERO:
		view = get_viewport_rect().size
	portrait = view.y / view.x > 0.8125
	ui_scale = view.x / 1280.0 if portrait else minf(view.x / 1280.0, view.y / 800.0)
	ui_origin = Vector2((view.x - 1280.0 * ui_scale) * 0.5, 0)
	layout_h = view.y / ui_scale
	world_top = 320.0 if portrait else 128.0
	panel_y = 870.0 if portrait else 620.0
	buttons.clear()
	buttons.help = Rect2(1156, 26, 44, 44)
	buttons.sound = Rect2(1098, 26, 44, 44)
	buttons.restart = Rect2(1210, 26, 44, 44)
	if portrait:
		buttons.help = Rect2(1020, 24, 100, 90)
		buttons.sound = Rect2(900, 24, 100, 90)
		buttons.restart = Rect2(1140, 24, 100, 90)
		buttons.left = Rect2(44, panel_y + 92, 160, 144)
		buttons.right = Rect2(216, panel_y + 92, 160, 144)
		buttons.jump = Rect2(390, panel_y + 92, 182, 144)
		buttons.angle_down = Rect2(44, panel_y + 336, 160, 138)
		buttons.angle_up = Rect2(410, panel_y + 336, 160, 138)
		buttons.power_down = Rect2(680, panel_y + 336, 160, 138)
		buttons.power_up = Rect2(1046, panel_y + 336, 160, 138)
		buttons.weapon = Rect2(638, panel_y + 92, 568, 144)
		buttons.fire = Rect2(44, panel_y + 552, 1162, 152)
		buttons.start = Rect2(316, world_top + 330, 648, 112)
	else:
		buttons.left = Rect2(28, panel_y + 66, 66, 62)
		buttons.right = Rect2(102, panel_y + 66, 66, 62)
		buttons.jump = Rect2(180, panel_y + 66, 92, 62)
		buttons.angle_down = Rect2(307, panel_y + 68, 48, 58)
		buttons.angle_up = Rect2(464, panel_y + 68, 48, 58)
		buttons.power_down = Rect2(547, panel_y + 68, 48, 58)
		buttons.power_up = Rect2(704, panel_y + 68, 48, 58)
		buttons.weapon = Rect2(790, panel_y + 64, 190, 66)
		buttons.fire = Rect2(1008, panel_y + 48, 244, 84)
		buttons.start = Rect2(423, world_top + 294, 434, 74)
	buttons.online = Rect2(316, world_top + 394, 648, 70) if portrait else Rect2(423, world_top + 340, 434, 56)
	if portrait:
		buttons.start = Rect2(316, world_top + 294, 648, 80)
	else:
		buttons.start = Rect2(423, world_top + 270, 434, 56)
	if lobby != null:
		lobby.place(ui_origin, ui_scale, world_top, portrait)
	buttons.close_help = Rect2(400, world_top + 344, 480, 74)
	last_size = view

func _generate_terrain() -> void:
	terrain = Image.create(WW, WH, false, Image.FORMAT_RGBA8)
	terrain.fill(Color.TRANSPARENT)
	for x in range(WW):
		var surface := int(310 + 42 * sin(float(x) / 121.0) + 23 * cos(float(x) / 63.0) - 26 * sin(float(x) / 290.0))
		# Flat little launch pads keep the opening fair.
		if abs(x - 224) < 33:
			surface = 307
		if abs(x - 1050) < 33:
			surface = 325
		for y in range(surface, WH):
			var d := y - surface
			var col := Color("45364f")
			if d < 5:
				col = Color("f5d07e")
			elif d < 14:
				col = Color("bf9b7d")
			elif d < 22:
				col = Color("906d6b")
			elif y % 44 < 2:
				col = Color("6c4765")
			elif (x * 23 + y * 53) % 191 < 3:
				col = Color("865c75")
			terrain.set_pixel(x, y, col)
	terrain_texture = ImageTexture.create_from_image(terrain)

func _spawn_fighters() -> void:
	fighters = [
		{"name": "Daniel", "pos": Vector2(224, 307), "vel": Vector2.ZERO, "hp": 100, "face": 1.0, "ground": true},
		{"name": "Jesus", "pos": Vector2(1050, 325), "vel": Vector2.ZERO, "hp": 100, "face": -1.0, "ground": true}
	]

func start_game() -> void:
	craters.clear()
	_remote_held.clear()
	_pending_aim.clear()
	_generate_terrain()
	_spawn_fighters()
	projectile.clear()
	trail.clear()
	particles.clear()
	floaters.clear()
	active = 0
	turn = 1
	winner = -1
	shots = 0
	hits = 0
	angle = 46.0
	power = 70.0
	weapon = 0
	phase = "aim"
	wind = rng.randf_range(-23, 23)
	move_left = 170
	turn_clock = 40
	banner = "Daniel börjar!"
	banner_clock = 2.0
	help_open = false
	pointers.clear()
	held.clear()
	_sound("start")

func _solid(p: Vector2) -> bool:
	if p.x < 0 or p.x >= WW or p.y < 0 or p.y >= WH:
		return false
	return terrain.get_pixel(int(p.x), int(p.y)).a > 0.5

func _is_grounded(p: Vector2) -> bool:
	return _solid(p + Vector2(-7, 2)) or _solid(p + Vector2(7, 2)) or _solid(p + Vector2(0, 2))

func _move_character(direction: float, delta: float) -> void:
	if move_left <= 0:
		return
	var f: Dictionary = fighters[active]
	f.face = direction
	var step := direction * minf(105.0 * delta, move_left)
	var target: Vector2 = f.pos + Vector2(step, 0)
	target.x = clampf(target.x, 20, WW - 20)
	var can_move := true
	if f.ground:
		var rise := 0
		while (_solid(target + Vector2(0, -1)) or _solid(target + Vector2(direction * 9, -9))) and rise < 10:
			target.y -= 1
			rise += 1
		can_move = rise < 10
	elif _solid(target + Vector2(direction * 9, -15)):
		can_move = false
	if can_move:
		f.pos = target
		move_left = maxf(0, move_left - absf(step))

func _jump() -> void:
	if online and not _applying_remote:
		if not _can_control():
			return
		if net.seat == 1:
			_send_guest_input("jump")
			return
	if phase != "aim" or move_left < 20 or not fighters[active].ground:
		return
	fighters[active].vel = Vector2(fighters[active].face * 65, -285)
	fighters[active].ground = false
	move_left -= 20
	_sound("jump")

func _physics_process(delta: float) -> void:
	if online:
		if not net.together() or net.seat != 0 or not _host_focused:
			return
		_remote_input_age += delta
		if _remote_input_age > 0.6:
			_remote_held.clear()
	if phase == "title" or phase == "over" or (help_open and not online):
		return
	if phase == "aim":
		turn_clock -= delta
		if turn_clock <= 0:
			phase = "settle"
			settle_clock = 1.0
			banner = "Tiden tog slut"
			banner_clock = 1.8
		else:
			var direction := _held_value("right", KEY_D, KEY_RIGHT) - _held_value("left", KEY_A, KEY_LEFT)
			if direction != 0:
				_move_character(direction, delta)
			angle = clampf(angle + (_held_value("angle_up", KEY_W, KEY_UP) - _held_value("angle_down", KEY_S, KEY_DOWN)) * delta * 44, 5, 85)
			power = clampf(power + (_held_value("power_up", KEY_E, KEY_EQUAL) - _held_value("power_down", KEY_Q, KEY_MINUS)) * delta * 44, 12, 100)
	for i in range(2):
		_step_fighter(i, delta)
	if phase == "flying":
		_step_projectile(delta)
	elif phase == "settle":
		settle_clock -= delta
		if settle_clock <= 0 and _everyone_settled():
			_finish_turn()
		elif settle_clock < -4:
			_finish_turn()
	if phase == "aim" and (fighters[0].hp <= 0 or fighters[1].hp <= 0):
		_check_winner()

func _held_value(action: String, key1: int, key2: int) -> float:
	if online and active == 1 and net.seat == 0:
		return float(_remote_held.get(action, 0.0))
	if online and (help_open or not _can_control()):
		return 0.0
	return 1.0 if held.get(action, false) or Input.is_physical_key_pressed(key1) or Input.is_physical_key_pressed(key2) else 0.0

func _step_fighter(i: int, delta: float) -> void:
	var f: Dictionary = fighters[i]
	if f.hp <= 0:
		return
	var p: Vector2 = f.pos
	var v: Vector2 = f.vel
	var on_ground := _is_grounded(p) and v.y >= 0
	if on_ground and v.length() < 25:
		v = Vector2.ZERO
	else:
		v.y += 720 * delta
		var steps := maxi(1, int(v.length() * delta / 3) + 1)
		for _n in range(steps):
			var next := p + v * delta / steps
			if next.x < 15 or next.x > WW - 15:
				v.x = 0
				next.x = clampf(next.x, 15, WW - 15)
			if _solid(next + Vector2(0, -15)):
				v.x = -v.x * 0.25
				next.x = p.x
			if v.y >= 0 and (_solid(next) or _solid(next + Vector2(-6, 0)) or _solid(next + Vector2(6, 0))):
				while _solid(next) and next.y > 0:
					next.y -= 1
				if v.y > 430:
					var damage := mini(20, int((v.y - 430) / 14))
					_damage(i, damage)
				v = Vector2.ZERO
				on_ground = true
			p = next
			if on_ground:
				break
	f.pos = p
	f.vel = v
	f.ground = on_ground
	if p.y > WATER + 10 and f.hp > 0:
		_damage(i, 100)
		_emit(p, MINT, 26, 150)
		_sound("splash")
		toast = "%s tog ett dopp!" % f.name
		toast_clock = 2.5

func _everyone_settled() -> bool:
	for f in fighters:
		if f.hp > 0 and not f.ground and f.vel.length() > 2:
			return false
	return true

func _direction() -> Vector2:
	return Vector2(cos(deg_to_rad(angle)) * fighters[active].face, -sin(deg_to_rad(angle)))

func fire() -> void:
	if online and not _applying_remote:
		if not _can_control():
			return
		if net.seat == 1:
			_send_guest_input("fire")
			return
	if phase != "aim" or (help_open and not _applying_remote):
		return
	var d := _direction()
	var start: Vector2 = fighters[active].pos + Vector2(0, -27) + d * 30
	projectile = {"pos": start, "vel": d * (250 + power * 5.2), "age": 0.0, "weapon": weapon, "bounces": 0}
	trail.clear()
	shots += 1
	phase = "flying"
	pointers.clear()
	held.clear()
	_emit(start, GOLD, 9, 80)
	_sound("fire")

func _step_projectile(delta: float) -> void:
	if projectile.is_empty():
		return
	projectile.age += delta
	projectile.vel += Vector2(wind, GRAVITY) * delta
	var steps := maxi(1, int(projectile.vel.length() * delta / 3) + 1)
	for _n in range(steps):
		var before: Vector2 = projectile.pos
		var next: Vector2 = before + projectile.vel * delta / steps
		var hit_character := false
		for i in range(2):
			if fighters[i].hp > 0 and (i != active or projectile.age > 0.3) and next.distance_to(fighters[i].pos + Vector2(0, -19)) < 20:
				hit_character = true
		if _solid(next) or hit_character:
			if projectile.weapon == 1 and not hit_character and projectile.bounces < 4 and projectile.age < 2.7:
				var normal := Vector2(float(int(_solid(next + Vector2(-4, 0))) - int(_solid(next + Vector2(4, 0)))), float(int(_solid(next + Vector2(0, -4))) - int(_solid(next + Vector2(0, 4)))))
				if normal.length() < 0.1:
					normal = Vector2.UP
				projectile.vel = projectile.vel.bounce(normal.normalized()) * 0.48
				projectile.pos = before + normal.normalized() * 5
				projectile.bounces += 1
				_sound("bounce")
				break
			_explode(next, 72.0 if projectile.weapon == 1 else 57.0)
			return
		projectile.pos = next
		if next.y > WATER:
			_emit(Vector2(next.x, WATER), MINT, 26, 160)
			_sound("splash")
			_end_shot()
			return
		if next.x < -100 or next.x > WW + 100 or next.y < -1100:
			_end_shot()
			return
	if projectile.age > (2.9 if projectile.weapon == 1 else 8.0):
		_explode(projectile.pos, 72 if projectile.weapon == 1 else 57)
		return
	trail.append(projectile.pos)
	if trail.size() > 28:
		trail.pop_front()

func _explode(p: Vector2, radius: float) -> void:
	carve(p, radius)
	shake = 9.0
	for i in range(2):
		var f: Dictionary = fighters[i]
		var dist: float = p.distance_to(f.pos + Vector2(0, -16))
		if dist < radius + 35 and f.hp > 0:
			var amount := int(clampf(52 * (1.0 - dist / (radius + 38)), 3, 52))
			_damage(i, amount)
			hits += 1
			var away: Vector2 = (f.pos + Vector2(0, -25) - p).normalized()
			f.vel = Vector2(away.x * 220, -170 - amount * 2.0)
			f.ground = false
	_emit(p, GOLD, 28, 270)
	_emit(p, Color("f29c72"), 20, 180)
	_emit(p, Color("a0788c"), 20, 140)
	_sound("boom")
	_end_shot()

func carve(p: Vector2, radius: float) -> void:
	craters.append([p.x, p.y, radius])
	for y in range(maxi(0, int(p.y - radius - 3)), mini(WH, int(p.y + radius + 4))):
		for x in range(maxi(0, int(p.x - radius - 3)), mini(WW, int(p.x + radius + 4))):
			var distance := Vector2(x, y).distance_to(p)
			if distance < radius:
				terrain.set_pixel(x, y, Color.TRANSPARENT)
			elif distance < radius + 3 and _solid(Vector2(x, y)):
				terrain.set_pixel(x, y, Color("9c7180"))
	terrain_texture.update(terrain)

func _damage(i: int, amount: int) -> void:
	if amount <= 0:
		return
	fighters[i].hp = maxi(0, fighters[i].hp - amount)
	floaters.append({"pos": fighters[i].pos + Vector2(0, -63), "text": "−%d" % amount, "life": 1.7, "color": GOLD})

func _end_shot() -> void:
	projectile.clear()
	phase = "settle"
	settle_clock = 1.7

func _finish_turn() -> void:
	_remote_held.clear()
	_pending_aim.clear()
	if _check_winner():
		return
	active = 1 - active
	turn += 1
	phase = "aim"
	move_left = 170
	turn_clock = 40
	wind = rng.randf_range(-32, 32)
	fighters[active].face = 1.0 if fighters[1 - active].pos.x > fighters[active].pos.x else -1.0
	angle = 46
	power = 70
	trail.clear()
	banner = "%s, din tur!" % fighters[active].name
	banner_clock = 2.0
	_sound("turn")

func _check_winner() -> bool:
	if fighters[0].hp > 0 and fighters[1].hp > 0:
		return false
	winner = -1 if fighters[0].hp <= 0 and fighters[1].hp <= 0 else (0 if fighters[0].hp > 0 else 1)
	phase = "over"
	banner_clock = 0
	_sound("win")
	for n in range(60):
		particles.append({"pos": Vector2(rng.randf_range(180, 1100), rng.randf_range(-150, 80)), "vel": Vector2(rng.randf_range(-30, 30), rng.randf_range(15, 80)), "life": 5.0, "max": 5.0, "color": [MINT, PURPLE, GOLD][n % 3], "size": rng.randf_range(3, 7)})
	return true

func _process(delta: float) -> void:
	_network_tick(delta)
	elapsed += delta
	if last_size != get_viewport_rect().size:
		_layout()
	banner_clock = maxf(0, banner_clock - delta)
	toast_clock = maxf(0, toast_clock - delta)
	shake = maxf(0, shake - delta * 27)
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].pos += particles[i].vel * delta
		particles[i].vel.y += delta * (30 if phase == "over" else 290)
		if particles[i].life <= 0:
			particles.remove_at(i)
	for i in range(floaters.size() - 1, -1, -1):
		floaters[i].life -= delta
		floaters[i].pos.y -= delta * 27
		if floaters[i].life <= 0:
			floaters.remove_at(i)
	queue_redraw()

func _emit(p: Vector2, col: Color, count: int, speed: float) -> void:
	for n in range(count):
		var life := rng.randf_range(0.35, 0.95)
		particles.append({"pos": p, "vel": Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(speed * 0.2, speed), "life": life, "max": life, "color": col, "size": rng.randf_range(2, 6)})

func _input(event: InputEvent) -> void:
	if lobby != null and lobby.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				if phase == "title" or phase == "over":
					_start_action()
				else:
					fire()
			KEY_J: _jump()
			KEY_TAB: _weapon_action()
			KEY_ESCAPE: help_open = not help_open
			KEY_R: _restart_action()
			KEY_M: sound_on = not sound_on
			KEY_ENTER:
				if phase == "title" or phase == "over":
					_start_action()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer((event.position - ui_origin) / ui_scale, -1, event.pressed)
	elif event is InputEventMouseMotion and pointers.has(-1) and pointers[-1] == "aim":
		_aim_at((event.position - ui_origin) / ui_scale)
	elif event is InputEventScreenTouch:
		_pointer((event.position - ui_origin) / ui_scale, event.index, event.pressed)
	elif event is InputEventScreenDrag and pointers.get(event.index, "") == "aim":
		_aim_at((event.position - ui_origin) / ui_scale)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pointers.clear()
		held.clear()
		_remote_held.clear()
		_host_focused = false
		if online and net != null and net.together():
			if net.seat == 0:
				_send_state(true)
			else:
				_send_guest_input()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_host_focused = true
		_remote_held.clear()
		if online and net != null and net.together() and net.seat == 0:
			_send_state(true)
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN] and online and net != null:
		_refresh_network_overlay()

func _pointer(p: Vector2, id: int, pressed: bool) -> void:
	if not pressed:
		pointers.erase(id)
		_refresh_held()
		return
	if help_open:
		if buttons.close_help.has_point(p) or buttons.help.has_point(p):
			help_open = false
		return
	if buttons.help.has_point(p):
		help_open = true
		return
	if buttons.sound.has_point(p):
		sound_on = not sound_on
		return
	if buttons.restart.has_point(p):
		_restart_action()
		return
	if phase == "title" or phase == "over":
		if phase == "title" and buttons.online.has_point(p):
			_open_online()
		elif buttons.start.has_point(p):
			_start_action()
		return
	if phase != "aim" or not _can_control():
		return
	for action in ["left", "right", "jump", "angle_down", "angle_up", "power_down", "power_up", "weapon", "fire"]:
		if buttons[action].has_point(p):
			match action:
				"jump": _jump()
				"weapon": _weapon_action()
				"fire": fire()
				_:
					pointers[id] = action
					_refresh_held()
			return
	if p.y > world_top and p.y < world_top + WATER:
		pointers[id] = "aim"
		_aim_at(p)

func _refresh_held() -> void:
	held.clear()
	for action in pointers.values():
		held[action] = true

func _aim_at(p: Vector2) -> void:
	if not _can_control():
		return
	var delta: Vector2 = p - Vector2(0, world_top) - fighters[active].pos + Vector2(0, 25)
	if delta.length() < 15:
		return
	if absf(delta.x) > 0.01:
		fighters[active].face = signf(delta.x)
	angle = clampf(rad_to_deg(atan2(-delta.y, absf(delta.x))), 5, 85)
	if online and net.seat == 1:
		_pending_aim = [fighters[active].face, angle]

func _restart_action() -> void:
	if online:
		_leave_online()
		return
	# One click returns to the title; a separate start prevents accidental resets.
	if phase != "title":
		phase = "title"
		projectile.clear()
		pointers.clear()
		held.clear()
	else:
		start_game()

func _round_rect(rect: Rect2, color: Color, radius: float = 12, border: Color = Color.TRANSPARENT, border_width: int = 0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.border_color = border
	style.set_border_width_all(border_width)
	draw_style_box(style, rect)

func _text(text: String, pos: Vector2, size_px: int, color: Color = CREAM, bold: bool = false, center: bool = false) -> void:
	var font: Font = BOLD if bold else FONT
	var origin := pos
	if center:
		origin.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x * 0.5
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _draw() -> void:
	draw_rect(get_viewport_rect(), INK)
	draw_set_transform(ui_origin, 0, Vector2.ONE * ui_scale)
	draw_rect(Rect2(0, 0, 1280, layout_h), INK)
	_draw_header()
	var wobble := Vector2(sin(elapsed * 66), cos(elapsed * 52)) * shake
	draw_set_transform((Vector2(0, world_top) + wobble) * ui_scale + ui_origin, 0, Vector2.ONE * ui_scale)
	_draw_world()
	draw_set_transform(ui_origin, 0, Vector2.ONE * ui_scale)
	_draw_controls()
	if phase == "title":
		_draw_title()
	elif phase == "over":
		_draw_victory()
	elif banner_clock > 0:
		var alpha := minf(1, banner_clock * 2)
		_round_rect(Rect2(420, world_top + 18, 440, 56), Color(0.09, 0.10, 0.17, alpha * 0.96), 28)
		_text(banner, Vector2(640, world_top + 55), 24, Color(1, 0.95, 0.85, alpha), true, true)
	if toast_clock > 0 and phase != "over":
		_text(toast, Vector2(640, world_top + 102), 22, CREAM, true, true)
	if help_open:
		_draw_help()

func _online_header(include_room: bool) -> String:
	if net == null or net.seat < 0:
		return "ONLINE · PRIVAT RUM"
	var role := "DANIEL" if net.seat == 0 else "JESUS"
	return "ONLINE · %s · DU ÄR %s" % [net.room, role] if include_room else "ONLINE · DU ÄR " + role

func _draw_header() -> void:
	if portrait:
		_text("KRATERKOMPISAR", Vector2(44, 69), 40, GOLD, true)
		_text("DANIEL × JESUS", Vector2(46, 101), 22, MUTED, true)
		_text("?", Vector2(1070, 82), 48, CREAM, true, true)
		_text("♫" if sound_on else "♪", Vector2(950, 82), 48, MINT if sound_on else MUTED, true, true)
		_text("↻", Vector2(1190, 83), 54, MUTED, false, true)
		for i in range(2):
			var xx := 44.0 + i * 604
			var col: Color = MINT if i == 0 else PURPLE
			var hp: int = fighters[i].hp if fighters.size() == 2 else 100
			_round_rect(Rect2(xx, 134, 560, 112), Color("26283e"), 22, col if phase == "aim" and active == i else Color("3a3b50"), 3)
			_text("DANIEL" if i == 0 else "JESUS", Vector2(xx + 28, 182), 31, CREAM, true)
			_text("%d" % hp, Vector2(xx + 506, 182), 33, col, true, true)
			_round_rect(Rect2(xx + 28, 209, 504, 10), Color("414154"), 5)
			if hp > 0:
				_round_rect(Rect2(xx + 28, 209, 504.0 * hp / 100, 10), col, 5)
		_text(_online_header(false) if online else "TURVIS PÅ SAMMA SKÄRM", Vector2(640, 291), 24, MUTED, true, true)
		return
	_text("KRATER", Vector2(28, 42), 26, CREAM, true)
	_text("KOMPISAR", Vector2(143, 42), 26, GOLD, true)
	_text("DANIEL × JESUS", Vector2(30, 67), 12, MUTED, true)
	_text("?", Vector2(1178, 56), 24, CREAM, true, true)
	_text("♫" if sound_on else "♪", Vector2(1120, 56), 25, MINT if sound_on else MUTED, true, true)
	_text("↻", Vector2(1232, 58), 30, MUTED, false, true)
	for i in range(2):
		var xx := 400.0 + i * 350
		var col: Color = MINT if i == 0 else PURPLE
		var hp: int = fighters[i].hp if fighters.size() == 2 else 100
		var highlight := phase == "aim" and i == active
		_round_rect(Rect2(xx, 23, 310, 66), Color("26283e"), 15, col if highlight else Color("3a3b50"), 2 if highlight else 1)
		draw_circle(Vector2(xx + 27, 46), 7, col)
		_text("DANIEL" if i == 0 else "JESUS", Vector2(xx + 45, 51), 17, CREAM, true)
		_text("%d" % hp, Vector2(xx + 282, 51), 18, col, true, true)
		_round_rect(Rect2(xx + 21, 65, 268, 6), Color("414154"), 3)
		if hp > 0:
			_round_rect(Rect2(xx + 21, 65, 268.0 * hp / 100, 6), col, 3)
	if portrait:
		_text("EN LITEN Ö. TVÅ STORA EGON.", Vector2(640, 170), 32, CREAM, true, true)
		_text("Turvis på samma skärm", Vector2(640, 212), 24, MUTED, false, true)
	else:
		_text("Ö 01  /  SKYMNINGSSKÄRET", Vector2(28, 113), 13, MUTED, true)
		var mode_text := _online_header(true) if online else "LOKAL DUELL  •  2 SPELARE"
		_text(mode_text, Vector2(1252, 113) - Vector2(FONT.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 0), 13, MUTED)

func _draw_world() -> void:
	# A warm, hand-drawn archipelago, all original vector art.
	draw_rect(Rect2(0, 0, WW, WH), Color("eab0a1"))
	for n in range(12):
		draw_rect(Rect2(0, n * 39.2, WW, 40), Color("ebc3ab").lerp(Color("bc8d9e"), float(n) / 14))
	draw_circle(Vector2(642, 154), 91, Color("f6d898"))
	draw_circle(Vector2(642, 154), 71, Color("f9e0a7"))
	for c in [[Vector2(139, 73), 1.0], [Vector2(904, 105), 0.75], [Vector2(1160, 50), 0.58]]:
		var cp: Vector2 = c[0] + Vector2(sin(elapsed * 0.06 + c[0].x) * 8, 0)
		for n in range(4):
			draw_circle(cp + Vector2(n * 32 * c[1], sin(n * 2.0) * 8), 22 * c[1], Color("f0cbbb"))
	var back := PackedVector2Array([Vector2(0, 305), Vector2(75, 225), Vector2(182, 268), Vector2(292, 163), Vector2(430, 297), Vector2(546, 237), Vector2(671, 311), Vector2(822, 193), Vector2(950, 274), Vector2(1108, 183), Vector2(1280, 279), Vector2(1280, WH), Vector2(0, WH)])
	draw_colored_polygon(back, Color("a58c9e"))
	var front := PackedVector2Array([Vector2(0, 355), Vector2(158, 308), Vector2(308, 341), Vector2(483, 279), Vector2(692, 337), Vector2(891, 282), Vector2(1104, 350), Vector2(1280, 301), Vector2(1280, WH), Vector2(0, WH)])
	draw_colored_polygon(front, Color("8c7a94"))
	# Distant lighthouse and little birds.
	draw_colored_polygon(PackedVector2Array([Vector2(855, 238), Vector2(871, 238), Vector2(867, 199), Vector2(859, 199)]), Color("ead3b7"))
	draw_rect(Rect2(856, 192, 15, 9), Color("535165"))
	draw_colored_polygon(PackedVector2Array([Vector2(853, 192), Vector2(863, 184), Vector2(873, 192)]), Color("535165"))
	for n in range(4):
		var bp := Vector2(434 + n * 37, 103 + sin(n * 3.3) * 19)
		draw_polyline(PackedVector2Array([bp + Vector2(-6, -3), bp, bp + Vector2(6, -3)]), Color("9c7787"), 2, true)
	draw_texture(terrain_texture, Vector2.ZERO)
	# Flowers and tufts survive only while their ground survives.
	for x in [64, 128, 350, 392, 748, 799, 925, 1178, 1202]:
		var y := 0
		while y < WH and not _solid(Vector2(x, y)):
			y += 1
		if y < WATER - 5:
			draw_line(Vector2(x, y), Vector2(x - 4, y - 13), Color("ded395"), 2, true)
			draw_line(Vector2(x, y), Vector2(x + 5, y - 10), Color("c6c38e"), 2, true)
			if x % 2 == 0:
				draw_circle(Vector2(x - 4, y - 14), 3, CREAM)
	if phase == "aim":
		_draw_aim()
	for n in range(trail.size()):
		if trail[n].y > 0:
			draw_circle(trail[n], 2.8 * float(n + 1) / maxf(1, trail.size()), Color(1, 0.95, 0.82, 0.45 * float(n + 1) / maxf(1, trail.size())))
	for i in range(2):
		if fighters[i].hp > 0:
			_draw_character(i, fighters[i].pos, 1.25 if portrait else 1.0, fighters[i].face, true)
		elif fighters[i].pos.y < WATER:
			var p: Vector2 = fighters[i].pos
			draw_line(p + Vector2(-8, 0), p + Vector2(8, -20), CREAM, 4, true)
			draw_line(p + Vector2(8, 0), p + Vector2(-8, -20), CREAM, 4, true)
	if not projectile.is_empty():
		var p: Vector2 = projectile.pos
		if p.y >= 3:
			if projectile.weapon == 0:
				draw_circle(p, 7, CREAM)
				draw_circle(p, 4, GOLD)
			else:
				draw_circle(p, 10, MINT)
				draw_line(p + Vector2(0, -8), p + Vector2(4, -15), CREAM, 2, true)
				draw_circle(p + Vector2(4, -15), 3, GOLD)
		else:
			_text("•  %dm" % int(-p.y / 10), Vector2(clampf(p.x, 50, 1230), 22), 18, INK, true, true)
	for part in particles:
		var col: Color = part.color
		col.a = minf(1, part.life / part.max * 2)
		draw_circle(part.pos, part.size, col)
	for f in floaters:
		_text(f.text, f.pos, 25, f.color, true, true)
	# Water moves independently of the destructible bitmap.
	draw_rect(Rect2(0, WATER, WW, WH - WATER), Color("426d7a"))
	var wave := PackedVector2Array()
	for x in range(0, WW + 1, 8):
		wave.append(Vector2(x, WATER + sin(x * 0.035 + elapsed * 2.0) * 2.0))
	draw_polyline(wave, Color("94bfba"), 4, true)
	for n in range(15):
		var x := fmod(n * 97 + elapsed * 8, 1280)
		draw_line(Vector2(x, 454 + (n % 3) * 5), Vector2(x + 31, 454 + (n % 3) * 5), Color("69959b"), 2)
	# Wind badge.
	_round_rect(Rect2(1074, 18, 179, 42), Color(0.99, 0.94, 0.84, 0.84), 21)
	_text("VIND  %s %d" % ["→" if wind >= 0 else "←", int(absf(wind))], Vector2(1164, 46), 16, INK, true, true)

func _draw_character(i: int, p: Vector2, s: float, face: float, label: bool) -> void:
	var bounce := sin(elapsed * 3.3 + i) * 1.2
	var center := p + Vector2(0, -24 * s + bounce)
	var col: Color = MINT if i == 0 else PURPLE
	draw_ellipse_shadow(p + Vector2(0, 2 * s), Vector2(22, 5) * s)
	# Boots and short limbs.
	for side in [-1, 1]:
		draw_line(p + Vector2(side * 7, -12) * s, p + Vector2(side * 10, -4) * s, Color("46405e"), 7 * s, true)
		draw_line(p + Vector2(side * 10, -3) * s, p + Vector2(side * 16, -3) * s, INK, 6 * s, true)
	if i == 0:
		_round_rect(Rect2(center + Vector2(-16, -3) * s, Vector2(32, 25) * s), Color("70ad98"), 8 * s)
		draw_circle(center + Vector2(0, -15) * s, 17 * s, Color("edbd94"))
		draw_arc(center + Vector2(-1, -20) * s, 15 * s, PI, TAU + 0.25, 20, Color("5c4a43"), 8 * s, true)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-19, -25) * s, center + Vector2(12, -27) * s, center + Vector2(24, -21) * s, center + Vector2(-19, -19) * s]), MINT)
		draw_line(center + Vector2(-16, 6) * s, center + Vector2(16, 6) * s, GOLD, 5 * s, true)
		draw_line(center + Vector2(8, 7) * s, center + Vector2(14, 17) * s, GOLD, 5 * s, true)
		draw_circle(center + Vector2(face * 6, -15) * s, 2.3 * s, INK)
		draw_arc(center + Vector2(face * 4, -11) * s, 5 * s, 0, PI * 0.7, 8, INK, 1.6 * s, true)
	else:
		# Lavender ring, based on Jesus's own round avatar.
		draw_circle(center + Vector2(0, -7) * s, 24 * s, Color("8875be"))
		draw_circle(center + Vector2(0, -10) * s, 23 * s, PURPLE)
		draw_circle(center + Vector2(0, -12) * s, 10 * s, Color("c39e9f"))
		draw_arc(center + Vector2(-2, -13) * s, 18 * s, 3.4, 5.1, 16, Color("d4c8f9"), 3 * s, true)
		for side in [-1, 1]:
			draw_circle(center + Vector2(side * 15, -7) * s, 2.5 * s, INK)
		draw_arc(center + Vector2(0, 0) * s, 7 * s, 0.1, PI - 0.1, 16, INK, 2 * s, true)
		draw_circle(center + Vector2(-18, -1) * s, 3 * s, Color("d994ae"))
		draw_circle(center + Vector2(18, -1) * s, 3 * s, Color("d994ae"))
	var aim_dir := _direction() if i == active and phase == "aim" and label else Vector2(face, -0.3).normalized()
	var gun_start := center + Vector2(face * 13, 1) * s
	var gun_end := gun_start + aim_dir * 26 * s
	draw_line(gun_start + Vector2(0, 4) * s, gun_end + Vector2(0, 4) * s, Color("39374a"), 12 * s, true)
	draw_line(gun_start, gun_end, Color("ded5bc"), 10 * s, true)
	draw_circle(gun_start, 6 * s, col)
	if label:
		var selected := i == active and phase == "aim"
		if selected:
			var arrow := p + Vector2(0, -91 + sin(elapsed * 4) * 3)
			draw_colored_polygon(PackedVector2Array([arrow + Vector2(-7, -7), arrow + Vector2(7, -7), arrow + Vector2(0, 2)]), col)
		_round_rect(Rect2(p + Vector2(-48, -79), Vector2(96, 23)), INK, 11)
		_text(fighters[i].name, p + Vector2(0, -62), 13, col, true, true)
		_round_rect(Rect2(p + Vector2(-26, -53), Vector2(52, 4)), Color("514959"), 2)
		_round_rect(Rect2(p + Vector2(-26, -53), Vector2(52.0 * fighters[i].hp / 100, 4)), col, 2)

func draw_ellipse_shadow(p: Vector2, radii: Vector2) -> void:
	var points := PackedVector2Array()
	for n in range(24):
		points.append(p + Vector2(cos(n * TAU / 24), sin(n * TAU / 24)) * radii)
	draw_colored_polygon(points, Color(0.1, 0.1, 0.15, 0.22))

func _draw_aim() -> void:
	var d := _direction()
	var start: Vector2 = fighters[active].pos + Vector2(0, -27) + d * 30
	var velocity := d * (250 + power * 5.2)
	for n in range(1, 16):
		var t := n * 0.045
		var p := start + velocity * t + Vector2(wind, GRAVITY) * t * t * 0.5
		if _solid(p) or p.y > WATER:
			break
		if p.y > 1:
			draw_circle(p, 2.3 if n < 10 else 1.7, Color(1, 0.98, 0.85, 1.0 - n / 20.0))

func _button(action: String, label: String, color: Color = Color("303249"), text_color: Color = CREAM, size_px: int = 26) -> void:
	var r: Rect2 = buttons[action]
	var down: bool = held.get(action, false)
	var disabled := (phase != "aim" or not _can_control()) and action not in ["start", "online", "close_help"]
	var col := color.lightened(0.15) if down else color
	if disabled:
		col = col.darkened(0.25)
	_round_rect(Rect2(r.position + Vector2(0, 4), r.size), Color("111323"), 14)
	_round_rect(r, col, 14, col.lightened(0.13), 1)
	_text(label, r.get_center() + Vector2(0, size_px * 0.36), size_px, text_color.darkened(0.30) if disabled else text_color, true, true)

func _draw_controls() -> void:
	var col: Color = MINT if active == 0 else PURPLE
	var live := phase == "aim"
	var info_y := panel_y + 23
	_text(("JESUS TUR" if active == 1 else "DANIELS TUR") if live else ("SKOTTET ÄR I LUFTEN…" if phase == "flying" else "DANIEL + JESUS = KRATERKOMPISAR"), Vector2(28, info_y), 16 if not portrait else 28, col, true)
	if online and live and not _can_control():
		_text("VÄNTA PÅ DIN TUR", Vector2(640, info_y), 16 if not portrait else 24, MUTED, true, true)
	var time_text := "%02d s" % int(ceil(turn_clock)) if live else ""
	_text(time_text, Vector2(1248, info_y), 16 if not portrait else 28, GOLD if turn_clock < 10 else MUTED, true, true)
	if portrait:
		_text("FÖRFLYTTA DIG", Vector2(44, panel_y + 68), 25, MUTED, true)
		_text("DITT VAPEN", Vector2(638, panel_y + 68), 25, MUTED, true)
		_text("VINKEL", Vector2(308, panel_y + 303), 28, MUTED, true, true)
		_text("KRAFT", Vector2(940, panel_y + 303), 28, MUTED, true, true)
		_text("%d°" % int(angle), Vector2(308, panel_y + 422), 55, CREAM, true, true)
		_text("%d%%" % int(power), Vector2(940, panel_y + 422), 55, GOLD, true, true)
		_button("left", "←", Color("303249"), CREAM, 58)
		_button("right", "→", Color("303249"), CREAM, 58)
		_button("jump", "HOPPA", Color("303249"), CREAM, 29)
		for k in ["angle_down", "power_down"]:
			_button(k, "−", Color("303249"), CREAM, 48)
		for k in ["angle_up", "power_up"]:
			_button(k, "+", Color("303249"), CREAM, 48)
		_button("weapon", "●  RAKET" if weapon == 0 else "●  STUDSBOMB", Color("373249"), GOLD, 34)
		_button("fire", "SKJUT!  ↗", GOLD, INK, 46)
		_text("Tryck i himlen för att sikta. Håll +/− för att finjustera.", Vector2(640, panel_y + 770), 25, MUTED, false, true)
		_text("Liggande skärm ger större spelplan.", Vector2(640, panel_y + 814), 25, MUTED, false, true)
		_text("BYGGT I GODOT  •  ORIGINALGRAFIK  •  BARA EN DUELL TILL", Vector2(640, maxf(panel_y + 910, layout_h - 55)), 19, Color("6e708d"), true, true)
	else:
		_text("FLYTTA", Vector2(28, panel_y + 52), 12, MUTED, true)
		_text("VINKEL", Vector2(410, panel_y + 52), 12, MUTED, true, true)
		_text("KRAFT", Vector2(650, panel_y + 52), 12, MUTED, true, true)
		_text("VAPEN  ·  TRYCK FÖR ATT BYTA", Vector2(884, panel_y + 51), 11, MUTED, true, true)
		_button("left", "←")
		_button("right", "→")
		_button("jump", "HOPP", Color("303249"), CREAM, 15)
		for k in ["angle_down", "power_down"]:
			_button(k, "−")
		for k in ["angle_up", "power_up"]:
			_button(k, "+")
		_text("%d°" % int(angle), Vector2(408, panel_y + 107), 32, CREAM, true, true)
		_text("%d%%" % int(power), Vector2(650, panel_y + 107), 32, GOLD, true, true)
		_button("weapon", "●  RAKET" if weapon == 0 else "●  STUDSBOMB", Color("373249"), GOLD, 16)
		_button("fire", "SKJUT!  ↗", GOLD, INK, 25)
		_text("A/D  flytta    J  hoppa    W/S  vinkel    Q/E  kraft    Tab  vapen    Mellanslag  skjut", Vector2(28, panel_y + 169), 13, MUTED)
		_text("GODOT / 01", Vector2(1224, panel_y + 169), 12, Color("777995"), true, true)
	# Remaining walk budget.
	var bar_pos := Vector2(28, panel_y + 140) if not portrait else Vector2(44, panel_y + 252)
	var bar_width := 244.0 if not portrait else 526.0
	_round_rect(Rect2(bar_pos, Vector2(bar_width, 4)), Color("36384d"), 2)
	_round_rect(Rect2(bar_pos, Vector2(maxf(1, bar_width * move_left / 170), 4)), col, 2)

func _draw_title() -> void:
	draw_rect(Rect2(0, world_top, 1280, WH), Color(0.09, 0.10, 0.17, 0.35))
	_round_rect(Rect2(244, world_top + 15, 792, 427 if not portrait else 465), Color("1f2237"), 26, Color("58516c"), 2)
	_text("EN LITEN Ö. TVÅ STORA EGON.", Vector2(640, world_top + 80), 14 if not portrait else 23, GOLD, true, true)
	_text("Kraterkompisar", Vector2(640, world_top + 144), 51, CREAM, true, true)
	_text("Daniel & Jesus gör upp i skärgården.", Vector2(640, world_top + 185), 22, MUTED, false, true)
	_text("Sikta. Skjut. Lämna en krater.", Vector2(640, world_top + 219), 20, MUTED, false, true)
	_draw_character(0, Vector2(344, world_top + 283), 2.1, 1, false)
	_draw_character(1, Vector2(936, world_top + 283), 2.1, -1, false)
	_button("start", "LOKAL DUELL · SAMMA SKÄRM", GOLD, INK, 20 if not portrait else 25)
	_button("online", "ONLINE · VARSIN SKÄRM", Color("51466f"), CREAM, 20 if not portrait else 27)
	if not portrait:
		_text("2 spelare · inga konton · 40 sekunder per tur", Vector2(640, world_top + 426), 13, MUTED, false, true)

func _draw_victory() -> void:
	draw_rect(Rect2(0, world_top, 1280, WH), Color(0.09, 0.10, 0.17, 0.50))
	_round_rect(Rect2(270, world_top + 35, 740, 365 if not portrait else 430), Color("1f2237"), 26, Color("746789"), 2)
	_text("SKÄRGÅRDENS NYA MÄSTARE", Vector2(640, world_top + 82), 16, GOLD, true, true)
	_text("Oavgjort!" if winner < 0 else "%s vann!" % fighters[winner].name, Vector2(640, world_top + 151), 52, CREAM, true, true)
	_text("%d skott. En ö med helt ny planlösning." % shots, Vector2(640, world_top + 192), 21, MUTED, false, true)
	if winner >= 0:
		_draw_character(winner, Vector2(640, world_top + 279), 1.4, 1, false)
	_button("start", ("NYTT RUM  →" if online else "EN DUELL TILL  ↻"), GOLD, INK, 24 if not portrait else 32)

func _draw_help() -> void:
	draw_rect(Rect2(0, 0, 1280, layout_h), Color(0.06, 0.07, 0.12, 0.90))
	_round_rect(Rect2(210, world_top + 4, 860, 442), Color("25283f"), 24, Color("57516a"), 2)
	_text("Så blir du ö-mästare", Vector2(640, world_top + 57), 32, CREAM, true, true)
	var lines := ["1. Flytta med pilarna. Hoppa över kanter och kratrar.", "2. Sikta i himlen eller ändra vinkel och kraft med +/−.", "3. Skjut en raket, eller prova en studsande bomb.", ("4. Spela bara din figur. Klockan går när hjälpen är öppen." if online else "4. Lämna över skärmen. Den som överlever vinner!"), "Vinden påverkar skottet. Vattnet är farligt. Marken går sönder.", "Tangentbord: A/D, J, W/S, Q/E, Tab, mellanslag.  M = ljud."]
	for n in range(lines.size()):
		_text(lines[n], Vector2(640, world_top + 109 + n * 38), 19 if n < 4 else 16, CREAM if n < 4 else MUTED, false, true)
	_button("close_help", "NU KÖR VI", MINT, INK, 23)

func _make_audio() -> void:
	audio = AudioStreamPlayer.new()
	audio.volume_db = -15
	add_child(audio)
	for kind in ["fire", "boom", "jump", "bounce", "turn", "start", "win", "splash"]:
		var duration := 0.40 if kind == "boom" else (0.65 if kind == "win" else 0.16)
		var rate := 22050
		var count := int(duration * rate)
		var data := PackedByteArray()
		data.resize(count * 2)
		for n in range(count):
			var t := float(n) / rate
			var freq := 440.0
			match kind:
				"fire": freq = lerpf(360, 90, t / duration)
				"jump": freq = lerpf(230, 730, t / duration)
				"turn": freq = 650 if t < 0.08 else 880
				"start": freq = 440 if t < 0.08 else 660
				"bounce": freq = lerpf(180, 80, t / duration)
				"win": freq = [523.0, 659.0, 784.0, 1047.0][mini(3, int(t / 0.15))]
				"splash": freq = 180
				"boom": freq = lerpf(100, 30, t / duration)
			var sample := sin(t * freq * TAU) * 0.5
			if kind in ["boom", "splash", "fire"]:
				sample = sample * 0.45 + rng.randf_range(-1, 1) * 0.5
			sample *= pow(1 - t / duration, 1.8)
			data.encode_s16(n * 2, int(sample * 24000))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = data
		audio_data[kind] = stream

func _sound(kind: String) -> void:
	if sound_on and audio != null and audio_data.has(kind):
		audio.stream = audio_data[kind]
		audio.play()

## A deterministic, read-only snapshot used by the test harness.
func test_snapshot() -> Dictionary:
	return {"phase": phase, "turn": turn, "active": active, "hp": [fighters[0].hp, fighters[1].hp], "angle": angle, "power": power, "shots": shots, "winner": winner, "projectile": not projectile.is_empty(), "terrain_center": _solid(Vector2(640, 400)), "size": get_viewport_rect().size}

## Online mode. Only Daniel's device simulates. Jesus sends bounded controls.
func _can_control() -> bool:
	return not online or (net != null and net.together() and net.seat == active and phase == "aim" and not _online_paused())

func _start_action() -> void:
	if online:
		if phase == "over":
			_leave_online()
			_open_online()
		return
	start_game()

func _weapon_action() -> void:
	if phase != "aim" or not _can_control():
		return
	if online and net.seat == 1:
		_send_guest_input("weapon")
	else:
		weapon = 1 - weapon

func _open_online() -> void:
	online = true
	_online_started = false
	_host_paused = false
	_state_age = 0
	phase = "title"
	_last_received_seq = -1
	_remote_input_seq = -1
	_last_commit_key = ""
	_remote_held.clear()
	pointers.clear()
	held.clear()
	lobby.visible = true
	lobby.refresh(net)

func _leave_online() -> void:
	online = false
	net.leave()
	_online_started = false
	_remote_held.clear()
	_pending_aim.clear()
	lobby.visible = false
	phase = "title"
	projectile.clear()
	pointers.clear()
	held.clear()
	help_open = false

func _copy_room() -> void:
	if not net.room.is_empty():
		DisplayServer.clipboard_set(net.room)
		lobby.message.text = "Rumskoden är %s. Skicka den till din medspelare." % net.room

func _network_changed() -> void:
	if not online or lobby == null:
		return
	_remote_held.clear()
	pointers.clear()
	held.clear()
	if net.together() and net.seat == 0 and not _online_started:
		start_game()
		_online_started = true
		_send_state(true)
	_refresh_network_overlay()

func _network_welcome(data: Dictionary) -> void:
	var snapshot = data.get("snapshot")
	if snapshot is Dictionary and not snapshot.is_empty():
		if apply_network_snapshot(snapshot):
			_online_started = true
			_last_received_seq = int(data.get("seq", -1))
	_remote_input_seq = -1
	_remote_input_age = 1.0
	_state_age = 0

func _network_received(data: Dictionary) -> void:
	if not online:
		return
	if data.get("type") == "state" and net.seat == 1:
		var sequence := int(data.get("seq", -1))
		if sequence <= _last_received_seq:
			return
		var snapshot = data.get("snapshot")
		if snapshot is Dictionary and apply_network_snapshot(snapshot):
			_last_received_seq = sequence
			_online_started = true
			_state_age = 0
			_refresh_network_overlay()
	elif data.get("type") == "input" and net.seat == 0:
		_apply_remote_input(data)

func _online_paused() -> bool:
	if not online or net == null:
		return false
	return not _host_focused if net.seat == 0 else (_host_paused or _state_age > 5)

func _refresh_network_overlay() -> void:
	if not online:
		return
	lobby.visible = not net.together() or not _online_started or _online_paused()
	lobby.refresh(net)
	if net.together() and _online_started and _online_paused():
		held.clear()
		pointers.clear()
		_pending_aim.clear()
		lobby.message.text = "Matchen är pausad. Be Daniel öppna spelfliken igen." if net.seat == 1 else "Matchen är pausad medan spelfönstret är i bakgrunden."

func _network_tick(delta: float) -> void:
	if online and net != null and net.seat == 1 and _online_started:
		_state_age += delta
		if _state_age > 5:
			held.clear()
			pointers.clear()
			_pending_aim.clear()
			_refresh_network_overlay()
	if not online or net == null or not net.together() or not _online_started:
		return
	if net.seat == 0:
		_state_clock += delta
		var key := "%s/%d/%d/%d" % [phase, turn, shots, craters.size()]
		var commit := key != _last_commit_key
		if _state_clock >= 0.10 or commit:
			_send_state(commit)
	else:
		_input_clock += delta
		if _input_clock >= 0.08:
			_input_clock = 0
			_send_guest_input()

func _send_state(commit: bool) -> void:
	_state_clock = 0
	_last_commit_key = "%s/%d/%d/%d" % [phase, turn, shots, craters.size()]
	net.send_state(network_snapshot(), commit)

func _send_guest_input(action: String = "") -> void:
	if not online or net.seat != 1 or not net.together() or active != 1 or phase != "aim" or _online_paused():
		return
	var controls := {"move": 0.0, "angle_axis": 0.0, "power_axis": 0.0}
	if not help_open:
		controls.move = _held_value("right", KEY_D, KEY_RIGHT) - _held_value("left", KEY_A, KEY_LEFT)
		controls.angle_axis = _held_value("angle_up", KEY_W, KEY_UP) - _held_value("angle_down", KEY_S, KEY_DOWN)
		controls.power_axis = _held_value("power_up", KEY_E, KEY_EQUAL) - _held_value("power_down", KEY_Q, KEY_MINUS)
		if not _pending_aim.is_empty():
			controls.aim = _pending_aim.duplicate()
		if not action.is_empty():
			controls.action = action
	if net.send_input(controls, turn):
		_pending_aim.clear()

func _apply_remote_input(data: Dictionary) -> bool:
	if not online or net.seat != 0 or not net.together() or phase != "aim" or active != 1 or not _host_focused:
		return false
	if int(data.get("seat", -1)) != 1 or int(data.get("turn", -1)) != turn:
		return false
	var sequence := int(data.get("seq", -1))
	if sequence <= _remote_input_seq:
		return false
	for key in ["move", "angle_axis", "power_axis"]:
		if not _number_in(data.get(key, 0), -1, 1):
			return false
	if data.has("aim") and not _valid_pair(data.aim, -85, 85):
		return false
	_remote_input_seq = sequence
	_remote_input_age = 0
	var movement := float(data.get("move", 0))
	var angle_axis := float(data.get("angle_axis", 0))
	var power_axis := float(data.get("power_axis", 0))
	_remote_held = {"right": maxf(movement, 0), "left": maxf(-movement, 0), "angle_up": maxf(angle_axis, 0), "angle_down": maxf(-angle_axis, 0), "power_up": maxf(power_axis, 0), "power_down": maxf(-power_axis, 0)}
	if data.has("aim"):
		fighters[1].face = 1.0 if float(data.aim[0]) >= 0 else -1.0
		angle = clampf(float(data.aim[1]), 5, 85)
	_applying_remote = true
	match str(data.get("action", "")):
		"jump": _jump()
		"weapon": weapon = 1 - weapon
		"fire": fire()
	_applying_remote = false
	return true

func network_snapshot() -> Dictionary:
	var people: Array = []
	for f in fighters:
		people.append({"pos": [f.pos.x, f.pos.y], "vel": [f.vel.x, f.vel.y], "hp": f.hp, "face": f.face, "ground": f.ground})
	var bullet := {}
	if not projectile.is_empty():
		bullet = {"pos": [projectile.pos.x, projectile.pos.y], "vel": [projectile.vel.x, projectile.vel.y], "age": projectile.age, "weapon": projectile.weapon, "bounces": projectile.bounces}
	var path: Array = []
	for point in trail:
		path.append([point.x, point.y])
	return {"schema": 1, "paused": (not _host_focused if net != null and net.seat == 0 else _host_paused) if online else false, "phase": phase, "turn": turn, "active": active, "angle": angle, "power": power, "weapon": weapon, "wind": wind, "move_left": move_left, "turn_clock": turn_clock, "settle_clock": settle_clock, "winner": winner, "shots": shots, "hits": hits, "fighters": people, "projectile": bullet, "terrain_version": craters.size(), "craters": craters.duplicate(true), "trail": path}

func _number_in(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _valid_pair(value, low: float = -5000, high: float = 5000) -> bool:
	return value is Array and value.size() == 2 and _number_in(value[0], low, high) and _number_in(value[1], low, high)

func _valid_snapshot(data: Dictionary) -> bool:
	if data.get("schema") != 1 or data.get("phase") not in ["aim", "flying", "settle", "over"]:
		return false
	if data.has("paused") and not data.paused is bool:
		return false
	var ranges := {"turn": [1, 100000], "active": [0, 1], "angle": [5, 85], "power": [12, 100], "weapon": [0, 1], "wind": [-100, 100], "move_left": [0, 170], "turn_clock": [-1, 40], "settle_clock": [-10, 10], "winner": [-1, 1], "shots": [0, 100000], "hits": [0, 200000]}
	for key in ranges:
		if not _number_in(data.get(key), ranges[key][0], ranges[key][1]):
			return false
	for key in ["turn", "active", "weapon", "winner", "shots", "hits"]:
		if float(data[key]) != floorf(float(data[key])):
			return false
	if not data.get("fighters") is Array or data.fighters.size() != 2:
		return false
	for f in data.fighters:
		if not f is Dictionary or not _valid_pair(f.get("pos")) or not _valid_pair(f.get("vel")) or not _number_in(f.get("hp"), 0, 100) or f.get("face") not in [-1.0, 1.0] or not f.get("ground") is bool:
			return false
	if not data.get("craters") is Array or data.craters.size() > 500 or data.get("terrain_version") != data.craters.size():
		return false
	for crater in data.craters:
		if not crater is Array or crater.size() != 3 or not _number_in(crater[0], -2000, 3000) or not _number_in(crater[1], -2000, 1500) or not _number_in(crater[2], 1, 100):
			return false
	if not data.get("trail") is Array or data.trail.size() > 28:
		return false
	for point in data.trail:
		if not _valid_pair(point):
			return false
	if not data.get("projectile") is Dictionary:
		return false
	var bullet: Dictionary = data.projectile
	if not bullet.is_empty():
		if not _valid_pair(bullet.get("pos")) or not _valid_pair(bullet.get("vel")) or not _number_in(bullet.get("age"), 0, 10) or not _number_in(bullet.get("weapon"), 0, 1) or float(bullet.weapon) != floorf(float(bullet.weapon)) or not _number_in(bullet.get("bounces"), 0, 4):
			return false
	return true

func apply_network_snapshot(data: Dictionary) -> bool:
	# Validate everything before changing the scene. Never decode executable objects.
	if not _valid_snapshot(data):
		return false
	var old_phase := phase
	var old_turn := turn
	var old_shots := shots
	var old_craters := craters.size()
	var same_prefix: bool = craters.size() <= data.craters.size()
	if same_prefix:
		for i in range(craters.size()):
			if craters[i] != data.craters[i]:
				same_prefix = false
				break
	if not same_prefix:
		_generate_terrain()
		craters.clear()
	for i in range(craters.size(), data.craters.size()):
		var crater: Array = data.craters[i]
		carve(Vector2(float(crater[0]), float(crater[1])), float(crater[2]))
	for i in range(2):
		var f: Dictionary = data.fighters[i]
		var damage := int(fighters[i].hp) - int(f.hp)
		fighters[i] = {"name": "Daniel" if i == 0 else "Jesus", "pos": Vector2(float(f.pos[0]), float(f.pos[1])), "vel": Vector2(float(f.vel[0]), float(f.vel[1])), "hp": int(f.hp), "face": float(f.face), "ground": bool(f.ground)}
		if damage > 0:
			floaters.append({"pos": fighters[i].pos + Vector2(0, -63), "text": "−%d" % damage, "life": 1.7, "color": GOLD})
	_host_paused = bool(data.get("paused", false))
	phase = str(data.phase)
	turn = int(data.turn)
	active = int(data.active)
	angle = float(data.angle)
	power = float(data.power)
	weapon = int(data.weapon)
	wind = float(data.wind)
	move_left = float(data.move_left)
	turn_clock = float(data.turn_clock)
	settle_clock = float(data.settle_clock)
	winner = int(data.winner)
	shots = int(data.shots)
	hits = int(data.hits)
	projectile.clear()
	if not data.projectile.is_empty():
		var b: Dictionary = data.projectile
		projectile = {"pos": Vector2(float(b.pos[0]), float(b.pos[1])), "vel": Vector2(float(b.vel[0]), float(b.vel[1])), "age": float(b.age), "weapon": int(b.weapon), "bounces": int(b.bounces)}
	trail.clear()
	for point in data.trail:
		trail.append(Vector2(float(point[0]), float(point[1])))
	if shots > old_shots:
		_sound("fire")
	if craters.size() > old_craters:
		var latest: Array = craters.back()
		var impact := Vector2(float(latest[0]), float(latest[1]))
		_emit(impact, GOLD, 28, 270)
		_emit(impact, Color("f29c72"), 20, 180)
		shake = 9
		_sound("boom")
	if turn != old_turn or old_phase == "title":
		banner = "%s, din tur!" % fighters[active].name
		banner_clock = 2
		_sound("turn")
		pointers.clear()
		held.clear()
		_pending_aim.clear()
	if phase == "over" and old_phase != "over":
		_sound("win")
	return true

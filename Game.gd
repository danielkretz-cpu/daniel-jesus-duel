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
const MapThemes = preload("res://MapThemes.gd")
const World3DScript = preload("res://World3D.gd")
const StartMenuScript = preload("res://StartMenu.gd")
const FriendInvite = preload("res://FriendInvite.gd")
const ClientPredictionScript = preload("res://ClientPrediction.gd")
const FighterScript = preload("res://Fighter3D.gd")
const ROCKET := 0
const BOMB := 1
const BANANA := 2
const FREEDOM := 3
const BANANA_FRAGMENT := 4
const FREEDOM_DAMAGE := 49
const BANANA_FRAGMENTS := 5

var terrain: Image
var terrain_texture: ImageTexture
var _terrain_texture_dirty := false
var terrain_texture_uploads := 0
const PARTICLE_CAP := 128
const MAX_CRATERS := 500
var _terrain_limit_notified := false
var fighters: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var projectile: Dictionary = {}
var fragments: Array[Dictionary] = []
var freedom: Array[int] = [0, 0]
var player_names: Array[String] = ["Daniel", "Jesus"]
var target := 1
var _remote_input_sequences: Dictionary = {}
var start_menu
var compact_landscape := false
var touch_controls := false
var force_touch_controls := false
var map_id := 0
var trail: Array[Vector2] = []
var phase := "title"
var active := 0
var turn := 1
var angle := 46.0
var power := 70.0
const CHARGE_MIN := 12.0
const CHARGE_MAX := 100.0
const CHARGE_SPEED := 88.0
var _charge_active := false
var _charge_power := CHARGE_MIN
var _charge_elapsed := 0.0
var _charge_source := -99
var _charge_context := ""
var _released_context := ""
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
# UI-space world rectangle; the camera extends upward without stretching physics.
var world_rect := Rect2(0, 0, 1280, 688)
var header_bottom := 84.0
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
var _host_charge_controls := true
var _state_age := 0.0
var world3d
var prediction = ClientPredictionScript.new()

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
	lobby.create_requested.connect(func(chosen_name: String): net.create_room(chosen_name, 6, map_id))
	lobby.join_requested.connect(func(code: String, chosen_name: String): net.join_room(code, chosen_name))
	lobby.start_requested.connect(func(selected_map: int): net.start_match(selected_map))
	lobby.map_changed.connect(_lobby_map_changed)
	lobby.leave_requested.connect(_leave_online)
	if lobby.has_signal("leave_cancelled"):
		lobby.leave_cancelled.connect(_refresh_network_overlay)
	lobby.reconnect_requested.connect(func(): net.reconnect())
	start_menu = StartMenuScript.new()
	add_child(start_menu)
	start_menu.local_requested.connect(_menu_local)
	start_menu.online_requested.connect(_menu_online)
	start_menu.map_changed.connect(_set_preview_map)
	net.changed.connect(_network_changed)
	net.welcomed.connect(_network_welcome)
	net.received.connect(_network_received)
	# The renderer never owns gameplay state. Dedicated/headless tests skip GPU work.
	if DisplayServer.get_name() != "headless" or OS.get_cmdline_user_args().has("--render-3d"):
		world3d = World3DScript.new()
		add_child(world3d)
		world3d.initialize(self)
	_layout()
	var invited_room: String = FriendInvite.current_room()
	if not invited_room.is_empty():
		_open_online()
		lobby.open_invite(invited_room)
	queue_redraw()

func _layout(view: Vector2 = Vector2.ZERO) -> void:
	if view == Vector2.ZERO:
		view = get_viewport_rect().size
	view = view.max(Vector2.ONE)
	portrait = view.y / view.x > 0.8125
	touch_controls = force_touch_controls or DisplayServer.is_touchscreen_available() or portrait or view.y < 600 or view.x < 1100
	compact_landscape = not portrait and touch_controls
	# The arena uses the complete width, including short landscape phones.
	ui_scale = view.x / 1280.0
	ui_origin = Vector2.ZERO
	layout_h = view.y / ui_scale
	var touch_unit := maxf(132.0, 44.0 / ui_scale) if portrait else maxf(68.0, 44.0 / ui_scale)
	var dock_h := 460.0 if portrait else (108.0 if compact_landscape else 28.0)
	if portrait:
		dock_h = maxf(dock_h, touch_unit * 2 + 180.0)
	elif compact_landscape:
		dock_h = maxf(dock_h, touch_unit + 36.0)
	panel_y = layout_h - dock_h
	world_rect = Rect2(0, 0, 1280, layout_h)
	world_top = panel_y - WH
	buttons.clear()
	if portrait:
		var icon_h := touch_unit
		buttons.sound = Rect2(836, 12, 136, icon_h)
		buttons.help = Rect2(984, 12, 136, icon_h)
		buttons.restart = Rect2(1132, 12, 128, icon_h)
		header_bottom = icon_h + 30.0 + (194.0 if fighters.size() > 3 else 98.0)
		var row_y := panel_y + 58.0
		var arrow_w := maxf(138.0, touch_unit)
		var jump_w := maxf(176.0, touch_unit)
		buttons.left = Rect2(20, row_y, arrow_w, touch_unit)
		buttons.right = Rect2(34 + arrow_w, row_y, arrow_w, touch_unit)
		buttons.jump = Rect2(48 + arrow_w * 2, row_y, jump_w, touch_unit)
		var weapon_x: float = buttons.jump.end.x + 20.0
		var weapon_w := 1260.0 - weapon_x
		buttons.weapon = Rect2(weapon_x, row_y, weapon_w if fighters.size() <= 2 else (weapon_w - 16.0) * 0.5, touch_unit)
		if fighters.size() > 2:
			buttons.target = Rect2(weapon_x + (weapon_w + 16.0) * 0.5, row_y, (weapon_w - 16.0) * 0.5, touch_unit)
		var second_y := row_y + touch_unit + 18.0
		buttons.angle_down = Rect2(20, second_y, arrow_w, touch_unit)
		buttons.angle_up = Rect2(buttons.jump.end.x - arrow_w, second_y, arrow_w, touch_unit)
		buttons.fire = Rect2(weapon_x, second_y, weapon_w, touch_unit)
	elif compact_landscape:
		var icon_h := touch_unit
		buttons.restart = Rect2(1260 - touch_unit, 6, touch_unit, icon_h)
		buttons.help = Rect2(1248 - touch_unit * 2, 6, touch_unit, icon_h)
		buttons.sound = Rect2(1236 - touch_unit * 3, 6, touch_unit, icon_h)
		header_bottom = maxf(icon_h + 6.0, 74.0 if fighters.size() <= 3 else 118.0)
		var row_y := panel_y + 28.0
		buttons.left = Rect2(20, row_y, touch_unit, touch_unit)
		buttons.right = Rect2(32 + touch_unit, row_y, touch_unit, touch_unit)
		buttons.jump = Rect2(44 + touch_unit * 2, row_y, 126, touch_unit)
		buttons.angle_down = Rect2(buttons.jump.end.x + 18, row_y, touch_unit, touch_unit)
		buttons.angle_up = Rect2(buttons.angle_down.end.x + 66, row_y, touch_unit, touch_unit)
		var weapon_x: float = buttons.angle_up.end.x + 18
		var weapon_w := 1026.0 - weapon_x
		buttons.weapon = Rect2(weapon_x, row_y, weapon_w if fighters.size() <= 2 else (weapon_w - 16.0) * 0.5, touch_unit)
		if fighters.size() > 2:
			buttons.target = Rect2(weapon_x + (weapon_w + 16.0) * 0.5, row_y, (weapon_w - 16.0) * 0.5, touch_unit)
		buttons.fire = Rect2(1044, row_y, 216, touch_unit)
	else:
		# Desktop movement and aim are keys/mouse, with only small edge actions.
		buttons.sound = Rect2(1140, 10, 32, 32)
		buttons.help = Rect2(1184, 10, 32, 32)
		buttons.restart = Rect2(1228, 10, 32, 32)
		header_bottom = 56.0
		buttons.weapon = Rect2(842, layout_h - 58, 184, 38)
		if fighters.size() > 2:
			buttons.target = Rect2(642, layout_h - 58, 184, 38)
		buttons.fire = Rect2(1042, layout_h - 58, 218, 38)
	# Legacy title/victory actions remain reachable; the main menu owns its own UI.
	var overlay_y := maxf(header_bottom + 12.0, (panel_y - 430.0) * 0.5)
	buttons.start = Rect2(423, overlay_y + 310, 434, 68)
	buttons.online = Rect2(423, overlay_y + 384, 434, 56)
	buttons.map_prev = Rect2(286, overlay_y + 163, 72, 66)
	buttons.map_next = Rect2(922, overlay_y + 163, 72, 66)
	if portrait:
		buttons.start = Rect2(240, overlay_y + 310, 800, touch_unit)
		buttons.online = Rect2(240, overlay_y + 466, 800, touch_unit)
		buttons.map_prev = Rect2(80, overlay_y + 163, 140, touch_unit)
		buttons.map_next = Rect2(1060, overlay_y + 163, 140, touch_unit)
	var help_h := 750.0 if portrait else 442.0
	var help_y := maxf(16.0, (layout_h - help_h) * 0.5)
	buttons.close_help = Rect2(390, help_y + help_h - (touch_unit + 28.0 if portrait else 98.0), 500, touch_unit if portrait else 74.0)
	if lobby != null:
		lobby.layout(view)
	if start_menu != null:
		start_menu.layout(view)
	last_size = view

func world_to_ui(point: Vector2) -> Vector2:
	return point + Vector2(0, world_top)

func ui_to_world(point: Vector2) -> Vector2:
	return point - Vector2(0, world_top)

func _generate_terrain() -> void:
	terrain = Image.create(WW, WH, false, Image.FORMAT_RGBA8)
	terrain.fill(Color.TRANSPARENT)
	for x in range(WW):
		var surface := MapThemes.surface_y(map_id, x)
		for y in range(surface, WH):
			terrain.set_pixel(x, y, MapThemes.terrain_color(map_id, x, y, surface))
	terrain_texture = ImageTexture.create_from_image(terrain)
	_terrain_texture_dirty = false
	_terrain_limit_notified = false
	if world3d != null:
		world3d.terrain_changed(terrain, terrain_texture)

func _spawn_fighters() -> void:
	if online and net != null and net.roster.size() >= 2:
		player_names.clear()
		for player in net.roster:
			player_names.append(str(player.name))
	if player_names.size() < 2 or player_names.size() > 6:
		player_names = ["Daniel", "Jesus"]
	fighters.clear()
	var count := player_names.size()
	for i in range(count):
		var x := (224 if i == 0 else 1050) if count == 2 else int(round(100.0 + i * 1080.0 / (count - 1)))
		if count > 2:
			var preferred := x
			var found := false
			for offset in range(37):
				for sign_x in [-1, 1]:
					var candidate := clampi(preferred + offset * sign_x, 20, WW - 21)
					var height := MapThemes.surface_y(map_id, candidate)
					if MapThemes.surface_y(map_id, candidate - 12) >= height - 12 and MapThemes.surface_y(map_id, candidate + 12) >= height - 12:
						x = candidate
						found = true
						break
				if found:
					break
		var spawn := Vector2(x, MapThemes.surface_y(map_id, x))
		fighters.append({"name": player_names[i], "pos": spawn, "vel": Vector2.ZERO, "hp": 100, "face": 1.0 if x < 640 else -1.0, "ground": true})
	freedom.resize(count)
	target = _nearest_target(0)

func _nearest_target(owner: int) -> int:
	var closest := -1
	var distance := INF
	for i in range(fighters.size()):
		if i == owner or fighters[i].hp <= 0:
			continue
		var candidate: float = fighters[i].pos.distance_squared_to(fighters[owner].pos)
		if candidate < distance:
			distance = candidate
			closest = i
	return closest if closest >= 0 else (owner + 1) % fighters.size()

func _valid_target(value: int, owner: int) -> bool:
	return value >= 0 and value < fighters.size() and value != owner and fighters[value].hp > 0

func _target_action() -> void:
	if phase != "aim" or not _can_control():
		return
	if online and net.seat > 0 and not _applying_remote:
		_send_guest_input("target")
		return
	for offset in range(1, fighters.size() + 1):
		var candidate := (target + offset) % fighters.size()
		if _valid_target(candidate, active):
			target = candidate
			break

func _fighter_color(index: int) -> Color:
	return FighterScript.fighter_color(index)

func _menu_local(selected_map: int) -> void:
	map_id = selected_map
	player_names = ["Daniel", "Jesus"]
	start_game()

func _menu_online(selected_map: int) -> void:
	map_id = selected_map
	_open_online()

func _set_preview_map(selected_map: int) -> void:
	if phase != "title":
		return
	map_id = clampi(selected_map, 0, MapThemes.count() - 1)
	craters.clear()
	_generate_terrain()
	_spawn_fighters()
	if start_menu != null:
		start_menu.set_map(map_id)

func _lobby_map_changed(selected_map: int) -> void:
	_set_preview_map(selected_map)
	if net != null and not net.room.is_empty() and net.seat == 0:
		net.set_map(selected_map)

func _map_action(direction: int) -> void:
	if phase != "title" or online:
		return
	map_id = posmod(map_id + direction, MapThemes.count())
	craters.clear()
	_generate_terrain()
	_spawn_fighters()
	projectile.clear()
	fragments.clear()
	particles.clear()
	trail.clear()

func start_game() -> void:
	_cancel_charge()
	_released_context = ""
	prediction.reset()
	if online and net != null and net.started:
		map_id = net.map_id
	_remote_input_sequences.clear()
	fragments.clear()
	craters.clear()
	_remote_held.clear()
	_pending_aim.clear()
	_generate_terrain()
	_spawn_fighters()
	freedom.fill(0)
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
	target = _nearest_target(active)
	banner = "%s börjar!" % fighters[active].name
	banner_clock = 2.0
	help_open = false
	toast_clock = 0
	pointers.clear()
	held.clear()
	if start_menu != null:
		start_menu.hide()
	_layout(last_size)
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
	if help_open and not _applying_remote:
		return
	if online and not _applying_remote:
		if not _can_control():
			return
		if net.seat > 0:
			prediction.reset()
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
			# Preserve legacy remote-client axis inputs; new clients send exact release power.
			if online and active > 0:
				power = clampf(power + (float(_remote_held.get("power_up", 0)) - float(_remote_held.get("power_down", 0))) * delta * 44, 12, 100)
	for i in range(fighters.size()):
		_step_fighter(i, delta)
	if phase == "flying":
		_step_projectile(delta)
	elif phase == "settle":
		settle_clock -= delta
		if settle_clock <= 0 and _everyone_settled():
			_finish_turn()
		elif settle_clock < -4:
			_finish_turn()
	if phase == "aim":
		if _check_winner():
			return
		if fighters[active].hp <= 0:
			_finish_turn()
		elif not _valid_target(target, active):
			target = _nearest_target(active)

func _held_value(action: String, key1: int, key2: int) -> float:
	if online and active > 0 and net.seat == 0:
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
		if net.seat > 0:
			_send_guest_input("fire")
			return
	if phase != "aim" or (help_open and not _applying_remote):
		return
	if weapon == FREEDOM and freedom[active] == 0:
		toast = "Freedom är låst. Träffa motståndaren direkt först!"
		toast_clock = 3.0
		return
	if not _valid_target(target, active):
		target = _nearest_target(active)
	if weapon == FREEDOM:
		freedom[active] = 0
	var d := _direction()
	var start: Vector2 = fighters[active].pos + Vector2(0, -27) + d * 30
	projectile = {"pos": start, "vel": d * (250 + power * 5.2), "age": 0.0, "weapon": weapon, "bounces": 0, "owner": active, "target": target}
	fragments.clear()
	trail.clear()
	shots += 1
	phase = "flying"
	pointers.clear()
	held.clear()
	_emit(start, GOLD, 9, 80)
	_sound("fire")

func _step_projectile(delta: float) -> void:
	if not projectile.is_empty():
		_step_main_projectile(delta)
	# Secondary bananas are actual bounded projectiles, never a cosmetic explosion.
	for index in range(fragments.size() - 1, -1, -1):
		if _step_fragment(fragments[index], delta):
			fragments.remove_at(index)
	if projectile.is_empty() and fragments.is_empty() and phase == "flying":
		_end_shot()

func _direct_target(bullet: Dictionary, point: Vector2) -> int:
	var owner := int(bullet.get("owner", active))
	for i in range(fighters.size()):
		if int(bullet.weapon) == FREEDOM and i != int(bullet.get("target", _nearest_target(owner))):
			continue
		if fighters[i].hp > 0 and (i != owner or bullet.age > 0.3) and point.distance_to(fighters[i].pos + Vector2(0, -19)) < 20:
			return i
	return -1

func _reward_direct_hit(owner: int, target: int, source_weapon: int) -> void:
	# Only a projectile body hitting the enemy qualifies, never blast proximity.
	# One held missile per player. A Freedom hit cannot create a free missile chain.
	if target < 0 or target == owner or source_weapon == FREEDOM or freedom[owner] != 0:
		return
	freedom[owner] = 1
	_show_freedom_reward(owner)

func _show_freedom_reward(owner: int) -> void:
	toast = "%s: fullträff! Freedom +1" % fighters[owner].name
	toast_clock = 3.5
	floaters.append({"pos": fighters[owner].pos + Vector2(0, -76), "text": "FREEDOM +1", "life": 2.5, "color": MINT})
	_sound("turn")

func _step_main_projectile(delta: float) -> void:
	projectile.age += delta
	if projectile.weapon == FREEDOM:
		var target_pos: Vector2 = fighters[int(projectile.target)].pos + Vector2(0, -19)
		# Loft above intervening terrain before the final homing dive.
		var destination := target_pos
		if absf(target_pos.x - projectile.pos.x) > 150:
			var ceiling := 150.0
			for x in range(int(minf(projectile.pos.x, target_pos.x)), int(maxf(projectile.pos.x, target_pos.x)), 30):
				ceiling = minf(ceiling, MapThemes.surface_y(map_id, clampi(x, 0, WW - 1)) - 85.0)
			destination.y = minf(target_pos.y - 100, ceiling)
		var desired: Vector2 = (destination - projectile.pos).normalized() * 480.0
		projectile.vel = projectile.vel.move_toward(desired, 1450.0 * delta)
	else:
		projectile.vel += Vector2(wind, GRAVITY) * delta
	if projectile.weapon == BANANA and (projectile.age >= 1.2 or (projectile.age > 0.45 and projectile.vel.y >= 0)):
		_burst_banana(projectile.pos)
		return
	var steps := maxi(1, int(projectile.vel.length() * delta / 3) + 1)
	for _n in range(steps):
		var before: Vector2 = projectile.pos
		var next: Vector2 = before + projectile.vel * delta / steps
		var target := _direct_target(projectile, next)
		if _solid(next) or target >= 0:
			if projectile.weapon == BOMB and target < 0 and projectile.bounces < 4 and projectile.age < 2.7:
				var normal := Vector2(float(int(_solid(next + Vector2(-4, 0))) - int(_solid(next + Vector2(4, 0)))), float(int(_solid(next + Vector2(0, -4))) - int(_solid(next + Vector2(0, 4)))))
				if normal.length() < 0.1:
					normal = Vector2.UP
				projectile.vel = projectile.vel.bounce(normal.normalized()) * 0.48
				projectile.pos = before + normal.normalized() * 5
				projectile.bounces += 1
				_sound("bounce")
				break
			_reward_direct_hit(int(projectile.owner), target, int(projectile.weapon))
			if projectile.weapon == FREEDOM:
				_freedom_impact(next, target)
			elif projectile.weapon == BANANA:
				_burst_banana(before, true)
			else:
				_explode(next, 72.0 if projectile.weapon == BOMB else 57.0)
			return
		projectile.pos = next
		if next.y > WATER or next.x < -100 or next.x > WW + 100 or next.y < -1100:
			if next.y > WATER:
				_emit(Vector2(next.x, WATER), MapThemes.wave_color(map_id), 26, 160)
				_sound("splash")
			_end_shot()
			return
	if projectile.age > (2.9 if projectile.weapon == BOMB else 8.0):
		if projectile.weapon == FREEDOM:
			_freedom_impact(projectile.pos, -1)
		else:
			_explode(projectile.pos, 72 if projectile.weapon == BOMB else 57)
		return
	trail.append(projectile.pos)
	if trail.size() > 28:
		trail.pop_front()

func _burst_banana(point: Vector2, impact: bool = false) -> void:
	var owner := int(projectile.owner)
	var selected_target := int(projectile.target)
	var inherited: Vector2 = projectile.vel * 0.16
	projectile.clear()
	trail.clear()
	for n in range(BANANA_FRAGMENTS):
		var velocity := Vector2((n - 2) * 95.0, -190.0 - (2 - abs(n - 2)) * 34.0) + inherited
		fragments.append({"pos": point + Vector2((n - 2) * 4, -7), "vel": velocity, "age": 0.0, "weapon": BANANA_FRAGMENT, "bounces": 0, "owner": owner, "target": selected_target})
	_emit(point, GOLD, 24, 170)
	_sound("bounce")
	toast = "BANANREGN! Fem små överraskningar."
	toast_clock = 1.8
	if impact:
		_blast(point, 26, 9, false)

func _step_fragment(bullet: Dictionary, delta: float) -> bool:
	bullet.age += delta
	bullet.vel += Vector2(wind * 0.7, GRAVITY) * delta
	var steps := maxi(1, int(bullet.vel.length() * delta / 3) + 1)
	for _n in range(steps):
		var next: Vector2 = bullet.pos + bullet.vel * delta / steps
		var target := _direct_target(bullet, next)
		if _solid(next) or target >= 0:
			_reward_direct_hit(int(bullet.owner), target, BANANA_FRAGMENT)
			_blast(next, 32, 11, false)
			return true
		bullet.pos = next
		if next.y > WATER or next.x < -100 or next.x > WW + 100:
			_emit(Vector2(clampf(next.x, 0, WW), minf(next.y, WATER)), GOLD, 6, 70)
			return true
	if bullet.age > 3.5:
		_blast(bullet.pos, 32, 11, false)
		return true
	return false

func _freedom_impact(point: Vector2, target: int) -> void:
	# Exactly 49 direct damage, no splash, falloff, knockback, or terrain removal.
	if target >= 0 and target == int(projectile.target):
		_damage(target, FREEDOM_DAMAGE)
		hits += 1
		toast = "FREEDOM! Exakt 49 skada."
	else:
		toast = "Freedom stoppades av terrängen."
	toast_clock = 2.5
	_emit(point, Color("99ddff"), 30, 220)
	_emit(point, CREAM, 18, 130)
	shake = 6
	_sound("boom")
	_end_shot()

func _explode(p: Vector2, radius: float) -> void:
	_blast(p, radius, 52, true)
	_end_shot()

func _blast(p: Vector2, radius: float, max_damage: int, knockback: bool) -> void:
	carve(p, radius)
	shake = 9.0 if max_damage > 20 else 4.0
	for i in range(fighters.size()):
		var f: Dictionary = fighters[i]
		var dist: float = p.distance_to(f.pos + Vector2(0, -16))
		if dist < radius + 35 and f.hp > 0:
			var amount := int(clampf(max_damage * (1.0 - dist / (radius + 38)), 1 if max_damage < 20 else 3, max_damage))
			_damage(i, amount)
			hits += 1
			if knockback:
				var away: Vector2 = (f.pos + Vector2(0, -25) - p).normalized()
				f.vel = Vector2(away.x * 220, -170 - amount * 2.0)
				f.ground = false
	_emit(p, GOLD, 28 if max_damage > 20 else 12, 270)
	_emit(p, Color("f29c72"), 20 if max_damage > 20 else 8, 180)
	_sound("boom")

func carve(p: Vector2, radius: float, record_noop: bool = false) -> void:
	# Protocol 3 has a bounded canonical history. Never send an unreceivable state.
	# Damage still resolves after this limit; only further terrain cutting stops.
	if craters.size() >= MAX_CRATERS:
		_show_terrain_limit()
		return
	var rim := Color("9c7180")
	var inner_squared := radius * radius
	var outer_squared := (radius + 3) * (radius + 3)
	var bounds := Rect2i(
		Vector2i(maxi(0, int(p.x - radius - 3)), maxi(0, int(p.y - radius - 3))),
		Vector2i.ZERO)
	bounds.end = Vector2i(mini(WW, int(p.x + radius + 4)), mini(WH, int(p.y + radius + 4)))
	var changed := false
	if bounds.has_area():
		var before := terrain.get_region(bounds).get_data()
		for y in range(bounds.position.y, bounds.end.y):
			var dy_squared := (float(y) - p.y) * (float(y) - p.y)
			var left := bounds.position.x
			var right := left
			if dy_squared < inner_squared:
				var half_width := sqrt(inner_squared - dy_squared)
				left = clampi(int(floor(p.x - half_width)) + 1, bounds.position.x, bounds.end.x)
				right = clampi(int(ceil(p.x + half_width)), bounds.position.x, bounds.end.x)
				# Keep the original strict pixel-center radius test at rounded edges.
				while left < right and Vector2(left, y).distance_squared_to(p) >= inner_squared:
					left += 1
				while right > left and Vector2(right - 1, y).distance_squared_to(p) >= inner_squared:
					right -= 1
				if right > left:
					terrain.fill_rect(Rect2i(left, y, right - left, 1), Color.TRANSPARENT)
			# Native fill handles the interior. Only the narrow scorched rim needs
			# per-pixel reads so holes are never filled back in.
			for span in [Vector2i(bounds.position.x, left), Vector2i(right, bounds.end.x)]:
				for x in range(span.x, span.y):
					var distance_squared := Vector2(x, y).distance_squared_to(p)
					if distance_squared >= inner_squared and distance_squared < outer_squared and terrain.get_pixel(x, y).a > 0.5:
						terrain.set_pixel(x, y, rim)
		changed = before != terrain.get_region(bounds).get_data()
	# Replaying a legacy host must retain every history entry, including no-ops.
	if changed or record_noop:
		craters.append([p.x, p.y, radius])
	if craters.size() >= MAX_CRATERS:
		_show_terrain_limit()
	if not changed:
		return
	# Collision changes immediately; presentation uploads only once per rendered frame.
	# Banana bursts and reconnect replay must not upload this 2.4 MB image per crater.
	_terrain_texture_dirty = true
	if world3d != null:
		world3d.carve_changed(p, radius)

func _show_terrain_limit() -> void:
	if _terrain_limit_notified:
		return
	_terrain_limit_notified = true
	toast = "Terränggränsen är nådd. Skott gör fortfarande skada."
	toast_clock = 6.0

func _flush_terrain_texture() -> void:
	if not _terrain_texture_dirty:
		return
	terrain_texture.update(terrain)
	_terrain_texture_dirty = false
	terrain_texture_uploads += 1

func _damage(i: int, amount: int) -> void:
	if amount <= 0:
		return
	fighters[i].hp = maxi(0, fighters[i].hp - amount)
	floaters.append({"pos": fighters[i].pos + Vector2(0, -63), "text": "−%d" % amount, "life": 1.7, "color": GOLD})

func _end_shot() -> void:
	projectile.clear()
	fragments.clear()
	phase = "settle"
	settle_clock = 1.7

func _finish_turn() -> void:
	_cancel_charge()
	_released_context = ""
	_remote_held.clear()
	_pending_aim.clear()
	if _check_winner():
		return
	for offset in range(1, fighters.size() + 1):
		var candidate := (active + offset) % fighters.size()
		if fighters[candidate].hp > 0:
			active = candidate
			break
	target = _nearest_target(active)
	if weapon == FREEDOM and freedom[active] == 0:
		weapon = ROCKET
	turn += 1
	phase = "aim"
	move_left = 170
	turn_clock = 40
	wind = rng.randf_range(-32, 32)
	fighters[active].face = 1.0 if fighters[target].pos.x > fighters[active].pos.x else -1.0
	angle = 46
	power = 70
	trail.clear()
	banner = "%s, din tur!" % fighters[active].name
	banner_clock = 2.0
	_sound("turn")

func _check_winner() -> bool:
	var alive: Array[int] = []
	for i in range(fighters.size()):
		if fighters[i].hp > 0:
			alive.append(i)
	if alive.size() > 1:
		return false
	winner = -1 if alive.is_empty() else alive[0]
	phase = "over"
	banner_clock = 0
	_sound("win")
	for n in range(60):
		particles.append({"pos": Vector2(rng.randf_range(180, 1100), rng.randf_range(-150, 80)), "vel": Vector2(rng.randf_range(-30, 30), rng.randf_range(15, 80)), "life": 5.0, "max": 5.0, "color": [MINT, PURPLE, GOLD][n % 3], "size": rng.randf_range(3, 7)})
	return true

func _process(delta: float) -> void:
	_update_charge(delta)
	prediction.update(self, delta)
	_network_tick(delta)
	if start_menu != null:
		start_menu.visible = phase == "title" and not online
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
	_flush_terrain_texture()
	if world3d != null:
		world3d.sync(self, delta)
	queue_redraw()

func _emit(p: Vector2, col: Color, count: int, speed: float) -> void:
	for n in range(mini(count, maxi(0, PARTICLE_CAP - particles.size()))):
		var life := rng.randf_range(0.35, 0.95)
		particles.append({"pos": p, "vel": Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(speed * 0.2, speed), "life": life, "max": life, "color": col, "size": rng.randf_range(2, 6)})

func _charge_key() -> String:
	return "%d/%d/%s/%d" % [turn, active, phase, shots]

func _charge_allowed() -> bool:
	return phase == "aim" and _host_focused and _can_control() and (start_menu == null or not start_menu.visible) and _released_context != _charge_key()

func _begin_charge(source: int) -> void:
	# One physical gesture owns the shot. Additional fingers/keys cannot release it.
	if _charge_active or not _charge_allowed():
		return
	if online and net.seat > 0 and not _host_charge_controls:
		toast = "Värden behöver ladda om spelet för de nya skottkontrollerna."
		toast_clock = 4.0
		return
	if weapon == FREEDOM and freedom[active] == 0:
		toast = "Freedom är låst. Träffa motståndaren direkt först!"
		toast_clock = 3.0
		return
	_charge_active = true
	_charge_source = source
	_charge_context = _charge_key()
	_charge_elapsed = 0.0
	_charge_power = CHARGE_MIN

func _update_charge(delta: float) -> void:
	if not _charge_active:
		return
	if not _charge_allowed() or _charge_context != _charge_key() or (online and net.seat > 0 and not _host_charge_controls):
		_cancel_charge()
		return
	_charge_elapsed += maxf(0.0, delta)
	# A triangle wave stays bounded even through long frames and many cycles.
	var travel := fposmod(_charge_elapsed * CHARGE_SPEED, 2.0 * (CHARGE_MAX - CHARGE_MIN))
	_charge_power = CHARGE_MIN + (CHARGE_MAX - CHARGE_MIN) - absf(travel - (CHARGE_MAX - CHARGE_MIN))

func _cancel_charge() -> void:
	_charge_active = false
	_charge_source = -99
	_charge_context = ""

func _release_charge(source: int) -> void:
	if not _charge_active or source != _charge_source:
		return
	var valid: bool = _charge_allowed() and _charge_context == _charge_key() and (not online or net.seat == 0 or _host_charge_controls)
	var selected_power := _charge_power
	_cancel_charge()
	if not valid:
		return
	# Consume the gesture before sending. Snapshot delay cannot cause duplicate shots.
	if online and net.seat > 0:
		if _send_guest_input("fire", selected_power):
			_released_context = _charge_key()
	else:
		power = selected_power
		fire()

func _input(event: InputEvent) -> void:
	# Process releases before modal guards, but validity prevents a modal/focus fire.
	if event is InputEventKey and event.physical_keycode == KEY_K and not event.pressed:
		_release_charge(-2)
	elif event is InputEventScreenTouch and not event.pressed:
		if event.canceled and _charge_source == event.index:
			_cancel_charge()
		else:
			_release_charge(event.index)
		pointers.erase(event.index)
		_refresh_held()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_release_charge(-1)
		pointers.erase(-1)
		_refresh_held()
	if lobby != null and lobby.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			lobby.request_leave()
		return
	if start_menu != null and start_menu.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				if phase == "title" or phase == "over":
					_start_action()
				else:
					_jump()
			KEY_K: _begin_charge(-2)
			KEY_J: _jump()
			KEY_TAB: _weapon_action()
			KEY_T: _target_action()
			KEY_LEFT:
				if phase == "title": _map_action(-1)
			KEY_RIGHT:
				if phase == "title": _map_action(1)
			KEY_ESCAPE:
				_clear_local_controls(true)
				help_open = not help_open
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
		_cancel_charge()
		prediction.reset()
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
		_release_charge(id)
		pointers.erase(id)
		_refresh_held()
		return
	if help_open:
		if buttons.close_help.has_point(p) or buttons.help.has_point(p):
			help_open = false
		return
	if buttons.help.has_point(p):
		_clear_local_controls(true)
		help_open = true
		return
	if buttons.sound.has_point(p):
		sound_on = not sound_on
		return
	if buttons.restart.has_point(p):
		_restart_action()
		return
	if phase == "title" or phase == "over":
		if phase == "title" and buttons.map_prev.has_point(p):
			_map_action(-1)
		elif phase == "title" and buttons.map_next.has_point(p):
			_map_action(1)
		elif phase == "title" and buttons.online.has_point(p):
			_open_online()
		elif buttons.start.has_point(p):
			_start_action()
		return
	if phase != "aim" or not _can_control():
		return
	for action in ["left", "right", "jump", "angle_down", "angle_up", "weapon", "target", "fire"]:
		if action == "target" and weapon != FREEDOM:
			continue
		if buttons.has(action) and buttons[action].has_point(p):
			match action:
				"jump": _jump()
				"weapon": _weapon_action()
				"target": _target_action()
				"fire":
					_begin_charge(id)
					if _charge_active and _charge_source == id:
						pointers[id] = "fire"
						_refresh_held()
				_:
					pointers[id] = action
					_refresh_held()
			return
	if world_rect.has_point(p) and p.y > header_bottom and ui_to_world(p).y < WATER:
		pointers[id] = "aim"
		_aim_at(p)

func _refresh_held() -> void:
	held.clear()
	for action in pointers.values():
		held[action] = true

func _aim_at(p: Vector2) -> void:
	if not _can_control():
		return
	var delta: Vector2 = ui_to_world(p) - _view_position(active) + Vector2(0, 25)
	if delta.length() < 15:
		return
	if absf(delta.x) > 0.01:
		fighters[active].face = signf(delta.x)
	angle = clampf(rad_to_deg(atan2(-delta.y, absf(delta.x))), 5, 85)
	if online and net.seat > 0:
		_pending_aim = [fighters[active].face, angle]

func _restart_action() -> void:
	_clear_local_controls(true)
	if online:
		lobby.visible = true
		lobby.request_leave()
		return
	# One click returns to the title; a separate start prevents accidental resets.
	if phase != "title":
		phase = "title"
		projectile.clear()
		fragments.clear()
		pointers.clear()
		held.clear()
	else:
		start_game()

func _clear_local_controls(send_neutral: bool = false) -> void:
	_cancel_charge()
	prediction.reset()
	pointers.clear()
	held.clear()
	_pending_aim.clear()
	if send_neutral and online and net != null and net.seat > 0 and net.together() and active == net.seat and phase == "aim":
		net.send_input({"move": 0.0, "angle_axis": 0.0, "power_axis": 0.0}, turn)

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
	var wobble := Vector2(sin(elapsed * 66), cos(elapsed * 52)) * shake
	draw_set_transform((world_to_ui(Vector2.ZERO) + wobble) * ui_scale + ui_origin, 0, Vector2.ONE * ui_scale)
	_draw_world()
	draw_set_transform(ui_origin, 0, Vector2.ONE * ui_scale)
	_draw_header()
	_draw_controls()
	if phase == "title" and start_menu == null:
		_draw_title()
	elif phase == "over":
		_draw_victory()
	elif banner_clock > 0:
		var alpha := minf(1, banner_clock * 2)
		var banner_y := header_bottom + 12.0
		_round_rect(Rect2(390, banner_y, 500, 56), Color(0.09, 0.10, 0.17, alpha * 0.96), 28)
		_text(banner, Vector2(640, banner_y + 37), 28 if portrait else 24, Color(1, 0.95, 0.85, alpha), true, true)
	if toast_clock > 0 and phase != "over":
		_text(toast, Vector2(640, header_bottom + 102), 27 if portrait else 22, CREAM, true, true)
	if help_open:
		_draw_help()

func _online_header(include_room: bool) -> String:
	if net == null or net.seat < 0:
		return "ONLINE · PRIVAT RUM"
	var role := str(net.roster[net.seat].name).to_upper() if net.seat < net.roster.size() else "SPELARE"
	return "ONLINE · %s · DU ÄR %s" % [net.room, role] if include_room else "ONLINE · DU ÄR " + role

func _draw_header() -> void:
	_draw_group_header()

func _draw_group_header() -> void:
	if not touch_controls:
		_draw_desktop_header()
		return
	var compact := compact_landscape
	var title_size := 36 if portrait else (22 if compact else 22)
	var title_y := 55.0 if portrait else 32.0
	_round_rect(Rect2(8, 6, 802 if portrait else 300, 116 if portrait else 56), Color(0.09, 0.10, 0.17, 0.76), 12)
	_round_rect(Rect2(8, header_bottom - 35, 1264, 37), Color(0.09, 0.10, 0.17, 0.64), 10)
	_text("KRATERKOMPISAR", Vector2(20, title_y), title_size, GOLD, true)
	var subtitle := "BANA %d · %s" % [map_id + 1, MapThemes.title(map_id)]
	_text(subtitle, Vector2(20, 96 if portrait else 53), 24 if portrait else (14 if compact else 12), MUTED)
	for action in ["sound", "help", "restart"]:
		var r: Rect2 = buttons[action]
		var symbol := "?" if action == "help" else ("↻" if action == "restart" else ("♫" if sound_on else "♪"))
		_round_rect(r, Color(0.19, 0.20, 0.29, 0.72), 12)
		_text(symbol, r.get_center() + Vector2(0, 15 if portrait else 10), 46 if portrait else (32 if compact else 26), CREAM if action == "help" else MUTED, true, true)
	var count := fighters.size()
	var columns := mini(3, count)
	var card_span: float = minf(688.0, buttons.sound.position.x - 342.0)
	var card_w := (1240.0 - (columns - 1) * 14.0) / columns if portrait else (card_span - (columns - 1) * 12.0) / columns
	var card_h := 82.0 if portrait else 34.0
	var card_y: float = buttons.help.end.y + 14.0 if portrait else 10.0
	var card_x := 20.0 if portrait else 326.0
	for i in range(count):
		var r := Rect2(card_x + (i % columns) * (card_w + (14.0 if portrait else 12.0)), card_y + int(i / columns) * (card_h + 8.0), card_w, card_h)
		var color := _fighter_color(i)
		var alive: bool = fighters[i].hp > 0
		var selected := i == active and phase == "aim"
		_round_rect(r, Color("26283e"), 9, color if selected else Color("3a3b50"), 2 if selected else 1)
		var font_size := 30 if portrait else 16
		var name_text := str(fighters[i].name)
		var name_limit := card_w - (134.0 if portrait else 73.0)
		while BOLD.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > name_limit and name_text.length() > 2:
			name_text = name_text.left(name_text.length() - 1)
		_text(name_text, r.position + Vector2(12, 42 if portrait else 23), font_size, color if alive else MUTED, true)
		_text(str(fighters[i].hp) if alive else "UTE", r.position + Vector2(r.size.x - (40 if portrait else 24), 42 if portrait else 23), font_size, color if alive else MUTED, true, true)
		if freedom[i] > 0:
			_text("F", r.position + Vector2(r.size.x - (90 if portrait else 53), 42 if portrait else 23), 27 if portrait else 14, GOLD, true)
		var bar := Rect2(r.position + Vector2(12, 60 if portrait else 29), Vector2(r.size.x - 24, 7 if portrait else 3))
		_round_rect(bar, Color("414154"), 3)
		bar.size.x *= float(fighters[i].hp) / 100.0
		if bar.size.x > 0:
			_round_rect(bar, color, 3)
	var wind_text := "VIND %s %d" % ["→" if wind >= 0 else "←", int(absf(wind))]
	if portrait:
		_text(wind_text, Vector2(20, header_bottom - 6), 25, CREAM, true)
		_text("TUR %d · %02d s" % [turn, maxi(0, int(ceil(turn_clock)))], Vector2(1260, header_bottom - 6) - Vector2(BOLD.get_string_size("TUR %d · %02d s" % [turn, maxi(0, int(ceil(turn_clock)))], HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x, 0), 25, GOLD, true)
	else:
		_text(wind_text, Vector2(20, header_bottom - 6), 14 if compact else 12, CREAM, true)
		if online:
			_text(_online_header(false), Vector2(660, header_bottom - 6), 13 if compact else 12, MUTED, true, true)

func _draw_desktop_header() -> void:
	# Separate translucent chips leave the entire arena behind the HUD visible.
	var live := phase == "aim"
	var state := "%s · %02d s" % [str(fighters[active].name), maxi(0, int(ceil(turn_clock)))] if live else "SKOTTET ÄR I LUFTEN…"
	_round_rect(Rect2(14, 8, 258, 44), Color(0.09, 0.10, 0.17, 0.76), 10)
	_text(state, Vector2(24, 27), 16, _fighter_color(active), true)
	_text("TUR %d · VIND %s %d" % [turn, "→" if wind >= 0 else "←", int(absf(wind))], Vector2(24, 44), 11, CREAM)
	var count := fighters.size()
	var card_w := minf(172.0, (842.0 - (count - 1) * 8.0) / count)
	var start_x := 1124.0 - (card_w * count + (count - 1) * 8.0)
	for i in range(count):
		var r := Rect2(start_x + i * (card_w + 8), 10, card_w, 32)
		var col := _fighter_color(i)
		var alive: bool = fighters[i].hp > 0
		_round_rect(r, Color(0.09, 0.10, 0.17, 0.77), 8, col if i == active and live else Color(0.5, 0.5, 0.6, 0.25), 1)
		var name_text := str(fighters[i].name)
		while BOLD.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > card_w - 56 and name_text.length() > 2:
			name_text = name_text.left(name_text.length() - 1)
		_text(name_text, r.position + Vector2(9, 20), 13, col if alive else MUTED, true)
		_text(str(fighters[i].hp) if alive else "UTE", r.position + Vector2(card_w - 19, 20), 13, col if alive else MUTED, true, true)
		if freedom[i] > 0:
			_text("F", r.position + Vector2(card_w - 43, 20), 11, GOLD, true)
		var bar := Rect2(r.position + Vector2(9, 26), Vector2(card_w - 18, 2))
		_round_rect(bar, Color("414154"), 1)
		bar.size.x *= float(fighters[i].hp) / 100.0
		if bar.size.x > 0:
			_round_rect(bar, col, 1)
	for action in ["sound", "help", "restart"]:
		var r: Rect2 = buttons[action]
		var symbol := "?" if action == "help" else ("↻" if action == "restart" else ("♫" if sound_on else "♪"))
		_round_rect(r, Color(0.09, 0.10, 0.17, 0.75), 9)
		_text(symbol, r.get_center() + Vector2(0, 7), 21, CREAM if action == "help" else MUTED, true, true)

func _draw_world() -> void:
	if world3d != null:
		_draw_3d_world()
		return
	MapThemes.draw_background(self, map_id, elapsed)
	draw_texture(terrain_texture, Vector2.ZERO)
	# Flowers and tufts survive only while their ground survives.
	for x in [64, 128, 350, 392, 748, 799, 925, 1178, 1202]:
		var y := 0
		while y < WH and not _solid(Vector2(x, y)):
			y += 1
		if y < WATER - 5:
			draw_line(Vector2(x, y), Vector2(x - 4, y - 13), MapThemes.accent_color(map_id), 2, true)
			draw_line(Vector2(x, y), Vector2(x + 5, y - 10), MapThemes.accent_color(map_id).darkened(0.15), 2, true)
			if x % 2 == 0:
				draw_circle(Vector2(x - 4, y - 14), 3, CREAM)
	if phase == "aim":
		_draw_aim()
	for n in range(trail.size()):
		if trail[n].y > ui_to_world(Vector2(0, header_bottom)).y:
			draw_circle(trail[n], 2.8 * float(n + 1) / maxf(1, trail.size()), Color(1, 0.95, 0.82, 0.45 * float(n + 1) / maxf(1, trail.size())))
	for i in range(fighters.size()):
		if fighters[i].hp > 0:
			_draw_character(i, _view_position(i), 1.25 if portrait else 1.0, prediction.face_for(self, i), true)
		elif fighters[i].pos.y < WATER:
			var p: Vector2 = fighters[i].pos
			draw_line(p + Vector2(-8, 0), p + Vector2(8, -20), CREAM, 4, true)
			draw_line(p + Vector2(8, 0), p + Vector2(-8, -20), CREAM, 4, true)
	if not projectile.is_empty():
		_draw_projectile(projectile)
	for fragment in fragments:
		_draw_projectile(fragment)
	for part in particles:
		var col: Color = part.color
		col.a = minf(1, part.life / part.max * 2)
		draw_circle(part.pos, part.size, col)
	for f in floaters:
		_text(f.text, f.pos, 25, f.color, true, true)
	# Water moves independently of the destructible bitmap.
	draw_rect(Rect2(0, WATER, WW, WH - WATER), MapThemes.water_color(map_id))
	var wave := PackedVector2Array()
	for x in range(0, WW + 1, 8):
		wave.append(Vector2(x, WATER + sin(x * 0.035 + elapsed * 2.0) * 2.0))
	draw_polyline(wave, MapThemes.wave_color(map_id), 4, true)
	for n in range(15):
		var x := fmod(n * 97 + elapsed * 8, 1280)
		draw_line(Vector2(x, 454 + (n % 3) * 5), Vector2(x + 31, 454 + (n % 3) * 5), MapThemes.wave_color(map_id).darkened(0.2), 2)

func _draw_3d_world() -> void:
	draw_texture_rect(world3d.get_texture(), world3d.render_bounds, false)
	# Only readable tactical annotations stay on the 2D canvas.
	if phase == "aim":
		_draw_aim()
	for n in range(trail.size()):
		if trail[n].y > ui_to_world(Vector2(0, header_bottom)).y:
			draw_circle(trail[n], 2.8 * float(n + 1) / maxf(1, trail.size()), Color(1, 0.95, 0.82, 0.45 * float(n + 1) / maxf(1, trail.size())))
	for i in range(fighters.size()):
		if fighters[i].hp <= 0:
			continue
		var p: Vector2 = _view_position(i)
		var col: Color = _fighter_color(i)
		var name_label := str(fighters[i].name).left(12)
		var label_width := clampf(BOLD.get_string_size(name_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0, 96, 186)
		if i == active and phase == "aim":
			var arrow := p + Vector2(0, -108 + sin(elapsed * 4) * 3)
			draw_colored_polygon(PackedVector2Array([arrow + Vector2(-7, -7), arrow + Vector2(7, -7), arrow + Vector2(0, 2)]), col)
		_round_rect(Rect2(p + Vector2(-label_width * 0.5, -96), Vector2(label_width, 23)), INK, 11)
		_text(name_label, p + Vector2(0, -79), 13, col, true, true)
		_round_rect(Rect2(p + Vector2(-26, -69), Vector2(52, 4)), Color("514959"), 2)
		_round_rect(Rect2(p + Vector2(-26, -69), Vector2(52.0 * fighters[i].hp / 100, 4)), col, 2)
	var rendered: Array = fragments.duplicate()
	if not projectile.is_empty():
		rendered.append(projectile)
	for bullet in rendered:
		if bullet.pos.y < ui_to_world(Vector2(0, header_bottom)).y + 3:
			_draw_projectile(bullet)
		elif int(bullet.weapon) == FREEDOM:
			var target: Vector2 = fighters[int(bullet.target)].pos + Vector2(0, -19)
			draw_arc(target, 28, elapsed * 3, elapsed * 3 + PI * 1.5, 24, Color("83d9fa"), 2, true)
	for f in floaters:
		_text(f.text, f.pos, 25, f.color, true, true)

func _draw_projectile(bullet: Dictionary) -> void:
	var p: Vector2 = bullet.pos
	if p.y < ui_to_world(Vector2(0, header_bottom)).y + 3:
		_text("•  %dm" % int(-p.y / 10), Vector2(clampf(p.x, 50, 1230), ui_to_world(Vector2(0, header_bottom)).y + 22), 18, CREAM, true, true)
		return
	match int(bullet.weapon):
		ROCKET:
			draw_circle(p, 7, CREAM)
			draw_circle(p, 4, GOLD)
		BOMB:
			draw_circle(p, 10, MINT)
			draw_line(p + Vector2(0, -8), p + Vector2(4, -15), CREAM, 2, true)
			draw_circle(p + Vector2(4, -15), 3, GOLD)
		BANANA, BANANA_FRAGMENT:
			var radius := 14.0 if bullet.weapon == BANANA else 8.0
			var rotation: float = bullet.age * 4.0
			var peel := PackedVector2Array()
			for n in range(9):
				peel.append(p + Vector2.from_angle(rotation + PI * 0.15 + n * PI * 0.12) * radius)
			draw_polyline(peel, Color("785327"), 9 if bullet.weapon == BANANA else 6, true)
			draw_polyline(peel, GOLD, 6 if bullet.weapon == BANANA else 4, true)
			draw_circle(peel[0], 2, Color("5e472d"))
			draw_circle(peel[peel.size() - 1], 2, Color("5e472d"))
		FREEDOM:
			var heading: Vector2 = bullet.vel.normalized()
			var side := heading.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + heading * 15, p - heading * 9 + side * 6, p - heading * 6 - side * 6]), CREAM)
			draw_line(p - heading * 8, p - heading * (21 + sin(elapsed * 40) * 4), GOLD, 5, true)
			draw_line(p - side * 7 - heading * 6, p + side * 7 - heading * 6, Color("83d9fa"), 3, true)
			var target: Vector2 = fighters[int(bullet.target)].pos + Vector2(0, -19)
			draw_arc(target, 28, elapsed * 3, elapsed * 3 + PI * 1.5, 24, Color("83d9fa"), 2, true)

func _draw_character(i: int, p: Vector2, s: float, face: float, label: bool) -> void:
	var bounce := sin(elapsed * 3.3 + i) * 1.2
	var center := p + Vector2(0, -24 * s + bounce)
	var col: Color = _fighter_color(i)
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
	var aim_dir := _view_direction() if i == active and phase == "aim" and label else Vector2(face, -0.3).normalized()
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

func _view_position(index: int) -> Vector2:
	return prediction.position_for(self, index)

func _view_direction() -> Vector2:
	var view_angle: float = prediction.angle_for(self)
	return Vector2(cos(deg_to_rad(view_angle)) * prediction.face_for(self, active), -sin(deg_to_rad(view_angle)))

func _draw_aim() -> void:
	var d := _view_direction()
	var start: Vector2 = _view_position(active) + Vector2(0, -27) + d * 30
	var velocity := d * (250 + prediction.power_for(self) * 5.2)
	for n in range(1, 16):
		var t := n * 0.045
		var p := start + velocity * t + Vector2(wind, GRAVITY) * t * t * 0.5
		if _solid(p) or p.y > WATER:
			break
		if p.y > ui_to_world(Vector2(0, header_bottom)).y:
			draw_circle(p, 2.3 if n < 10 else 1.7, Color(1, 0.98, 0.85, 1.0 - n / 20.0))

func _button(action: String, label: String, color: Color = Color("303249"), text_color: Color = CREAM, size_px: int = 26) -> void:
	var r: Rect2 = buttons[action]
	var down: bool = held.get(action, false)
	var disabled := (phase != "aim" or not _can_control()) and action not in ["start", "online", "map_prev", "map_next", "close_help"]
	var col := color.lightened(0.15) if down else color
	col.a = 0.84 if not down else 0.96
	if disabled:
		col = col.darkened(0.25)
	_round_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0.07, 0.08, 0.14, 0.25), 14)
	_round_rect(r, col, 14, col.lightened(0.13), 1)
	_text(label, r.get_center() + Vector2(0, size_px * 0.36), size_px, text_color.darkened(0.30) if disabled else text_color, true, true)

func _weapon_label() -> String:
	return ["● RAKET", "● STUDSBOMB", "BANANKLUSTER", "FREEDOM ×%d" % freedom[active]][weapon]

func _weapon_hint() -> String:
	return ["Raket · direktträff låser upp Freedom", "Studsbomb · studsar, sedan BOOM", "Banan · fem explosiva småbananer", "Målsökande · exakt 49 skada" if freedom[active] else "LÅST · direktträffa motståndaren först"][weapon]

func _draw_controls() -> void:
	if not touch_controls:
		_draw_desktop_controls()
		return
	var color := _fighter_color(active)
	var live := phase == "aim"
	# Controls float over the rendered water; there is no reserved opaque panel.
	_round_rect(Rect2(8, panel_y + 4, 1264, layout_h - panel_y - 8), Color(0.09, 0.10, 0.17, 0.42), 18)
	if compact_landscape:
		_draw_compact_controls(color, live)
		return
	var status := ("%s · DIN TUR" % str(fighters[active].name)) if live else ("SKOTTET ÄR I LUFTEN…" if phase == "flying" else "KRATERKOMPISAR")
	if online and live and not _can_control():
		status = "%s · VÄNTA PÅ DIN TUR" % str(fighters[active].name)
	_text(status, Vector2(20, panel_y + (36 if portrait else 22)), 28 if portrait else 15, color, true)
	var time_text := "%02d s" % maxi(0, int(ceil(turn_clock))) if live else ""
	_text(time_text, Vector2(1224, panel_y + (36 if portrait else 22)), 28 if portrait else 15, GOLD if turn_clock < 10 else MUTED, true, true)
	_button("left", "←", Color("303249"), CREAM, 52 if portrait else 27)
	_button("right", "→", Color("303249"), CREAM, 52 if portrait else 27)
	_button("jump", "HOPPA" if portrait else "HOPP", Color("303249"), CREAM, 27 if portrait else 15)
	_button("angle_down", "−", Color("303249"), CREAM, 48 if portrait else 28)
	_button("angle_up", "+", Color("303249"), CREAM, 48 if portrait else 28)
	var angle_center := Vector2((buttons.angle_down.end.x + buttons.angle_up.position.x) * 0.5, buttons.angle_up.get_center().y)
	_text("%d°" % int(prediction.angle_for(self)), angle_center + Vector2(0, 14 if portrait else 9), 43 if portrait else 25, CREAM, true, true)
	_button("weapon", _weapon_label() + ("  ↻" if portrait else "  · TAB"), Color("373249"), GOLD if weapon != FREEDOM or freedom[active] else MUTED, 27 if portrait else 15)
	_draw_target_button()
	_draw_charge_button()
	var walk := Rect2(buttons.left.position + Vector2(0, buttons.left.size.y + 8), Vector2(buttons.jump.end.x - buttons.left.position.x, 4))
	_round_rect(walk, Color("36384d"), 2)
	walk.size.x *= clampf(move_left / 170.0, 0, 1)
	if walk.size.x > 0:
		_round_rect(walk, color, 2)
	if portrait:
		_text("Dra i himlen för att sikta · håll och släpp för att skjuta", Vector2(640, buttons.fire.end.y + 48), 25, MUTED, false, true)
		_text("Liggande skärm ger större figurer och bättre överblick", Vector2(640, buttons.fire.end.y + 84), 24, MUTED, false, true)
	else:
		_text("A/D  flytta    Mellanslag  hoppa    W/S  sikta    Tab  vapen    K  håll & släpp" + ("    T  mål" if fighters.size() > 2 else ""), Vector2(20, panel_y + 103), 13, MUTED)
		_text("KRAFT %d%%" % int(prediction.power_for(self)), Vector2(1074, panel_y + 103), 13, GOLD, true, true)

func _draw_desktop_controls() -> void:
	_round_rect(Rect2(14, layout_h - 62, 568, 46), Color(0.09, 0.10, 0.17, 0.66), 10)
	_text("A/D  flytta   Mellanslag  hoppa   W/S eller mus  sikta   Tab  vapen", Vector2(24, layout_h - 42), 12, CREAM)
	var detail := "%d° · %s" % [int(prediction.angle_for(self)), _weapon_hint()]
	if online and not _can_control() and phase == "aim":
		detail = "VÄNTA PÅ DIN TUR · " + str(fighters[active].name)
	_text(detail, Vector2(24, layout_h - 25), 11, GOLD if weapon == FREEDOM else MUTED)
	_button("weapon", _weapon_label() + " ↻", Color("373249"), GOLD if weapon != FREEDOM or freedom[active] else MUTED, 13)
	if weapon == FREEDOM:
		_draw_target_button()
	_draw_charge_button()

func _draw_charge_button() -> void:
	var r: Rect2 = buttons.fire
	var charging := _charge_active
	var disabled := phase != "aim" or not _can_control()
	var col := GOLD.lightened(0.12) if charging else GOLD
	col.a = 0.92
	if disabled:
		col = col.darkened(0.35)
	_round_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0.07, 0.08, 0.14, 0.25), 12)
	_round_rect(r, col, 12, col.lightened(0.12), 1)
	var label := "SLÄPP!  %d%%" % int(prediction.power_for(self)) if charging else ("HÅLL & SLÄPP" if portrait or compact_landscape else "K · HÅLL & SLÄPP")
	var font_size := 36 if portrait else (19 if compact_landscape else 14)
	_text(label, r.get_center() + Vector2(0, -2 if portrait else 1), font_size, INK, true, true)
	var meter := Rect2(r.position + Vector2(16, r.size.y - (28 if portrait else 13)), Vector2(r.size.x - 32, 10 if portrait else 5))
	_round_rect(meter, Color(0.1, 0.11, 0.18, 0.22), 4)
	meter.size.x *= clampf(prediction.power_for(self) / 100.0, 0, 1)
	_round_rect(meter, INK, 4)

func _draw_target_button() -> void:
	if fighters.size() <= 2 or not buttons.has("target"):
		return
	var label := "MÅL: %s" % str(fighters[target].name).left(12)
	_button("target", label + " ↻", Color("373249"), _fighter_color(target) if weapon == FREEDOM else MUTED, 25 if portrait else (18 if compact_landscape else 14))

func _draw_compact_controls(color: Color, live: bool) -> void:
	var status := ("%s · DIN TUR" % str(fighters[active].name)) if live else "SKOTTET ÄR I LUFTEN…"
	if online and live and not _can_control():
		status = "%s · VÄNTA PÅ DIN TUR" % str(fighters[active].name)
	_text(status, Vector2(20, panel_y + 21), 19, color, true)
	_text("%02d s" % maxi(0, int(ceil(turn_clock))) if live else "", Vector2(990, panel_y + 21), 19, GOLD, true, true)
	_button("left", "←", Color("303249"), CREAM, 32)
	_button("right", "→", Color("303249"), CREAM, 32)
	_button("jump", "HOPP", Color("303249"), CREAM, 21)
	_button("angle_down", "−", Color("303249"), CREAM, 34)
	_button("angle_up", "+", Color("303249"), CREAM, 34)
	_text("%d°" % int(prediction.angle_for(self)), Vector2((buttons.angle_down.end.x + buttons.angle_up.position.x) * 0.5, buttons.angle_up.get_center().y + 10), 28, CREAM, true, true)
	_button("weapon", ["RAKET ↻", "STUDSBOMB ↻", "BANANKLUSTER ↻", "FREEDOM ×%d ↻" % freedom[active]][weapon], Color("373249"), GOLD, 20)
	_draw_target_button()
	_draw_charge_button()

func _draw_title() -> void:
	draw_rect(Rect2(0, world_top, 1280, WH), Color(0.09, 0.10, 0.17, 0.25))
	_round_rect(Rect2(80 if portrait else 244, world_top + 10, 1120 if portrait else 792, 640 if portrait else 443), Color("1f2237"), 26, Color("58516c"), 2)
	_text("FEM VÄRLDAR. TVÅ STORA EGON.", Vector2(640, world_top + (60 if portrait else 52)), 25 if portrait else 14, GOLD, true, true)
	_text("Kraterkompisar", Vector2(640, world_top + (130 if portrait else 108)), 59 if portrait else 51, CREAM, true, true)
	_text("Daniel & Jesus · välj er arena", Vector2(640, world_top + (178 if portrait else 140)), 29 if portrait else 19, MUTED, false, true)
	_button("map_prev", "←", Color("373249"), CREAM, 50 if portrait else 30)
	_button("map_next", "→", Color("373249"), CREAM, 50 if portrait else 30)
	_text("%d / %d  ·  %s" % [map_id + 1, MapThemes.count(), MapThemes.title(map_id)], Vector2(640, world_top + (262 if portrait else 193)), 30 if portrait else 22, MapThemes.accent_color(map_id), true, true)
	_text(MapThemes.subtitle(map_id), Vector2(640, world_top + (309 if portrait else 222)), 23 if portrait else 14, MUTED, false, true)
	_button("start", "LOKAL DUELL · SAMMA SKÄRM", GOLD, INK, 29 if portrait else 20)
	_button("online", "ONLINE · VARSIN SKÄRM", Color("51466f"), CREAM, 31 if portrait else 20)
	if not portrait:
		_text("Värden väljer bana · 40 sekunder per tur · inga konton", Vector2(640, world_top + 426), 13, MUTED, false, true)

func _draw_victory() -> void:
	draw_rect(world_rect, Color(0.09, 0.10, 0.17, 0.50))
	var y: float = buttons.start.position.y - (420.0 if portrait else 284.0)
	var card := Rect2(80 if portrait else 270, y, 1120 if portrait else 740, buttons.start.end.y - y + 24.0)
	_round_rect(card, Color("1f2237"), 26, Color("746789"), 2)
	_text("ARENANS NYA MÄSTARE", Vector2(640, y + 52), 28 if portrait else 16, GOLD, true, true)
	var headline := "Oavgjort!" if winner < 0 else "%s vann!" % fighters[winner].name
	var headline_size := 58 if portrait else 52
	while BOLD.get_string_size(headline, HORIZONTAL_ALIGNMENT_LEFT, -1, headline_size).x > card.size.x - 60 and headline_size > 28:
		headline_size -= 2
	_text(headline, Vector2(640, y + (138 if portrait else 122)), headline_size, CREAM, true, true)
	_text("%d skott. En bana med helt ny planlösning." % shots, Vector2(640, y + (202 if portrait else 164)), 29 if portrait else 21, MUTED, false, true)
	if winner >= 0:
		_text("★", Vector2(640, y + (335 if portrait else 246)), 92 if portrait else 66, _fighter_color(winner), true, true)
	_button("start", ("NYTT RUM  →" if online else "EN DUELL TILL  ↻"), GOLD, INK, 24 if not portrait else 32)

func _draw_help() -> void:
	draw_rect(Rect2(0, 0, 1280, layout_h), Color(0.06, 0.07, 0.12, 0.90))
	var h := 750.0 if portrait else 442.0
	var y := maxf(16.0, (layout_h - h) * 0.5)
	_round_rect(Rect2(40 if portrait else 210, y, 1200 if portrait else 860, h), Color("25283f"), 24, Color("57516a"), 2)
	_text("Så blir du arenamästare", Vector2(640, y + (72 if portrait else 57)), 43 if portrait else 32, CREAM, true, true)
	var lines := ["A/D eller pilar: flytta. Mellanslag: hoppa.", "W/S eller dra i himlen: sikta. Tab: byt vapen.", "Håll K: kraften går upp och ner. Släpp K: skjut!", "På mobil: håll skjutknappen och släpp vid rätt kraft.", "Direktträff ger Freedom: målsökande, exakt 49 skada.", "T / Mål byter fiende. Välj en av fem banor i menyn."]
	for n in range(lines.size()):
		_text(lines[n], Vector2(640, y + (150 if portrait else 109) + n * (67 if portrait else 38)), 36 if portrait else 19, CREAM if n < 4 else MUTED, false, true)
	_button("close_help", "NU KÖR VI", MINT, INK, 34 if portrait else 23)

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
	return {"phase": phase, "turn": turn, "active": active, "hp": fighters.map(func(f): return f.hp), "angle": angle, "power": power, "shots": shots, "winner": winner, "projectile": not projectile.is_empty(), "terrain_center": _solid(Vector2(640, 400)), "size": get_viewport_rect().size}

## Online mode. Only Daniel's device simulates. Jesus sends bounded controls.
func _can_control() -> bool:
	if help_open or (lobby != null and lobby.visible):
		return false
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
	_cancel_charge()
	if online and net.seat > 0:
		_send_guest_input("weapon")
	else:
		weapon = (weapon + 1) % 4

func _open_online() -> void:
	_cancel_charge()
	_released_context = ""
	online = true
	_online_started = false
	_host_charge_controls = false
	_host_paused = false
	_state_age = 0
	phase = "title"
	_last_received_seq = -1
	_remote_input_seq = -1
	_last_commit_key = ""
	_remote_held.clear()
	pointers.clear()
	held.clear()
	lobby.set_map(map_id)
	lobby.visible = true
	if start_menu != null:
		start_menu.hide()
	lobby.refresh(net)

func _leave_online() -> void:
	_cancel_charge()
	_released_context = ""
	prediction.reset()
	online = false
	net.leave()
	_online_started = false
	_remote_held.clear()
	_pending_aim.clear()
	lobby.visible = false
	phase = "title"
	projectile.clear()
	fragments.clear()
	pointers.clear()
	held.clear()
	help_open = false
	player_names = ["Daniel", "Jesus"]
	_spawn_fighters()
	_layout()
	if start_menu != null:
		start_menu.set_map(map_id)
		start_menu.show()

func _copy_room() -> void:
	if not net.room.is_empty():
		DisplayServer.clipboard_set(net.room)
		lobby.message.text = "Rumskoden är %s. Skicka den till din medspelare." % net.room

func _network_changed() -> void:
	_cancel_charge()
	_released_context = ""
	if not online or lobby == null:
		return
	_remote_held.clear()
	pointers.clear()
	held.clear()
	if not net.started and not net.room.is_empty() and net.map_id != map_id:
		_set_preview_map(net.map_id)
		lobby.set_map(map_id)
	if net.together() and net.seat == 0 and not _online_started:
		start_game()
		_online_started = true
		_send_state(true)
	_refresh_network_overlay()

func _network_welcome(data: Dictionary) -> void:
	_cancel_charge()
	_released_context = ""
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
	if data.get("type") == "state" and net.seat > 0:
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
	var show_overlay: bool = lobby.is_confirming_leave() or not net.together() or not _online_started or _online_paused()
	# Hidden lobby controls need no font/layout refresh on every 10 Hz snapshot.
	# Presence/status changes still refresh via _network_changed.
	if not show_overlay and not lobby.visible:
		return
	lobby.visible = show_overlay
	lobby.refresh(net)
	if net.together() and _online_started and _online_paused():
		held.clear()
		pointers.clear()
		_pending_aim.clear()
		lobby.message.text = "Matchen är pausad. Be värden öppna spelfliken igen." if net.seat > 0 else "Matchen är pausad medan spelfönstret är i bakgrunden."

func _network_tick(delta: float) -> void:
	if online and net != null and net.seat > 0 and _online_started:
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

func _send_guest_input(action: String = "", shot_power: float = -1.0) -> bool:
	if not online or net.seat <= 0 or not net.together() or active != net.seat or phase != "aim" or _online_paused():
		return false
	var controls := {"move": 0.0, "angle_axis": 0.0, "power_axis": 0.0}
	if not help_open and _host_focused and (lobby == null or not lobby.visible):
		controls.move = _held_value("right", KEY_D, KEY_RIGHT) - _held_value("left", KEY_A, KEY_LEFT)
		controls.angle_axis = _held_value("angle_up", KEY_W, KEY_UP) - _held_value("angle_down", KEY_S, KEY_DOWN)
		if not _pending_aim.is_empty():
			controls.aim = _pending_aim.duplicate()
		if not action.is_empty():
			controls.action = action
	if action == "fire" and shot_power >= CHARGE_MIN:
		controls.shot_power = shot_power
	if net.send_input(controls, turn):
		_pending_aim.clear()
		return true
	return false

func _apply_remote_input(data: Dictionary) -> bool:
	if not online or net.seat != 0 or not net.together() or phase != "aim" or active <= 0 or not _host_focused:
		return false
	for key in ["seat", "turn", "seq"]:
		if not _number_in(data.get(key), 0, 1000000000) or float(data[key]) != floorf(float(data[key])):
			return false
	if data.get("action", "") not in ["", "jump", "weapon", "target", "fire"]:
		return false
	if data.has("shot_power") and (data.get("action", "") != "fire" or not _number_in(data.shot_power, CHARGE_MIN, CHARGE_MAX)):
		return false
	var sender := int(data.get("seat", -1))
	if sender != active or int(data.get("turn", -1)) != turn:
		return false
	var sequence := int(data.get("seq", -1))
	if sequence <= int(_remote_input_sequences.get(sender, -1)):
		return false
	for key in ["move", "angle_axis", "power_axis"]:
		if not _number_in(data.get(key, 0), -1, 1):
			return false
	if data.has("aim") and not _valid_pair(data.aim, -85, 85):
		return false
	if data.has("target") and (not _number_in(data.target, 0, fighters.size() - 1) or float(data.target) != floorf(float(data.target)) or not _valid_target(int(data.target), active)):
		return false
	_remote_input_seq = sequence
	_remote_input_sequences[sender] = sequence
	_remote_input_age = 0
	if data.has("target"):
		target = int(data.target)
	var movement := float(data.get("move", 0))
	var angle_axis := float(data.get("angle_axis", 0))
	var power_axis := float(data.get("power_axis", 0))
	_remote_held = {"right": maxf(movement, 0), "left": maxf(-movement, 0), "angle_up": maxf(angle_axis, 0), "angle_down": maxf(-angle_axis, 0), "power_up": maxf(power_axis, 0), "power_down": maxf(-power_axis, 0)}
	if data.has("aim"):
		fighters[active].face = 1.0 if float(data.aim[0]) >= 0 else -1.0
		angle = clampf(float(data.aim[1]), 5, 85)
	_applying_remote = true
	match str(data.get("action", "")):
		"jump": _jump()
		"weapon": weapon = (weapon + 1) % 4
		"target":
			if not data.has("target"):
				for offset in range(1, fighters.size() + 1):
					var candidate := (target + offset) % fighters.size()
					if _valid_target(candidate, active):
						target = candidate
						break
		"fire":
			if data.has("shot_power"):
				power = float(data.shot_power)
			fire()
	_applying_remote = false
	return true

func _wire_float(value: float) -> float:
	# JSON decimal parsing may move a binary64 number by one ULP in Godot.
	# Canonical wire scalars use binary32, matching the engine's Vector2 data.
	# Re-normalize after parsing so every client holds the same exact wire state.
	return PackedFloat32Array([value])[0]

func _bullet_snapshot(bullet: Dictionary) -> Dictionary:
	if bullet.is_empty():
		return {}
	return {"pos": [bullet.pos.x, bullet.pos.y], "vel": [bullet.vel.x, bullet.vel.y], "age": _wire_float(bullet.age), "weapon": bullet.weapon, "bounces": bullet.bounces, "owner": bullet.owner, "target": bullet.target}

func _bullet_from_snapshot(bullet: Dictionary) -> Dictionary:
	if bullet.is_empty():
		return {}
	return {"pos": Vector2(float(bullet.pos[0]), float(bullet.pos[1])), "vel": Vector2(float(bullet.vel[0]), float(bullet.vel[1])), "age": _wire_float(float(bullet.age)), "weapon": int(bullet.weapon), "bounces": int(bullet.bounces), "owner": int(bullet.owner), "target": int(bullet.target)}

func network_snapshot() -> Dictionary:
	var people: Array = []
	for f in fighters:
		people.append({"pos": [f.pos.x, f.pos.y], "vel": [f.vel.x, f.vel.y], "hp": f.hp, "face": f.face, "ground": f.ground})
	var pieces: Array = []
	for fragment in fragments:
		pieces.append(_bullet_snapshot(fragment))
	var path: Array = []
	for point in trail:
		path.append([point.x, point.y])
	return {"schema": 3, "charge_controls": 1, "target": target, "map_id": map_id, "freedom": freedom.duplicate(), "fragments": pieces, "paused": (not _host_focused if net != null and net.seat == 0 else _host_paused) if online else false, "phase": phase, "turn": turn, "active": active, "angle": _wire_float(angle), "power": _wire_float(power), "weapon": weapon, "wind": _wire_float(wind), "move_left": _wire_float(move_left), "turn_clock": _wire_float(turn_clock), "settle_clock": _wire_float(settle_clock), "winner": winner, "shots": shots, "hits": hits, "fighters": people, "projectile": _bullet_snapshot(projectile), "terrain_version": craters.size(), "craters": craters.duplicate(true), "trail": path}

func _number_in(value, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _valid_pair(value, low: float = -5000, high: float = 5000) -> bool:
	return value is Array and value.size() == 2 and _number_in(value[0], low, high) and _number_in(value[1], low, high)

func _valid_snapshot(data: Dictionary) -> bool:
	if data.get("schema") != 3 or data.get("phase") not in ["aim", "flying", "settle", "over"]:
		return false
	if data.has("paused") and not data.paused is bool:
		return false
	if not data.get("fighters") is Array or data.fighters.size() < 2 or data.fighters.size() > 6:
		return false
	var count: int = data.fighters.size()
	if online and net != null and net.roster.size() >= 2 and count != net.roster.size():
		return false
	var ranges := {"turn": [1, 100000], "active": [0, count - 1], "target": [0, count - 1], "angle": [5, 85], "power": [12, 100], "weapon": [0, 3], "wind": [-100, 100], "move_left": [0, 170], "turn_clock": [-1, 40], "settle_clock": [-10, 10], "winner": [-1, count - 1], "shots": [0, 100000], "hits": [0, 200000]}
	for key in ranges:
		if not _number_in(data.get(key), ranges[key][0], ranges[key][1]):
			return false
	for key in ["turn", "active", "target", "weapon", "winner", "shots", "hits"]:
		if float(data[key]) != floorf(float(data[key])):
			return false
	if int(data.target) == int(data.active):
		return false
	if not _number_in(data.get("map_id"), 0, MapThemes.count() - 1) or float(data.map_id) != floorf(float(data.map_id)):
		return false
	if not data.get("freedom") is Array or data.freedom.size() != count:
		return false
	for ammo in data.freedom:
		if not _number_in(ammo, 0, 1) or float(ammo) != floorf(float(ammo)):
			return false
	var alive: Array[int] = []
	for index in range(count):
		var f = data.fighters[index]
		if not f is Dictionary or not _valid_pair(f.get("pos")) or not _valid_pair(f.get("vel")) or not _number_in(f.get("hp"), 0, 100) or float(f.hp) != floorf(float(f.hp)) or f.get("face") not in [-1.0, 1.0] or not f.get("ground") is bool:
			return false
		if f.hp > 0:
			alive.append(index)
	if data.phase == "aim" and (not int(data.active) in alive or not int(data.target) in alive):
		return false
	if data.phase == "over" and (alive.size() > 1 or int(data.winner) != (-1 if alive.is_empty() else alive[0])):
		return false
	if data.phase != "over" and int(data.winner) != -1:
		return false
	if not data.get("fragments") is Array or data.fragments.size() > BANANA_FRAGMENTS:
		return false
	for fragment in data.fragments:
		if not _valid_bullet(fragment, true, count):
			return false
	if not data.get("craters") is Array or data.craters.size() > MAX_CRATERS or data.get("terrain_version") != data.craters.size():
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
	return data.projectile.is_empty() or _valid_bullet(data.projectile, false, count)

func _valid_bullet(bullet, fragment: bool, count: int = -1) -> bool:
	if count < 0:
		count = fighters.size()
	if not bullet is Dictionary or not _valid_pair(bullet.get("pos")) or not _valid_pair(bullet.get("vel")) or not _number_in(bullet.get("age"), 0, 10):
		return false
	var ranges := {"weapon": [4, 4] if fragment else [0, 3], "bounces": [0, 4], "owner": [0, count - 1], "target": [0, count - 1]}
	for key in ranges:
		if not _number_in(bullet.get(key), ranges[key][0], ranges[key][1]) or float(bullet[key]) != floorf(float(bullet[key])):
			return false
	return int(bullet.target) != int(bullet.owner)

func apply_network_snapshot(data: Dictionary) -> bool:
	# Validate everything before changing the scene. Never decode executable objects.
	if not _valid_snapshot(data):
		return false
	var old_phase := phase
	var old_turn := turn
	var old_shots := shots
	var old_craters := craters.size()
	var same_prefix: bool = map_id == int(data.map_id) and craters.size() <= data.craters.size()
	map_id = int(data.map_id)
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
		carve(Vector2(float(crater[0]), float(crater[1])), float(crater[2]), true)
	var old_fighters := fighters.duplicate(true)
	var old_freedom := freedom.duplicate()
	fighters.clear()
	freedom.clear()
	for i in range(data.fighters.size()):
		var f: Dictionary = data.fighters[i]
		var name_text := str(net.roster[i].name) if online and net != null and i < net.roster.size() else (player_names[i] if i < player_names.size() else "Spelare %d" % (i + 1))
		var damage := (int(old_fighters[i].hp) if i < old_fighters.size() else 100) - int(f.hp)
		fighters.append({"name": name_text, "pos": Vector2(float(f.pos[0]), float(f.pos[1])), "vel": Vector2(float(f.vel[0]), float(f.vel[1])), "hp": int(f.hp), "face": float(f.face), "ground": bool(f.ground)})
		freedom.append(int(data.freedom[i]))
		if damage > 0:
			floaters.append({"pos": fighters[i].pos + Vector2(0, -63), "text": "−%d" % damage, "life": 1.7, "color": GOLD})
		if i < old_freedom.size() and freedom[i] > old_freedom[i]:
			_show_freedom_reward(i)
	target = int(data.target)
	if old_fighters.size() != fighters.size():
		_layout()
	_host_paused = bool(data.get("paused", false))
	_host_charge_controls = data.get("charge_controls", 0) == 1
	phase = str(data.phase)
	turn = int(data.turn)
	active = int(data.active)
	angle = _wire_float(float(data.angle))
	power = _wire_float(float(data.power))
	weapon = int(data.weapon)
	wind = _wire_float(float(data.wind))
	move_left = _wire_float(float(data.move_left))
	turn_clock = _wire_float(float(data.turn_clock))
	settle_clock = _wire_float(float(data.settle_clock))
	winner = int(data.winner)
	shots = int(data.shots)
	hits = int(data.hits)
	projectile = _bullet_from_snapshot(data.projectile)
	fragments.clear()
	for piece in data.fragments:
		fragments.append(_bullet_from_snapshot(piece))
	trail.clear()
	for point in data.trail:
		trail.append(Vector2(float(point[0]), float(point[1])))
	if _charge_active and (_charge_context != _charge_key() or not _charge_allowed()):
		_cancel_charge()
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
	if online and net != null:
		net.accept_snapshot(data)
	prediction.reconcile(self)
	return true

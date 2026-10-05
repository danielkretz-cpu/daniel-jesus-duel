extends SceneTree
## Independent charge regression review: gestures, interruption and wire authority.
class CaptureNet:
	extends "res://NetSession.gd"
	var packets: Array = []
	func send_input(input: Dictionary, turn_number: int) -> bool:
		packets.append(input.duplicate(true).merged({"turn": turn_number}))
		return true
var game
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func key(code: int, down: bool, repeat: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = down
	e.echo = repeat
	game._input(e)
func reset() -> void:
	game.online = false
	game.help_open = false
	game.lobby.visible = false
	game._host_focused = true
	game.start_game()
	game.start_menu.visible = false
	game._layout(Vector2(1280, 800))
func connect_as(seat: int) -> void:
	game.online = true
	game.net.seat = seat
	game.net.status = "connected"
	game.net.host_connected = true
	game.net.guest_connected = true
	game.net.started = true
	game.net.capacity = 2
	game.net.roster = [{"seat": 0, "name": "One", "connected": true, "alive": true}, {"seat": 1, "name": "Two", "connected": true, "alive": true}]
	game.active = 1
	game.target = 0
	game.turn = 2
func touch(index: int, down: bool, p: Vector2, cancelled: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = down
	e.position = p * game.ui_scale + game.ui_origin
	e.canceled = cancelled
	game._input(e)
func mouse(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p * game.ui_scale + game.ui_origin
	game._input(e)
func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	await process_frame
	reset()
	key(KEY_K, false)
	check(game.shots == 0, "Orphan K release cannot shoot")
	key(KEY_K, true)
	game._update_charge(0.37)
	var power_before: float = game._charge_power
	key(KEY_K, true, true)
	check(game._charge_active and is_equal_approx(game._charge_power, power_before) and game.shots == 0, "Key repeat preserves charge rather than restarting or firing")
	key(KEY_K, false)
	check(game.shots == 1 and not game._charge_active and is_equal_approx(game.projectile.vel.length(), 250 + power_before * 5.2), "K release fires exactly selected power")
	key(KEY_K, false)
	check(game.shots == 1, "Repeated release cannot duplicate launch")
	reset()
	key(KEY_SPACE, true)
	check(game.shots == 0 and game.fighters[0].vel.y < 0, "Space jumps immediately without shooting")
	reset()
	var fire_center: Vector2 = game.buttons.fire.get_center()
	touch(7, true, fire_center)
	game._update_charge(0.3)
	key(KEY_K, true)
	key(KEY_K, false)
	check(game._charge_active and game.shots == 0, "Keyboard cannot steal or release touch-owned charge")
	touch(8, true, fire_center)
	touch(8, false, fire_center)
	check(game._charge_active and game.shots == 0, "Second touch cannot steal or release first charge")
	touch(7, false, fire_center)
	check(game.shots == 1 and not game._charge_active, "Owning touch releases exactly one shot")
	reset()
	key(KEY_K, true)
	touch(7, true, fire_center)
	touch(7, false, fire_center)
	check(game._charge_active and game.shots == 0, "Touch cannot release keyboard-owned charge")
	key(KEY_K, false)
	check(game.shots == 1, "Keyboard still owns release after simultaneous touch")
	reset()
	touch(7, true, fire_center)
	touch(7, false, fire_center, true)
	check(not game._charge_active and game.shots == 0, "OS-cancelled touch never fires")
	reset()
	touch(7, true, fire_center)
	var drag := InputEventScreenDrag.new()
	drag.index = 7
	drag.position = Vector2(15, 15)
	game._input(drag)
	touch(7, false, Vector2(15, 15))
	check(game.shots == 1 and not game._charge_active, "Owning pointer drag outside button keeps release ownership")
	reset()
	touch(7, true, fire_center)
	mouse(true, fire_center)
	touch(7, false, fire_center)
	mouse(false, fire_center)
	mouse(true, fire_center)
	mouse(false, fire_center)
	check(game.shots == 1, "Synthesized mouse events around touch release cannot duplicate shot")
	reset()
	key(KEY_K, true)
	var half_cycle: float = (game.CHARGE_MAX - game.CHARGE_MIN) / game.CHARGE_SPEED
	game._update_charge(half_cycle)
	check(is_equal_approx(game._charge_power, game.CHARGE_MAX), "Charge reaches upper endpoint exactly")
	game._update_charge(half_cycle)
	check(is_equal_approx(game._charge_power, game.CHARGE_MIN), "Charge returns to lower endpoint exactly")
	game._update_charge(20 * half_cycle + half_cycle * 0.5)
	check(is_equal_approx(game._charge_power, (game.CHARGE_MAX + game.CHARGE_MIN) * 0.5), "Long hold crosses ten whole cycles without clipping or drift")
	key(KEY_K, false)
	check(game.shots == 1, "Long hold still releases exactly once")
	for interruption in ["help", "focus", "restart", "turn", "phase", "lobby", "rematch", "weapon"]:
		reset()
		key(KEY_K, true)
		game._update_charge(0.4)
		match interruption:
			"help": key(KEY_ESCAPE, true)
			"focus": game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
			"restart": game._restart_action()
			"turn": game.turn += 1
			"phase": game.phase = "settle"
			"lobby": game.lobby.visible = true
			"rematch": game.start_game()
			"weapon": game._weapon_action()
		key(KEY_K, false)
		check(game.shots == 0 and not game._charge_active, "Interrupted %s gesture cancels without delayed shot" % interruption)
	reset()
	connect_as(1)
	game.active = 0
	key(KEY_K, true)
	check(not game._charge_active and game.shots == 0, "Guest cannot begin charge on another seat's turn")
	reset()
	connect_as(1)
	key(KEY_K, true)
	game.net.roster[0].connected = false
	game.net.host_connected = false
	game._network_changed()
	key(KEY_K, false)
	check(not game._charge_active and game.shots == 0, "Disconnect cancels charge without replay after reconnect")
	reset()
	var original_net = game.net
	var capture = CaptureNet.new()
	game.add_child(capture)
	capture.set_process(false)
	game.net = capture
	connect_as(1)
	var old_host: Dictionary = game.network_snapshot()
	old_host.erase("charge_controls")
	check(game.apply_network_snapshot(old_host), "Legacy host snapshot remains readable")
	key(KEY_K, true)
	check(not game._charge_active and capture.packets.is_empty(), "Guest refuses charged shot against host without capability")
	old_host.charge_controls = 1
	check(game.apply_network_snapshot(old_host), "Upgraded host advertises release power capability")
	game.power = 83
	key(KEY_K, true)
	game._update_charge(0.61)
	var selected: float = game._charge_power
	var snapshot: Dictionary = game.network_snapshot()
	snapshot.power = 19.0
	check(game.apply_network_snapshot(snapshot), "Delayed host snapshot remains valid while guest charges")
	check(is_equal_approx(game._charge_power, selected), "Delayed host snapshot cannot overwrite local selected charge")
	key(KEY_K, false)
	check(capture.packets.size() == 1 and capture.packets[0].get("action") == "fire" and is_equal_approx(float(capture.packets[0].get("shot_power", -1)), selected), "Guest release transmits chosen power once rather than stale host power")
	key(KEY_K, false)
	check(capture.packets.size() == 1, "Guest repeated release sends no duplicate fire packet")
	game.net = original_net
	capture.queue_free()
	reset()
	connect_as(0)
	game.power = 19
	var packet := {"seat": 1, "turn": 2, "seq": 10, "action": "fire", "shot_power": selected}
	check(game._apply_remote_input(packet) and is_equal_approx(game.projectile.vel.length(), 250 + selected * 5.2), "Host launches guest shot from release payload power")
	check(not game._apply_remote_input(packet) and game.shots == 1, "Host rejects replayed release packet")
	for bad in [NAN, INF, -1, 11.9, 100.1, "75", null]:
		reset()
		connect_as(0)
		var malformed := {"seat": 1, "turn": 2, "seq": 100, "action": "fire", "shot_power": bad}
		check(not game._apply_remote_input(malformed) and game.shots == 0 and game.power == 70, "Host rejects malformed release power %s without mutation" % str(bad))
	reset()
	for viewport_size in [Vector2(1280,800), Vector2(1920,1080), Vector2(430,932), Vector2(852,393), Vector2(667,375)]:
		game._layout(viewport_size)
		var hit_tests := true
		var tested := 0
		for x in range(100, 1200, 160):
			for y in range(int(game.header_bottom + 40), int(game.layout_h - 20), 100):
				var point := Vector2(x, y)
				var control := false
				for action in ["help", "sound", "restart", "left", "right", "jump", "angle_down", "angle_up", "weapon", "target", "fire"]:
					if game.buttons.has(action) and game.buttons[action].has_point(point):
						control = true
				if control or game.ui_to_world(point).y >= game.WATER: continue
				game._pointer(point, 99, true)
				hit_tests = hit_tests and game.pointers.get(99) == "aim"
				game._pointer(point, 99, false)
				tested += 1
		check(hit_tests and tested > 0, "Overlay background leaves %d battlefield aim points usable at %s" % [tested, viewport_size])
		var origin := Vector2(375, 240)
		check(game.ui_to_world(game.world_to_ui(origin)).distance_to(origin) < 0.001, "Pointer/world mapping round trips at %s" % viewport_size)
	print("RESULT: %d independent charge checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

extends SceneTree
## Real scene tests for authority, replay, malformed packets and interrupted flows.
var host
var guest
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func scene():
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	return game

func connected(game, seat: int) -> void:
	game.online = true
	game.net.seat = seat
	game.net.status = "connected"
	game.net.host_connected = true
	game.net.guest_connected = true

func transfer() -> bool:
	# A JSON round trip exercises wire numbers rather than sharing objects.
	return guest.apply_network_snapshot(JSON.parse_string(JSON.stringify(host.network_snapshot(), "", true, true)))

func step(seconds: float) -> void:
	for _n in range(int(seconds * 120)):
		host._physics_process(1.0 / 120)

func run() -> void:
	host = scene()
	guest = scene()
	await process_frame
	host.net.server_url = ""
	check(not host.net.configured(), "Unconfigured build never pretends the online server exists")
	check(host.net.valid_room_code("2ABCDEFG"), "Room code may start with a digit")
	check(not host.net.valid_room_code("ABC DEF!"), "Invalid room code rejected before network")
	host._open_online()
	check(host.lobby.visible and host.online and host.phase == "title", "Online opens a lobby rather than starting local play")
	host.net.create_room()
	check(host.net.status == "error" and host.lobby.visible, "Missing backend reports a useful error and preserves lobby")
	host._leave_online()
	check(not host.online and not host.lobby.visible and host.net.token.is_empty(), "Leaving clears room session and restores local title")
	host.start_game()
	host.wind = 0
	connected(host, 0)
	connected(guest, 1)
	check(transfer(), "Guest accepts canonical initial state through JSON")
	check(host.network_snapshot() == guest.network_snapshot(), "Initial fighters, turn and aim match exactly")
	host._aim_at(Vector2(host.fighters[0].pos.x, host.world_top + 100))
	check(host.fighters[0].face == 1.0 and host._valid_snapshot(host.network_snapshot()), "Vertical aiming preserves a valid facing direction")
	host.angle = 46
	check(host._can_control() and not guest._can_control(), "Only Daniel can control Daniel's opening turn")
	guest.fire()
	check(guest.shots == 0 and guest.phase == "aim", "Guest cannot fire out of turn")
	var before: float = guest.turn_clock
	guest._physics_process(2)
	check(guest.turn_clock == before, "Guest never independently advances physics or turn clock")
	host.fire()
	check(transfer() and guest.phase == "flying", "Guest receives authoritative projectile launch")
	step(6)
	check(host.active == 1 and host.turn == 2, "Authoritative host resolves first shot and passes turn")
	check(transfer(), "Guest accepts resolved explosion and turn")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Crater replay produces byte-identical terrain")
	check(host.network_snapshot() == guest.network_snapshot(), "Guest exactly matches authoritative post-shot state")
	check(not host._can_control() and guest._can_control(), "Only Jesus can control Jesus's turn")
	var shots_before: int = host.shots
	host.fire()
	host._jump()
	host._weapon_action()
	check(host.shots == shots_before and host.fighters[1].ground and host.weapon == 0, "Host UI cannot control guest's turn")
	check(not host._apply_remote_input({"seat": 0, "seq": 1, "turn": 2, "action": "fire"}), "Wrong-seat input rejected")
	check(not host._apply_remote_input({"seat": 1, "seq": 1, "turn": 1, "action": "fire"}), "Stale-turn input rejected")
	check(not host._apply_remote_input({"seat": 1, "seq": 1, "turn": 2, "move": 900}), "Out-of-range movement input rejected")
	check(host._apply_remote_input({"seat": 1, "seq": 1, "turn": 2, "move": -1, "angle_axis": 1}), "Current guest controls accepted by host")
	var old_x: float = host.fighters[1].pos.x
	step(0.2)
	check(host.fighters[1].pos.x < old_x and host.angle > 46, "Guest control moves and aims on authoritative host")
	check(not host._apply_remote_input({"seat": 1, "seq": 1, "turn": 2, "action": "fire"}), "Duplicate input sequence cannot trigger another action")
	step(0.7)
	check(host._remote_held.is_empty(), "Interrupted controls expire after 600 ms")
	host.help_open = true
	before = host.turn_clock
	step(0.1)
	check(host.turn_clock < before, "Opening host help cannot pause an online opponent")
	check(host._apply_remote_input({"seat": 1, "seq": 2, "turn": 2, "aim": [-1, 50], "action": "fire"}), "Guest fires while host's help is open")
	check(host.shots == shots_before + 1 and host.phase == "flying", "Exactly one canonical guest shot is launched")
	host.help_open = false
	step(6)
	check(transfer() and host.network_snapshot() == guest.network_snapshot(), "Both sides agree after guest's full shot")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Multiple craters remain byte-identical")
	var pristine: Dictionary = guest.network_snapshot()
	var malformed: Dictionary = pristine.duplicate(true)
	malformed.fighters[0].pos = ["no", null]
	check(not guest.apply_network_snapshot(malformed), "Malformed vector rejected without executing or coercing data")
	check(guest.network_snapshot() == pristine, "Rejected snapshot leaves scene unchanged")
	malformed = pristine.duplicate(true)
	malformed.active = 0.5
	check(not guest.apply_network_snapshot(malformed), "Fractional seat index rejected")
	malformed = pristine.duplicate(true)
	malformed.craters.append([20, 30, 9000])
	malformed.terrain_version = malformed.craters.size()
	check(not guest.apply_network_snapshot(malformed), "Oversized crater rejected before expensive drawing")
	malformed = pristine.duplicate(true)
	malformed.turn_clock = NAN
	check(not guest.apply_network_snapshot(malformed), "Non-finite snapshot number rejected")
	host.net.guest_connected = false
	before = host.turn_clock
	var pos_before: Vector2 = host.fighters[host.active].pos
	step(2)
	check(host.turn_clock == before and host.fighters[host.active].pos == pos_before, "Peer disconnect pauses full authoritative match")
	host._network_changed()
	check(host.lobby.visible and host._remote_held.is_empty(), "Disconnected match shows recovery lobby and clears held input")
	host._online_started = true
	host.net.guest_connected = true
	host._network_changed()
	check(not host.lobby.visible, "Reconnected peer resumes existing match")
	guest._last_received_seq = 10
	guest._network_received({"type": "state", "seq": 9, "snapshot": malformed})
	check(guest.network_snapshot() == pristine, "Old network state sequence is ignored")
	host.online = false
	host.start_game()
	check(transfer() and guest.craters.is_empty(), "Fresh canonical match resets prior crater history")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Snapshot replacement rebuilds pristine terrain exactly")
	for viewport in [Vector2(1280, 800), Vector2(852, 393), Vector2(430, 932)]:
		host._layout(viewport)
		var online_end: Vector2 = host.buttons.online.end * host.ui_scale + host.ui_origin
		check(online_end.x <= viewport.x and online_end.y <= viewport.y, "Online entry stays on screen at %dx%d" % [viewport.x, viewport.y])
	host._leave_online()
	host.start_game()
	check(host.phase == "aim" and not host.online, "Local duel still starts after leaving online flow")
	print("RESULT: %d online checks, %d failures" % [checks, failures])
	host.queue_free()
	guest.queue_free()
	await process_frame
	quit(1 if failures else 0)

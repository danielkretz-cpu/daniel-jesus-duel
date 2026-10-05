extends SceneTree
## Engine-native rules and hostile-state regressions for every room size and arena.
var host
var guest
var checks := 0
var failures := 0
const NAMES := ["Åsa", "Jesus", "Mika 李", "Zoë", "Søren", "Élodie"]

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

func connect_fixture(game, seat: int, count: int, map_index: int = 0) -> void:
	game.online = true
	game.net.seat = seat
	game.net.status = "connected"
	game.net.host_connected = true
	game.net.guest_connected = true
	game.net.started = true
	game.net.capacity = count
	game.net.map_id = map_index
	game.net.roster.clear()
	for i in range(count):
		game.net.roster.append({"seat": i, "name": NAMES[i], "connected": true, "alive": true})

func reset(count: int = 6, map_index: int = 0) -> void:
	connect_fixture(host, 0, count, map_index)
	connect_fixture(guest, count - 1, count, map_index)
	host.map_id = map_index
	host.start_game()
	host.rng.seed = 42
	host.wind = 0

func transfer() -> bool:
	return guest.apply_network_snapshot(JSON.parse_string(JSON.stringify(host.network_snapshot(), "", true, true)))

func step(seconds: float) -> void:
	for _n in range(int(seconds * 120)):
		host._physics_process(1.0 / 120)

func reject_atomically(snapshot: Dictionary, message: String) -> void:
	var old_state: Dictionary = guest.network_snapshot()
	var old_pixels: PackedByteArray = guest.terrain.get_data()
	# Valid concurrent changes make partial application observable.
	snapshot.turn += 1
	snapshot.craters.append([570, 400, 17])
	snapshot.terrain_version = snapshot.craters.size()
	check(not guest.apply_network_snapshot(snapshot) and guest.network_snapshot() == old_state and guest.terrain.get_data() == old_pixels, message)

func run() -> void:
	host = scene()
	guest = scene()
	await process_frame
	test_names()
	test_all_sizes_and_maps()
	test_local_names()
	test_turns_and_targets()
	test_all_guest_inputs()
	test_six_player_weapons()
	test_roster_pause_rules()
	test_malformed_states()
	print("RESULT: %d multiplayer checks, %d failures" % [checks, failures])
	host.queue_free()
	guest.queue_free()
	await process_frame
	quit(1 if failures else 0)

func test_names() -> void:
	for display_name in NAMES:
		check(host.net.valid_player_name(display_name), "Authenticated name %s accepts its original Unicode characters" % display_name)
	for display_name in ["", "   ", "<script>", "A".repeat(21)]:
		check(not host.net.valid_player_name(display_name), "Unsafe or unusable name %s is rejected before connecting" % str(display_name))
	check(host.net.normalize_player_name("  Åsa\t\n\u202e ") == "Åsa", "Name normalization removes control and bidi characters while preserving actual text")

func test_all_sizes_and_maps() -> void:
	for count in range(2, 7):
		for map_index in range(5):
			reset(count, map_index)
			check(host.fighters.size() == count and host.freedom.size() == count and host.freedom.count(0) == count, "%d players on map %d have matching fighter and inventory arrays" % [count, map_index])
			var spawn_positions: Array = []
			var safe := true
			var named := true
			for i in range(count):
				var fighter: Dictionary = host.fighters[i]
				safe = safe and fighter.hp == 100 and host._is_grounded(fighter.pos) and not host._solid(fighter.pos + Vector2(0, -19)) and not host._solid(fighter.pos + Vector2(-8, -19)) and not host._solid(fighter.pos + Vector2(8, -19)) and fighter.pos.y < host.WATER - 20
				named = named and fighter.name == NAMES[i]
				for prior in spawn_positions:
					safe = safe and fighter.pos.distance_to(prior) > 45
				spawn_positions.append(fighter.pos)
			check(safe and named, "%d named players spawn dry, grounded and separated on map %d" % [count, map_index])
			if count == 2:
				check(spawn_positions == host.MapThemes.spawn_points(map_index), "Two-player map %d keeps original launch positions" % map_index)
			var expected_target := -1
			var closest := INF
			for i in range(1, count):
				var distance: float = host.fighters[0].pos.distance_squared_to(host.fighters[i].pos)
				if distance < closest:
					closest = distance
					expected_target = i
			check(host.target == expected_target, "%d players on map %d default to the nearest live opponent" % [count, map_index])
			check(host.network_snapshot().schema == 3 and transfer() and host.network_snapshot() == guest.network_snapshot(), "%d-player map %d snapshot round-trips exactly through JSON" % [count, map_index])
			check(host.terrain.get_data() == guest.terrain.get_data(), "%d-player map %d uses byte-identical terrain on guest" % [count, map_index])
			step(0.25)
			var stable := true
			for fighter in host.fighters:
				stable = stable and fighter.hp == 100 and fighter.ground
			check(stable, "%d-player map %d remains healthy and grounded after physics" % [count, map_index])
			host.start_game()
			var repeated: Array = []
			for fighter in host.fighters:
				repeated.append(fighter.pos)
			check(repeated == spawn_positions, "%d-player map %d restart uses deterministic spawn positions" % [count, map_index])

func test_local_names() -> void:
	host.online = false
	host.player_names.assign(["Daniel", "Jesus"])
	host.start_game()
	check(host.fighters.size() == 2 and host.fighters[0].name == "Daniel" and host.fighters[1].name == "Jesus", "Local default still starts the original named two-player duel")
	host.player_names.assign(NAMES)
	host.start_game()
	var names_match: bool = host.fighters.size() == 6
	for i in range(host.fighters.size()):
		names_match = names_match and host.fighters[i].name == NAMES[i]
	check(names_match, "Local named roster supports all six players")
	host.player_names.assign(["Daniel", "Jesus"])

func test_turns_and_targets() -> void:
	for count in range(2, 7):
		reset(count)
		var rotation: Array = []
		for _i in range(count + 1):
			rotation.append(host.active)
			host._finish_turn()
		var expected: Array = range(count)
		expected.append(0)
		check(rotation == expected and host.turn == count + 2, "%d-player turn order visits every seat and wraps once" % count)
		reset(count)
		var targets: Array = []
		for _i in range(count - 1):
			targets.append(host.target)
			host._target_action()
		targets.sort()
		check(targets == range(1, count), "%d-player target cycling visits every opponent exactly once" % count)
	reset()
	host.fighters[1].hp = 0
	host.fighters[3].hp = 0
	host.fighters[4].hp = 0
	check(not host._check_winner() and host.phase != "over", "Three eliminations do not end a six-player match with three survivors")
	var survivors: Array = []
	for _i in range(4):
		survivors.append(host.active)
		host._finish_turn()
	check(survivors == [0, 2, 5, 0], "Turn rotation skips all eliminated seats without renumbering survivors")
	host.active = 0
	host.target = 2
	host._target_action()
	check(host.target == 5, "Target action skips adjacent and separated eliminated players")
	host._target_action()
	check(host.target == 2, "Target action wraps without selecting self or eliminated players")
	host.fighters[2].hp = 0
	check(not host._check_winner(), "Two remaining players keep the six-player match running")
	host.fighters[0].hp = 0
	check(host._check_winner() and host.phase == "over" and host.winner == 5, "Final survivor wins with original seat five preserved")
	check(transfer() and guest.winner == 5 and guest.fighters[5].name == NAMES[5], "Final winner and authenticated name survive guest synchronization")
	reset()
	for fighter in host.fighters:
		fighter.hp = 0
	check(host._check_winner() and host.phase == "over" and host.winner == -1, "Simultaneous elimination of all six produces a draw")
	check(transfer(), "All-eliminated draw is a valid canonical final snapshot")

func test_all_guest_inputs() -> void:
	reset()
	for seat in range(1, 6):
		host._finish_turn()
		check(host.active == seat, "Seat %d receives its real next turn" % seat)
		var old_angle: float = host.angle
		var wrong_seat := 1 if seat != 1 else 2
		check(not host._apply_remote_input({"seat": wrong_seat, "seq": 1, "turn": host.turn, "action": "fire"}), "Seat %d cannot be controlled by another authenticated guest" % seat)
		check(host._apply_remote_input({"seat": seat, "seq": 1, "turn": host.turn, "move": 1, "angle_axis": 1, "target": 0}), "Seat %d independently starts its own input sequence and selects target zero" % seat)
		step(0.1)
		check(host.target == 0 and host.angle > old_angle, "Seat %d applies target and continuous aim on the host" % seat)
		check(not host._apply_remote_input({"seat": seat, "seq": 1, "turn": host.turn, "action": "fire"}), "Seat %d duplicate input cannot shoot twice" % seat)
		var state_before: Dictionary = host.network_snapshot()
		for malformed in [{"seat": float(seat) + 0.5}, {"turn": float(host.turn) + 0.5}, {"seq": 2.5}, {"move": 2}, {"target": seat}, {"target": 6}, {"target": 0.5}, {"target": "0"}, {"action": "unknown"}]:
			var packet := {"seat": seat, "seq": 2, "turn": host.turn, "angle_axis": 0}
			packet.merge(malformed, true)
			check(not host._apply_remote_input(packet) and host.network_snapshot() == state_before, "Seat %d rejects malformed input %s atomically" % [seat, str(malformed)])
		check(host._apply_remote_input({"seat": seat, "seq": 2, "turn": host.turn, "action": "target"}), "Seat %d can cycle target with a discrete input action" % seat)
		check(host._apply_remote_input({"seat": seat, "seq": 3, "turn": host.turn, "action": "target", "target": 0}) and host.target == 0, "Seat %d explicit target plus target action never cycles twice" % seat)
		step(0.7)
		check(host._remote_held.is_empty(), "Seat %d interrupted controls expire" % seat)
	reset()
	host._finish_turn()
	host.fighters[5].hp = 0
	check(not host._apply_remote_input({"seat": 1, "seq": 1, "turn": host.turn, "target": 5}), "Guest cannot select an eliminated target")

func test_six_player_weapons() -> void:
	reset()
	host.active = 4
	host.target = 1
	host.phase = "flying"
	host.projectile = {"weapon": host.ROCKET, "owner": 4, "target": 1, "pos": host.fighters[1].pos + Vector2(-29, -19), "vel": Vector2(500, 0), "age": 0.4, "bounces": 0}
	host._step_projectile(0.06)
	check(host.freedom == [0, 0, 0, 0, 1, 0] and host.fighters[1].hp < 100, "Seat four earns its own Freedom from a direct hit on a nonadjacent seat")
	for owner in range(6):
		reset()
		host.online = false
		host.active = owner
		host.target = (owner + 3) % 6
		host.freedom[owner] = 1
		host.weapon = host.FREEDOM
		host.fire()
		check(host.phase == "flying" and host.projectile.owner == owner and host.projectile.target == host.target and host.freedom.count(0) == 6, "Seat %d launches Freedom at selected nonadjacent target and consumes only its charge" % owner)
		var pixels: PackedByteArray = host.terrain.get_data()
		var victim: int = host.target
		# A downward approach isolates body collision from sloping terrain beside the spawn.
		host.projectile.pos = host.fighters[victim].pos + Vector2(0, -48)
		host.projectile.vel = Vector2(0, 480)
		host._step_projectile(0.06)
		var exact_damage := true
		for i in range(6):
			exact_damage = exact_damage and host.fighters[i].hp == (51 if i == victim else 100)
		check(exact_damage and host.freedom.count(0) == 6 and host.terrain.get_data() == pixels, "Seat %d Freedom still deals exactly 49 only to its selected target with no new reward or terrain damage" % owner)
	reset()
	host.online = false
	host.active = 5
	host.target = 2
	host.weapon = host.BANANA
	host.fire()
	host.projectile.pos = Vector2(640, 70)
	host.projectile.vel = Vector2(150, -40)
	host.projectile.age = 1.19
	host._step_projectile(0.02)
	var attribution: bool = host.fragments.size() == 5
	for fragment in host.fragments:
		attribution = attribution and fragment.owner == 5 and fragment.target == 2
	check(attribution and transfer() and host.network_snapshot() == guest.network_snapshot(), "Seat five banana keeps ownership and selected target across all five fragments and canonical JSON")

func test_roster_pause_rules() -> void:
	reset()
	host.net.roster[5].connected = false
	check(not host.net.together(), "Live disconnected seat five blocks the match")
	host.fighters[5].hp = 0
	host.net._update_health(host.network_snapshot())
	check(host.net.together(), "Eliminated disconnected guest does not block the remaining players")
	var before: float = host.turn_clock
	step(0.1)
	check(host.turn_clock < before, "Authoritative timer continues after an eliminated guest disconnects")
	host.net.roster[0].alive = false
	host.net.roster[0].connected = false
	host.net.host_connected = false
	check(not host.net.together(), "Disconnected host always blocks the match, even when eliminated")

func test_malformed_states() -> void:
	reset()
	check(transfer(), "Six-player canonical baseline accepted before hostile packet tests")
	var clean: Dictionary = guest.network_snapshot()
	for changes in [{"schema": 2}, {"active": 6}, {"active": -1}, {"active": 2.5}, {"target": 6}, {"target": -1}, {"target": 0}, {"target": 1.5}, {"winner": 6}, {"winner": 1}, {"phase": "over"}]:
		var bad: Dictionary = clean.duplicate(true)
		bad.merge(changes, true)
		reject_atomically(bad, "Malformed six-player state %s leaves all state and terrain intact" % str(changes))
	for missing in ["target", "fighters", "freedom"]:
		var bad: Dictionary = clean.duplicate(true)
		bad.erase(missing)
		reject_atomically(bad, "Missing schema-3 %s is rejected atomically" % missing)
	for count in [0, 1, 2, 5, 7]:
		var bad: Dictionary = clean.duplicate(true)
		bad.fighters.resize(count)
		reject_atomically(bad, "Fighter count %d cannot replace the authenticated six-player roster" % count)
		bad = clean.duplicate(true)
		bad.freedom.resize(count)
		reject_atomically(bad, "Inventory count %d must match the six-player fighter array" % count)
	var bad: Dictionary = clean.duplicate(true)
	bad.fighters[bad.target].hp = 0
	reject_atomically(bad, "Aim state cannot select an eliminated target")
	bad = clean.duplicate(true)
	bad.fighters[bad.active].hp = 0
	reject_atomically(bad, "Aim state cannot give the turn to an eliminated player")
	bad = clean.duplicate(true)
	bad.fighters[4].hp = 49.5
	reject_atomically(bad, "Fractional fighter health is rejected instead of silently truncated")
	bad = clean.duplicate(true)
	bad.fighters[5].name = "Spoofed identity"
	var accepted: bool = guest.apply_network_snapshot(bad)
	check((not accepted or guest.fighters[5].name == NAMES[5]) and guest.fighters[0].name == NAMES[0], "Snapshot data cannot spoof authenticated roster display names")
	guest._last_received_seq = 10
	var roster_before: Array = guest.net.roster.duplicate(true)
	var canonical_before: Dictionary = guest.network_snapshot()
	bad = clean.duplicate(true)
	bad.fighters[5].hp = 0
	guest.net._handle({"type": "state", "seq": 9, "snapshot": bad})
	check(guest.net.roster == roster_before and guest.network_snapshot() == canonical_before, "Old network state cannot mutate alive presence before sequence rejection")
	bad.target = bad.active
	guest.net._handle({"type": "state", "seq": 11, "snapshot": bad})
	check(guest.net.roster == roster_before and guest.network_snapshot() == canonical_before, "Malformed new network state cannot mutate alive presence before validation")
	host.phase = "flying"
	host.projectile = {"weapon": host.BANANA, "owner": 5, "target": 2, "pos": Vector2(640, 80), "vel": Vector2(50, -30), "age": 0.4, "bounces": 0}
	check(transfer(), "Seat five projectile with nonadjacent target is a valid six-player snapshot")
	clean = guest.network_snapshot()
	for changes in [{"owner": 6}, {"owner": -1}, {"owner": 5.5}, {"target": 6}, {"target": 5}, {"target": 2.5}]:
		bad = clean.duplicate(true)
		bad.projectile.merge(changes, true)
		reject_atomically(bad, "Malformed six-player projectile %s is rejected atomically" % str(changes))

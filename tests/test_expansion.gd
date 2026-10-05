extends SceneTree
## Engine-native expansion regressions. No relay or mocked gameplay required.
## godot --headless --path . --script res://tests/test_expansion.gd
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

func reset(map_index: int = 0) -> void:
	host.online = false
	host.map_id = map_index
	host.start_game()
	host.rng.seed = 42
	host.wind = 0

func step(seconds: float) -> void:
	for _n in range(int(seconds * 120)):
		host._physics_process(1.0 / 120)

func transfer() -> bool:
	return guest.apply_network_snapshot(JSON.parse_string(JSON.stringify(host.network_snapshot(), "", true, true)))

func bullet(kind: int, owner: int, pos: Vector2, velocity: Vector2, age: float = 0.4) -> Dictionary:
	return {"weapon": kind, "owner": owner, "target": 1 - owner, "pos": pos, "vel": velocity, "age": age, "bounces": 0}

func direct_shot(kind: int, owner: int = 0, victim: int = 1) -> void:
	# Move a real projectile through the collision radius, rather than calling a reward helper.
	host.active = owner
	host.phase = "flying"
	host.projectile = bullet(kind, owner, host.fighters[victim].pos + Vector2(-29, -19), Vector2(500, 0))
	host._step_projectile(0.06)

func rejected_atomically(snapshot: Dictionary, message: String) -> void:
	var before: Dictionary = guest.network_snapshot()
	var pixels: PackedByteArray = guest.terrain.get_data()
	# Pair the corrupt field with valid changes, so an early partial application
	# cannot hide behind the other fields already matching the current scene.
	snapshot.turn += 1
	snapshot.fighters[0].hp = 37
	snapshot.craters.append([500, 400, 19])
	snapshot.terrain_version = snapshot.craters.size()
	if snapshot.get("map_id") is int and snapshot.map_id >= 0 and snapshot.map_id < 5:
		snapshot.map_id = (snapshot.map_id + 1) % 5
	var accepted: bool = guest.apply_network_snapshot(snapshot)
	check(not accepted and guest.network_snapshot() == before and guest.terrain.get_data() == pixels, message)

func run() -> void:
	host = scene()
	guest = scene()
	await process_frame
	check(host.net.PROTOCOL == 3, "Client advertises expansion protocol version 3")
	host.net._handle({"type": "welcome", "protocol": 1, "seat": 0})
	check(host.net.status == "error" and host.net.seat == -1 and host.net.status_text.contains("versionerna") and host.net.status_text.contains("Ladda om"), "Legacy welcome fails with a useful version/reload message before joining")
	test_freedom()
	test_banana()
	test_maps()
	test_snapshots()
	test_malformed()
	test_numeric_roundtrips()
	print("RESULT: %d expansion checks, %d failures" % [checks, failures])
	host.queue_free()
	guest.queue_free()
	await process_frame
	quit(1 if failures else 0)

func test_freedom() -> void:
	reset()
	check(host.freedom == [0, 0], "Freedom starts locked separately for both players")
	host.weapon = host.FREEDOM
	var clock_before: float = host.turn_clock
	host.fire()
	check(host.phase == "aim" and host.shots == 0 and host.projectile.is_empty() and host.turn_clock == clock_before, "Locked Freedom cannot launch or consume the turn")
	host.weapon = host.ROCKET
	var cycle: Array = []
	for _i in range(4):
		host._weapon_action()
		cycle.append(host.weapon)
	check(cycle == [host.BOMB, host.BANANA, host.FREEDOM, host.ROCKET], "Weapon selector reaches all four weapons and wraps")
	for kind in [host.ROCKET, host.BOMB, host.BANANA]:
		reset()
		direct_shot(kind)
		check(host.freedom == [1, 0], "Real weapon %d body collision earns only its owner's Freedom" % kind)
		check(host.fighters[1].hp < 100, "Real weapon %d collision damages the opponent" % kind)
	reset()
	direct_shot(host.ROCKET, 1, 0)
	check(host.freedom == [0, 1], "Jesus can independently earn Freedom from a direct hit")
	reset()
	host.freedom[0] = 1
	direct_shot(host.ROCKET)
	check(host.freedom == [1, 0], "Further direct hits never stack more than one held Freedom")
	reset()
	direct_shot(host.ROCKET, 0, 0)
	check(host.fighters[0].hp < 100 and host.freedom == [0, 0], "Actual returning projectile self-hit does not award Freedom")
	reset()
	var center: Vector2 = host.fighters[1].pos + Vector2(0, -16)
	host._explode(center + Vector2(40, 0), 57)
	check(host.fighters[1].hp < 100 and host.freedom == [0, 0], "Nearby radial blast damage alone never unlocks Freedom")
	reset()
	host.freedom[0] = 1
	host.weapon = host.FREEDOM
	host.fire()
	check(host.freedom == [0, 0] and host.shots == 1 and host.projectile.weapon == host.FREEDOM, "Firing earned Freedom consumes exactly one charge")
	check(host.projectile.owner == 0 and host.projectile.target == 1, "Freedom stores the firing player and opposing target")
	host.fire()
	check(host.shots == 1, "Repeated Freedom fire during flight cannot duplicate the shot")
	var pristine_pixels: PackedByteArray = host.terrain.get_data()
	var target_velocity: Vector2 = host.fighters[1].vel
	host.projectile.pos = host.fighters[1].pos + Vector2(-29, -19)
	host.projectile.vel = Vector2(480, 0)
	host._step_projectile(0.06)
	check(host.fighters[1].hp == 51 and host.fighters[0].hp == 100, "Real Freedom collision deals exactly 49 damage only to its target")
	check(host.fighters[1].vel == target_velocity and host.craters.is_empty() and host.terrain.get_data() == pristine_pixels, "Freedom collision produces no knockback or terrain damage")
	check(host.freedom == [0, 0] and host.projectile.is_empty() and host.phase == "settle", "Freedom resolves without recursively granting another missile")
	step(2)
	check(host.active == 1 and host.weapon == host.ROCKET and host.freedom == [0, 0], "Turn passes safely with locked Freedom reset to the rocket")
	reset()
	host.freedom[0] = 1
	host.weapon = host.FREEDOM
	host.fire()
	var start_position: Vector2 = host.projectile.pos
	step(0.3)
	check(not host.projectile.is_empty() and host.projectile.pos.distance_to(start_position) > 60, "Freedom really travels and steers through engine physics")
	step(7)
	check(host.fighters[1].hp == 51 and host.freedom == [0, 0] and host.phase == "aim", "Natural homing flight hits for 49 and completes the whole turn")
	reset()
	host.freedom[0] = 1
	host.weapon = host.FREEDOM
	host.fire()
	host.projectile.pos = Vector2(640, 430)
	host.projectile.vel = Vector2(0, 100)
	host._step_projectile(0.01)
	check(host.fighters[1].hp == 100 and host.freedom == [0, 0] and host.craters.is_empty(), "Terrain interception consumes Freedom without remote damage or crater")
	reset()
	host.freedom[0] = 1
	host.freedom[1] = 1
	host.start_game()
	check(host.freedom == [0, 0] and host.fragments.is_empty(), "Restart clears both inventories and secondary projectiles")

func test_banana() -> void:
	reset()
	host.weapon = host.BANANA
	host.fire()
	check(host.projectile.weapon == host.BANANA and host.fragments.is_empty(), "Banana begins as one actual primary projectile")
	# Isolate the airburst timer from terrain and fighter collision.
	host.projectile.pos = Vector2(640, 70)
	host.projectile.vel = Vector2(150, -40)
	host.projectile.age = 1.19
	host._step_projectile(0.02)
	check(host.projectile.is_empty() and host.fragments.size() == 5 and host.phase == "flying", "Banana timer physically splits into exactly five live fragments")
	var distinct_velocities: Dictionary = {}
	var valid_fragments := true
	var old_positions: Array = []
	for part in host.fragments:
		distinct_velocities[part.vel] = true
		valid_fragments = valid_fragments and part.weapon == host.BANANA_FRAGMENT and part.owner == 0 and part.target == 1
		old_positions.append(part.pos)
	check(valid_fragments and distinct_velocities.size() == 5, "All five fragments retain attribution and have distinct physical spread")
	host._step_projectile(0.05)
	var all_moved: bool = host.fragments.size() == 5
	for i in range(host.fragments.size()):
		all_moved = all_moved and host.fragments[i].pos.distance_to(old_positions[i]) > 1
	check(all_moved, "Every banana fragment advances independently in flight")
	check(transfer() and host.network_snapshot() == guest.network_snapshot(), "Midflight banana fragments survive an exact canonical JSON round trip")
	step(8)
	check(host.fragments.is_empty() and host.projectile.is_empty() and host.phase in ["aim", "over"], "Five fragments all resolve before the turn can finish")
	check(host.craters.size() <= 5, "Each airborne banana fragment makes at most one blast")
	reset()
	host.phase = "flying"
	host.fragments.append(bullet(host.BANANA_FRAGMENT, 0, host.fighters[1].pos + Vector2(-29, -19), Vector2(500, 0)))
	host._step_projectile(0.06)
	check(host.freedom == [1, 0] and host.fighters[1].hp >= 89 and host.fighters[1].hp < 100, "A real fragment direct hit earns Freedom with at most 11 damage")
	check(host.fragments.is_empty() and host.craters.size() == 1, "A colliding fragment is removed exactly once")
	reset()
	host.phase = "flying"
	for _i in range(5):
		host.fragments.append(bullet(host.BANANA_FRAGMENT, 0, host.fighters[1].pos + Vector2(-29, -19), Vector2(500, 0)))
	host._step_projectile(0.06)
	check(host.fighters[1].hp >= 45 and host.fighters[1].hp < 100 and host.freedom == [1, 0], "Five simultaneous fragment impacts cap total blast damage at 55 and inventory at one")
	check(host.fragments.is_empty() and host.craters.size() >= 1 and host.craters.size() <= 5 and host.phase == "settle", "Five-fragment volley resolves every impact while redundant terrain changes may be coalesced")
	reset()
	host.phase = "flying"
	host.fragments.append(bullet(host.BANANA_FRAGMENT, 0, Vector2(700, 60), Vector2.ZERO, 3.49))
	host._step_projectile(0.02)
	check(host.fragments.is_empty() and host.phase == "settle", "Fragment fuse bounds lifetime even without a terrain or fighter collision")

func test_maps() -> void:
	check(host.MapThemes.count() == 5, "Five selectable maps are available")
	var terrains: Array[PackedByteArray] = []
	var profiles: Array = []
	for map_index in range(host.MapThemes.count()):
		reset(map_index)
		var spawns: Array = host.MapThemes.spawn_points(map_index)
		var fair: bool = host.fighters[0].hp == 100 and host.fighters[1].hp == 100
		fair = fair and absf(spawns[0].x + spawns[1].x - host.WW) <= 8 and absf(spawns[0].y - spawns[1].y) <= 20
		for i in range(2):
			fair = fair and host._is_grounded(spawns[i]) and not host._solid(spawns[i] + Vector2(0, -19)) and spawns[i].y < host.WATER - 20
		check(fair, "Map %d has dry grounded, fair opposing spawn positions" % map_index)
		step(0.25)
		check(host.fighters[0].hp == 100 and host.fighters[1].hp == 100 and host.fighters[0].ground and host.fighters[1].ground, "Map %d starts stably without falling or water damage" % map_index)
		var profile: Array = []
		for x in range(0, host.WW, 16):
			profile.append(host.MapThemes.surface_y(map_index, x))
		check(not profiles.has(profile), "Map %d has distinct playable terrain geometry" % map_index)
		check(not terrains.has(host.terrain.get_data()), "Map %d has distinct terrain pixels" % map_index)
		profiles.append(profile)
		terrains.append(host.terrain.get_data())
		host.carve(Vector2(640, 410), 23)
		check(transfer() and guest.map_id == map_index and host.terrain.get_data() == guest.terrain.get_data(), "Map %d and crater replay stay identical after switching from an equal crater prefix" % map_index)
		host.start_game()
		check(host.map_id == map_index and host.craters.is_empty() and host.terrain.get_data() == terrains[map_index], "Restart preserves selected map %d and rebuilds its pristine terrain" % map_index)
		host.wind = 0
		host.freedom[0] = 1
		host.weapon = host.FREEDOM
		host.fire()
		step(7)
		check(host.fighters[1].hp == 51 and host.freedom == [0, 0] and host.phase == "aim", "Natural Freedom homing from map %d untouched spawns deals exactly 49 and resolves" % map_index)
		check(host.craters.is_empty() and host.terrain.get_data() == terrains[map_index], "Natural Freedom on map %d preserves all terrain" % map_index)
	host.phase = "title"
	host.map_id = 4
	host._map_action(1)
	check(host.map_id == 0, "Title map selector wraps from last map to first")
	host._map_action(-1)
	check(host.map_id == 4, "Title map selector wraps backward to the last map")
	host.online = true
	host._map_action(1)
	check(host.map_id == 4, "Map selection is locked once an online lobby has opened")
	host.online = false
	host.start_game()
	host._map_action(1)
	check(host.map_id == 4, "Map cannot change during an active duel")
	# Empty crater lists also compare as equal prefixes; base map must still change.
	check(transfer(), "Guest accepts the empty-crater map before replacement")
	reset(1)
	check(transfer() and guest.map_id == 1 and host.terrain.get_data() == guest.terrain.get_data(), "Changing map with two empty crater histories rebuilds the guest base terrain")

func test_snapshots() -> void:
	reset(3)
	host.freedom[0] = 1
	host.freedom[1] = 1
	host.weapon = host.BANANA
	host.fire()
	var wire: Dictionary = host.network_snapshot()
	check(wire.schema == 3 and wire.map_id == 3 and wire.freedom == [1, 1] and wire.fragments == [], "Schema 3 explicitly carries map, both inventories, and fragment list")
	check(transfer() and host.network_snapshot() == guest.network_snapshot(), "Primary banana ownership and all schema-3 fields round-trip exactly")
	reset(4)
	host.freedom[0] = 1
	host.weapon = host.FREEDOM
	host.fire()
	check(transfer() and guest.projectile.owner == 0 and guest.projectile.target == 1 and guest.freedom == [0, 0] and host.network_snapshot() == guest.network_snapshot(), "In-flight Freedom target and consumed charge round-trip exactly")

func test_malformed() -> void:
	reset(2)
	host.carve(Vector2(640, 410), 23)
	host.freedom[0] = 1
	host.phase = "flying"
	host.fragments.append(bullet(host.BANANA_FRAGMENT, 0, Vector2(600, 120), Vector2(93, -170), 0.25))
	check(transfer(), "Valid nontrivial schema-3 baseline is accepted before corruption tests")
	var clean: Dictionary = guest.network_snapshot()
	for invalid_map in [-1, 5, 0.5, "2", null]:
		var malformed: Dictionary = clean.duplicate(true)
		malformed.map_id = invalid_map
		rejected_atomically(malformed, "Invalid map %s is rejected before state or terrain mutation" % str(invalid_map))
	for bad_inventory in [[], [1], [1, 0, 1], [2, 0], [-1, 0], [0.5, 0], [true, 0], ["1", 0], null]:
		var malformed: Dictionary = clean.duplicate(true)
		malformed.freedom = bad_inventory
		rejected_atomically(malformed, "Invalid Freedom inventory %s is rejected atomically" % str(bad_inventory))
	for field in ["map_id", "freedom", "fragments"]:
		var malformed: Dictionary = clean.duplicate(true)
		malformed.erase(field)
		rejected_atomically(malformed, "Missing required schema-3 %s is rejected atomically" % field)
	var malformed: Dictionary = clean.duplicate(true)
	malformed.schema = 1
	rejected_atomically(malformed, "Old schema cannot silently drop map or weapon state")
	malformed = clean.duplicate(true)
	for _i in range(5):
		malformed.fragments.append(clean.fragments[0].duplicate(true))
	rejected_atomically(malformed, "Six simultaneous fragments are rejected atomically")
	for mutation in [{"weapon": 2}, {"weapon": 4.5}, {"owner": 2}, {"owner": 0.5}, {"target": -1}, {"target": 0}, {"bounces": 0.5}, {"age": NAN}, {"pos": ["x", 4]}, {"vel": [0, INF]}]:
		malformed = clean.duplicate(true)
		malformed.fragments[0].merge(mutation, true)
		rejected_atomically(malformed, "Malformed fragment %s is rejected atomically" % str(mutation))
	malformed = clean.duplicate(true)
	malformed.fragments = [null]
	rejected_atomically(malformed, "Non-dictionary fragment is rejected atomically")
	malformed = clean.duplicate(true)
	malformed.fragments[0].erase("owner")
	rejected_atomically(malformed, "Unattributed fragment is rejected atomically")
	reset()
	host.weapon = host.BANANA
	host.fire()
	check(transfer(), "Primary projectile is accepted before primary-field corruption tests")
	clean = guest.network_snapshot()
	for mutation in [{"owner": -1}, {"owner": 0.5}, {"target": 0}, {"target": 2}, {"weapon": 4}, {"bounces": 1.5}]:
		malformed = clean.duplicate(true)
		malformed.projectile.merge(mutation, true)
		rejected_atomically(malformed, "Malformed primary attribution %s is rejected atomically" % str(mutation))

func test_numeric_roundtrips() -> void:
	reset(4)
	var precision_rng := RandomNumberGenerator.new()
	precision_rng.seed = 20261006
	var exact := true
	for sample in range(1000):
		host.wind = precision_rng.randf_range(-32, 32)
		host.angle = precision_rng.randf_range(5, 85)
		host.power = precision_rng.randf_range(12, 100)
		host.move_left = precision_rng.randf_range(0, 170)
		host.turn_clock = precision_rng.randf_range(0, 40)
		host.settle_clock = precision_rng.randf_range(-4, 2)
		host.freedom[0] = sample % 2
		host.freedom[1] = int(sample / 2) % 2
		host.weapon = sample % 4
		host.phase = "flying"
		host.projectile.clear()
		host.fragments.clear()
		if sample % 2 == 0:
			host.projectile = bullet(int(sample / 2) % 4, int(sample / 4) % 2, Vector2(precision_rng.randf_range(-90, 1350), precision_rng.randf_range(-300, 430)), Vector2(precision_rng.randf_range(-700, 700), precision_rng.randf_range(-700, 700)), precision_rng.randf_range(0, 2.9))
		else:
			for index in range(5):
				host.fragments.append(bullet(host.BANANA_FRAGMENT, int(sample / 4) % 2, Vector2(precision_rng.randf_range(-90, 1350), precision_rng.randf_range(-300, 430)), Vector2(precision_rng.randf_range(-700, 700), precision_rng.randf_range(-700, 700)), precision_rng.randf_range(0, 3.5)))
		for fighter in host.fighters:
			fighter.pos = Vector2(precision_rng.randf_range(20, 1260), precision_rng.randf_range(50, 400))
			fighter.vel = Vector2(precision_rng.randf_range(-500, 500), precision_rng.randf_range(-500, 500))
		host.trail.clear()
		host.trail.append(Vector2(27.700096130371094, precision_rng.randf_range(-300, 430)))
		if not transfer() or host.network_snapshot() != guest.network_snapshot():
			exact = false
			push_error("Canonical schema-3 numeric mismatch at sample %d" % sample)
			break
	check(exact, "1000 randomized schema-3 snapshots preserve exact binary32 primary, fragment, fighter and inventory state through JSON")

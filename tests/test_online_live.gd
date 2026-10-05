extends SceneTree
## Independent Godot clients against the real WebSocket relay, including six-player rooms.
## Start online-server/npm run dev; then run with -- --server-url=ws://127.0.0.1:8787
var host
var guest
var six_clients: Array = []
var extra_client
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

func wait_until(predicate: Callable, seconds: float = 10) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func scene():
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.sound_on = false
	return game

func run() -> void:
	host = scene()
	guest = scene()
	if "--six-only" in OS.get_cmdline_user_args():
		await test_six_live()
		await finish()
		return
	host._open_online()
	host.net.create_room("Daniel", 6, host.map_id)
	check(await wait_until(func(): return host.net.status == "connected"), "Host creates a real room through WebSocket")
	if host.net.status != "connected":
		print("BLOCKER: ", host.net.status_text)
		await finish()
		return
	check(host.net.room.length() == 8 and host.net.seat == 0, "Server assigns room code and Daniel seat")
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	guest._open_online()
	guest.net.join_room(host.net.room, "Jesus")
	check(await wait_until(func(): return host.net.roster.size() == 2 and guest.net.roster.size() == 2), "Both players join the waiting room before manual start")
	check(not host.net.started and not guest.net.started and host.phase == "title" and guest.phase == "title", "A second player joining does not automatically start the match")
	check(host.net.start_match(host.map_id), "Host explicitly starts the connected two-player roster")
	check(await wait_until(func(): return host.net.together() and guest.net.together() and guest._online_started), "Second client joins room and receives initial match")
	check(guest.net.seat == 1 and guest.active == 0 and guest.turn == 1, "Guest is Jesus and sees Daniel's opening turn")
	check(host.lobby.visible and guest.lobby.visible and guest._host_paused, "Guest joining while host shares code sees paused room")
	check(host.net.capacity == 6 and host.net.player_count == 2, "Host may start with two players without filling all six available places")
	var late_guest = scene()
	late_guest._open_online()
	late_guest.net.join_room(host.net.room, "Too late")
	check(await wait_until(func(): return late_guest.net.status == "error") and late_guest.net.status_text.contains("redan startat"), "Started two-player match rejects a late join even with four unused capacity slots")
	late_guest._leave_online()
	late_guest.queue_free()
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(await wait_until(func(): return not host.lobby.visible and not guest.lobby.visible), "Host returning after blurred join dismisses both pause overlays")
	check(not host.lobby.visible and not guest.lobby.visible, "Both lobbies close only after genuine connection and state")
	# Model a guest render/main-thread stall while host and relay keep advancing.
	var coalesced_before: int = guest.net.coalesced_states
	guest.net.set_process(false)
	await create_timer(2.0).timeout
	guest.net._process(0.0)
	guest.net.set_process(true)
	check(guest.net.status == "connected" and guest.net.coalesced_states >= coalesced_before + 5, "Two-second guest receive stall coalesces queued states without disconnecting")
	check(await wait_until(func(): return guest._last_received_seq >= host.net.state_seq - 1), "Stalled guest catches up to current authority instead of replaying stale frames")
	host.wind = 0
	host.fire()
	check(await wait_until(func(): return guest.shots == 1 and guest.phase == "flying"), "Canonical host shot is visible on guest")
	check(await wait_until(func(): return host.turn == 2 and guest.turn == 2), "Host shot resolves and synchronizes next turn")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Real relay delivers byte-identical destroyed terrain")
	var old_x: float = host.fighters[1].pos.x
	guest.held.left = true
	await create_timer(0.25).timeout
	guest.held.clear()
	check(host.fighters[1].pos.x < old_x, "Guest's held movement reaches host simulation")
	var before_seq: int = guest.net.input_seq
	for i in range(150):
		guest._aim_at(Vector2(700 + i, guest.world_top + 100))
	check(guest.net.input_seq == before_seq, "150 drag events coalesce without flooding WebSocket")
	guest._pending_aim = [-1.0, 46.0]
	guest.fire()
	check(await wait_until(func(): return host.shots == 2 and guest.shots == 2), "Guest fire reaches host once and canonical shot returns")
	check(await wait_until(func(): return host.turn == 3 and guest.turn == 3), "Both clients complete a full two-player turn cycle")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Terrain remains identical after both players fire")
	guest.held.left = true
	guest.pointers[0] = "left"
	guest._pending_aim = [-1.0, 50.0]
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(await wait_until(func(): return guest._host_paused and guest.lobby.visible), "Host backgrounding sends explicit pause to guest")
	check(guest.held.is_empty() and guest.pointers.is_empty() and guest._pending_aim.is_empty(), "Pause clears touch movement and pending aim before finger-up can be hidden")
	var background_clock: float = host.turn_clock
	await create_timer(0.2).timeout
	check(host.turn_clock == background_clock, "Host background pause freezes physics and turn timer")
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(await wait_until(func(): return not guest._host_paused and not guest.lobby.visible), "Returning host foreground safely resumes guest")
	guest._state_age = 5.1
	guest._network_tick(0.01)
	check(guest.lobby.visible and not guest._can_control(), "Stale snapshot watchdog blocks guest controls")
	host._send_state(true)
	check(await wait_until(func(): return guest._state_age < 1 and not guest.lobby.visible), "Fresh authoritative snapshot clears stale-host warning")
	var guest_room: String = guest.net.room
	var guest_token: String = guest.net.token
	guest.net._fail("Integration-test disconnection")
	check(await wait_until(func(): return not host.net.guest_connected), "Host receives peer-disconnected presence")
	var clock_before: float = host.turn_clock
	await create_timer(0.25).timeout
	check(host.turn_clock == clock_before and host.lobby.visible, "Authoritative clock pauses during disconnect")
	guest.net.reconnect()
	check(await wait_until(func(): return host.net.together() and guest.net.together() and not guest.lobby.visible), "Guest reconnects with same room and seat token")
	check(guest.net.room == guest_room and guest.net.token == guest_token and guest.turn == host.turn, "Reconnect restores current match rather than starting a new one")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Reconnect restores all canonical craters")
	var host_token: String = host.net.token
	host.net._fail("Integration-test host interruption")
	check(await wait_until(func(): return not guest.net.host_connected), "Guest sees host interruption and pauses")
	host.net.reconnect()
	check(await wait_until(func(): return host.net.together() and guest.net.together() and not host.lobby.visible), "Host reconnects to its authoritative seat")
	check(host.net.token == host_token and host.turn == guest.turn, "Host restoration retains the match and role")
	host.set_physics_process(false)
	host._send_state(true)
	check(await wait_until(func(): return guest._last_received_seq >= host.net.state_seq), "Guest catches up to final authoritative sequence")
	check(host.network_snapshot() == guest.network_snapshot(), "Final full gameplay snapshots agree exactly")
	check(host.net.status == "connected" and guest.net.status == "connected", "No protocol errors or rate-limit disconnects in full play/rejoin flow")
	await test_expansion_live()
	await test_six_live()
	await finish()

func test_expansion_live() -> void:
	# Select a new map through the actual title action, then create a fresh room.
	# Physics stays frozen except for deliberate authoritative projectile steps.
	host._leave_online()
	guest._leave_online()
	host._map_action(2 - host.map_id)
	guest._map_action(4 - guest.map_id)
	check(host.map_id == 2 and guest.map_id == 4, "Both clients can select different title maps before joining")
	host._open_online()
	host.net.create_room("Daniel", 2, host.map_id)
	check(await wait_until(func(): return host.net.status == "connected"), "Host creates a new schema-3 room on its selected map")
	if host.net.status != "connected":
		return
	guest._open_online()
	guest.net.join_room(host.net.room, "Jesus")
	check(await wait_until(func(): return host.net.roster.size() == 2 and guest.net.roster.size() == 2), "Both players join the waiting room before manual start")
	check(not host.net.started and not guest.net.started and host.phase == "title" and guest.phase == "title", "A second player joining does not automatically start the match")
	check(host.net.start_match(host.map_id), "Host explicitly starts the connected two-player roster")
	check(await wait_until(func(): return host.net.together() and guest.net.together() and guest._online_started), "Guest joins the selected-map room through the real relay")
	if not host.net.together() or not guest.net.together():
		return
	check(host.map_id == 2 and guest.map_id == 2 and host.terrain.get_data() == guest.terrain.get_data(), "Host map overrides guest title choice with byte-identical terrain")
	host._map_action(1)
	guest._map_action(-1)
	check(host.map_id == 2 and guest.map_id == 2, "Neither client can switch the map inside the online match")
	check(host.network_snapshot().schema == 3 and guest.network_snapshot().schema == 3, "Both real clients use expansion snapshot schema 3")
	# Inject a near-target rocket but run its real movement/collision on the host.
	host.wind = 0
	host.phase = "flying"
	host.projectile = {"weapon": host.ROCKET, "owner": 0, "target": 1, "pos": host.fighters[1].pos + Vector2(-29, -19), "vel": Vector2(500, 0), "age": 0.4, "bounces": 0}
	host._step_projectile(0.06)
	host._send_state(true)
	check(await wait_until(func(): return guest.freedom == [1, 0] and guest._last_received_seq >= host.net.state_seq), "Direct-hit reward inventory reaches the guest over WebSocket")
	check(host.network_snapshot() == guest.network_snapshot(), "Earned Freedom and impact crater have exact canonical relay equality")
	host.phase = "aim"
	host.weapon = host.FREEDOM
	var health_before: int = host.fighters[1].hp
	host.fire()
	host._send_state(true)
	check(await wait_until(func(): return not guest.projectile.is_empty() and guest.projectile.weapon == guest.FREEDOM and guest.freedom == [0, 0]), "Freedom launch and charge consumption relay together atomically")
	check(host.network_snapshot() == guest.network_snapshot() and guest.projectile.owner == 0 and guest.projectile.target == 1, "In-flight Freedom preserves exact primary ownership and target")
	host.projectile.pos = host.fighters[1].pos + Vector2(-29, -19)
	host.projectile.vel = Vector2(480, 0)
	host._step_projectile(0.06)
	host._send_state(true)
	check(await wait_until(func(): return guest.fighters[1].hp == health_before - 49 and guest.projectile.is_empty()), "Actual Freedom impact relays exactly 49 damage")
	check(host.freedom == [0, 0] and guest.freedom == [0, 0], "Neither client invents a recursive Freedom reward")
	# Freeze a real five-fragment airburst at a deliberately nonintegral wire state.
	host.start_game()
	host.wind = 27.700096130371094
	host.freedom[0] = 1
	host.freedom[1] = 1
	host.weapon = host.BANANA
	host.fire()
	host.projectile.pos = Vector2(640.1234130859375, 90.98765563964844)
	host.projectile.vel = Vector2(190.1234588623047, -80.87654113769531)
	host.projectile.age = 1.19
	host._step_projectile(0.02)
	host.carve(Vector2(640, 410), 23)
	host._send_state(true)
	check(await wait_until(func(): return guest.fragments.size() == 5 and guest.projectile.is_empty() and guest.freedom == [1, 1]), "Real banana airburst relays five moving fragments and both held charges")
	check(host.network_snapshot() == guest.network_snapshot(), "Midflight fragment vectors and ages retain exact canonical wire precision")
	var preserved: Dictionary = host.network_snapshot()
	var saved_guest_token: String = guest.net.token
	guest.net._fail("Expansion-test guest interruption")
	check(await wait_until(func(): return not host.net.guest_connected), "Fragment flight pauses when guest disconnects")
	guest.net.reconnect()
	check(await wait_until(func(): return host.net.together() and guest.net.together() and not guest.lobby.visible and guest.fragments.size() == 5), "Guest rejoins the existing midflight fragment volley")
	check(guest.net.token == saved_guest_token and host.network_snapshot() == preserved and guest.network_snapshot() == preserved, "Guest reconnect preserves exact map, inventory, fragments and complete schema-3 state")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Guest reconnect also reconstructs exact selected-map craters")
	var saved_host_token: String = host.net.token
	host.net._fail("Expansion-test host interruption")
	check(await wait_until(func(): return not guest.net.host_connected), "Guest observes host interruption during five-fragment flight")
	host.net.reconnect()
	check(await wait_until(func(): return host.net.together() and guest.net.together() and not host.lobby.visible and host.fragments.size() == 5), "Host rejoins its authoritative midflight fragment state")
	host._send_state(true)
	check(await wait_until(func(): return guest._last_received_seq >= host.net.state_seq), "Guest catches up to resumed schema-3 authority")
	check(host.net.token == saved_host_token and host.network_snapshot() == preserved and guest.network_snapshot() == preserved, "Host reconnect preserves exact map, both inventories, fragments and complete schema-3 state")
	# Resume the host manually, proving restored fragments are live rather than decorative.
	for _n in range(960):
		host._physics_process(1.0 / 120)
	host._send_state(true)
	check(await wait_until(func(): return guest.fragments.is_empty() and guest.turn == host.turn and guest._last_received_seq >= host.net.state_seq), "Restored fragments finish their physical impacts and synchronize the next turn")
	check(host.phase in ["aim", "over"] and host.network_snapshot() == guest.network_snapshot() and host.terrain.get_data() == guest.terrain.get_data(), "Post-reconnect banana resolution converges on exact canonical state and terrain")
	# A started room freezes its map. New maps therefore use fresh waiting rooms.
	check(not host.net.set_map((host.map_id + 1) % 5), "Started rooms refuse map edits without changing their canonical arena")
	for chosen_map in range(5):
		host._leave_online()
		guest._leave_online()
		host.map_id = chosen_map
		host._open_online()
		host.net.create_room("Daniel", 2, chosen_map)
		check(await wait_until(func(): return host.net.status == "connected"), "Host creates a fresh room for selected map %d" % chosen_map)
		if host.net.status != "connected":
			return
		guest._open_online()
		guest.net.join_room(host.net.room, "Jesus")
		check(await wait_until(func(): return host.net.can_start() and guest.net.roster.size() == 2), "Both players join map %d before its explicit start" % chosen_map)
		check(host.net.start_match(chosen_map), "Host explicitly starts selected map %d" % chosen_map)
		check(await wait_until(func(): return host.net.together() and guest._online_started), "Selected map %d match starts through the live relay" % chosen_map)
		host.carve(Vector2(640, 410), 23)
		host._send_state(true)
		check(await wait_until(func(): return guest.map_id == chosen_map and guest._last_received_seq >= host.net.state_seq), "Selected map %d snapshot passes the live relay" % chosen_map)
		check(host.network_snapshot() == guest.network_snapshot() and host.terrain.get_data() == guest.terrain.get_data(), "Live map %d and its crater terrain synchronize exactly" % chosen_map)
	check(host.net.status == "connected" and guest.net.status == "connected", "Expansion play and both reconnect paths cause no protocol or rate-limit errors")


func all_six_synced() -> bool:
	if six_clients.size() != 6:
		return false
	var authority = six_clients[0]
	for i in range(1, 6):
		if not six_clients[i]._online_started or six_clients[i].network_snapshot() != authority.network_snapshot():
			return false
	return true

func test_six_live() -> void:
	# Independent real WebSocket clients share no NetSession or gameplay state.
	# Freeze automatic physics so comparisons and interrupted volleys are exact.
	host._leave_online()
	guest._leave_online()
	var names := ["Åsa", "Jesus", "Mika 李", "Zoë", "Søren", "Élodie"]
	for _i in range(6):
		var game = scene()
		game.set_physics_process(false)
		six_clients.append(game)
	var authority = six_clients[0]
	authority._open_online()
	authority.net.create_room(names[0], 6, 4)
	check(await wait_until(func(): return authority.net.status == "connected"), "Six-player host creates a real named waiting room")
	if authority.net.status != "connected":
		return
	check(authority.net.capacity == 6 and authority.net.roster.size() == 1 and not authority.net.started and not authority.net.can_start(), "Host alone cannot start and capacity six is advertised")
	check(not authority.net.start_match(4), "Start request is refused before a second player arrives")
	for i in range(1, 6):
		var player = six_clients[i]
		player._open_online()
		player.net.join_room(authority.net.room, names[i])
		check(await wait_until(func(): return player.net.status == "connected" and authority.net.roster.size() == i + 1), "Named client %d joins the actual six-player waiting room" % i)
		if player.net.status != "connected":
			return
		check(player.net.seat == i and not authority.net.started and authority.phase == "title" and player.phase == "title", "Seat %d remains stable and joining never starts the match" % i)
	check(await wait_until(func():
		for game in six_clients:
			if game.net.roster.size() != 6:
				return false
		return true), "All six clients receive the full named roster")
	check(not six_clients[5].net.can_start() and not six_clients[5].net.start_match(4), "A guest cannot start the host's room")
	extra_client = scene()
	extra_client.set_physics_process(false)
	extra_client._open_online()
	extra_client.net.join_room(authority.net.room, "Seventh")
	check(await wait_until(func(): return extra_client.net.status == "error"), "Seventh client is rejected without disturbing the full waiting room")
	check(authority.net.roster.size() == 6 and authority.net.can_start(), "Rejected seventh join leaves all six existing slots and host start intact")
	check(authority.net.set_map(3), "Host selects a different arena while still in the waiting room")
	check(await wait_until(func():
		for game in six_clients:
			if game.net.map_id != 3:
				return false
		return true), "Waiting-room map selection reaches every connected client")
	check(authority.net.start_match(3), "Host explicitly starts all six connected named players")
	check(await wait_until(all_six_synced), "All five guests receive the exact canonical six-player opening state")
	if authority.fighters.size() != 6:
		check(false, "Six-player scene creates all six fighters before continuing")
		return
	var authentic_names := true
	for game in six_clients:
		authentic_names = authentic_names and not game.lobby.visible and game.net.started and game.map_id == 3
		for i in range(6):
			authentic_names = authentic_names and game.fighters[i].name == names[i]
	check(authentic_names, "Every client closes its waiting room and displays the authenticated Unicode names and host map")
	extra_client.net.join_room(authority.net.room, "Late arrival")
	check(await wait_until(func(): return extra_client.net.status == "error"), "Late join after match start is rejected without reallocating a seat")
	check(authority.net.roster.size() == 6 and authority.net.player_count == 6, "Started match retains its frozen six-player roster after a late join")
	# Exercise each guest's actual control emitter, authenticated relay seat, and host rules.
	for seat in range(1, 6):
		authority.start_game()
		for _turn in range(seat):
			authority._finish_turn()
		authority._send_state(true)
		check(await wait_until(all_six_synced), "All clients synchronize before guest seat %d takes control" % seat)
		var player = six_clients[seat]
		var inactive = six_clients[1 if seat != 1 else 2]
		var shots_before: int = authority.shots
		inactive.net.send_input({"action": "fire", "seat": seat}, authority.turn)
		await create_timer(0.12).timeout
		check(authority.shots == shots_before and authority.phase == "aim", "Relay authentication prevents another guest from spoofing active seat %d" % seat)
		var previous_target: int = authority.target
		player._target_action()
		check(await wait_until(func(): return authority.target != previous_target), "Guest seat %d target action reaches the host" % seat)
		var move_right: bool = not authority._solid(authority.fighters[seat].pos + Vector2(15, -19))
		var move_key := "right" if move_right else "left"
		player.held[move_key] = true
		player._send_guest_input()
		check(await wait_until(func(): return float(authority._remote_held.get(move_key, 0)) > 0), "Guest seat %d held movement reaches host simulation" % seat)
		var x_before: float = authority.fighters[seat].pos.x
		for _n in range(12):
			authority._physics_process(1.0 / 120)
		player.held.clear()
		player._send_guest_input()
		check((authority.fighters[seat].pos.x - x_before) * (1 if move_right else -1) > 0, "Guest seat %d moves its own fighter on the authoritative host" % seat)
		player._pending_aim = [1.0, 85.0]
		player.fire()
		check(await wait_until(func(): return authority.shots == shots_before + 1 and authority.phase == "flying"), "Guest seat %d launches one real canonical shot" % seat)
		check(authority.projectile.owner == seat and authority.projectile.target != seat, "Guest seat %d projectile carries its actual owner and selected opponent" % seat)
		authority._send_state(true)
		check(await wait_until(all_six_synced), "All six clients exactly agree on guest seat %d's launch" % seat)
	# Preserve a real five-fragment volley and all six inventories across both reconnect paths.
	authority.start_game()
	authority.wind = 27.700096130371094
	for i in range(6):
		authority.freedom[i] = 1
	authority.weapon = authority.BANANA
	authority.target = 5
	authority.fire()
	authority.projectile.pos = Vector2(640.1234130859375, 70.98765563964844)
	authority.projectile.vel = Vector2(190.1234588623047, -80.87654113769531)
	authority.projectile.age = 1.19
	authority._step_projectile(0.02)
	authority.carve(Vector2(640, 410), 23)
	authority._send_state(true)
	check(await wait_until(all_six_synced) and authority.fragments.size() == 5, "All six clients synchronize a real banana airburst with six independent inventories")
	var preserved: Dictionary = authority.network_snapshot()
	var last = six_clients[5]
	var last_token: String = last.net.token
	last.net._fail("Six-player mid-banana seat-five interruption")
	check(await wait_until(func(): return not authority.net.roster[5].connected and not authority.net.together()), "Live seat-five disconnect pauses the six-player volley")
	for _n in range(60):
		authority._physics_process(1.0 / 120)
	check(authority.network_snapshot() == preserved, "Interrupted six-player flight advances neither fragments nor turn state")
	last.net.reconnect()
	check(await wait_until(func(): return authority.net.together() and last.net.together() and all_six_synced()), "Seat five reconnects into the exact existing six-player banana volley")
	check(last.net.seat == 5 and last.net.token == last_token and last.fighters[5].name == names[5] and authority.network_snapshot() == preserved, "Seat-five reconnect preserves seat, token, name and all canonical gameplay state")
	var host_token: String = authority.net.token
	authority.net._fail("Six-player host interruption")
	check(await wait_until(func():
		for i in range(1, 6):
			if six_clients[i].net.host_connected or not six_clients[i].lobby.visible:
				return false
		return true), "Host disconnect pauses all five guests during the same live volley")
	authority.net.reconnect()
	check(await wait_until(func(): return authority.net.together() and all_six_synced()), "Host rejoins its original authority and restores exact state to all five guests")
	check(authority.net.token == host_token and authority.network_snapshot() == preserved, "Host reconnect does not rebuild or reset the six-player match")
	for _n in range(960):
		authority._physics_process(1.0 / 120)
	authority._send_state(true)
	check(await wait_until(all_six_synced) and authority.fragments.is_empty() and authority.phase in ["aim", "over"], "Reconnected six-player banana fragments physically resolve and converge for every guest")
	var equal_terrain := true
	for game in six_clients:
		equal_terrain = equal_terrain and game.terrain.get_data() == authority.terrain.get_data()
	check(equal_terrain, "All six clients retain byte-identical terrain after restored banana impacts")
	# Disconnected eliminated guests no longer hold surviving players hostage.
	authority.start_game()
	authority.fighters[5].hp = 0
	authority._send_state(true)
	check(await wait_until(all_six_synced), "Elimination state reaches every client before disconnecting that guest")
	last.net._fail("Eliminated seat-five departure")
	check(await wait_until(func(): return not authority.net.roster[5].connected), "Host observes the eliminated guest's departure")
	check(authority.net.together() and not authority.lobby.visible, "Eliminated guest disconnect leaves the surviving match available")
	var clock_before: float = authority.turn_clock
	for _n in range(30):
		authority._physics_process(1.0 / 120)
	check(authority.turn_clock < clock_before, "Remaining players' authoritative clock advances after eliminated guest leaves")
	# Host remains mandatory even when its own fighter has already been eliminated.
	authority.fighters[0].hp = 0
	authority._finish_turn()
	authority._send_state(true)
	check(await wait_until(func(): return six_clients[1].fighters[0].hp == 0), "Remaining guests receive the host fighter's elimination")
	authority.net._fail("Eliminated host disconnect")
	check(await wait_until(func(): return not six_clients[1].net.host_connected and six_clients[1].lobby.visible and not six_clients[1].net.together()), "Host disconnection still pauses survivors even after the host fighter is eliminated")
	authority.net.reconnect()
	check(await wait_until(func(): return authority.net.together() and six_clients[1].net.together() and not authority.lobby.visible), "Eliminated host reconnect restores authority without requiring the departed eliminated guest")
	var healthy := true
	for i in range(5):
		healthy = healthy and six_clients[i].net.status == "connected"
	check(healthy, "Six-player control, targeting, both reconnect paths and eliminations cause no protocol or rate-limit errors")

func finish() -> void:
	print("RESULT: %d real-WebSocket checks, %d failures" % [checks, failures])
	host._leave_online()
	guest._leave_online()
	host.queue_free()
	guest.queue_free()
	for game in six_clients:
		game._leave_online()
		game.queue_free()
	if extra_client != null:
		extra_client._leave_online()
		extra_client.queue_free()
	await process_frame
	quit(1 if failures else 0)

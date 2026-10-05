extends SceneTree
## Two independent Godot clients, real WebSocket relay, no mock networking.
## Start online-server/npm run dev; then run with -- --server-url=ws://127.0.0.1:8787
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
	host._open_online()
	host.net.create_room()
	check(await wait_until(func(): return host.net.status == "connected"), "Host creates a real room through WebSocket")
	if host.net.status != "connected":
		print("BLOCKER: ", host.net.status_text)
		await finish()
		return
	check(host.net.room.length() == 8 and host.net.seat == 0, "Server assigns room code and Daniel seat")
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	guest._open_online()
	guest.net.join_room(host.net.room)
	check(await wait_until(func(): return host.net.together() and guest.net.together() and guest._online_started), "Second client joins room and receives initial match")
	check(guest.net.seat == 1 and guest.active == 0 and guest.turn == 1, "Guest is Jesus and sees Daniel's opening turn")
	check(host.lobby.visible and guest.lobby.visible and guest._host_paused, "Guest joining while host shares code sees paused room")
	host._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(await wait_until(func(): return not host.lobby.visible and not guest.lobby.visible), "Host returning after blurred join dismisses both pause overlays")
	check(not host.lobby.visible and not guest.lobby.visible, "Both lobbies close only after genuine connection and state")
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
	await finish()

func finish() -> void:
	print("RESULT: %d real-WebSocket checks, %d failures" % [checks, failures])
	host._leave_online()
	guest._leave_online()
	host.queue_free()
	guest.queue_free()
	await process_frame
	quit(1 if failures else 0)

extends SceneTree
## Deterministic safeguards, not a browser FPS benchmark.
const World = preload("res://World3D.gd")
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

func make_game():
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.start_game()
	return game

func legacy_carve(image: Image, point: Vector2, radius: float) -> void:
	for y in range(maxi(0, int(point.y - radius - 3)), mini(470, int(point.y + radius + 4))):
		for x in range(maxi(0, int(point.x - radius - 3)), mini(1280, int(point.x + radius + 4))):
			var distance := Vector2(x, y).distance_to(point)
			if distance < radius:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif distance < radius + 3 and image.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, Color("9c7180"))

func run() -> void:
	var host = make_game()
	var guest = make_game()
	await process_frame
	var reference: Image = host.terrain.duplicate()
	var random := RandomNumberGenerator.new()
	random.seed = 431619574
	for i in range(200):
		var point := Vector2(random.randf_range(-100, 1380), random.randf_range(250, 570))
		var radius := random.randf_range(1, 100)
		legacy_carve(reference, point, radius)
		host.carve(point, radius)
	check(reference.get_data() == host.terrain.get_data(), "200 randomized span carves match original pixel kernel byte-for-byte, including borders")
	host.start_game()
	var uploads: int = host.terrain_texture_uploads
	for i in range(5):
		host.carve(Vector2(150 + i * 180, 400), 22)
	check(host.terrain_texture_uploads == uploads, "Five-crater burst never uploads inside collision updates")
	check(not host._solid(Vector2(150, 400)), "Collision mask changes before deferred GPU upload")
	host._flush_terrain_texture()
	check(host.terrain_texture_uploads == uploads + 1, "Five-crater burst uploads terrain once")
	host._flush_terrain_texture()
	check(host.terrain_texture_uploads == uploads + 1, "Clean terrain never reuploads")
	var count: int = host.craters.size()
	host.carve(Vector2(150, 400), 22)
	host.carve(Vector2(-100, -100), 20)
	check(host.craters.size() == count and not host._terrain_texture_dirty, "No-op blasts consume no history, mesh rebuild or upload")
	check(guest.apply_network_snapshot(host.network_snapshot()), "Batched host state is accepted")
	check(host.terrain.get_data() == guest.terrain.get_data(), "Batched guest collision mask is byte-identical")
	host.start_game()
	for i in range(499):
		host.carve(Vector2(-100, -100), 20, true)
	check(host.craters.size() == 499, "Legacy no-op history is preserved exactly during replay")
	host.carve(Vector2(640, 400), 20)
	check(host.craters.size() == 500 and host._terrain_limit_notified, "500th crater remains valid and shows one-time safety notice")
	var capped: PackedByteArray = host.terrain.get_data()
	host.toast_clock = 0.25
	host.carve(Vector2(400, 400), 20)
	check(host.craters.size() == 500 and host.terrain.get_data() == capped, "501st crater cannot invalidate protocol3 or desync terrain")
	check(host.toast_clock == 0.25, "Terrain-limit notice is not repeated by subsequent shots")
	var hp: int = host.fighters[1].hp
	host._blast(host.fighters[1].pos + Vector2(0, -20), 30, 10, false)
	check(host.fighters[1].hp < hp, "Explosions still deal damage after terrain safety cap")
	check(guest.apply_network_snapshot(host.network_snapshot()), "Guest accepts state after crossing terrain limit")
	check(host.terrain.get_data() == guest.terrain.get_data(), "500-crater legacy-compatible replay remains byte-identical")
	host.start_game()
	for i in range(499):
		host.carve(Vector2(-100, -100), 20, true)
	for i in range(5):
		host._blast(Vector2(180 + i * 180, 430), 18, 10, false)
	check(host.craters.size() == 500 and host.fragments.is_empty(), "Five banana-sized impacts crossing cap retain bounded terrain history")
	check(guest.apply_network_snapshot(host.network_snapshot()) and host.terrain.get_data() == guest.terrain.get_data(), "Guest accepts capped multi-impact volley without losing canonical terrain")
	for i in range(100):
		host._emit(Vector2.ZERO, Color.WHITE, 48, 10)
	check(host.particles.size() <= host.PARTICLE_CAP, "Presentation particles stay bounded under repeated bursts")
	host.start_game()
	check(host.craters.is_empty() and not host._terrain_limit_notified, "New round restores full destructibility and resets safety notice")
	var view = World.new()
	view.adaptive_quality = true
	view.quality_step = 10
	for i in range(300):
		view.sample_frame_time(0.04)
	check(view.quality_step == 5, "Sustained slow frames reduce graphics to bounded half resolution")
	view.sample_frame_time(10.0)
	check(view.quality_step == 5, "Suspended-tab gap does not change graphics policy")
	for i in range(660):
		view.sample_frame_time(1.0 / 60.0)
	check(view.quality_step == 6, "Stable recovery raises quality gradually with hysteresis")
	view.quality_step = 10
	for i in range(20):
		view.sample_frame_time(0.4)
	check(view.quality_step < 10, "Sustained sub-4-FPS rendering still triggers quality reduction")
	view.free()
	guest.start_game()
	guest.online = true
	guest.net.seat = 1
	guest.net.status = "connected"
	guest.net.started = true
	guest.net.host_connected = true
	guest.net.guest_connected = true
	guest.net.roster = [{"seat": 0, "name": "A", "connected": true, "alive": true}, {"seat": 1, "name": "B", "connected": true, "alive": true}]
	guest._online_started = true
	guest.lobby.hide()
	guest.active = 1
	guest.target = 0
	guest.terrain.fill(Color.TRANSPARENT)
	guest.terrain.fill_rect(Rect2i(0, 300, 1280, 170), Color.WHITE)
	guest.fighters[1].pos = Vector2(100, 300)
	guest.fighters[1].ground = true
	guest.held = {"right": true, "angle_up": true, "power_up": true}
	var canonical: Dictionary = guest.network_snapshot()
	guest._process(1.0 / 60.0)
	check(guest._view_position(1).x > guest.fighters[1].pos.x, "Real Game render hook previews guest movement on first frame")
	check(guest._view_direction() != guest._direction() and guest.prediction.power_for(guest) > guest.power, "Real Game aim and HUD hooks show predicted keyboard input")
	check(guest.network_snapshot() == canonical, "Real Game prediction frame never mutates canonical gameplay snapshot")
	guest._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(guest._view_position(1) == guest.fighters[1].pos, "Real Game focus loss immediately removes visual prediction")
	guest._notification(Control.NOTIFICATION_APPLICATION_FOCUS_IN)
	guest.online = false
	host.queue_free()
	guest.queue_free()
	await process_frame
	print("RESULT: %d performance checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

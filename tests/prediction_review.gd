extends SceneTree
## Independent integration checks with the actual Game/NetSession, no network calls.
var game
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)
func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.start_game()
	game.terrain.fill(Color.TRANSPARENT)
	game.terrain.fill_rect(Rect2i(0, 300, 1280, 170), Color.WHITE)
	game.active = 1
	game.target = 0
	game.fighters[1].pos = Vector2(700, 298)
	game.fighters[1].ground = true
	game.fighters[1].vel = Vector2.ZERO
	game.net.status = "connected"
	game.net.seat = 1
	game.net.started = true
	game.net.host_connected = true
	game.net.guest_connected = true
	game.net.roster = [{"name":"A","seat":0,"alive":true,"connected":true},{"name":"B","seat":1,"alive":true,"connected":true}]
	game.online = true
	game._online_started = true
	game.lobby.hide()
	game._host_focused = true
	game._state_age = 0
	game.held = {"right":true,"angle_up":true,"power_up":true}
	var before: String = JSON.stringify(game.network_snapshot())
	var pixels: PackedByteArray = game.terrain.get_data()
	for n in range(20):
		game.prediction.update(game, 0.01)
	check(game._view_position(1).x > game.fighters[1].pos.x, "Real Game renderer position responds before authority changes")
	game.world3d = load("res://World3D.gd").new()
	game.add_child(game.world3d)
	game.world3d.initialize(game)
	game.world3d.sync(game, 0.016)
	var rendered: Vector2 = game.world3d.game_point(game.world3d.actors[1].position)
	check(rendered.distance_to(game._view_position(1)) < 0.01, "Actual 3D actor uses the predicted presentation position")
	check(JSON.stringify(game.network_snapshot()) == before and game.terrain.get_data() == pixels, "Real Game network snapshot and terrain remain byte-identical after prediction")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game._view_position(1) == game.fighters[1].pos and not game.prediction._active, "Actual focus-out handler removes predicted pose")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.held = {"left":true}
	game.prediction.update(game, 0.1)
	check(game._view_position(1).x < game.fighters[1].pos.x, "Refocus predicts current direction without replaying prior movement")
	game._clear_local_controls()
	check(game._view_position(1) == game.fighters[1].pos and game.held.is_empty(), "Actual cancellation clears both controls and prediction")
	game.held = {"right":true}
	game.prediction.update(game, 0.1)
	game._jump()
	check(game._view_position(1) == game.fighters[1].pos and not game.prediction._active, "Guest jump resets speculative ground motion without simulating jump")
	game.prediction.update(game, 0.1)
	game._state_age = 0.51
	check(game._view_position(1) == game.fighters[1].pos, "A stale real Game snapshot disables speculative rendering")
	game._state_age = 0
	game.prediction.update(game, 0.1)
	game.net.status = "disconnected"
	game._network_changed()
	check(game._view_position(1) == game.fighters[1].pos, "Actual disconnect overlay prevents stale predicted rendering")
	game.online = false
	game.net.leave()
	game.queue_free()
	await process_frame
	print("RESULT: %d independent prediction checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

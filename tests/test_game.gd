extends SceneTree
## Engine-native regression tests: run godot --headless --path . --script res://tests/test_game.gd
var game
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

func step(seconds: float) -> void:
	for n in range(int(seconds * 120)):
		game._physics_process(1.0 / 120)

func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	check(game.phase == "title", "Game opens on title")
	check(game._solid(Vector2(640, 410)), "Generated ground is solid")
	check(not game._solid(Vector2(640, 10)), "Sky is not solid")
	game.start_game()
	game.rng.seed = 42
	game.wind = 0
	check(game.phase == "aim" and game.active == 0, "Daniel opens first turn")
	check(game.fighters[0].hp == 100 and game.fighters[1].hp == 100, "Both fighters begin with 100 health")
	var old_x: float = game.fighters[0].pos.x
	game._move_character(1, 0.1)
	check(game.fighters[0].pos.x > old_x and game.move_left < 170, "Walking moves character and consumes budget")
	game._jump()
	check(game.fighters[0].vel.y < 0 and not game.fighters[0].ground, "Jump applies upward impulse")
	step(1.1)
	check(game.fighters[0].ground, "Gravity lands jumping fighter")
	game.start_game()
	game.wind = 0
	game.fire()
	check(game.phase == "flying" and game.shots == 1, "Fire launches exactly one rocket")
	game.fire()
	check(game.shots == 1, "Repeated fire is locked while shot is in flight")
	step(6.0)
	check(game.phase == "aim" and game.active == 1 and game.turn == 2, "Shot resolves and turn passes to Jesus")
	check(game.fighters[1].hp < 100, "Opening rocket reaches and damages opponent")
	game.start_game()
	game.carve(Vector2(640, 410), 35)
	check(not game._solid(Vector2(640, 410)), "Explosion removes terrain pixels")
	check(game._solid(Vector2(700, 410)), "Crater preserves nearby unaffected terrain")
	game._explode(game.fighters[1].pos + Vector2(0, -15), 57)
	check(game.fighters[1].hp < 100, "Blast inflicts radial damage")
	check(game.fighters[1].vel.y < 0, "Blast applies upward knockback")
	game.start_game()
	game.weapon = 1
	game.power = 20
	game.angle = 10
	game.wind = 0
	game.fire()
	check(game.projectile.weapon == 1, "Second weapon launches a bouncing bomb")
	var saw_bounce := false
	for n in range(600):
		game._physics_process(1.0 / 120)
		if not game.projectile.is_empty() and game.projectile.bounces > 0:
			saw_bounce = true
	check(saw_bounce, "Bomb bounces on terrain before exploding")
	check(game.projectile.is_empty() and game.active == 1, "Bomb fuse resolves and turn passes")
	game.start_game()
	game.turn_clock = 0.01
	step(2)
	check(game.active == 1 and game.turn == 2, "Turn timeout passes turn without firing")
	game.start_game()
	game.fighters[1].pos = Vector2(1050, 460)
	game._step_fighter(1, 0.01)
	check(game.fighters[1].hp == 0, "Water is fatal")
	game._check_winner()
	check(game.phase == "over" and game.winner == 0, "Last surviving fighter wins")
	game.start_game()
	game.fighters[0].hp = 0
	game.fighters[1].hp = 0
	game._check_winner()
	check(game.phase == "over" and game.winner == -1, "Simultaneous elimination is a draw")
	game.start_game()
	check(game.phase == "aim" and game.fighters[1].hp == 100 and game.shots == 0, "Restart resets health, turns, projectile, and score")
	check(game._solid(Vector2(640, 410)), "Restart rebuilds destroyed terrain")
	game.help_open = true
	var paused_state: Dictionary = game.network_snapshot()
	game._jump()
	game._weapon_action()
	game._target_action()
	game.fire()
	check(game.network_snapshot() == paused_state, "Help ignores gameplay actions without altering the match")
	var time_before: float = game.turn_clock
	step(2)
	check(game.turn_clock == time_before, "Help pauses the turn timer")
	game.help_open = false
	game._restart_action()
	check(game.phase == "title", "Restart icon returns to title before starting a fresh duel")
	for viewport_size in [Vector2(1280, 800), Vector2(852, 393), Vector2(430, 932)]:
		game._layout(viewport_size)
		var fire_end: Vector2 = game.buttons.fire.end * game.ui_scale + game.ui_origin
		check(fire_end.x <= viewport_size.x + 1 and fire_end.y <= viewport_size.y + 1, "Fire button stays visible at %dx%d" % [viewport_size.x, viewport_size.y])
		var button_center: Vector2 = game.buttons.fire.get_center()
		var screen_center: Vector2 = button_center * game.ui_scale + game.ui_origin
		check(((screen_center - game.ui_origin) / game.ui_scale).distance_to(button_center) < 0.01, "Pointer transform round-trips at %dx%d" % [viewport_size.x, viewport_size.y])
		game.start_game()
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = screen_center
		touch.pressed = true
		game._input(touch)
		check(game.phase == "flying" and game.shots == 1, "Touch Fire button launches a shot at %dx%d" % [viewport_size.x, viewport_size.y])
	game._layout()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

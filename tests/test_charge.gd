extends SceneTree
var game
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)
func key(code: int, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	game._input(event)
func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.start_game()
	key(KEY_SPACE, true)
	check(game.shots == 0 and game.fighters[0].vel.y < 0, "Space jumps without firing")
	game.start_game()
	key(KEY_K, true)
	check(game._charge_active and game.shots == 0 and game._charge_power == 12, "K starts charge at minimum without firing")
	game._update_charge(1.0)
	check(is_equal_approx(game._charge_power, 100), "Charge reaches maximum after one second")
	game._update_charge(0.5)
	check(is_equal_approx(game._charge_power, 56), "Charge descends for release timing skill")
	key(KEY_K, true, true)
	check(is_equal_approx(game._charge_power, 56), "Key repeat never resets charge")
	key(KEY_K, false)
	check(game.shots == 1 and is_equal_approx(game.power, 56), "K release fires exactly the displayed power")
	key(KEY_K, false)
	check(game.shots == 1, "Repeated release cannot fire again")
	game.start_game()
	game._begin_charge(3)
	game._update_charge(200.25)
	check(is_equal_approx(game._charge_power, 34), "Long frames and many cycles remain bounded")
	game._release_charge(-2)
	check(game._charge_active and game.shots == 0, "Different input source cannot release the shot")
	game._release_charge(3)
	check(game.shots == 1 and is_equal_approx(game.power, 34), "Touch release uses exact charge value")
	game.start_game()
	game._begin_charge(-2)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._release_charge(-2)
	check(game.shots == 0 and not game._charge_active, "Focus loss cancels charge without a phantom shot")
	game._begin_charge(-2)
	key(KEY_ESCAPE, true)
	key(KEY_K, false)
	check(game.shots == 0 and game.help_open, "Opening help cancels held shot")
	game.start_game()
	game._begin_charge(-2)
	game._finish_turn()
	game._release_charge(-2)
	check(game.shots == 0 and not game._charge_active, "Turn transition cancels charge")
	print("Charge controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

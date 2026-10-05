extends SceneTree
var game
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	var render = load("res://World3D.gd").new()
	game.add_child(render)
	render.initialize(game)
	game.world3d = render
	for count in range(2,7):
		game.player_names.clear()
		for i in range(count):
			game.player_names.append("Spelare %d" % i)
		game.start_game()
		for spec in [[Vector2(320,568),false], [Vector2(393,852),false], [Vector2(430,932),false], [Vector2(667,375),false], [Vector2(852,393),false], [Vector2(1024,768),false], [Vector2(1280,800),false], [Vector2(1920,1080),false], [Vector2(1280,800),true], [Vector2(1920,1080),true]]:
			var screen: Vector2 = spec[0]
			game.force_touch_controls = spec[1]
			game._layout(screen)
			render.sync(game,0)
			await process_frame
			check((game.world_rect.size * game.ui_scale).distance_to(screen) < 0.01, "world fills screen")
			var actions := ["left","right","jump","angle_down","angle_up","weapon","fire"] if game.touch_controls else ["weapon","fire"]
			if count > 2: actions.append("target")
			for action in actions:
				var rect: Rect2 = game.buttons[action]
				check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1280 and rect.end.y <= game.layout_h, "%s stays in %s" % [action,screen])
				if game.touch_controls:
					check(rect.size.x * game.ui_scale >= 43.99 and rect.size.y * game.ui_scale >= 43.99, "%s >= 44px in %s" % [action,screen])
				for other in actions:
					if action != other: check(not rect.intersects(game.buttons[other]), "%s overlaps %s in %s" % [action,other,screen])
			for point in [Vector2(0,0),Vector2(224,307), Vector2(1050,325),Vector2(1280,470),Vector2(650,-100)]:
				var projected: Vector2 = render.camera.unproject_position(render.world_point(point,30))
				var drawn: Vector2 = render.render_bounds.position + projected / Vector2(render.render_size) * render.render_bounds.size
				check(drawn.distance_to(point)<0.02, "camera render maps point exactly at %s" % screen)
				check(game.ui_to_world(game.world_to_ui(point)).distance_to(point)<0.02,"input inverse matches")
			print("GEOMETRY ", count, " ", screen, " renderer ",render.render_size)
	print("RESULT: %d compact layout checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

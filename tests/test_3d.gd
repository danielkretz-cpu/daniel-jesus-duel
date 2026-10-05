extends SceneTree
## Real 3D scene / exact 2D simulation contract. No display/GPU is required.
const WorldScript = preload("res://World3D.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func coverage_matches(mesh, terrain: Image) -> bool:
	# Reconstruct the mesh's front triangles from their greedy rectangles.
	var coverage := Image.create(1280, 470, false, Image.FORMAT_RGBA8)
	coverage.fill(Color.TRANSPARENT)
	for chunk in mesh.chunks.values():
		for rectangle in chunk.get_meta("rectangles", []):
			coverage.fill_rect(rectangle, Color.WHITE)
	var source := terrain.get_data()
	var drawn := coverage.get_data()
	for index in range(3, source.size(), 4):
		if (source[index] > 127) != (drawn[index] > 127):
			return false
	return true

func geometry_matches(mesh) -> bool:
	for chunk in mesh.chunks.values():
		if chunk.mesh == null:
			continue
		var front: Array = chunk.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = front[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = front[Mesh.ARRAY_TEX_UV]
		for i in range(vertices.size()):
			var logical := WorldScript.game_point(vertices[i])
			if logical.distance_to(uv[i] * Vector2(1280, 470)) > 0.002:
				return false
		if chunk.mesh.get_surface_count() < 2:
			continue
		var walls: Array = chunk.mesh.surface_get_arrays(1)
		var wall_vertices: PackedVector3Array = walls[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = walls[Mesh.ARRAY_NORMAL]
		for i in range(0, wall_vertices.size(), 4):
			var a := WorldScript.game_point(wall_vertices[i])
			var b := WorldScript.game_point(wall_vertices[i + 1])
			var outside := Vector2.RIGHT if absf(a.x - b.x) < 0.001 else Vector2.DOWN
			var inside_pixel := Vector2i(((a + b) * 0.5 - outside * 0.5).floor())
			var outside_pixel := Vector2i(((a + b) * 0.5 + outside * 0.5).floor())
			if mesh.solid_pixel(inside_pixel.x, inside_pixel.y) == mesh.solid_pixel(outside_pixel.x, outside_pixel.y):
				return false
			if not is_equal_approx(wall_vertices[i + 2].z - wall_vertices[i + 1].z, -mesh.DEPTH):
				return false
	return true

func run() -> void:
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	check(game.world3d == null, "Ordinary headless game skips 3D renderer")
	var view = WorldScript.new()
	game.add_child(view)
	view.initialize(game)
	game.world3d = view
	await process_frame
	check(view.viewport.own_world_3d, "3D renderer has an isolated world")
	check(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Camera is fixed orthographic")
	check(view.actors.size() == 2 and view.actors[0] is Node3D and view.actors[1] is Node3D, "Both fighters are actual Node3D models")
	check(view.bullets.size() == 6, "Primary and five banana fragments have 3D slots")
	var projected_ok := true
	for p in [Vector2.ZERO, Vector2(224, 307), Vector2(640, 235), Vector2(1050, 325), Vector2(1280, 470)]:
		for depth in [-100.0, 0.0, 18.0, 30.0]:
			var projected := WorldScript.game_point(WorldScript.world_point(p, depth))
			projected_ok = projected_ok and projected.distance_to(p) < 0.0002
	check(projected_ok, "3D projection round-trips every gameplay plane exactly")
	for scale_factor in [0.32, 0.49, 0.75, 1.0, 2.0]:
		view.resize_for_scale(scale_factor)
		await process_frame
		var accurate := true
		for point in [Vector2(0, 0), Vector2(640, 235), Vector2(1280, 470), Vector2(224, 307)]:
			var screen: Vector2 = view.camera.unproject_position(WorldScript.world_point(point, 18))
			var logical: Vector2 = screen * Vector2(1280, 470) / Vector2(view.render_size)
			accurate = accurate and logical.distance_to(point) < 0.02
		check(accurate, "Native Camera3D projection matches input at scale %.2f" % scale_factor)
	var timer := Time.get_ticks_msec()
	for map_index in range(5):
		game.map_id = map_index
		game.start_game()
		view.sync(game, 0)
		var terrain_mesh = view.terrain_view
		check(coverage_matches(terrain_mesh, game.terrain), "Map %d mesh exactly covers every collision pixel" % map_index)
		check(view.last_map == map_index and view.last_terrain == game.terrain, "Map %d renderer follows selected terrain" % map_index)
		var previous_rebuilds: int = terrain_mesh.rebuild_count
		for i in range(20):
			view.sync(game, 1.0 / 60)
		check(previous_rebuilds == terrain_mesh.rebuild_count, "Map %d idle animation never rebuilds terrain" % map_index)
		game.carve(Vector2(640, 408), 19)
		view.sync(game, 0)
		check(not terrain_mesh.mesh_covers_pixel(Vector2i(640, 408)), "Map %d tunnel has no front geometry in crater" % map_index)
		check(terrain_mesh.last_rebuilt_chunks <= 4, "Map %d crater rebuild touches only local chunks" % map_index)
		check(coverage_matches(terrain_mesh, game.terrain), "Map %d crater mesh equals alpha collision mask" % map_index)
		game.carve(Vector2(256, 350), 58)
		game.carve(Vector2(284, 364), 47)
		view.sync(game, 0)
		check(coverage_matches(terrain_mesh, game.terrain), "Map %d overlapping chunk-boundary blasts remain exact" % map_index)
		check(geometry_matches(terrain_mesh), "Map %d actual vertices, UVs and extruded hole walls match collision" % map_index)
		game.start_game()
		view.sync(game, 0)
		check(coverage_matches(terrain_mesh, game.terrain), "Map %d restart rebuilds pristine 3D terrain" % map_index)
	print("3D_TERRAIN_SUITE_MS: ", Time.get_ticks_msec() - timer)
	game.map_id = 3
	game.start_game()
	game.carve(Vector2(500, 380), 48)
	var snapshot: Dictionary = game.network_snapshot()
	game.map_id = 0
	game.start_game()
	check(game.apply_network_snapshot(snapshot), "Remote snapshot with different map is accepted")
	view.sync(game, 0)
	check(view.last_map == 3 and coverage_matches(view.terrain_view, game.terrain), "Guest 3D map and craters follow authoritative snapshot")
	for weapon_index in range(4):
		game.start_game()
		game.weapon = weapon_index
		game.freedom[0] = 1
		game.fire()
		view.sync(game, 0)
		check(view.bullets[0].visible and WorldScript.game_point(view.bullets[0].position).distance_to(game.projectile.pos) < 0.01, "Weapon %d mesh follows exact ballistic point" % weapon_index)
	game.start_game()
	game.weapon = 2
	game.fire()
	game._burst_banana(Vector2(640, 150))
	view.sync(game, 0)
	var visible_fragments := 0
	for bullet in view.bullets:
		if bullet.visible:
			visible_fragments += 1
	check(visible_fragments == 5, "All five banana fragments render as 3D projectiles")
	for size in [Vector2(1280, 800), Vector2(852, 393), Vector2(430, 932)]:
		game._layout(size)
		view.sync(game, 0)
		var point: Vector2 = game.fighters[game.active].pos + Vector2(150, -100)
		var screen: Vector2 = (point + Vector2(0, game.world_top)) * game.ui_scale + game.ui_origin
		var restored: Vector2 = (screen - game.ui_origin) / game.ui_scale - Vector2(0, game.world_top)
		check(restored.distance_to(point) < 0.001, "3D aim/touch coordinates stay stable at %dx%d" % [size.x, size.y])
		var projected_pixel: Vector2 = view.camera.unproject_position(WorldScript.world_point(point, 18))
		var projected_world: Vector2 = projected_pixel * view.render_bounds.size / Vector2(view.render_size) + view.render_bounds.position
		check(game.world_to_ui(projected_world).distance_to(game.world_to_ui(point)) < 0.02, "Adaptive full-screen Camera3D stays aligned with overlay aim at %dx%d" % [size.x, size.y])
		check(is_equal_approx(game.world_rect.size.y, game.layout_h) and game.ui_origin == Vector2.ZERO, "Arena fills full viewport beneath overlays at %dx%d" % [size.x, size.y])
	for count in range(2, 7):
		game.player_names.clear()
		for i in range(count):
			game.player_names.append("Test %d" % (i + 1))
		game.start_game()
		view.sync(game, 0)
		check(view.actors.size() == count, "%d players create exactly %d 3D rigs" % [count, count])
		var aligned := true
		var palette: Array[Color] = []
		for i in range(count):
			aligned = aligned and WorldScript.game_point(view.actors[i].position).distance_to(game.fighters[i].pos) < 0.002
			palette.append(game._fighter_color(i))
		check(aligned, "%d players' actual mesh roots match collision feet" % count)
		var unique := true
		for i in range(palette.size()):
			for j in range(i + 1, palette.size()):
				unique = unique and palette[i] != palette[j]
		check(unique, "%d players retain distinct seat colors" % count)
	game._layout(Vector2(852, 393))
	var finger_sized := true
	for action in ["left", "right", "jump", "angle_down", "angle_up", "weapon", "fire"]:
		var physical: Vector2 = game.buttons[action].size * game.ui_scale
		finger_sized = finger_sized and physical.x >= 44 and physical.y >= 44
	check(finger_sized, "Every primary landscape touch button is at least 44 pixels")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

extends SceneTree
## Independent repeatable CPU/resource review; not a browser FPS benchmark.
var game
var failures := 0
var records: Array = []

func _initialize() -> void:
	call_deferred("run")

func record(label: String, fields: Dictionary) -> void:
	fields["label"] = label
	records.append(fields)
	print("PERF_REVIEW ", JSON.stringify(fields))

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func flush_view() -> void:
	if game.world3d != null:
		game.world3d.sync(game, 0.0)
	elif game.has_method("_flush_terrain_texture"):
		game._flush_terrain_texture()

func resource_counts(node: Node) -> Dictionary:
	var result := {"nodes": 1, "mesh_instances": 0, "triangles": 0, "surfaces": 0}
	if node is MeshInstance3D and node.mesh != null:
		result.mesh_instances += 1
		for surface in range(node.mesh.get_surface_count()):
			result.surfaces += 1
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays.size() == Mesh.ARRAY_MAX:
				result.triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
	for child in node.get_children():
		var count := resource_counts(child)
		for key in result:
			result[key] += count[key]
	return result

func run() -> void:
	var begin := Time.get_ticks_usec()
	game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	if game.world3d == null and OS.get_cmdline_user_args().has("--mesh"):
		game.world3d = load("res://World3D.gd").new()
		game.add_child(game.world3d)
		game.world3d.initialize(game)
	game.player_names.assign(["A", "B", "C", "D", "E", "F"])
	game.start_game()
	flush_view()
	await process_frame
	record("startup", {"ms": (Time.get_ticks_usec()-begin)/1000.0, "headless": DisplayServer.get_name() == "headless", "world": game.world3d != null, "resources": resource_counts(game)})
	for crater_count in [0, 25, 100, 500]:
		game.map_id = 3
		game.start_game()
		flush_view()
		var snapshot: Dictionary = game.network_snapshot()
		for n in range(crater_count):
			snapshot.craters.append([30.0 + float((n*137)%1210), 295.0 + float((n*31)%140), 18.0 + float(n%4)*3.0])
		snapshot.terrain_version = crater_count
		var timer := Time.get_ticks_usec()
		check(game.apply_network_snapshot(snapshot), "replay rejected")
		var apply_ms := (Time.get_ticks_usec()-timer)/1000.0
		timer = Time.get_ticks_usec()
		flush_view()
		var flush_ms := (Time.get_ticks_usec()-timer)/1000.0
		var digest: String = game.terrain.get_data().hex_encode().sha256_text()
		timer = Time.get_ticks_usec()
		for n in range(100):
			check(game.apply_network_snapshot(snapshot), "repeat rejected")
		var repeat_ms := (Time.get_ticks_usec()-timer)/1000.0
		record("snapshot", {"craters": crater_count, "apply_ms": apply_ms, "flush_ms": flush_ms, "repeat_100_ms": repeat_ms, "collision_digest": digest, "resources": resource_counts(game), "snapshot_bytes": JSON.stringify(snapshot).to_utf8_buffer().size()})
		await process_frame
	var baseline_counts := {}
	var baseline_memory := 0.0
	var last_counts := {}
	for n in range(20):
		game.map_id = n%5
		game.start_game()
		flush_view()
		await process_frame
		if n == 4:
			baseline_counts = resource_counts(game)
			baseline_memory = Performance.get_monitor(Performance.MEMORY_STATIC)
		if n == 19: last_counts = resource_counts(game)
	check(baseline_counts == last_counts, "resources grow after identical map/roster restart cycles")
	record("restart_resources", {"after_5": baseline_counts, "after_20": last_counts, "static_memory_after5": baseline_memory, "static_memory_after20": Performance.get_monitor(Performance.MEMORY_STATIC), "failures": failures})
	var sync_timer := Time.get_ticks_usec()
	for n in range(1000):
		flush_view()
	record("idle_sync_1000", {"ms": (Time.get_ticks_usec()-sync_timer)/1000.0})
	game.queue_free()
	await process_frame
	print("PERF_REVIEW_RESULT ", failures)
	quit(1 if failures else 0)

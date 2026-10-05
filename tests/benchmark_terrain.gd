extends SceneTree
## CPU-only terrain mesh benchmark. Run with --headless --script; optional
## -- --baseline loads the unmodified local .cache/terrain_perf_baseline.gd.
## Before changing Terrain3D.gd, save that baseline with:
## cp Terrain3D.gd .cache/terrain_perf_baseline.gd
## -- --verify-baseline also compares complete mesh buffers, including walls,
## normals, alpha threshold cases, chunk seams, world edges and empty chunks.
## Image generation and carving are intentionally outside measured rebuilds.
const Themes = preload("res://MapThemes.gd")
const WIDTH := 1280
const HEIGHT := 470
var checks := 0
var failures := 0
var samples: Dictionary = {"initial": [], "small_crater": [], "large_crater": [], "five_craters": [], "idle": []}

func _initialize() -> void:
	call_deferred("run")

func carve(image: Image, center: Vector2i, radius: int) -> Rect2i:
	for y in range(maxi(0, center.y - radius), mini(HEIGHT, center.y + radius + 1)):
		var dy := y - center.y
		var half := int(sqrt(float(radius * radius - dy * dy)))
		var left := maxi(0, center.x - half)
		var right := mini(WIDTH - 1, center.x + half)
		image.fill_rect(Rect2i(left, y, right - left + 1, 1), Color.TRANSPARENT)
	return Rect2i(center - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1))

func measure(mesh, stage: String, record: bool) -> void:
	var start := Time.get_ticks_usec()
	mesh.flush()
	var elapsed := Time.get_ticks_usec() - start
	if record:
		samples[stage].append(elapsed)

func run() -> void:
	var script_path := "res://Terrain3D.gd"
	if "--baseline" in OS.get_cmdline_user_args():
		script_path = "res://.cache/terrain_perf_baseline.gd"
	if not FileAccess.file_exists(script_path):
		push_error("Missing saved baseline: " + script_path)
		quit(1)
		return
	var terrain_script = load(script_path)
	if "--verify-baseline" in OS.get_cmdline_user_args():
		if not FileAccess.file_exists("res://.cache/terrain_perf_baseline.gd"):
			push_error("Save the unmodified Terrain3D.gd to .cache/terrain_perf_baseline.gd first.")
			quit(1)
			return
		verify_baseline(terrain_script, load("res://.cache/terrain_perf_baseline.gd"))
	for round_index in range(4):
		for map_id in range(5):
			var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
			for x in range(WIDTH):
				var top: int = Themes.surface_y(map_id, x)
				image.fill_rect(Rect2i(x, top, 1, HEIGHT - top), Color("906d6b"))
			var mesh = terrain_script.new()
			root.add_child(mesh)
			mesh.configure(image, ImageTexture.create_from_image(image))
			measure(mesh, "initial", round_index > 0)
			mesh.mark_dirty(carve(image, Vector2i(640, 408), 19))
			measure(mesh, "small_crater", round_index > 0)
			mesh.mark_dirty(carve(image, Vector2i(256, 350), 58))
			measure(mesh, "large_crater", round_index > 0)
			for i in range(5):
				mesh.mark_dirty(carve(image, Vector2i(760 + i * 19, 355 + (i % 2) * 13), 27))
			measure(mesh, "five_craters", round_index > 0)
			measure(mesh, "idle", round_index > 0)
			mesh.free()
	print("TERRAIN_CPU_BENCHMARK: ", script_path)
	for stage in samples:
		var values: Array = samples[stage]
		values.sort()
		var total := 0.0
		for value in values:
			total += value
		print("%s n=%d median_ms=%.3f mean_ms=%.3f max_ms=%.3f" % [stage, values.size(), values[values.size() / 2] / 1000.0, total / values.size() / 1000.0, values[-1] / 1000.0])
	if checks:
		print("MESH_BUFFER_EQUIVALENCE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func compare_meshes(a, b, label: String) -> void:
	checks += 1
	var equal := true
	for key in a.chunks:
		var ca = a.chunks[key]
		var cb = b.chunks[key]
		equal = equal and ca.get_meta("rectangles") == cb.get_meta("rectangles")
		if ca.mesh == null or cb.mesh == null:
			equal = equal and ca.mesh == cb.mesh
			continue
		equal = equal and ca.mesh.get_surface_count() == cb.mesh.get_surface_count()
		for n in range(ca.mesh.get_surface_count()):
			var aa = ca.mesh.surface_get_arrays(n)
			var bb = cb.mesh.surface_get_arrays(n)
			for i in range(Mesh.ARRAY_MAX):
				if aa[i] != bb[i]:
					equal = false
					push_error("Array differs: %s chunk %s surface %d array %d" % [label, key, n, i])
	if not equal:
		failures += 1
	print("PASS: " if equal else "FAIL: ", label)

func verify_baseline(current_script: Script, baseline_script: Script) -> void:
	for map_id in range(6):
		var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
		if map_id < 5:
			for x in range(WIDTH):
				var y := Themes.surface_y(map_id, x)
				image.fill_rect(Rect2i(x, y, 1, HEIGHT - y), Color8((x * 23) % 256, (x * 41) % 256, (x * 53) % 256))
		else:
			for origin in [Vector2i(0, 0), Vector2i(1260, 0), Vector2i(0, 450), Vector2i(1260, 450), Vector2i(120, 120), Vector2i(632, 376)]:
				for x in range(20):
					for y in range(20):
						var alpha: int = [0, 1, 127, 128, 254, 255][(x * 3 + y) % 6]
						image.set_pixelv(origin + Vector2i(x, y), Color8(21 + x, 53 + y, 91, alpha))
		var a = current_script.new()
		var b = baseline_script.new()
		root.add_child(a)
		root.add_child(b)
		var texture := ImageTexture.create_from_image(image)
		a.configure(image, texture)
		b.configure(image, texture)
		a.flush()
		b.flush()
		compare_meshes(a, b, "Map %d initial exact buffers" % map_id)
		for region in [Rect2i(630, 398, 22, 22), Rect2i(122, 370, 31, 31), Rect2i(0, 0, WIDTH, HEIGHT)]:
			image.fill_rect(region, Color.TRANSPARENT)
			a.mark_dirty(region)
			b.mark_dirty(region)
			a.flush()
			b.flush()
			compare_meshes(a, b, "Map %d edit %s exact buffers" % [map_id, region])
		a.free()
		b.free()

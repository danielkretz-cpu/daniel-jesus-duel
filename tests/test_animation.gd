extends SceneTree
## Headless character-presentation regression gate; no scene, network or GPU needed.
## Run: godot --headless --path . --script res://tests/test_animation.gd
const FighterScript = preload("res://Fighter3D.gd")
const EXPECTED_COLORS := ["91d2b0", "b6a4ef", "f39c89", "7ed4df", "f9c95e", "83aef0"]
const FRAME_RATES := [15, 30, 60, 144]
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

func run() -> void:
	for seat in range(6):
		check(FighterScript.fighter_color(seat).to_html(false) == EXPECTED_COLORS[seat], "Seat %d keeps its distinct HUD/model palette" % seat)
	for fps in FRAME_RATES:
		for seat in range(6):
			run_animation_case(seat, fps)
	# Flush queued mesh cleanup as well as all rigs before reporting a clean exit.
	await process_frame
	print("RESULT: %d checks, %d failures; 6 seats x 4 frame rates" % [checks, failures])
	quit(1 if failures else 0)

func run_animation_case(seat: int, fps: int) -> void:
	var label := "Seat %d at %d FPS: " % [seat, fps]
	var rig := FighterScript.new()
	root.add_child(rig)
	rig.configure(seat)
	rig.position = Vector3(120, 34, -8)
	var model := rig.get_node_or_null("SquashAndStretch") as Node3D
	var body := rig.get_node_or_null("SquashAndStretch/Body") as Node3D
	check(model != null and body != null, label + "foot-anchored deformation and body pivots exist")
	if model == null or body == null:
		rig.queue_free()
		return
	var initial_ids := geometry_ids(rig)
	check(initial_ids.size() >= 7 and initial_ids.size() <= 10, label + "static parts stay batched to a small draw count")
	check(batched_materials_valid(rig), label + "batched meshes retain lit sRGB vertex-color materials and normals")
	check(body_has_color(body, FighterScript.fighter_color(seat)), label + "seat palette is baked into the body geometry")
	check(body.has_node("ScarfTail") == (seat % 2 == 0), label + "even seats are explorers and odd seats are rings")
	for n in range(12):
		rig.configure(seat)
	check(geometry_ids(rig) == initial_ids and rig.get_node("SquashAndStretch") == model, label + "same-seat configure preserves all existing geometry")
	var fighter := {"hp":100, "ground":true, "vel":Vector2.ZERO, "face":1.0 if seat % 2 == 0 else -1.0, "pos":Vector2(120, 340)}
	var aim := Vector2(float(fighter.face), -0.7)
	var delta := 1.0 / fps
	var elapsed := 0.0
	var invariants := 3
	for n in range(fps):
		elapsed += delta
		invariants &= pose_step(rig, fighter, aim, elapsed, delta)
	fighter.ground = false
	fighter.vel = Vector2(30, -270)
	var jump_min := 10.0
	var jump_max := 0.0
	for n in range(int(fps * 0.7)):
		elapsed += delta
		fighter.vel.y = -270 + n * delta * 850
		invariants &= pose_step(rig, fighter, aim, elapsed, delta)
		jump_min = minf(jump_min, model.scale.y)
		jump_max = maxf(jump_max, model.scale.y)
	check(jump_min < 0.98, label + "jump has brief cosmetic anticipation")
	check(jump_max > 1.08, label + "airborne body stretches visibly")
	fighter.ground = true
	fighter.vel = Vector2.ZERO
	var landing_min := 10.0
	var landing_rebounded := false
	for n in range(int(fps * 0.7)):
		elapsed += delta
		invariants &= pose_step(rig, fighter, aim, elapsed, delta)
		landing_min = minf(landing_min, model.scale.y)
		# Idle breathing is phase-shifted by seat, so recovery may finish just below 1.0.
		landing_rebounded = landing_rebounded or (landing_min < 0.96 and model.scale.y > 0.985 and model.scale.y > landing_min + 0.06)
	check(landing_min < 0.96, label + "landing compresses in response to fall speed")
	check(landing_rebounded, label + "landing spring rebounds to near-idle height")
	rig.react_shot()
	invariants &= pose_step(rig, fighter, aim, elapsed, delta)
	check(absf(body.position.x) > 0.5, label + "confirmed shot produces visible recoil")
	fighter.hp = 60
	invariants &= pose_step(rig, fighter, aim, elapsed, delta)
	check(rig.get("_hit_clock") > 0.0, label + "authoritative HP loss triggers a hit reaction")
	for n in range(fps * 8):
		elapsed += delta
		invariants &= pose_step(rig, fighter, aim, elapsed, delta)
	check(rig.get("_recoil") == 0.0 and absf(body.position.x) < 0.001, label + "recoil fully settles without horizontal drift")
	check(rig.get("_hit_clock") == 0.0, label + "hit reaction ends")
	check(absf(model.scale.y - 1.0) < 0.015, label + "deformation returns to idle after jump, landing and impacts")
	# Pauses, repeated impacts and zero-delta syncs must not destabilize the spring.
	for n in range(5):
		rig.react_hit(1.0)
		rig.react_shot()
		invariants &= pose_step(rig, fighter, Vector2.ZERO, elapsed, 4.0)
		invariants &= pose_step(rig, fighter, Vector2.ZERO, elapsed, 0.0)
	check((invariants & 1) != 0, label + "every pose preserves input dictionary and parent-assigned root transform")
	check((invariants & 2) != 0, label + "every pose preserves volume and bounded finite scale, including pauses")
	check(geometry_ids(rig) == initial_ids, label + "animation never rebuilds meshes")
	rig.queue_free()

func pose_step(rig: Node3D, fighter: Dictionary, aim: Vector2, elapsed: float, delta: float) -> int:
	var before := fighter.duplicate(true)
	var transform_before := rig.transform
	rig.update_pose(fighter, aim, true, elapsed, delta)
	var result := 0
	if fighter == before and rig.transform.is_equal_approx(transform_before):
		result |= 1
	var deform := rig.get_node("SquashAndStretch") as Node3D
	var scale := deform.scale
	if scale.is_finite() and scale.y >= 0.77 and scale.y <= 1.24 and absf(scale.x * scale.y * scale.z - 1.0) < 0.0001:
		result |= 2
	return result

func geometry_ids(node: Node) -> Array[int]:
	var ids: Array[int] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			ids.append(child.get_instance_id())
		ids.append_array(geometry_ids(child))
	return ids

func batched_materials_valid(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance3D and child.name == "StaticGeometry":
			if not child.mesh is ArrayMesh or child.mesh.get_surface_count() != 1:
				return false
			var material := child.material_override as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo or not material.vertex_color_is_srgb:
				return false
			if material.albedo_color != Color.WHITE or material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return false
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if vertices.is_empty() or vertices.size() != normals.size() or vertices.size() != colors.size():
				return false
			for normal in normals:
				if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001:
					return false
		if not batched_materials_valid(child):
			return false
	return true

func body_has_color(body: Node3D, expected: Color) -> bool:
	for child in body.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh:
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for color in colors:
				if absf(color.r - expected.r) <= 1.0 / 255.0 and absf(color.g - expected.g) <= 1.0 / 255.0 and absf(color.b - expected.b) <= 1.0 / 255.0:
					return true
	return false

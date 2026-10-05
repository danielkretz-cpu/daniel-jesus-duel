extends Node3D
## Procedural, genuinely volumetric characters. One unit is one gameplay pixel.
## +Y is up, +Z is the face/camera side; local (0, 0, 0) is the feet.
## No game state, collision, or network ownership lives in this presentation rig.

const INK := Color("25263c")
const MINT := Color("91d2b0")
const PURPLE := Color("b6a4ef")
const GOLD := Color("f9c95e")
const CREAM := Color("fff3db")
const SEAT_COLORS := [MINT, PURPLE, Color("f39c89"), Color("7ed4df"), GOLD, Color("83aef0")]
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

var fighter_index := 0
var _deform: Node3D
var _body: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _free_arm: Node3D
var _weapon: Node3D
var _scarf: Node3D
var _selection: Node3D
var _eyes: Array[Node3D] = []
var _last_position := Vector3.ZERO
var _has_position := false
var _walk_phase := 0.0
var _motion := 0.0
var _blink := 1.0
var _has_pose := false
var _was_grounded := true
var _previous_hp := 100
var _last_vertical_speed := 0.0
var _stretch := 1.0
var _stretch_speed := 0.0
var _jump_clock := -1.0
var _landing_clock := 1.0
var _landing_strength := 0.0
var _recoil := 0.0
var _hit_clock := 0.0
var _hit_strength := 0.0

static func fighter_color(index: int) -> Color:
	return SEAT_COLORS[posmod(index, SEAT_COLORS.size())]

func configure(index: int) -> void:
	if _body != null and fighter_index == index:
		return
	fighter_index = index
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_eyes.clear()
	_has_position = false
	_has_pose = false
	_stretch = 1.0
	_stretch_speed = 0.0
	_jump_clock = -1.0
	_landing_clock = 1.0
	_landing_strength = 0.0
	_recoil = 0.0
	_hit_clock = 0.0
	_hit_strength = 0.0
	_deform = _pivot(self, Vector3.ZERO, "SquashAndStretch")
	_body = _pivot(_deform, Vector3.ZERO, "Body")
	var outfit := fighter_color(index)
	_left_leg = _make_leg(-1.0, index)
	_right_leg = _make_leg(1.0, index)
	if index % 2 == 0:
		_build_explorer()
	else:
		_build_ring()
	_free_arm = _pivot(_body, Vector3(-16, 27, 0), "FreeArm")
	_part(_free_arm, "sphere", Vector3(4.5, 6.5, 4.5), Vector3(0, -3, 0), outfit.darkened(0.09))
	_part(_free_arm, "sphere", Vector3(3.9, 3.9, 3.9), Vector3(0, -8.2, 1.5), Color("edbd94") if index % 2 == 0 else outfit.lightened(0.1))
	_build_weapon(outfit)
	_selection = _pivot(self, Vector3(0, 1.0, 0), "SelectedGroundRing")
	var ring := _part(_selection, "selection_ring", Vector3.ONE, Vector3.ZERO, GOLD)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection.visible = false
	_batch_static_parts(self)

func update_pose(fighter: Dictionary, aim: Vector2, selected: bool, elapsed: float, delta: float) -> void:
	if _body == null:
		return
	var safe_delta := maxf(delta, 0.0001)
	var movement := 0.0
	if _has_position:
		movement = clampf(absf(position.x - _last_position.x) / safe_delta / 78.0, 0.0, 1.0)
	_last_position = position
	_has_position = true
	var velocity: Vector2 = fighter.get("vel", Vector2.ZERO)
	var grounded: bool = fighter.get("ground", true)
	var face := float(fighter.get("face", 1.0))
	_update_deformation(fighter, grounded, velocity, elapsed, clampf(delta, 0.0, 0.1))
	_motion = lerpf(_motion, movement if grounded else 0.0, minf(1.0, safe_delta * 12.0))
	_walk_phase += safe_delta * lerpf(4.0, 13.0, _motion)
	var stride := sin(_walk_phase) * _motion
	var idle := sin(elapsed * 3.3 + fighter_index) * 0.6
	_body.position.y = idle + absf(stride) * 1.5
	_body.position.x = -face * _recoil * 1.8
	_body.rotation.z = -face * _motion * 0.07 + sin(elapsed * 2.1 + fighter_index) * 0.017 - face * _recoil * 0.085
	if _hit_clock > 0.0:
		_body.rotation.z += sin(_hit_clock * 55.0) * _hit_strength * 0.12 * (_hit_clock / 0.34)
	_left_leg.rotation.z = stride * 0.48 if grounded else -0.3
	_right_leg.rotation.z = -stride * 0.48 if grounded else 0.36
	_left_leg.position.y = 12.0 + maxf(0.0, stride) * 2.0
	_right_leg.position.y = 12.0 + maxf(0.0, -stride) * 2.0
	_body.scale.y = 1.0
	_free_arm.position.x = -face * (16.0 if fighter_index % 2 == 0 else 21.0)
	_free_arm.rotation.z = -face * (0.15 + stride * 0.35)
	if not grounded:
		_free_arm.rotation.z -= face * 0.4
	var direction := aim.normalized() if aim.length_squared() > 0.001 else Vector2(face, -0.3).normalized()
	_weapon.position = Vector3(face * (11.0 if fighter_index % 2 == 0 else 16.0), 24.5, 10.0)
	_weapon.position -= Vector3(direction.x, -direction.y, 0) * _recoil * 4.2
	_weapon.rotation.z = atan2(-direction.y, direction.x)
	# Keep the under-barrel grip on the underside when pointing left.
	_weapon.scale.y = 1.0 if direction.x >= 0.0 else -1.0
	if _scarf != null:
		_scarf.rotation.z = face * (0.13 + sin(elapsed * 6.0) * 0.07 + _motion * 0.3)
	# A blink is a tiny transform of existing meshes, never a redraw/allocation.
	var blink_time := fmod(elapsed + fighter_index * 1.7, 4.4)
	_blink = 0.14 if blink_time > 4.19 and blink_time < 4.31 else 1.0
	for eye in _eyes:
		eye.scale.y = _blink
	_selection.visible = selected and int(fighter.get("hp", 100)) > 0
	var pulse := 1.0 + sin(elapsed * 4.0) * 0.025
	_selection.scale = Vector3(pulse, 1.0, pulse)

func react_shot() -> void:
	# The renderer calls this on a confirmed shot, never while charging/aiming.
	_recoil = 1.0
	_stretch_speed = maxf(-5.0, _stretch_speed - 2.6)

func react_hit(strength: float = 1.0) -> void:
	# update_pose invokes this automatically when authoritative HP decreases.
	_hit_strength = clampf(strength, 0.2, 1.0)
	_hit_clock = 0.34
	_stretch_speed = maxf(-5.5, _stretch_speed - 3.7 * _hit_strength)

func _update_deformation(fighter: Dictionary, grounded: bool, velocity: Vector2, elapsed: float, delta: float) -> void:
	var hp := int(fighter.get("hp", 100))
	var damage := maxi(0, _previous_hp - hp) if _has_pose else 0
	if damage > 0:
		react_hit(clampf(float(damage) / 35.0, 0.3, 1.0))
	if _has_pose and grounded != _was_grounded:
		if grounded:
			_landing_clock = 0.0
			_landing_strength = clampf(absf(_last_vertical_speed) / 360.0, 0.22, 1.0)
			_stretch_speed = maxf(-5.5, _stretch_speed - 4.6 * _landing_strength)
			_jump_clock = -1.0
		elif velocity.y < -20.0 and damage == 0:
			# Anticipation is visual only: physics has already jumped this frame.
			_jump_clock = 0.0
			_stretch_speed = maxf(-4.0, _stretch_speed - 2.6)
	_previous_hp = hp
	_was_grounded = grounded
	_last_vertical_speed = velocity.y
	_has_pose = true
	var target := 1.0 + sin(elapsed * 3.3 + fighter_index) * 0.009
	if grounded:
		target += sin(_walk_phase * 2.0) * _motion * 0.032
		target -= 0.19 * _landing_strength * exp(-_landing_clock * 16.0)
	else:
		target = 1.035 + clampf(absf(velocity.y) / 1400.0, 0.0, 0.13)
		if _jump_clock >= 0.0:
			var jump_shape := lerpf(0.81, 1.20, smoothstep(0.025, 0.095, _jump_clock))
			target = lerpf(jump_shape, target, smoothstep(0.18, 0.34, _jump_clock))
	target -= _recoil * 0.04
	# Substepped, damped spring: stable at low FPS and bounded after pauses.
	# A slight overshoot gives landings a soft rebound with no persistent drift.
	var remaining := delta
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_stretch_speed += ((target - _stretch) * 285.0 - _stretch_speed * 19.5) * step
		_stretch += _stretch_speed * step
		remaining -= step
	_stretch = clampf(_stretch, 0.77, 1.24)
	if (_stretch <= 0.77 and _stretch_speed < 0.0) or (_stretch >= 1.24 and _stretch_speed > 0.0):
		_stretch_speed = 0.0
	var breadth := 1.0 / sqrt(_stretch)
	_deform.scale = Vector3(breadth, _stretch, breadth)
	# All deformation is above a feet-origin pivot; the simulation position stays exact.
	if _jump_clock >= 0.0:
		_jump_clock += delta
	_landing_clock = minf(_landing_clock + delta, 2.0)
	_recoil *= exp(-delta * 13.5)
	if _recoil < 0.0001:
		_recoil = 0.0
	_hit_clock = maxf(0.0, _hit_clock - delta)

func _build_explorer() -> void:
	# Seat-colored hiking jacket/cap, with the original skin, hair and gold scarf.
	var outfit := fighter_color(fighter_index)
	var jacket := Color("70ad98") if fighter_index == 0 else outfit.darkened(0.18)
	var backpack := Color("52695e") if fighter_index == 0 else outfit.darkened(0.48)
	var straps := Color("415d52") if fighter_index == 0 else outfit.darkened(0.58)
	var cap_button := Color("568d78") if fighter_index == 0 else outfit.darkened(0.36)
	_part(_body, "sphere", Vector3(13, 13, 8), Vector3(0, 20, 0), jacket)
	_part(_body, "box", Vector3(14, 14, 5), Vector3(0, 24, -8), backpack)
	_part(_body, "box", Vector3(1.7, 15, 1.2), Vector3(-7, 22, 7.3), straps)
	_part(_body, "box", Vector3(1.7, 15, 1.2), Vector3(7, 22, 7.3), straps)
	_part(_body, "sphere", Vector3(3.4, 4, 2.3), Vector3(-12.8, 39, 0), Color("e3ad87"))
	_part(_body, "sphere", Vector3(3.4, 4, 2.3), Vector3(12.8, 39, 0), Color("e3ad87"))
	_part(_body, "sphere", Vector3(14, 14, 10), Vector3(0, 40, 0), Color("5c4a43"))
	_part(_body, "sphere", Vector3(12.4, 12.5, 9.5), Vector3(0, 39, 2.5), Color("edbd94"))
	_part(_body, "sphere", Vector3(14.4, 8, 10.5), Vector3(0, 49.5, 0), outfit)
	_part(_body, "sphere", Vector3(17, 2.1, 11.5), Vector3(2, 48.5, 6.5), outfit.lightened(0.09))
	_part(_body, "sphere", Vector3(2, 1.2, 2), Vector3(0, 57.3, 0), cap_button)
	_part(_body, "sphere", Vector3(3.2, 2.8, 0.6), Vector3(0, 52.1, 9.7), CREAM)
	_part(_body, "box", Vector3(1.1, 2.8, 0.8), Vector3(0, 52.2, 10.2), outfit.darkened(0.35))
	_make_eye(Vector3(-4.6, 40.0, 11.2), 1.5)
	_make_eye(Vector3(5.3, 40.0, 11.2), 1.5)
	_part(_body, "sphere", Vector3(2, 2.2, 2.3), Vector3(1, 37.5, 12.2), Color("e3aa82"))
	_arc(_body, Vector3(0.7, 35.2, 11.1), 3.7, PI * 1.05, PI * 1.87, 0.55, INK, 9)
	_part(_body, "sphere", Vector3(1.6, 0.9, 0.5), Vector3(-8, 36.3, 9.8), Color("d9948b"))
	_part(_body, "sphere", Vector3(1.6, 0.9, 0.5), Vector3(8, 36.3, 9.8), Color("d9948b"))
	_part(_body, "sphere", Vector3(13.7, 3.6, 8.6), Vector3(0, 28.2, 0), GOLD)
	_scarf = _pivot(_body, Vector3(8.5, 27, 8), "ScarfTail")
	_part(_scarf, "box", Vector3(5, 10, 1.7), Vector3(0, -5, 0), GOLD)
	_part(_scarf, "box", Vector3(5, 1.2, 2), Vector3(0, -9.2, 0), Color("e3a33e"))
	_part(_body, "sphere", Vector3(2.8, 2.8, 1.4), Vector3(8, 27.2, 8.5), GOLD.lightened(0.08))

func _build_ring() -> void:
	# The hole is open: this is a TorusMesh with a circular tube, not a sprite.
	var outfit := fighter_color(fighter_index)
	var glint := Color("dcd2ff") if fighter_index == 1 else outfit.lightened(0.5)
	var ring := _part(_body, "donut", Vector3.ONE, Vector3(0, 32, 0), outfit)
	ring.rotation.x = PI * 0.5
	_make_eye(Vector3(-15.8, 32.5, 7.1), 2.0)
	_make_eye(Vector3(15.8, 32.5, 7.1), 2.0)
	_part(_body, "sphere", Vector3(3.1, 1.9, 0.55), Vector3(-18.3, 26.4, 6.6), Color("e69cb5"))
	_part(_body, "sphere", Vector3(3.1, 1.9, 0.55), Vector3(18.3, 26.4, 6.6), Color("e69cb5"))
	_arc(_body, Vector3(0, 21.5, 7.15), 5, PI * 1.05, PI * 1.95, 0.7, INK, 12)
	# A rounded pale glint follows the curved front of the upper-left ring.
	_arc(_body, Vector3(0, 32, 6.4), 17.7, PI * 0.58, PI * 0.88, 1.0, glint, 10)
	_part(_body, "sphere", Vector3(1.3, 1.3, 0.6), Vector3(-16.9, 34.5, 7.0), glint)
	_scarf = null

func _make_eye(pos: Vector3, size: float) -> void:
	var pivot := _pivot(_body, pos, "Eye")
	_part(pivot, "sphere", Vector3(size * 0.85, size * 1.15, 0.95), Vector3.ZERO, INK)
	_part(pivot, "sphere", Vector3(0.48, 0.55, 0.24), Vector3(-0.38, 0.7, 0.83), CREAM)
	_eyes.append(pivot)

func _make_leg(side: float, index: int) -> Node3D:
	var leg := _pivot(_deform, Vector3(side * 7.5, 12, 0), "LeftBoot" if side < 0 else "RightBoot")
	_part(leg, "sphere", Vector3(3.6, 5.0, 3.8), Vector3(0, -3.3, 0), Color("46405e"))
	_part(leg, "sphere", Vector3(6.3, 3.1, 6.4), Vector3(side * 1.0, -9.0, 2.0), INK)
	_part(leg, "box", Vector3(9.5, 1.4, 9), Vector3(side * 1.0, -10.8, 2.3), Color("3c384f"))
	_part(leg, "box", Vector3(4.0, 0.9, 0.6), Vector3(side * 1.0, -7.1, 7), GOLD if index % 2 == 0 else fighter_color(index))
	return leg

func _build_weapon(outfit: Color) -> void:
	_weapon = _pivot(_body, Vector3(12, 24.5, 10), "AimArmAndLauncher")
	_part(_weapon, "sphere", Vector3(5.8, 5.7, 5.4), Vector3.ZERO, outfit)
	_part(_weapon, "sphere", Vector3(7, 3.2, 3.4), Vector3(6, -1, 0), outfit.darkened(0.07))
	_part(_weapon, "box", Vector3(4.7, 7, 4.7), Vector3(14, -4.5, 0), INK)
	var barrel := _part(_weapon, "cylinder", Vector3(5, 24, 5), Vector3(17, 0.7, 0), Color("ded5bc"))
	barrel.rotation.z = PI * 0.5
	var collar := _part(_weapon, "cylinder", Vector3(5.8, 3, 5.8), Vector3(27.5, 0.7, 0), Color("626375"))
	collar.rotation.z = PI * 0.5
	var muzzle := _part(_weapon, "cylinder", Vector3(4, 0.45, 4), Vector3(29.2, 0.7, 0), INK)
	muzzle.rotation.z = PI * 0.5
	_part(_weapon, "box", Vector3(4, 2.8, 3), Vector3(22, 6.0, 0), Color("5c7c72"))
	_part(_weapon, "sphere", Vector3(3.8, 3.8, 3.8), Vector3(11.5, -3.7, 3), Color("edbd94") if fighter_index % 2 == 0 else outfit.lightened(0.07))

static func _pivot(parent: Node3D, at: Vector3, title: String) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = at
	parent.add_child(node)
	return node

static func _part(parent: Node3D, shape: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(shape)
	node.material_override = _material(color)
	node.position = at
	node.scale = size
	parent.add_child(node)
	return node

static func _mesh(shape: String) -> Mesh:
	if _meshes.has(shape):
		return _meshes[shape]
	var mesh: Mesh
	match shape:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			sphere.radial_segments = 16
			sphere.rings = 8
			mesh = sphere
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			cylinder.radial_segments = 16
			mesh = cylinder
		"donut", "selection_ring":
			var torus := TorusMesh.new()
			torus.inner_radius = 9.0 if shape == "donut" else 26.7
			torus.outer_radius = 23.0 if shape == "donut" else 28.0
			torus.rings = 40
			torus.ring_segments = 12 if shape == "donut" else 6
			mesh = torus
		_:
			mesh = BoxMesh.new()
	_meshes[shape] = mesh
	return mesh

static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.78
		material.metallic_specular = 0.28
		_materials[key] = material
	return _materials[key]

static func _arc(parent: Node3D, center: Vector3, radius: float, start: float, end: float, thickness: float, color: Color, segments: int) -> void:
	for n in range(segments):
		var angle_a := lerpf(start, end, float(n) / segments)
		var angle_b := lerpf(start, end, float(n + 1) / segments)
		var a := center + Vector3(cos(angle_a), sin(angle_a), 0) * radius
		var b := center + Vector3(cos(angle_b), sin(angle_b), 0) * radius
		var tube := _part(parent, "cylinder", Vector3(thickness, a.distance_to(b) + thickness * 0.5, thickness), (a + b) * 0.5, color)
		tube.rotation.z = atan2(-(b - a).x, (b - a).y)

static func _batch_static_parts(pivot: Node3D) -> void:
	# Batch only a pivot's direct meshes. Animated child pivots (eyes, legs, scarf,
	# arm and launcher) retain their hierarchy and all existing animation values.
	var parts: Array[MeshInstance3D] = []
	for child in pivot.get_children():
		if child is MeshInstance3D:
			parts.append(child)
		elif child is Node3D:
			_batch_static_parts(child)
	if parts.size() < 2:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var material := part.material_override as StandardMaterial3D
		if material == null:
			return
		var transform := part.transform
		# Inverse transpose is essential for the many flattened spheres/cylinders.
		var normal_transform := transform.basis.inverse().transposed()
		var mirrored := transform.basis.determinant() < 0.0
		for surface_index in range(part.mesh.get_surface_count()):
			var source := part.mesh.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
			var source_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
			var offset := vertices.size()
			for n in range(source_vertices.size()):
				vertices.append(transform * source_vertices[n])
				normals.append((normal_transform * source_normals[n]).normalized())
				colors.append(material.albedo_color)
			if source_indices.is_empty():
				for n in range(source_vertices.size()):
					source_indices.append(n)
			for n in range(0, source_indices.size(), 3):
				indices.append(offset + source_indices[n])
				indices.append(offset + source_indices[n + (2 if mirrored else 1)])
				indices.append(offset + source_indices[n + (1 if mirrored else 2)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var baked_mesh := ArrayMesh.new()
	baked_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var combined := MeshInstance3D.new()
	combined.name = "StaticGeometry"
	combined.mesh = baked_mesh
	if not _materials.has("_vertex_colors"):
		var vertex_material := StandardMaterial3D.new()
		vertex_material.albedo_color = Color.WHITE
		vertex_material.vertex_color_use_as_albedo = true
		# Our hex palette is sRGB. Compatibility uses it directly; this flag also
		# keeps the same authored palette if a native build uses Forward+/Mobile.
		vertex_material.vertex_color_is_srgb = true
		vertex_material.roughness = 0.78
		vertex_material.metallic_specular = 0.28
		_materials["_vertex_colors"] = vertex_material
	combined.material_override = _materials["_vertex_colors"]
	combined.cast_shadow = parts[0].cast_shadow
	pivot.add_child(combined)
	for part in parts:
		pivot.remove_child(part)
		part.queue_free()

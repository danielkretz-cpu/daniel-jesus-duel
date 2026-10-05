extends Node3D
## Volumetric visual rig for authoritative 2D projectiles. Local +X is forward.
const CREAM := Color("fff3db")
const GOLD := Color("f9c95e")
const INK := Color("303449")
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
var weapon := 0
var _model: Node3D
var _flame: Node3D
var _spark: Node3D

func configure(kind: int) -> void:
	# The world renderer may configure an existing slot every frame.
	if _model != null and weapon == kind:
		return
	weapon = kind
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_model = Node3D.new()
	_model.name = "ProjectileMesh"
	add_child(_model)
	_flame = null
	_spark = null
	match kind:
		0: _build_missile(false)
		1: _build_bomb()
		2, 4: _build_banana(kind == 4)
		3: _build_missile(true)

func update_pose(bullet: Dictionary, elapsed: float) -> void:
	if _model == null:
		return
	var velocity: Vector2 = bullet.get("vel", Vector2.RIGHT)
	var heading := atan2(-velocity.y, velocity.x)
	var age := float(bullet.get("age", 0.0))
	match weapon:
		0, 3:
			rotation.z = heading
			_model.rotation.x = sin(elapsed * 13.0) * 0.08
			if _flame != null:
				_flame.scale = Vector3(1.0 + sin(elapsed * 42.0) * 0.2, 0.92 + sin(elapsed * 27.0) * 0.08, 0.92 + cos(elapsed * 31.0) * 0.08)
		1:
			rotation.z = -age * 3.0
			if _spark != null:
				var flash := 0.85 + sin(elapsed * 41.0) * 0.25
				_spark.scale = Vector3.ONE * flash
		2, 4:
			rotation.z = -age * 4.0
			_model.rotation.y = sin(age * 3.1) * 0.23

func _build_missile(freedom: bool) -> void:
	var body_color := CREAM if freedom else Color("e7e7ce")
	var radius := 5.0 if freedom else 3.8
	var body := _part(_model, "cylinder", Vector3(radius, 20, radius), Vector3(-1, 0, 0), body_color)
	body.rotation.z = -PI * 0.5
	var nose := _part(_model, "cone", Vector3(radius, 10, radius), Vector3(14, 0, 0), Color("83d9fa") if freedom else GOLD)
	nose.rotation.z = -PI * 0.5
	var band := _part(_model, "cylinder", Vector3(radius + 0.25, 3, radius + 0.25), Vector3(-3, 0, 0), Color("df8d66") if freedom else Color("647b71"))
	band.rotation.z = -PI * 0.5
	var nozzle := _part(_model, "cylinder", Vector3(radius * 0.7, 3, radius * 0.7), Vector3(-12, 0, 0), INK)
	nozzle.rotation.z = -PI * 0.5
	for n in range(4):
		var fin := _part(_model, "fin", Vector3.ONE * (1.0 if freedom else 0.8), Vector3(-5, 0, 0), Color("83d9fa") if freedom else Color("91d2b0"))
		fin.rotation.x = float(n) * PI * 0.5
	_flame = Node3D.new()
	_flame.position = Vector3(-13, 0, 0)
	_model.add_child(_flame)
	var outer := _part(_flame, "cone", Vector3(radius * 0.75, 16 if freedom else 11, radius * 0.75), Vector3(-6 if freedom else -4.5, 0, 0), Color("f19b42"), true)
	outer.rotation.z = PI * 0.5
	var core := _part(_flame, "cone", Vector3(radius * 0.46, 11 if freedom else 8, radius * 0.46), Vector3(-3.7, 0, 0.25), GOLD.lightened(0.3), true)
	core.rotation.z = PI * 0.5
	if freedom:
		_part(_model, "sphere", Vector3(3.2, 2.6, 1.1), Vector3(6, 1, 4.4), Color("327c9f"))
		_part(_model, "sphere", Vector3(1.1, 0.65, 0.35), Vector3(6.5, 1.8, 5.3), CREAM)

func _build_bomb() -> void:
	_part(_model, "sphere", Vector3(10, 10, 10), Vector3.ZERO, Color("91d2b0"))
	var seam := _part(_model, "bomb_ring", Vector3.ONE, Vector3.ZERO, Color("5f9d86"))
	seam.rotation.z = 0.15
	_part(_model, "cylinder", Vector3(3, 3.5, 3), Vector3(0, 10, 0), INK)
	var fuse := _part(_model, "cylinder", Vector3(0.75, 6.5, 0.75), Vector3(1.3, 14.3, 0), CREAM)
	fuse.rotation.z = -0.37
	_spark = Node3D.new()
	_spark.position = Vector3(2.6, 17.4, 0)
	_model.add_child(_spark)
	_part(_spark, "sphere", Vector3(2, 2, 2), Vector3.ZERO, GOLD, true)
	for n in range(3):
		var ember := _part(_spark, "box", Vector3(0.9, 7, 0.9), Vector3.ZERO, GOLD.lightened(0.25), true)
		ember.rotation.z = float(n) * PI / 3.0
	_part(_model, "sphere", Vector3(2.9, 1.7, 0.6), Vector3(-3.5, 4.8, 8.2), Color("caead5"))

func _build_banana(fragment: bool) -> void:
	_part(_model, "banana", Vector3.ONE, Vector3.ZERO, GOLD)
	for side in [-1.0, 1.0]:
		var tip := Vector3(sin(1.13) * 13.0 * side, cos(1.13) * 13.0 - 8.0, 0)
		_part(_model, "sphere", Vector3(1.15, 1.5, 1.15), tip, Color("75502e"))
	if fragment:
		_model.scale = Vector3.ONE * 0.59

static func _part(parent: Node3D, shape: String, size: Vector3, at: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(shape)
	node.material_override = _material(color, glow)
	node.position = at
	node.scale = size
	if glow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _material(color: Color, glow: bool) -> StandardMaterial3D:
	var key := color.to_html() + ("_glow" if glow else "")
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.55
		material.metallic_specular = 0.35
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if glow:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.65
		_materials[key] = material
	return _materials[key]

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
		"cylinder", "cone":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if shape == "cone" else 1.0
			cylinder.bottom_radius = 1.0
			cylinder.height = 1.0
			cylinder.radial_segments = 16
			mesh = cylinder
		"bomb_ring":
			var torus := TorusMesh.new()
			torus.inner_radius = 9.55
			torus.outer_radius = 10.25
			torus.rings = 24
			torus.ring_segments = 6
			mesh = torus
		"banana": mesh = _banana_mesh()
		"fin": mesh = _fin_mesh()
		_: mesh = BoxMesh.new()
	_meshes[shape] = mesh
	return mesh

static func _banana_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const LENGTH_STEPS := 18
	const SIDES := 10
	for n in range(LENGTH_STEPS + 1):
		var fraction := float(n) / LENGTH_STEPS
		var angle := lerpf(-1.13, 1.13, fraction)
		var center := Vector3(sin(angle) * 13.0, cos(angle) * 13.0 - 8.0, 0)
		var normal := Vector3(sin(angle), cos(angle), 0)
		var radius := 0.7 + pow(sin(fraction * PI), 0.7) * 3.2
		for side in range(SIDES):
			var theta := float(side) * TAU / SIDES
			var radial := normal * cos(theta) + Vector3(0, 0, sin(theta))
			vertices.append(center + radial * radius)
			normals.append(radial)
	for n in range(LENGTH_STEPS):
		for side in range(SIDES):
			var a := n * SIDES + side
			var b := n * SIDES + (side + 1) % SIDES
			var c := (n + 1) * SIDES + side
			var d := (n + 1) * SIDES + (side + 1) % SIDES
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _fin_mesh() -> ArrayMesh:
	var a := Vector3(-5, 2, -0.65)
	var b := Vector3(-5, 10, -0.65)
	var c := Vector3(4, 2, -0.65)
	var d := a + Vector3(0, 0, 1.3)
	var e := b + Vector3(0, 0, 1.3)
	var f := c + Vector3(0, 0, 1.3)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [a, b, c, d, f, e, a, d, b, b, d, e, b, e, c, c, e, f, c, f, a, a, f, d]:
		surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

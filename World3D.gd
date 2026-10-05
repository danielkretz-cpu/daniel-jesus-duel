extends Node
## Presentation only. Gameplay, aiming, collision and network state stay in Game.gd.
const TerrainScript = preload("res://Terrain3D.gd")
const ProjectionMath = preload("res://Projection3D.gd")
const WIDTH := 1280.0
const HEIGHT := 470.0
const PITCH := ProjectionMath.PITCH
const COS_PITCH := ProjectionMath.COS_PITCH
const SIN_PITCH := ProjectionMath.SIN_PITCH
const FX_CAP := 96

var viewport: SubViewport
var scene: Node3D
var camera: Camera3D
var terrain_view
var scenery
var environment: Environment
var actors: Array = []
var bullets: Array = []
var water: MeshInstance3D
var water_material: StandardMaterial3D
var waves: Array[MeshInstance3D] = []
var effects: MultiMeshInstance3D
var last_map := -1
var last_terrain: Image
var last_craters := -1
var last_shots := 0
var render_size := Vector2i(1280, 470)

static func world_point(p: Vector2, depth: float = 0.0) -> Vector3:
	# With this camera, projecting any point returns exactly the simulation's XY.
	return ProjectionMath.point(p, depth)

static func game_point(p: Vector3) -> Vector2:
	return ProjectionMath.project(p)

func initialize(game) -> void:
	viewport = SubViewport.new()
	viewport.name = "Actual3DViewport"
	viewport.size = render_size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.gui_disable_input = true
	add_child(viewport)
	scene = Node3D.new()
	scene.name = "Diorama"
	viewport.add_child(scene)
	camera = Camera3D.new()
	camera.name = "FixedSideViewCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = HEIGHT
	camera.near = 1
	camera.far = 3200
	scene.add_child(camera)
	var focus := world_point(Vector2(WIDTH * 0.5, HEIGHT * 0.5))
	camera.position = focus + ProjectionMath.camera_offset() * 1500.0
	camera.look_at(focus)
	camera.current = true
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9c4e1")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	scene.add_child(world_environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-42, -28, 0)
	sunlight.light_color = Color("fff0da")
	sunlight.light_energy = 1.0
	sunlight.shadow_enabled = false
	scene.add_child(sunlight)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 145, 0)
	fill.light_color = Color("bab7ef")
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	scene.add_child(fill)
	terrain_view = TerrainScript.new()
	scene.add_child(terrain_view)
	scenery = load("res://Environment3D.gd").new()
	scene.add_child(scenery)
	for i in range(2):
		var actor = load("res://Fighter3D.gd").new()
		scene.add_child(actor)
		actor.configure(i)
		actors.append(actor)
	for i in range(6):
		var bullet = load("res://Projectile3D.gd").new()
		scene.add_child(bullet)
		bullet.visible = false
		bullets.append(bullet)
	_make_water()
	_make_effects()
	sync(game, 0.0)

func _make_water() -> void:
	water_material = StandardMaterial3D.new()
	water_material.roughness = 0.45
	water_material.metallic = 0.12
	water = MeshInstance3D.new()
	var shape := QuadMesh.new()
	shape.size = Vector2(WIDTH + 80, 58.0)
	water.mesh = shape
	water.material_override = water_material
	var right := world_point(Vector2.RIGHT) - world_point(Vector2.ZERO)
	var up := world_point(Vector2.UP) - world_point(Vector2.ZERO)
	water.transform = Transform3D(Basis(right, up, Vector3.BACK), world_point(Vector2(640, 471), 64))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(water)
	# Thin solid highlights, not a full-screen transparent water effect.
	for i in range(18):
		var line := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(24 + (i % 4) * 9, 1.4, 2.5)
		line.mesh = bar
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.material_override = mat
		scene.add_child(line)
		waves.append(line)

func _make_effects() -> void:
	effects = MultiMeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 5
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = FX_CAP
	multi.visible_instance_count = 0
	effects.multimesh = multi
	effects.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(effects)

func get_texture() -> ViewportTexture:
	return viewport.get_texture()

func resize_for_scale(scale_factor: float) -> void:
	# Keep the exact 128:47 aspect; lower fill cost on phones without camera drift.
	var multiplier := clampi(int(ceil(scale_factor * 10.0)), 5, 10)
	var desired := Vector2i(128 * multiplier, 47 * multiplier)
	if desired != render_size:
		render_size = desired
		viewport.size = render_size

func terrain_changed(image: Image, texture: ImageTexture) -> void:
	last_terrain = image
	terrain_view.configure(image, texture)

func carve_changed(point: Vector2, radius: float) -> void:
	terrain_view.mark_dirty(Rect2i(Vector2i((point - Vector2.ONE * (radius + 4)).floor()), Vector2i.ONE * int(ceil((radius + 4) * 2))))

func sync(game, delta: float) -> void:
	if viewport == null:
		return
	while actors.size() < game.fighters.size():
		var actor = load("res://Fighter3D.gd").new()
		scene.add_child(actor)
		actor.configure(actors.size())
		actors.append(actor)
	while actors.size() > game.fighters.size():
		var actor = actors.pop_back()
		scene.remove_child(actor)
		actor.queue_free()
	if game.terrain != last_terrain:
		terrain_changed(game.terrain, game.terrain_texture)
	if last_map != game.map_id:
		last_map = game.map_id
		scenery.configure(last_map)
		environment.background_color = scenery.sky_color(last_map)
		environment.ambient_light_color = scenery.ambient_color(last_map)
		water_material.albedo_color = game.MapThemes.water_color(last_map)
		for wave in waves:
			wave.material_override.albedo_color = game.MapThemes.wave_color(last_map)
	terrain_view.flush()
	scenery.animate(game.elapsed, delta)
	resize_for_scale(game.ui_scale)
	for i in range(game.fighters.size()):
		var fighter: Dictionary = game.fighters[i]
		var actor = actors[i]
		actor.visible = fighter.hp > 0 and fighter.pos.y < game.WATER + 8
		actor.position = world_point(fighter.pos, 40)
		actor.scale = Vector3.ONE * (1.12 if game.portrait else 1.0)
		var selected: bool = game.active == i and game.phase == "aim"
		var aim: Vector2 = game._direction() if selected else Vector2(fighter.face, -0.25).normalized()
		actor.update_pose(fighter, ProjectionMath.direction(aim), selected, game.elapsed, delta)
	if game.shots > last_shots and game.active < actors.size():
		actors[game.active].react_shot()
	last_shots = game.shots
	var active_bullets: Array = []
	if not game.projectile.is_empty():
		active_bullets.append(game.projectile)
	active_bullets.append_array(game.fragments)
	for i in range(bullets.size()):
		var model = bullets[i]
		model.visible = i < active_bullets.size()
		if model.visible:
			var bullet: Dictionary = active_bullets[i]
			model.configure(int(bullet.weapon))
			model.position = world_point(bullet.pos, 30)
			model.update_pose(bullet, game.elapsed)
			if int(bullet.weapon) in [0, 3]:
				var direction := ProjectionMath.direction(bullet.vel)
				model.rotation.z = atan2(-direction.y, direction.x)
	var count := mini(game.particles.size(), FX_CAP)
	effects.multimesh.visible_instance_count = count
	for i in range(count):
		var part: Dictionary = game.particles[i]
		var size: float = part.size * clampf(part.life / part.max * 2, 0.05, 1)
		var basis := Basis.from_scale(Vector3.ONE * size)
		effects.multimesh.set_instance_transform(i, Transform3D(basis, world_point(part.pos, 34 + i % 7)))
		effects.multimesh.set_instance_color(i, part.color)
	for i in range(waves.size()):
		var x := fmod(i * 97.0 + game.elapsed * 8, WIDTH)
		waves[i].position = world_point(Vector2(x, 444 + (i % 4) * 5 + sin(game.elapsed * 2 + i) * 1.2), 80)

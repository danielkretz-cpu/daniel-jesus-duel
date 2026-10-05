extends Node3D
## A genuinely extruded mesh of the authoritative pixel mask, including tunnels.
## Greedy rectangles retain every collision pixel. Only blast-touched chunks rebuild.
const WIDTH := 1280
const HEIGHT := 470
const CHUNK := 128
const DEPTH := 180.0
const ProjectionMath = preload("res://Projection3D.gd")
const FACET_X := 64.0
const FACET_Y := 48.0

var source: Image
var chunks: Dictionary = {}
var dirty: Dictionary = {}
var front_material: StandardMaterial3D
var side_material: StandardMaterial3D
var rebuild_count := 0
var last_rebuilt_chunks := 0
var rectangle_count := 0
var _bytes := PackedByteArray()
var _mask_bytes := PackedByteArray()
var _mask_columns := PackedByteArray()
var _mask_bounds := Rect2i()
var _depth_x := PackedFloat64Array()
var _depth_y := PackedFloat64Array()

func configure(image: Image, texture: ImageTexture) -> void:
	source = image
	if front_material == null:
		front_material = StandardMaterial3D.new()
		front_material.roughness = 0.92
		front_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		front_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		side_material = StandardMaterial3D.new()
		side_material.vertex_color_use_as_albedo = true
		side_material.roughness = 0.95
		side_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	front_material.albedo_texture = texture
	mark_dirty(Rect2i(0, 0, WIDTH, HEIGHT))

func mark_dirty(region: Rect2i) -> void:
	var rect := region.grow(1).intersection(Rect2i(0, 0, WIDTH, HEIGHT))
	if not rect.has_area():
		return
	for cy in range(rect.position.y / CHUNK, (rect.end.y - 1) / CHUNK + 1):
		for cx in range(rect.position.x / CHUNK, (rect.end.x - 1) / CHUNK + 1):
			dirty[Vector2i(cx, cy)] = true

func flush() -> void:
	last_rebuilt_chunks = 0
	if dirty.is_empty() or source == null:
		return
	if _depth_x.is_empty():
		_prepare_depths()
	# One byte copy per burst, never a terrain scan during ordinary animation.
	_bytes = source.get_data()
	for key in dirty:
		_rebuild_chunk(key)
		last_rebuilt_chunks += 1
		rebuild_count += 1
	dirty.clear()

func solid_pixel(x: int, y: int) -> bool:
	return x >= 0 and x < WIDTH and y >= 0 and y < HEIGHT and _bytes[(y * WIDTH + x) * 4 + 3] > 127

static func front_point(p: Vector2, depth: float = 0.0) -> Vector3:
	var surface_depth := front_depth(p)
	var position := ProjectionMath.point(p, surface_depth)
	position.z += depth
	return position

static func front_depth(p: Vector2) -> float:
	# Piecewise planar cliff facets. Adjacent cells share identical edge geometry.
	var cell_x := floorf(p.x / FACET_X)
	var cell_y := floorf(p.y / FACET_Y)
	var x_wave := lerpf(sin(cell_x * 1.9), sin((cell_x + 1) * 1.9), fposmod(p.x, FACET_X) / FACET_X)
	var y_wave := lerpf(cos(cell_y * 2.3), cos((cell_y + 1) * 2.3), fposmod(p.y, FACET_Y) / FACET_Y)
	return x_wave * 14.0 + y_wave * 9.0

func _prepare_depths() -> void:
	# Every terrain vertex is on an integer pixel/facet boundary. Cache the
	# separable facet waves once instead of repeating four trig calls per vertex.
	_depth_x.resize(WIDTH + 1)
	_depth_y.resize(HEIGHT + 1)
	for x in range(WIDTH + 1):
		var cell := floorf(x / FACET_X)
		_depth_x[x] = lerpf(sin(cell * 1.9), sin((cell + 1) * 1.9), fposmod(x, FACET_X) / FACET_X) * 14.0
	for y in range(HEIGHT + 1):
		var cell := floorf(y / FACET_Y)
		_depth_y[y] = lerpf(cos(cell * 2.3), cos((cell + 1) * 2.3), fposmod(y, FACET_Y) / FACET_Y) * 9.0

func _cached_front_point(p: Vector2) -> Vector3:
	return ProjectionMath.point(p, _depth_x[int(p.x)] + _depth_y[int(p.y)])

func _rectangles(rect: Rect2i) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	if not rect.has_area():
		return result
	var previous: Dictionary = {}
	for local_y in range(rect.size.y):
		var row_start := (rect.position.y + local_y - _mask_bounds.position.y) * _mask_bounds.size.x + rect.position.x - _mask_bounds.position.x
		var row := _mask_bytes.slice(row_start, row_start + rect.size.x)
		var current: Dictionary = {}
		var x := row.find(255)
		while x != -1:
			var end := row.find(0, x)
			if end == -1:
				end = rect.size.x
			var key := Vector2i(rect.position.x + x, rect.position.x + end)
			if previous.has(key):
				var index: int = previous[key]
				var old := result[index]
				old.size.y += 1
				result[index] = old
				current[key] = index
			else:
				current[key] = result.size()
				result.append(Rect2i(key.x, rect.position.y + local_y, end - x, 1))
			x = row.find(255, end)
		previous = current
	return result

# Typed mesh buffers avoid repeated dynamic Dictionary lookups while appending.
class SurfaceData:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

func _surface() -> SurfaceData:
	return SurfaceData.new()

func _quad(surface: SurfaceData, points: Array[Vector3], normal: Vector3, uv: Array[Vector2], color: Color = Color.WHITE) -> void:
	var start: int = surface.vertices.size()
	surface.vertices.append_array(PackedVector3Array(points))
	surface.normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	surface.uv.append_array(PackedVector2Array(uv))
	surface.colors.append_array(PackedColorArray([color, color, color, color]))
	surface.indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

func _add_surface(mesh: ArrayMesh, data: SurfaceData, material: Material) -> void:
	if data.vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)

func _wall(surface: SurfaceData, a: Vector2, b: Vector2, normal: Vector3, color: Color) -> void:
	# Split at the same global facet grid as the front face, retaining watertight
	# front edges even on very long flat platforms and the inner walls of holes.
	var distance := a.distance_to(b)
	if distance < 0.001:
		return
	var direction := (b - a) / distance
	var current := a
	while current.distance_to(b) > 0.001:
		var next := b
		if absf(direction.x) > 0.1:
			next.x = minf(b.x, (floorf(current.x / FACET_X) + 1.0) * FACET_X)
		else:
			next.y = minf(b.y, (floorf(current.y / FACET_Y) + 1.0) * FACET_Y)
		var fa := _cached_front_point(current)
		var fb := _cached_front_point(next)
		var ba := fa + Vector3(0, 0, -DEPTH)
		var face_normal := (fb - fa).cross(ba - fa).normalized()
		if face_normal.dot(normal) < 0:
			face_normal = -face_normal
		# Smooth the lighting across one-pixel stair edges without smoothing away
		# any collision pixels. Deep top surfaces must not become zebra stripes.
		var midpoint := (current + next) * 0.5
		var gradient := Vector2.ZERO
		var mx := int(midpoint.x) - _mask_bounds.position.x
		var my := int(midpoint.y) - _mask_bounds.position.y
		var stride := _mask_bounds.size.x
		var left := (my - 3) * stride + mx - 3
		var top := left
		for offset in range(7):
			gradient.x += float(int(_mask_bytes[left] > 0) - int(_mask_bytes[left + 6] > 0))
			gradient.y += float(int(_mask_bytes[top] > 0) - int(_mask_bytes[top + stride * 6] > 0))
			left += stride
			top += 1
		if gradient.length_squared() > 0.1:
			face_normal = Vector3(gradient.x, -gradient.y, 0).normalized()
		_quad(surface, [fa, fb, fb + Vector3(0, 0, -DEPTH), ba], face_normal, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], color)
		current = next

func _edge_color(x: int, y: int, top: bool) -> Color:
	var index := (y * WIDTH + x) * 4
	var color := Color8(_bytes[index], _bytes[index + 1], _bytes[index + 2])
	return color.lightened(0.12)

func _prepare_mask(rect: Rect2i) -> void:
	# Four transparent border pixels allow exact, branch-free wall lighting at
	# world edges as well as across chunk boundaries. Threshold and transpose
	# natively so both horizontal and vertical runs can use PackedByteArray.find.
	_mask_bounds = rect.grow(4)
	var clipped := _mask_bounds.intersection(Rect2i(0, 0, WIDTH, HEIGHT))
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(source.get_region(clipped), 0.5)
	var mask := Image.create(_mask_bounds.size.x, _mask_bounds.size.y, false, Image.FORMAT_L8)
	mask.blit_rect(bitmap.convert_to_image(), Rect2i(Vector2i.ZERO, clipped.size), clipped.position - _mask_bounds.position)
	_mask_bytes = mask.get_data()
	mask.rotate_90(COUNTERCLOCKWISE)
	_mask_columns = mask.get_data()

func _rebuild_chunk(key: Vector2i) -> void:
	var rect := Rect2i(key * CHUNK, Vector2i(CHUNK, CHUNK)).intersection(Rect2i(0, 0, WIDTH, HEIGHT))
	var front := _surface()
	var walls := _surface()
	var occupied := source.get_region(rect).get_used_rect()
	var scan_rect := Rect2i(rect.position + occupied.position, occupied.size)
	if scan_rect.has_area():
		_prepare_mask(rect)
	var rectangles := _rectangles(scan_rect)
	for r in rectangles:
		var y := float(r.position.y)
		while y < r.end.y:
			var bottom := minf(r.end.y, (floorf(y / FACET_Y) + 1.0) * FACET_Y)
			var x := float(r.position.x)
			while x < r.end.x:
				var right := minf(r.end.x, (floorf(x / FACET_X) + 1.0) * FACET_X)
				var points: Array[Vector2] = [Vector2(x, y), Vector2(right, y), Vector2(right, bottom), Vector2(x, bottom)]
				var vertices: Array[Vector3] = []
				var uv: Array[Vector2] = []
				for p in points:
					vertices.append(_cached_front_point(p))
					uv.append(p / Vector2(WIDTH, HEIGHT))
				var normal := -(vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
				_quad(front, vertices, normal, uv)
				x = right
			y = bottom
	# Only rectangle perimeters can be exterior edges. Search complete empty
	# neighbour runs natively instead of walking every pixel in GDScript.
	for r in rectangles:
		for sign_y in [-1, 1]:
			var y: int = r.position.y if sign_y == -1 else r.end.y - 1
			var row_start: int = (y + sign_y - _mask_bounds.position.y) * _mask_bounds.size.x + r.position.x - _mask_bounds.position.x
			var row := _mask_bytes.slice(row_start, row_start + r.size.x)
			var x := row.find(0)
			while x != -1:
				var end := row.find(255, x)
				if end == -1:
					end = r.size.x
				var edge_y := y if sign_y == -1 else y + 1
				var start: int = r.position.x + x
				_wall(walls, Vector2(start, edge_y), Vector2(r.position.x + end, edge_y), Vector3(0, -sign_y, 0), _edge_color(start, y, sign_y == -1))
				x = row.find(0, end)
		for sign_x in [-1, 1]:
			var x: int = r.position.x if sign_x == -1 else r.end.x - 1
			var column_start: int = (_mask_bounds.end.x - 1 - x - sign_x) * _mask_bounds.size.y + r.position.y - _mask_bounds.position.y
			var column := _mask_columns.slice(column_start, column_start + r.size.y)
			var y := column.find(0)
			while y != -1:
				var end := column.find(255, y)
				if end == -1:
					end = r.size.y
				var edge_x := x if sign_x == -1 else x + 1
				var start: int = r.position.y + y
				_wall(walls, Vector2(edge_x, start), Vector2(edge_x, r.position.y + end), Vector3(sign_x, 0, 0), _edge_color(x, start, false))
				y = column.find(0, end)
	var instance: MeshInstance3D
	if chunks.has(key):
		instance = chunks[key]
	else:
		instance = MeshInstance3D.new()
		instance.name = "Terrain_%d_%d" % [key.x, key.y]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunks[key] = instance
		add_child(instance)
	var mesh := ArrayMesh.new()
	_add_surface(mesh, front, front_material)
	_add_surface(mesh, walls, side_material)
	instance.mesh = mesh if mesh.get_surface_count() else null
	instance.set_meta("rectangles", rectangles)
	instance.set_meta("bounds", rect)

func mesh_covers_pixel(pixel: Vector2i) -> bool:
	# Test the actual greedy mesh rectangles independently of the source bitmap.
	var key := Vector2i(pixel.x / CHUNK, pixel.y / CHUNK)
	if not chunks.has(key):
		return false
	for rect in chunks[key].get_meta("rectangles", []):
		if rect.has_point(pixel):
			return true
	return false

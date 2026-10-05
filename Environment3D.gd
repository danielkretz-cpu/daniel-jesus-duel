extends Node3D
## Original, low-poly scenic dioramas for the five arenas.
## Static solids are merged into two vertex-coloured meshes (lit / luminous).
## No textures, external assets, lights, collisions, game RNG, or water ownership.
## All screen-space placements share the arena's fixed orthographic projection.

const ProjectionMath = preload("res://Projection3D.gd")
const SKY := [Color("d9a1ac"), Color("a2beb1"), Color("d79588"), Color("292e50"), Color("563d58")]
const HORIZON := [Color("efc5a0"), Color("d5d2ae"), Color("f4c598"), Color("927090"), Color("bd736c")]
const AMBIENT := [Color("b6b2d0"), Color("a4c6b8"), Color("e8b69e"), Color("8b96c7"), Color("c69ba7")]

var map_id := -1
var mesh_count := 0
var triangle_count := 0
var _lit: SurfaceTool
var _glow: SurfaceTool
var _motions: Array[Dictionary] = []
var _cache: Dictionary = {}
var _lit_material: StandardMaterial3D
var _glow_material: StandardMaterial3D

static func sky_color(id: int) -> Color:
	return SKY[clampi(id, 0, 4)]

static func ambient_color(id: int) -> Color:
	return AMBIENT[clampi(id, 0, 4)]

static func point(p: Vector2, depth: float) -> Vector3:
	return ProjectionMath.point(p, depth - 120.0)

func configure(id: int) -> void:
	map_id = clampi(id, 0, 4)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_motions.clear()
	mesh_count = 0
	triangle_count = 0
	_lit = SurfaceTool.new()
	_lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow = SurfaceTool.new()
	_glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	_lit_material = _material(false)
	_glow_material = _material(true)
	_sky_backdrop()
	match map_id:
		0: _archipelago()
		1: _jungle()
		2: _desert()
		3: _city()
		4: _citadel()
	_commit(_lit, _lit_material, "ScenerySolids")
	_commit(_glow, _glow_material, "SceneryLuminous")
	_lit = null
	_glow = null

func animate(elapsed: float, _delta: float = 0.0) -> void:
	for motion in _motions:
		var node: Node3D = motion.node
		var phase: float = elapsed * float(motion.speed) + float(motion.phase)
		if motion.mode == "rise":
			var offset := fposmod(elapsed * float(motion.speed) + float(motion.phase), 1.0)
			node.position = motion.origin + Vector3(sin(phase * 2.0) * 8.0, offset * 150.0, 0.0)
		else:
			node.position = motion.origin + motion.travel * sin(phase)

func _material(luminous: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	# Back faces can appear when looking across a thin leaf or pennant.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if luminous:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _commit(surface: SurfaceTool, material: Material, label: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	mesh_count += 1
	return instance

func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color, luminous := false) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.length_squared() < 0.1:
		return
	var surface: SurfaceTool = _glow if luminous else _lit
	surface.set_color(color)
	surface.set_normal(normal)
	# Godot's front faces use clockwise winding; normals stay outward.
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(b)
	triangle_count += 1

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, luminous := false) -> void:
	_tri(a, b, c, color, luminous)
	_tri(a, c, d, color, luminous)

func _sky_backdrop() -> void:
	# Sky only: a single opaque vertex-colour quad, behind all solid scenery.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var positions := [Vector2(-250, -250), Vector2(1530, -250), Vector2(1530, 750), Vector2(-250, 750)]
	for index in [0, 2, 1, 0, 3, 2]:
		surface.set_normal(Vector3.FORWARD)
		surface.set_color(SKY[map_id] if index < 2 else HORIZON[map_id])
		surface.add_vertex(point(positions[index], -1100.0))
	_commit(surface, _glow_material, "SkyGradient")
	triangle_count += 2

func _box(center: Vector3, size: Vector3, color: Color, luminous := false, rotation_y := 0.0) -> void:
	var h := size * 0.5
	var basis := Basis(Vector3.UP, rotation_y)
	var v: Array[Vector3] = []
	for p in [Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)]:
		v.append(center + basis * p)
	for f in [[4,5,6,7],[1,0,3,2],[0,4,7,3],[5,1,2,6],[7,6,2,3],[0,1,5,4]]:
		_quad(v[f[0]],v[f[1]],v[f[2]],v[f[3]],color,luminous)

func _ellipsoid(center: Vector3, size: Vector3, color: Color, luminous := false, segments := 12, rings := 6) -> void:
	for j in range(rings):
		var lat0 := -PI * 0.5 + PI * float(j) / float(rings)
		var lat1 := -PI * 0.5 + PI * float(j + 1) / float(rings)
		for i in range(segments):
			var lon0 := TAU * float(i) / float(segments)
			var lon1 := TAU * float(i + 1) / float(segments)
			var a := center + Vector3(cos(lat0)*cos(lon0),sin(lat0),cos(lat0)*sin(lon0)) * size
			var b := center + Vector3(cos(lat0)*cos(lon1),sin(lat0),cos(lat0)*sin(lon1)) * size
			var c := center + Vector3(cos(lat1)*cos(lon1),sin(lat1),cos(lat1)*sin(lon1)) * size
			var d := center + Vector3(cos(lat1)*cos(lon0),sin(lat1),cos(lat1)*sin(lon0)) * size
			_quad(a,d,c,b,color,luminous)

func _cone(center: Vector3, bottom: float, top: float, height: float, color: Color, segments := 8, luminous := false) -> void:
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var b := TAU * float(i + 1) / float(segments)
		var low_a := center + Vector3(cos(a)*bottom,-height*0.5,sin(a)*bottom)
		var low_b := center + Vector3(cos(b)*bottom,-height*0.5,sin(b)*bottom)
		var high_a := center + Vector3(cos(a)*top,height*0.5,sin(a)*top)
		var high_b := center + Vector3(cos(b)*top,height*0.5,sin(b)*top)
		_quad(low_a,high_a,high_b,low_b,color,luminous)
		if top > 0.0:
			_tri(center + Vector3.UP * height * 0.5,high_b,high_a,color,luminous)
		_tri(center - Vector3.UP * height * 0.5,low_a,low_b,color,luminous)

func _beam(a: Vector3, b: Vector3, radius: float, color: Color, luminous := false, segments := 6) -> void:
	var direction := (b - a).normalized()
	var tangent := direction.cross(Vector3.FORWARD).normalized()
	if tangent.length_squared() < 0.1:
		tangent = direction.cross(Vector3.UP).normalized()
	var bitangent := direction.cross(tangent).normalized()
	for n in range(segments):
		var a0 := TAU * float(n) / float(segments)
		var a1 := TAU * float(n + 1) / float(segments)
		var p0 := (tangent*cos(a0)+bitangent*sin(a0))*radius
		var p1 := (tangent*cos(a1)+bitangent*sin(a1))*radius
		_quad(a+p0,a+p1,b+p1,b+p0,color,luminous)
		_tri(a,a+p1,a+p0,color,luminous)
		_tri(b,b+p0,b+p1,color,luminous)

func _ridge(profile: Array[Vector2], depth: float, spread: float, color: Color, base_y := 435.0) -> void:
	# Triangulated mountain slopes, with a genuine rear face and broad depth.
	for n in range(profile.size() - 1):
		var a := point(profile[n],depth)
		var b := point(profile[n+1],depth)
		var fa := point(Vector2(profile[n].x,base_y),depth+spread)
		var fb := point(Vector2(profile[n+1].x,base_y),depth+spread)
		var ba := point(Vector2(profile[n].x,base_y),depth-spread)
		var bb := point(Vector2(profile[n+1].x,base_y),depth-spread)
		var shade := color.lightened(0.055) if n % 2 == 0 else color.darkened(0.035)
		_tri(fa,fb,a,shade)
		_tri(fb,b,a,color)
		_quad(a,b,bb,ba,color.darkened(0.06))

func _cloud(screen: Vector2, scale_value: float, depth: float, color: Color, phase: float) -> void:
	_begin_motion()
	for n in range(4):
		_ellipsoid(Vector3((n-1.5)*27.0, sin(n*2.4)*6.0, (n%2)*9.0)*scale_value,Vector3(29,13+(n%2)*8,18)*scale_value,color,false,10,4)
	_end_motion("Cloud",point(screen,depth),Vector3(12,0,0),0.06,phase)

func _begin_motion() -> void:
	_cache["lit_parent"] = _lit
	_cache["glow_parent"] = _glow
	_lit = SurfaceTool.new()
	_lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow = SurfaceTool.new()
	_glow.begin(Mesh.PRIMITIVE_TRIANGLES)

func _end_motion(label: String, origin: Vector3, travel: Vector3, speed: float, phase: float, luminous_only := false) -> void:
	var mesh := _commit(_glow if luminous_only else _lit,_glow_material if luminous_only else _lit_material,label)
	mesh.position = origin
	_motions.append({"node":mesh,"origin":origin,"travel":travel,"speed":speed,"phase":phase,"mode":"sway"})
	_lit = _cache["lit_parent"]
	_glow = _cache["glow_parent"]

func _archipelago() -> void:
	_ellipsoid(point(Vector2(624,128),-860),Vector3(86,86,65),Color("ffe1a0"),true,32,14)
	_ridge([Vector2(-120,345),Vector2(52,273),Vector2(161,307),Vector2(306,207),Vector2(465,314),Vector2(622,265),Vector2(769,318),Vector2(940,226),Vector2(1088,287),Vector2(1230,230),Vector2(1400,331)],-660,105,Color("ba96a6"))
	_ridge([Vector2(-120,383),Vector2(85,321),Vector2(253,354),Vector2(442,300),Vector2(603,365),Vector2(779,310),Vector2(919,329),Vector2(1056,280),Vector2(1221,332),Vector2(1400,307)],-435,85,Color("8f879d"))
	# Small wooded islands and a warm lantern above the right-hand headland.
	for n in range(11):
		var x := 22.0 + n * 121.0
		var y := 323.0 + sin(n * 1.71) * 19.0
		var base := point(Vector2(x,y),-360-float(n%3)*12.0)
		_ellipsoid(base+Vector3(0,-24,0),Vector3(71,32,47),Color("777b89"),false,9,4)
		_pine(base + Vector3(18,5,-3),26.0+float(n%4)*7.0,Color("576a75"))
		if n%2==0: _pine(base+Vector3(-21,0,7),25.0,Color("626f7c"))
	var base := point(Vector2(971,290),-300)
	_ellipsoid(base-Vector3(0,15,0),Vector3(74,29,55),Color("757482"),false,9,4)
	_cone(base+Vector3(0,51,0),18,11,102,Color("f1d3ac"),8)
	_cone(base+Vector3(0,33,0),16,15,13,Color("b97379"),8)
	_cone(base+Vector3(0,73,0),13,12,12,Color("b97379"),8)
	_cone(base+Vector3(0,105,0),18,18,6,Color("535b70"),8)
	_cone(base+Vector3(0,117,0),13,13,18,Color("ffe1a0"),8,true)
	for x in [-11,11]:
		_box(base+Vector3(x,117,10),Vector3(2.5,22,2.5),Color("51576b"))
	_cone(base+Vector3(0,133,0),20,0,17,Color("53556c"),8)
	_box(base+Vector3(0,10,17),Vector3(7,19,2),Color("5f6577"))
	_box(base+Vector3(0,57,14),Vector3(5,10,2),Color("66748c"))
	_cloud(Vector2(154,85),1.08,-750,Color("f3c8ba"),1.4)
	_cloud(Vector2(1041,74),0.75,-770,Color("f3c8ba"),4.0)
	for n in range(4):
		var p := point(Vector2(355+n*37,126+sin(n*2.0)*14),-530)
		_beam(p,p+Vector3(-8,3,-2),1.0,Color("947789"))
		_beam(p,p+Vector3(8,3,-2),1.0,Color("947789"))

func _pine(base: Vector3, height: float, color: Color) -> void:
	_cone(base+Vector3(0,height*0.32,0),2,1,height*0.64,Color("6f6973"),5)
	_cone(base+Vector3(0,height*0.54,0),height*0.28,0,height*0.74,color,6)
	_cone(base+Vector3(0,height*0.80,0),height*0.20,0,height*0.62,color.lightened(0.05),6)

func _jungle() -> void:
	_ellipsoid(point(Vector2(600,103),-860),Vector3(66,66,46),Color("e9ddb0"),true,28,12)
	_ridge([Vector2(-100,332),Vector2(117,214),Vector2(242,272),Vector2(354,178),Vector2(496,300),Vector2(635,226),Vector2(771,287),Vector2(917,196),Vector2(1076,290),Vector2(1245,196),Vector2(1400,316)],-670,110,Color("8ea99b"))
	_ridge([Vector2(-100,370),Vector2(133,307),Vector2(312,354),Vector2(435,285),Vector2(582,360),Vector2(729,333),Vector2(879,293),Vector2(1040,342),Vector2(1173,292),Vector2(1410,371)],-390,65,Color("668d7e"))
	# A gentle, long-necked herbivore model, behind the near foliage.
	var p := point(Vector2(718,281),-430)
	var skin := Color("688e7e")
	_ellipsoid(p,Vector3(67,27,28),skin,false,12,6)
	_beam(p+Vector3(38,9,0),p+Vector3(66,39,-2),16,skin)
	_beam(p+Vector3(66,39,-2),p+Vector3(76,100,-3),11,skin)
	_ellipsoid(p+Vector3(82,108,-3),Vector3(22,13,12),skin,false,10,5)
	_ellipsoid(p+Vector3(96,110,7),Vector3(1.5,1.5,1.5),Color("dce3b9"),true,6,3)
	_beam(p-Vector3(40,0,0),p+Vector3(-103,16,-5),11,skin)
	_beam(p+Vector3(-100,16,-5),p+Vector3(-143,38,-8),4,skin)
	for leg in [Vector3(-39,-13,-14),Vector3(-29,-13,18),Vector3(34,-13,-14),Vector3(46,-13,16)]:
		_beam(p+leg,p+leg+Vector3(-5,-57,0),8,skin.darkened(0.025))
		_ellipsoid(p+leg+Vector3(0,-59,3),Vector3(12,5,10),skin,false,8,4)
	for spec in [Vector3(67,325,169),Vector3(260,342,104),Vector3(1067,328,110),Vector3(1229,327,171)]:
		_palm(point(Vector2(spec.x,spec.y),-220),spec.z,Color("467765"))
	for n in range(13):
		var base := point(Vector2(-15+n*111,334+sin(n*2.1)*15),-270)
		_ellipsoid(base,Vector3(38,24,28),Color("507e65"),false,8,4)
		_ellipsoid(base+Vector3(21,9,-12),Vector3(27,23,21),Color("72965f"),false,8,4)
	for n in range(3):
		_begin_motion()
		var bird := Color("6a9184")
		_tri(Vector3(-29,5,-5),Vector3(0,0,4),Vector3(-7,-5,9),bird)
		_tri(Vector3(29,5,-5),Vector3(7,-5,9),Vector3(0,0,4),bird)
		_ellipsoid(Vector3.ZERO,Vector3(4,3,11),bird,false,6,4)
		_end_motion("FlyingReptile",point(Vector2(339+n*83,108+(n%2)*28),-525),Vector3(11,4,0),0.34,n*1.3)
	_cloud(Vector2(481,228),1.65,-510,Color("b9c8ad"),2.0)

func _palm(base: Vector3, height: float, leaf_color: Color) -> void:
	var top := base + Vector3(12,height,0)
	_beam(base,base+Vector3(7,height*0.55,-2),6.0,Color("687a62"),false,7)
	_beam(base+Vector3(7,height*0.55,-2),top,4.5,Color("8a9467"),false,7)
	_ellipsoid(top,Vector3(9,8,9),Color("627854"),false,8,4)
	for n in range(7):
		var angle := TAU*float(n)/7.0
		var direction := Vector3(cos(angle),0,sin(angle))
		var cross_direction := Vector3(-sin(angle),0,cos(angle))
		var middle := top+direction*30+Vector3.UP*19
		var tip := top+direction*(54.0+float(n%2)*12.0)-Vector3.UP*9
		_tri(top,middle+cross_direction*11,middle+Vector3.UP*3,leaf_color)
		_tri(top,middle+Vector3.UP*3,middle-cross_direction*11,leaf_color.lightened(0.08))
		_tri(middle+cross_direction*11,tip,middle+Vector3.UP*3,leaf_color)
		_tri(middle-cross_direction*11,middle+Vector3.UP*3,tip,leaf_color.lightened(0.08))

func _desert() -> void:
	_ellipsoid(point(Vector2(540,100),-890),Vector3(60,60,44),Color("ffe6ab"),true,28,12)
	_ellipsoid(point(Vector2(693,149),-850),Vector3(37,37,28),Color("f6c6b0"),true,24,10)
	_ridge([Vector2(-120,380),Vector2(100,307),Vector2(257,347),Vector2(416,300),Vector2(563,367),Vector2(754,312),Vector2(907,340),Vector2(1094,287),Vector2(1400,360)],-660,100,Color("bb8b8c"))
	_mesa(point(Vector2(183,342),-485),Vector3(112,149,95),Color("b5827b"))
	_mesa(point(Vector2(365,350),-500),Vector3(91,112,76),Color("b5827b"))
	_mesa(point(Vector2(1110,347),-490),Vector3(127,153,109),Color("b5827b"))
	_mesa(point(Vector2(1320,361),-525),Vector3(102,184,80),Color("b5827b"))
	_ridge([Vector2(-100,390),Vector2(106,347),Vector2(260,326),Vector2(424,367),Vector2(592,391),Vector2(793,333),Vector2(936,357),Vector2(1092,327),Vector2(1390,381)],-335,80,Color("cf9a80"))
	# Dusty domed frontier outpost, with visible roofs, doors and connecting pipes.
	for n in range(4):
		var p := point(Vector2(812+n*65,310+(n%2)*14),-265)
		var radius := 23.0-float(n)*2.0
		_cone(p+Vector3(0,15,0),radius,radius,30,Color("e3b294"),10)
		_ellipsoid(p+Vector3(0,30,0),Vector3(radius,radius*0.72,radius),Color("efc3a1"),false,12,6)
		_box(p+Vector3(0,8,radius),Vector3(9,18,2),Color("906f75"))
		_box(p+Vector3(11,18,radius-2),Vector3(5,5,3),Color("f6d3a5"),true)
		if n<3: _beam(p+Vector3(18,4,-9),p+Vector3(52,4,-9),4,Color("c19081"))
	var antenna := point(Vector2(854,285),-290)
	_beam(antenna,antenna+Vector3(0,60,0),2,Color("94737a"))
	_beam(antenna+Vector3(-12,46,0),antenna+Vector3(12,46,0),1.4,Color("94737a"))
	_ellipsoid(antenna+Vector3(0,62,0),Vector3(3,3,3),Color("ffd6ab"),true,8,4)
	_begin_motion()
	var ship_color := Color("866d7e")
	_ellipsoid(Vector3.ZERO,Vector3(23,8,12),ship_color,false,8,4)
	_tri(Vector3(-51,7,-16),Vector3(-9,0,12),Vector3(-3,7,-7),ship_color)
	_tri(Vector3(49,7,-16),Vector3(3,7,-7),Vector3(9,0,12),ship_color)
	_box(Vector3(0,6,8),Vector3(13,4,5),Color("cbb9aa"))
	_end_motion("SurveyShip",point(Vector2(938,105),-460),Vector3(24,2,0),0.13,0.0)
	for n in range(7):
		var p := point(Vector2(36+n*211,348+(n%2)*15),-190)
		_ellipsoid(p,Vector3(19,9,15),Color("bd8976"),false,7,4)

func _mesa(base: Vector3, size: Vector3, color: Color) -> void:
	# Tapered strata make the mesas three-dimensional rather than flat cut-outs.
	_cone(base+Vector3(0,size.y*0.27,0),size.x*0.75,size.x*0.46,size.y*0.54,color,6)
	_cone(base+Vector3(0,size.y*0.62,0),size.x*0.46,size.x*0.41,size.y*0.16,color.lightened(0.11),6)
	_cone(base+Vector3(0,size.y*0.83,0),size.x*0.41,size.x*0.36,size.y*0.26,color,6)
	_cone(base+Vector3(0,size.y*0.97,0),size.x*0.39,size.x*0.37,size.y*0.04,color.lightened(0.17),6)

func _city() -> void:
	_ellipsoid(point(Vector2(701,98),-880),Vector3(51,51,40),Color("9686a4"),true,28,12)
	_ellipsoid(point(Vector2(718,91),-810),Vector3(44,44,34),Color("494563"),true,28,12)
	_ring(point(Vector2(701,98),-760),76,2.2,Color("bba4c3"),true,32,0.30)
	for n in range(34):
		_ellipsoid(point(Vector2(20+(n*173)%1240,20+(n*41)%146),-910),Vector3.ONE*(1.0+float(n%3)*0.3),Color("bfb2ca"),true,5,3)
	# Two physical skyline layers: distant shapes and detailed near towers.
	for n in range(20):
		var x := -30.0+n*70.0
		var h := 52.0+float((n*73)%116)
		_box(point(Vector2(x,302-h*0.5),-660),Vector3(50,h/ProjectionMath.COS_PITCH,58),Color("65607e"),false,0.08)
	for n in range(13):
		var x := -12.0+n*107.0
		var h := 126.0+float((n*59)%136)
		var depth := -350.0-float(n%3)*32.0
		var base := point(Vector2(x,353),depth)
		var color := Color("494a68") if n%2==0 else Color("555172")
		_box(base+Vector3(0,h*0.5,0),Vector3(73,h,62),color,false,0.06)
		_box(base+Vector3(0,h+5,-3),Vector3(59,10,49),color.lightened(0.08),false,0.06)
		# Windows are batched solid luminous geometry, not individual nodes.
		for row in range(7):
			for col in range(3):
				if (row*5+col*3+n)%4==0: continue
				var y := 24.0+row*27.0
				if y>h-14.0: continue
				_box(base+Vector3(-21+col*21,y,32),Vector3(9,3.4,1.5),Color("8fb7c6") if n%2==0 else Color("bd8eba"),true)
		if n%3==1:
			_box(base+Vector3(32,h*0.58,34),Vector3(5,58,2),Color("d19ec3"),true)
			_beam(base+Vector3(0,h+10,0),base+Vector3(0,h+38,0),1.6,Color("8b829d"))
			_ellipsoid(base+Vector3(0,h+40,0),Vector3(2.5,2.5,2.5),Color("f3bfd5"),true,6,3)
	var rail_a := point(Vector2(292,184),-220)
	var rail_b := point(Vector2(853,138),-220)
	_beam(rail_a,rail_b,3,Color("9c8bad"))
	_beam(rail_a-Vector3(0,5,0),rail_b-Vector3(0,5,0),1,Color("b4e1e0"),true)
	_begin_motion()
	_box(Vector3.ZERO,Vector3(64,15,25),Color("a78dab"))
	_box(Vector3(2,4,14),Vector3(44,5,1),Color("a1dfdf"))
	_box(Vector3(-24,-7,0),Vector3(6,5,18),Color("5c5778"))
	_box(Vector3(24,-7,0),Vector3(6,5,18),Color("5c5778"))
	_end_motion("SkyTram",rail_a.lerp(rail_b,0.47)-Vector3(0,16,0),Vector3(132,11.2,0),0.12,0.0)

func _ring(center: Vector3, radius: float, thickness: float, color: Color, luminous: bool, segments := 32, tilt := 0.0) -> void:
	var basis := Basis(Vector3.FORWARD,tilt)
	for n in range(segments):
		var a := TAU*float(n)/float(segments)
		var b := TAU*float(n+1)/float(segments)
		var p0 := center+basis*Vector3(cos(a)*radius,sin(a)*radius*0.38,sin(a)*radius*0.35)
		var p1 := center+basis*Vector3(cos(b)*radius,sin(b)*radius*0.38,sin(b)*radius*0.35)
		_beam(p0,p1,thickness,color,luminous,4)

func _citadel() -> void:
	_ellipsoid(point(Vector2(326,96),-890),Vector3(64,64,45),Color("d8967d"),true,28,12)
	_ellipsoid(point(Vector2(341,84),-810),Vector3(58,58,38),Color("65445e"),true,28,12)
	_ridge([Vector2(-100,340),Vector2(72,224),Vector2(163,294),Vector2(270,176),Vector2(398,310),Vector2(516,234),Vector2(683,314),Vector2(818,205),Vector2(950,292),Vector2(1061,186),Vector2(1198,282),Vector2(1380,226)],-660,105,Color("986574"))
	_ridge([Vector2(-100,380),Vector2(104,306),Vector2(239,363),Vector2(387,265),Vector2(546,334),Vector2(647,240),Vector2(789,331),Vector2(930,270),Vector2(1086,350),Vector2(1247,307),Vector2(1400,371)],-460,85,Color("704c64"))
	# Truncated volcano with an open, hot crater and physical smoke lobes.
	var volcano := point(Vector2(1117,367),-410)
	_cone(volcano+Vector3(0,91,0),153,39,182,Color("805060"),9)
	_cone(volcano+Vector3(0,182,0),40,34,9,Color("d2876b"),9)
	_cone(volcano+Vector3(0,185,0),31,29,3,Color("ffcb81"),9,true)
	_beam(volcano+Vector3(20,170,21),volcano+Vector3(52,112,62),4,Color("e99b6b"),true)
	_beam(volcano+Vector3(52,112,62),volcano+Vector3(76,66,86),3,Color("e99b6b"),true)
	for n in range(4):
		_ellipsoid(volcano+Vector3(10+n*17,202+n*22,-10-n*4),Vector3(20+n*4,15+n*3,18+n*4),Color("99707d"),false,9,5)
	var base := point(Vector2(629,328),-320)
	_cone(base-Vector3(0,11,0),161,123,59,Color("655065"),8)
	_box(base+Vector3(0,49,0),Vector3(238,98,77),Color("55445c"))
	_box(base+Vector3(0,103,0),Vector3(246,13,83),Color("75556d"))
	for n in range(11):
		_box(base+Vector3(-117+n*23.4,119,30),Vector3(13,22,21),Color("695066"))
	for spec in [Vector3(-127,128,34),Vector3(-76,173,34),Vector3(0,208,43),Vector3(76,164,34),Vector3(129,120,31)]:
		_tower(base+Vector3(spec.x,0,-float(int(spec.x)%3)*3.0),spec.y,spec.z)
	# Inset luminous gate and a solid lava channel running out of the rock.
	_box(base+Vector3(0,28,40),Vector3(37,56,2),Color("d28c70"),true)
	_cone(base+Vector3(0,58,40),22,0,25,Color("d28c70"),5,true)
	_box(base+Vector3(0,26,43),Vector3(23,50,2),Color("81566a"))
	for n in range(4):
		_box(base+Vector3(-14+n*9,30,44),Vector3(2,51,2),Color("60495e"))
	_beam(base+Vector3(0,-1,54),base+Vector3(11,-35,105),8,Color("e8a275"),true)
	for n in range(17):
		_begin_motion()
		_ellipsoid(Vector3.ZERO,Vector3.ONE*(1.0+float(n%3)*0.4),Color("ffc591"),true,5,3)
		_end_motion("Ember",point(Vector2(43+(n*173)%1190,337),-180-float(n%3)*50),Vector3.ZERO,0.028+float(n%4)*0.005,float(n)*0.061,true)
		_motions[-1].mode = "rise"

func _tower(base: Vector3, height: float, width: float) -> void:
	var stone := Color("625069")
	_cone(base+Vector3(0,height*0.5,0),width*0.55,width*0.46,height,stone,8)
	_cone(base+Vector3(0,height-5,0),width*0.62,width*0.62,12,Color("806077"),8)
	_cone(base+Vector3(0,height+23,0),width*0.65,0,49,Color("513f59"),8)
	_box(base+Vector3(0,height-33,width*0.48),Vector3(6,23,2),Color("e5ab82"),true)
	_beam(base+Vector3(0,height+44,0),base+Vector3(0,height+62,0),1.0,Color("8f687c"))
	_tri(base+Vector3(0,height+61,0),base+Vector3(0,height+50,0),base+Vector3(18,height+55,0),Color("ad657b"))

extends RefCounted
## Five original, asset-free worlds. Draw backgrounds before the terrain bitmap.
## New terrain profiles use integer interpolation so host and guest agree exactly.
const WIDTH := 1280
const HEIGHT := 470
const WATER := 442
const TITLES := ["Skymningsskäret", "Urtidsdjungeln", "Dubbelsolens öken", "Neonmetropolen", "Eldcitadellet"]
const SUBTITLES := ["Skärgårdsduell", "Dinosaurieäventyr", "Rymdvästern", "Digital action", "Mörk fantasy"]
const JUNGLE: Array[Vector2i] = [Vector2i(0, 388), Vector2i(70, 344), Vector2i(138, 320), Vector2i(184, 310), Vector2i(266, 310), Vector2i(356, 347), Vector2i(438, 302), Vector2i(520, 346), Vector2i(610, 377), Vector2i(670, 377), Vector2i(760, 346), Vector2i(842, 302), Vector2i(924, 347), Vector2i(1014, 310), Vector2i(1096, 310), Vector2i(1142, 320), Vector2i(1210, 344), Vector2i(1279, 388)]
const DESERT: Array[Vector2i] = [Vector2i(0, 386), Vector2i(96, 352), Vector2i(184, 326), Vector2i(280, 326), Vector2i(366, 370), Vector2i(438, 390), Vector2i(480, 380), Vector2i(640, 254), Vector2i(800, 380), Vector2i(842, 390), Vector2i(914, 370), Vector2i(1000, 326), Vector2i(1096, 326), Vector2i(1184, 352), Vector2i(1279, 386)]
# Each roof is wide enough to stand on. Individual steps stay within jump range.
const CITY: Array[Vector2i] = [Vector2i(0, 400), Vector2i(80, 372), Vector2i(136, 342), Vector2i(184, 310), Vector2i(282, 338), Vector2i(350, 366), Vector2i(418, 394), Vector2i(486, 364), Vector2i(536, 334), Vector2i(580, 304), Vector2i(614, 276), Vector2i(666, 304), Vector2i(700, 334), Vector2i(744, 364), Vector2i(794, 394), Vector2i(862, 366), Vector2i(930, 338), Vector2i(998, 310), Vector2i(1096, 342), Vector2i(1144, 372), Vector2i(1200, 400)]
const VOLCANO: Array[Vector2i] = [Vector2i(0, 384), Vector2i(92, 344), Vector2i(184, 318), Vector2i(280, 318), Vector2i(340, 300), Vector2i(400, 274), Vector2i(480, 332), Vector2i(560, 382), Vector2i(620, 404), Vector2i(660, 404), Vector2i(720, 382), Vector2i(800, 332), Vector2i(880, 274), Vector2i(940, 300), Vector2i(1000, 318), Vector2i(1096, 318), Vector2i(1188, 344), Vector2i(1279, 384)]

static func count() -> int:
	return 5

static func title(id: int) -> String:
	return TITLES[clampi(id, 0, count() - 1)]

static func subtitle(id: int) -> String:
	return SUBTITLES[clampi(id, 0, count() - 1)]

static func surface_y(id: int, x: int) -> int:
	x = clampi(x, 0, WIDTH - 1)
	match id:
		1:
			return _interpolate(JUNGLE, x)
		2:
			return _interpolate(DESERT, x)
		3:
			for n in range(CITY.size() - 1, -1, -1):
				if x >= CITY[n].x:
					return CITY[n].y
		4:
			return _interpolate(VOLCANO, x)
	# Keep the original island, including its exact launch-pad boundaries.
	var surface := int(310 + 42 * sin(float(x) / 121.0) + 23 * cos(float(x) / 63.0) - 26 * sin(float(x) / 290.0))
	if abs(x - 224) < 33:
		surface = 307
	if abs(x - 1050) < 33:
		surface = 325
	return surface

@warning_ignore("integer_division")
static func _interpolate(profile: Array[Vector2i], x: int) -> int:
	for n in range(1, profile.size()):
		if x <= profile[n].x:
			var a := profile[n - 1]
			var b := profile[n]
			return a.y + ((x - a.x) * (b.y - a.y)) / (b.x - a.x)
	return profile[-1].y

static func spawn_points(id: int) -> Array[Vector2]:
	return [Vector2(224, surface_y(id, 224)), Vector2(1050, surface_y(id, 1050))]

static func terrain_color(id: int, x: int, y: int, surface: int) -> Color:
	var d := y - surface
	match id:
		1:
			if d < 5: return Color("c7dc81")
			if d < 13: return Color("798b57")
			if d < 23: return Color("596749")
			if y % 43 < 2: return Color("586253")
			if (x * 23 + y * 53) % 191 < 3: return Color("889278")
			return Color("384644")
		2:
			if d < 6: return Color("ffe1a1")
			if d < 16: return Color("dba971")
			if d < 28: return Color("b87c62")
			if (y + x / 9) % 39 < 3: return Color("bf886d")
			if (x * 23 + y * 53) % 197 < 3: return Color("e1b087")
			return Color("945f61")
		3:
			if d < 3: return Color("83f0db")
			if d < 9: return Color("397887")
			if d < 17: return Color("504b70")
			if y % 48 < 2: return Color("49496b")
			if x % 48 < 2: return Color("394664")
			if x % 48 > 16 and x % 48 < 25 and y % 48 > 20 and y % 48 < 29:
				return Color("6c8191") if (x + y) % 3 == 0 else Color("51677a")
			return Color("292c48")
		4:
			if d < 4: return Color("f3ae74")
			if d < 11: return Color("a45a53")
			if d < 22: return Color("734552")
			if (y + x / 5) % 51 < 2: return Color("775060")
			if (x * 23 + y * 53) % 197 < 3: return Color("bd705b")
			return Color("3b3044")
	# Original island colors and texture rules are preserved byte-for-byte.
	if d < 5: return Color("f5d07e")
	if d < 14: return Color("bf9b7d")
	if d < 22: return Color("906d6b")
	if y % 44 < 2: return Color("6c4765")
	if (x * 23 + y * 53) % 191 < 3: return Color("865c75")
	return Color("45364f")

static func water_color(id: int) -> Color:
	match id:
		1: return Color("305d62")
		2: return Color("7a5268")
		3: return Color("303756")
		4: return Color("b44349")
	return Color("426d7a")

static func wave_color(id: int) -> Color:
	match id:
		1: return Color("99c3a2")
		2: return Color("d8a08e")
		3: return Color("8be8dd")
		4: return Color("ffcb76")
	return Color("94bfba")

static func accent_color(id: int) -> Color:
	match id:
		1: return Color("c7dc81")
		2: return Color("ffe1a1")
		3: return Color("83f0db")
		4: return Color("ffb174")
	return Color("f9c95e")

static func draw_background(canvas: CanvasItem, id: int, elapsed: float) -> void:
	match id:
		1: _draw_jungle(canvas, elapsed)
		2: _draw_desert(canvas, elapsed)
		3: _draw_city(canvas, elapsed)
		4: _draw_volcano(canvas, elapsed)
		_: _draw_island(canvas, elapsed)

static func _sky(c: CanvasItem, top: Color, bottom: Color) -> void:
	# A fixed 16 strips, never a pixel-by-pixel per-frame gradient.
	for n in range(16):
		c.draw_rect(Rect2(0, n * 29.375, WIDTH, 30.375), top.lerp(bottom, float(n) / 15.0))

static func _ellipse(c: CanvasItem, p: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for n in range(20):
		points.append(p + Vector2(cos(n * TAU / 20), sin(n * TAU / 20)) * radius)
	c.draw_colored_polygon(points, color)

static func _draw_island(c: CanvasItem, elapsed: float) -> void:
	c.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color("eab0a1"))
	for n in range(12):
		c.draw_rect(Rect2(0, n * 39.2, WIDTH, 40), Color("ebc3ab").lerp(Color("bc8d9e"), float(n) / 14))
	c.draw_circle(Vector2(642, 154), 91, Color("f6d898"))
	c.draw_circle(Vector2(642, 154), 71, Color("f9e0a7"))
	for cloud in [[Vector2(139, 73), 1.0], [Vector2(904, 105), 0.75], [Vector2(1160, 50), 0.58]]:
		var cp: Vector2 = cloud[0] + Vector2(sin(elapsed * 0.06 + cloud[0].x) * 8, 0)
		for n in range(4):
			c.draw_circle(cp + Vector2(n * 32 * cloud[1], sin(n * 2.0) * 8), 22 * cloud[1], Color("f0cbbb"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 305), Vector2(75, 225), Vector2(182, 268), Vector2(292, 163), Vector2(430, 297), Vector2(546, 237), Vector2(671, 311), Vector2(822, 193), Vector2(950, 274), Vector2(1108, 183), Vector2(1280, 279), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("a58c9e"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 355), Vector2(158, 308), Vector2(308, 341), Vector2(483, 279), Vector2(692, 337), Vector2(891, 282), Vector2(1104, 350), Vector2(1280, 301), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("8c7a94"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(855, 238), Vector2(871, 238), Vector2(867, 199), Vector2(859, 199)]), Color("ead3b7"))
	c.draw_rect(Rect2(856, 192, 15, 9), Color("535165"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(853, 192), Vector2(863, 184), Vector2(873, 192)]), Color("535165"))
	for n in range(4):
		var bp := Vector2(434 + n * 37, 103 + sin(n * 3.3) * 19)
		c.draw_polyline(PackedVector2Array([bp + Vector2(-6, -3), bp, bp + Vector2(6, -3)]), Color("9c7787"), 2, true)

static func _draw_jungle(c: CanvasItem, elapsed: float) -> void:
	_sky(c, Color("b9c6aa"), Color("6e9690"))
	c.draw_circle(Vector2(610, 108), 64, Color("d3d7a4"))
	c.draw_circle(Vector2(610, 108), 48, Color("e4ddac"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 302), Vector2(100, 194), Vector2(195, 245), Vector2(322, 155), Vector2(430, 279), Vector2(540, 212), Vector2(641, 277), Vector2(735, 186), Vector2(875, 262), Vector2(1010, 173), Vector2(1132, 260), Vector2(1280, 186), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("8aa49a"))
	# Mist threads make the dinosaur read as a distant silhouette.
	_ellipse(c, Vector2(465, 224), Vector2(194, 13), Color("afbbb0"))
	_ellipse(c, Vector2(891, 204), Vector2(157, 9), Color("afbbb0"))
	var dinosaur := Color("6d8c83")
	_ellipse(c, Vector2(695, 282), Vector2(70, 29), dinosaur)
	c.draw_colored_polygon(PackedVector2Array([Vector2(645, 268), Vector2(590, 263), Vector2(542, 237), Vector2(580, 277), Vector2(648, 293)]), dinosaur)
	c.draw_colored_polygon(PackedVector2Array([Vector2(727, 272), Vector2(758, 245), Vector2(770, 187), Vector2(779, 170), Vector2(801, 166), Vector2(815, 174), Vector2(814, 183), Vector2(794, 186), Vector2(790, 228), Vector2(779, 276), Vector2(748, 298)]), dinosaur)
	for x in [656, 681, 722, 744]:
		c.draw_line(Vector2(x, 292), Vector2(x - 4, 336), dinosaur, 11, true)
		c.draw_line(Vector2(x - 4, 336), Vector2(x + 7, 336), dinosaur, 7, true)
	c.draw_circle(Vector2(801, 173), 1.8, Color("bed0b6"))
	# Flying reptiles, drawn as simple original wing silhouettes.
	for n in range(3):
		var p := Vector2(392 + n * 67, 107 + (n % 2) * 28 + sin(elapsed * 0.6 + n) * 3)
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(-23, -8), p + Vector2(-7, -5), p + Vector2(0, 1), p + Vector2(12, -9), p + Vector2(28, -11), p + Vector2(10, 1), p + Vector2(4, 6), p + Vector2(-5, 5)]), Color("78968b"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 352), Vector2(116, 301), Vector2(275, 344), Vector2(428, 281), Vector2(560, 354), Vector2(723, 349), Vector2(867, 291), Vector2(1021, 330), Vector2(1137, 289), Vector2(1280, 326), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("5b8077"))
	_palm(c, Vector2(82, 326), 175, Color("527b70"))
	_palm(c, Vector2(1186, 315), 168, Color("527b70"))
	_palm(c, Vector2(344, 320), 102, Color("60887a"))
	_palm(c, Vector2(977, 304), 113, Color("60887a"))
	for n in range(7):
		var p := Vector2(42 + n * 198, 317 + (n % 3) * 13)
		for side in [-1, 1]:
			c.draw_colored_polygon(PackedVector2Array([p, p + Vector2(side * 38, -41), p + Vector2(side * 18, -13), p + Vector2(side * 46, -20), p + Vector2(side * 22, -2)]), Color("628a76"))

static func _palm(c: CanvasItem, base: Vector2, height: float, color: Color) -> void:
	var top := base + Vector2(11, -height)
	c.draw_colored_polygon(PackedVector2Array([base + Vector2(-8, 0), top + Vector2(-4, 0), top + Vector2(4, 0), base + Vector2(7, 0)]), color)
	for side in [-1, 1]:
		for n in range(3):
			var tip := top + Vector2(side * (57 - n * 10), -23 + n * 22)
			c.draw_colored_polygon(PackedVector2Array([top, top + Vector2(side * 24, -22 + n * 15), tip, top + Vector2(side * 23, -2 + n * 14)]), color)

static func _draw_desert(c: CanvasItem, elapsed: float) -> void:
	_sky(c, Color("d99590"), Color("e8bb94"))
	c.draw_circle(Vector2(536, 96), 58, Color("f0c59d"))
	c.draw_circle(Vector2(536, 96), 47, Color("ffe4ae"))
	c.draw_circle(Vector2(682, 143), 37, Color("d58e92"))
	c.draw_circle(Vector2(682, 143), 29, Color("f6c8ad"))
	# Wind-carved mesas and a little domed outpost, all behind the playable dunes.
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 322), Vector2(63, 280), Vector2(128, 281), Vector2(150, 190), Vector2(209, 190), Vector2(240, 265), Vector2(339, 267), Vector2(377, 229), Vector2(414, 228), Vector2(474, 312), Vector2(1280, 342), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("bb8d87"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 370), Vector2(331, 311), Vector2(600, 359), Vector2(810, 279), Vector2(921, 300), Vector2(999, 211), Vector2(1078, 212), Vector2(1102, 275), Vector2(1203, 272), Vector2(1241, 188), Vector2(1280, 188), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("b07d7b"))
	for n in range(4):
		var x := 864 + n * 54
		var y := 292 + (n % 2) * 8
		c.draw_circle(Vector2(x, y), 24 - n * 2, Color("ce9e8c"))
		c.draw_rect(Rect2(x - 24 + n * 2, y, 48 - n * 4, 35), Color("ce9e8c"))
		c.draw_rect(Rect2(x - 3, y + 5, 7, 17), Color("aa7675"))
	c.draw_line(Vector2(889, 269), Vector2(889, 231), Color("ac7b79"), 3)
	c.draw_line(Vector2(878, 243), Vector2(900, 243), Color("ac7b79"), 2)
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 382), Vector2(120, 318), Vector2(240, 299), Vector2(386, 337), Vector2(560, 386), Vector2(771, 348), Vector2(968, 349), Vector2(1105, 305), Vector2(1280, 358), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("c6927c"))
	# Original crescent-wing survey ship; a quiet drift high above the battlefield.
	var p := Vector2(928 + sin(elapsed * 0.13) * 14, 94)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-39, -11), p + Vector2(-8, -4), p + Vector2(7, -12), p + Vector2(31, -8), p + Vector2(18, 0), p + Vector2(8, 4), p + Vector2(-16, 8), p + Vector2(-7, 1)]), Color("996f79"))
	c.draw_line(p + Vector2(-24, 3), p + Vector2(-14, 3), Color("ffddb1"), 2)
	for n in range(5):
		c.draw_line(Vector2(56 + n * 213, 282 + (n % 2) * 43), Vector2(124 + n * 213, 282 + (n % 2) * 43), Color("d6a18a"), 2)

static func _draw_city(c: CanvasItem, elapsed: float) -> void:
	_sky(c, Color("252c4c"), Color("756182"))
	for n in range(22):
		c.draw_circle(Vector2(36 + (n * 137) % 1200, 18 + (n * 37) % 140), 1.1 if n % 3 else 1.8, Color("a79bb7"))
	# A distant orbital ring, with deliberately low contrast behind trajectories.
	c.draw_circle(Vector2(720, 107), 56, Color("827291"))
	c.draw_circle(Vector2(730, 101), 46, Color("3c3858"))
	c.draw_arc(Vector2(720, 107), 70, 0.35, 3.4, 36, Color("ac90b0"), 2, true)
	c.draw_line(Vector2(20, 278), Vector2(1260, 278), Color("877a9d"), 2)
	for x in range(-320, 1601, 160):
		c.draw_line(Vector2(640, 238), Vector2(x, HEIGHT), Color("675d83"), 1)
	for y in [292, 315, 349, 395, 457]:
		c.draw_line(Vector2(0, y), Vector2(WIDTH, y), Color("75678c"), 1)
	# 13 skyline blocks, at most 6 windows each; no full-screen pixel loops.
	for n in range(13):
		var x := n * 105 - 18
		var h := 79 + (n * 47) % 127
		var y := 328 - h
		var fill := Color("424764") if n % 2 == 0 else Color("4d4b69")
		c.draw_rect(Rect2(x, y, 76, h + 100), fill)
		c.draw_rect(Rect2(x + 8, y - 9, 58, 10), fill)
		c.draw_line(Vector2(x + 4, y + 4), Vector2(x + 4, 328), Color("6a6987"), 2)
		if n % 3 == 0:
			c.draw_line(Vector2(x + 36, y), Vector2(x + 36, y - 27), Color("70708e"), 2)
			c.draw_circle(Vector2(x + 36, y - 27), 2, Color("c6a5c2"))
		for w in range(6):
			var wy := y + 22 + w * 22
			if wy < 325:
				c.draw_rect(Rect2(x + 17 + (w % 2) * 22, wy, 19, 3), Color("80929d") if n % 2 else Color("a883ac"))
		if n % 4 == 1:
			c.draw_rect(Rect2(x + 49, y + 17, 7, 46), Color("9b77a6"))
	# A sky tram on a fine beam, behind all fighters and destructible rooftops.
	c.draw_line(Vector2(53, 192), Vector2(478, 141), Color("77738f"), 2)
	var p := Vector2(387 + sin(elapsed * 0.16) * 25, 159)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-29, 0), p + Vector2(-17, -9), p + Vector2(23, -9), p + Vector2(31, -3), p + Vector2(22, 5), p + Vector2(-20, 5)]), Color("9c87b0"))
	c.draw_line(p + Vector2(-13, -5), p + Vector2(17, -5), Color("9bd0d0"), 3)
	c.draw_rect(Rect2(0, 342, WIDTH, 128), Color("3b3e5c"))

static func _draw_volcano(c: CanvasItem, elapsed: float) -> void:
	_sky(c, Color("48384f"), Color("b86c68"))
	c.draw_circle(Vector2(640, 98), 73, Color("774956"))
	c.draw_circle(Vector2(640, 98), 57, Color("ce876c"))
	c.draw_circle(Vector2(647, 89), 50, Color("49374e"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 293), Vector2(76, 204), Vector2(124, 244), Vector2(231, 138), Vector2(280, 218), Vector2(364, 186), Vector2(450, 284), Vector2(582, 213), Vector2(682, 280), Vector2(797, 171), Vector2(907, 251), Vector2(1008, 155), Vector2(1084, 239), Vector2(1190, 199), Vector2(1280, 289), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("855866"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 370), Vector2(101, 285), Vector2(238, 337), Vector2(370, 229), Vector2(492, 322), Vector2(548, 260), Vector2(640, 220), Vector2(732, 260), Vector2(788, 322), Vector2(920, 229), Vector2(1042, 337), Vector2(1179, 285), Vector2(1280, 370), Vector2(1280, HEIGHT), Vector2(0, HEIGHT)]), Color("654556"))
	# Original black-stone citadel, unmistakable but non-interactive background art.
	var stone := Color("584152")
	c.draw_rect(Rect2(526, 221, 228, 99), stone)
	for tower in [Vector3(517, 188, 42), Vector3(582, 158, 38), Vector3(629, 136, 43), Vector3(699, 170, 39), Vector3(747, 200, 34)]:
		var x: float = tower.x
		var y: float = tower.y
		var w: float = tower.z
		c.draw_rect(Rect2(x, y, w, 330 - y), stone)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y), Vector2(x + w * 0.5, y - 28), Vector2(x + w + 5, y)]), stone)
		c.draw_rect(Rect2(x + w * 0.5 - 3, y + 21, 6, 21), Color("c88b70"))
		c.draw_line(Vector2(x + 4, y + 8), Vector2(x + 4, 296), Color("775361"), 2)
	for n in range(9):
		c.draw_rect(Rect2(522 + n * 28, 213, 14, 15), stone)
	c.draw_circle(Vector2(640, 281), 19, Color("b57261"))
	c.draw_rect(Rect2(621, 281, 38, 49), Color("b57261"))
	c.draw_rect(Rect2(628, 286, 24, 44), Color("d49973"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(627, 327), Vector2(645, 327), Vector2(660, 360), Vector2(635, 396), Vector2(650, 432), Vector2(610, 432), Vector2(620, 392), Vector2(641, 359)]), Color("c07a61"))
	c.draw_polyline(PackedVector2Array([Vector2(638, 330), Vector2(650, 359), Vector2(626, 393), Vector2(629, 429)]), Color("e2a572"), 4, true)
	for n in range(16):
		var p := Vector2(49 + (n * 157) % 1180, 26 + fposmod(n * 31.0 - elapsed * (2 + n % 3), 265))
		if p.y >= 8:
			c.draw_circle(p, 1.2 if n % 2 else 1.8, Color("d99a7b"))

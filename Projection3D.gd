extends RefCounted
## A fixed diorama view with an exact inverse for the unchanged 2D simulation.
const PITCH := 25.0 * PI / 180.0
const YAW := 8.0 * PI / 180.0
const COS_PITCH := cos(PITCH)
const SIN_PITCH := sin(PITCH)
const COS_YAW := cos(YAW)
const SIN_YAW := sin(YAW)

static func point(p: Vector2, depth: float = 0.0) -> Vector3:
	var x := (p.x + SIN_YAW * depth) / COS_YAW
	var y := (-p.y + SIN_PITCH * (SIN_YAW * x + COS_YAW * depth)) / COS_PITCH
	return Vector3(x, y, depth)

static func project(p: Vector3) -> Vector2:
	return Vector2(COS_YAW * p.x - SIN_YAW * p.z, SIN_PITCH * (SIN_YAW * p.x + COS_YAW * p.z) - COS_PITCH * p.y)

static func camera_offset() -> Vector3:
	return Vector3(SIN_YAW * COS_PITCH, SIN_PITCH, COS_YAW * COS_PITCH)

static func direction(p: Vector2) -> Vector2:
	var vector := point(p) - point(Vector2.ZERO)
	return Vector2(vector.x, -vector.y).normalized()

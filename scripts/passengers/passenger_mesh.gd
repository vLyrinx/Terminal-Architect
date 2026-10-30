extends RefCounted
## The low-poly passenger figure (checklist step 27), built from boxes into
## one ArrayMesh so a whole crowd can share it in a MultiMesh. Origin: on the
## ground between the feet, facing -Z, about 1.77 m tall. Each vertex stores
## its body part in UV.x; passenger.gdshader colours the parts per instance
## and swings the arms and legs while walking.

enum Part { SKIN, HAIR, SHIRT, ARM, LEG, SHOE }

## Pivot heights, in metres; they must match passenger.gdshader.
const HIP_Y := 0.88
const SHOULDER_Y := 1.42
const HEIGHT := 1.77


static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.1, 0.1]:
		_box(st, Vector3(0.12, 0.08, 0.26), Vector3(x, 0.04, -0.03), Part.SHOE)
		_box(st, Vector3(0.13, HIP_Y - 0.08, 0.16), Vector3(x, (HIP_Y + 0.08) * 0.5, 0.0), Part.LEG)
	_box(st, Vector3(0.40, 0.58, 0.24), Vector3(0, HIP_Y + 0.29, 0), Part.SHIRT)
	for x in [-0.255, 0.255]:
		_box(st, Vector3(0.10, 0.58, 0.12), Vector3(x, SHOULDER_Y + 0.02 - 0.29, 0), Part.ARM)
	_box(st, Vector3(0.21, 0.24, 0.22), Vector3(0, 1.60, 0), Part.SKIN)
	_box(st, Vector3(0.23, 0.07, 0.24), Vector3(0, HEIGHT - 0.035, 0.01), Part.HAIR)
	return st.commit()


## Adds a box as 12 triangles with flat normals.
static func _box(st: SurfaceTool, size: Vector3, centre: Vector3, part: Part) -> void:
	var h := size * 0.5
	var uv := Vector2(part, 0)
	# Each face: normal, then two axes spanning it (counter-clockwise seen from outside).
	var faces := [
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := centre + n * h
		var corners := [c - u * h - v * h, c + u * h - v * h, c + u * h + v * h, c - u * h + v * h]
		# Godot treats clockwise triangles as front faces.
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(uv)
			st.add_vertex(corners[i])

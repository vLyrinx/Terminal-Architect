extends RefCounted
## Collects quads and boxes into one ArrayMesh (used by floors and walls).
## Reuse one builder: clear(), add shapes, then commit().
##
## Godot draws clockwise triangles as front faces. add_quad() winds each quad
## so it faces its normal, so corners can be listed in either direction.

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func clear() -> void:
	_verts.clear()
	_normals.clear()
	_colors.clear()
	_indices.clear()


func is_empty() -> bool:
	return _verts.is_empty()


func get_vertex_count() -> int:
	return _verts.size()


## Adds a flat quad. corners are four Vector3s in order around its edge.
func add_quad(corners: Array, normal: Vector3, color: Color) -> void:
	var start := _verts.size()
	for corner: Vector3 in corners:
		_verts.append(corner)
		_normals.append(normal)
		_colors.append(color)
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var clockwise := (b - a).cross(c - a).dot(normal) < 0.0
	if clockwise:
		_indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	else:
		_indices.append_array([start, start + 2, start + 1, start, start + 3, start + 2])


## Adds an axis-aligned box. The bottom face is left out unless with_bottom is true
## (most things stand on the ground, where nobody can see underneath).
func add_box(lo: Vector3, hi: Vector3, side_color: Color, top_color: Color, with_bottom := false) -> void:
	add_quad([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)],
		Vector3.UP, top_color)
	if with_bottom:
		add_quad([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)],
			Vector3.DOWN, side_color)
	add_quad([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)],
		Vector3.FORWARD, side_color)
	add_quad([Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)],
		Vector3.BACK, side_color)
	add_quad([Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)],
		Vector3.LEFT, side_color)
	add_quad([Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)],
		Vector3.RIGHT, side_color)


## Builds an ArrayMesh from everything added since clear(). Null if nothing was added.
func commit() -> ArrayMesh:
	if is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

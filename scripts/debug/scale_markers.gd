extends Node3D
## Temporary scale markers for judging the camera (checklist step 5).
## An orange passenger-sized block (0.5 x 1.8 m) at the plot centre and a
## blue 10 m post at each plot corner. Remove once real objects exist.

const PERSON_SIZE := Vector3(0.5, 1.8, 0.35)
const POST_SIZE := Vector3(2.0, 10.0, 2.0)
const CORNER := 198.0


func _ready() -> void:
	_add_box(Vector3(0.0, PERSON_SIZE.y * 0.5, 0.0), PERSON_SIZE, Color(0.96, 0.49, 0.24))
	var post_mat := _material(Color(0.27, 0.52, 0.93))
	for x: float in [-CORNER, CORNER]:
		for z: float in [-CORNER, CORNER]:
			_add_box(Vector3(x, POST_SIZE.y * 0.5, z), POST_SIZE, null, post_mat)


func _add_box(pos: Vector3, size: Vector3, color: Variant, mat: StandardMaterial3D = null) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat else _material(color)
	mi.position = pos
	add_child(mi)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m

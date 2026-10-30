extends Node3D
## A simple low-poly pushback tug (checklist step 26), built from boxes. It is
## shown in front of an aircraft's nose gear while the aircraft is pushed back
## off its stand. Origin: on the ground at the aircraft's nose gear; the tow
## bar and the tug lie ahead of it along -Z, like the aircraft's nose.

const BODY_COLOR := Color(0.95, 0.75, 0.15)
const DARK_COLOR := Color(0.2, 0.2, 0.22)
const GLASS_COLOR := Color(0.45, 0.6, 0.7)

## Tow bar length, in metres.
const TOW_BAR := 3.0
const LENGTH := 5.5
const WIDTH := 2.6


func _ready() -> void:
	var back := -TOW_BAR
	# Tow bar from the nose gear to the tug.
	_box(Vector3(0.15, 0.15, TOW_BAR), Vector3(0, 0.45, -TOW_BAR * 0.5), DARK_COLOR)
	# Low body, a cab on one side at the front, and four wheels.
	_box(Vector3(WIDTH, 0.9, LENGTH), Vector3(0, 0.75, back - LENGTH * 0.5), BODY_COLOR)
	_box(Vector3(1.1, 0.9, 1.4), Vector3(-0.6, 1.65, back - LENGTH + 0.9), GLASS_COLOR)
	_box(Vector3(1.2, 0.12, 1.5), Vector3(-0.6, 2.16, back - LENGTH + 0.9), BODY_COLOR)
	for x in [-1.0, 1.0]:
		for z in [back - 1.0, back - LENGTH + 1.0]:
			_box(Vector3(0.4, 0.7, 0.7), Vector3(x * (WIDTH * 0.5 - 0.1), 0.35, z), DARK_COLOR)


func _box(size: Vector3, centre: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = centre
	add_child(part)

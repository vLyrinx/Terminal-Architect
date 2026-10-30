extends MultiMeshInstance3D
## Draws every passenger with one MultiMesh (checklist step 27), so a crowd
## of hundreds or thousands costs a single draw call per pass. Passengers are
## added with add() and get an id; set_pose() moves them. Each passenger gets
## a random look (shirt colour, skin tone, trousers and hair) stored in the
## instance custom data; passenger.gdshader turns it into colours and swings
## the arms and legs of passengers that are walking.
##
## Instance data is kept in one float buffer and sent to the GPU once per
## frame, only when something changed.

const PassengerMeshScript := preload("res://scripts/passengers/passenger_mesh.gd")
const PassengerShader := preload("res://materials/passenger.gdshader")

const SHIRT_COLOURS: Array[Color] = [
	Color(0.85, 0.22, 0.20), Color(0.20, 0.45, 0.80), Color(0.95, 0.75, 0.20),
	Color(0.25, 0.65, 0.35), Color(0.95, 0.95, 0.93), Color(0.55, 0.30, 0.65),
	Color(0.95, 0.50, 0.15), Color(0.20, 0.22, 0.26), Color(0.40, 0.75, 0.80),
	Color(0.90, 0.55, 0.65),
]
## Floats per instance: 12 for the transform, 4 for custom data.
const STRIDE := 16
const WALKING_BIT := 64

## Multiplies the walk animation speed (for example the game speed).
var animation_speed := 1.0

var _buffer := PackedFloat32Array()
var _count := 0
## Passenger id -> slot in the buffer, and slot -> id.
var _slot_of := {}
var _id_at := PackedInt32Array()
var _next_id := 1
var _dirty := false
var _anim_time := 0.0
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = PassengerMeshScript.build()
	# A fixed box around the plot, so the engine never recomputes it from the buffer.
	multimesh.custom_aabb = AABB(Vector3(-3000, -10, -3000), Vector3(6000, 30, 6000))
	_material = ShaderMaterial.new()
	_material.shader = PassengerShader
	material_override = _material
	_rng.randomize()


func _process(delta: float) -> void:
	_anim_time += delta * animation_speed
	_material.set_shader_parameter(&"walk_time", _anim_time)
	if _dirty:
		multimesh.buffer = _buffer
		multimesh.visible_instance_count = _count
		_dirty = false


## Adds a passenger at position facing yaw (radians, 0 = -Z) and returns its id.
func add(position: Vector3, yaw: float, walking := true) -> int:
	if _count == multimesh.instance_count:
		_grow()
	var id := _next_id
	_next_id += 1
	var slot := _count
	_count += 1
	_slot_of[id] = slot
	_id_at[slot] = id
	_write_pose(slot, position, yaw)
	var shirt: Color = SHIRT_COLOURS[_rng.randi() % SHIRT_COLOURS.size()]
	var look := _rng.randi() % 4 | (_rng.randi() % 4) << 2 | (_rng.randi() % 4) << 4
	if walking:
		look |= WALKING_BIT
	var i := slot * STRIDE + 12
	_buffer[i] = shirt.r
	_buffer[i + 1] = shirt.g
	_buffer[i + 2] = shirt.b
	_buffer[i + 3] = look
	_dirty = true
	return id


## Removes a passenger. The last passenger moves into its slot.
func remove(id: int) -> void:
	if not _slot_of.has(id):
		return
	var slot: int = _slot_of[id]
	var last := _count - 1
	if slot != last:
		for k in STRIDE:
			_buffer[slot * STRIDE + k] = _buffer[last * STRIDE + k]
		var moved := _id_at[last]
		_id_at[slot] = moved
		_slot_of[moved] = slot
	_slot_of.erase(id)
	_count -= 1
	_dirty = true


func set_pose(id: int, position: Vector3, yaw: float) -> void:
	_write_pose(_slot_of[id], position, yaw)
	_dirty = true


func get_passenger_position(id: int) -> Vector3:
	var i: int = _slot_of[id] * STRIDE
	return Vector3(_buffer[i + 3], _buffer[i + 7], _buffer[i + 11])


func set_walking(id: int, walking: bool) -> void:
	var i: int = _slot_of[id] * STRIDE + 15
	var look := int(_buffer[i]) & ~WALKING_BIT
	_buffer[i] = look | (WALKING_BIT if walking else 0)
	_dirty = true


func set_shirt_colour(id: int, colour: Color) -> void:
	var i: int = _slot_of[id] * STRIDE + 12
	_buffer[i] = colour.r
	_buffer[i + 1] = colour.g
	_buffer[i + 2] = colour.b
	_dirty = true


## The look of a passenger: shirt colour in rgb and the packed palette indices in a.
func get_look(id: int) -> Color:
	var i: int = _slot_of[id] * STRIDE + 12
	return Color(_buffer[i], _buffer[i + 1], _buffer[i + 2], _buffer[i + 3])


func has_passenger(id: int) -> bool:
	return _slot_of.has(id)


func get_count() -> int:
	return _count


func clear() -> void:
	_slot_of.clear()
	_count = 0
	_dirty = true


## The yaw that faces a passenger along direction (on the ground plane).
static func yaw_towards(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


func _write_pose(slot: int, position: Vector3, yaw: float) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var i := slot * STRIDE
	# Rotation about Y, row by row, with the origin at the end of each row.
	_buffer[i] = c
	_buffer[i + 1] = 0.0
	_buffer[i + 2] = s
	_buffer[i + 3] = position.x
	_buffer[i + 4] = 0.0
	_buffer[i + 5] = 1.0
	_buffer[i + 6] = 0.0
	_buffer[i + 7] = position.y
	_buffer[i + 8] = -s
	_buffer[i + 9] = 0.0
	_buffer[i + 10] = c
	_buffer[i + 11] = position.z


## Doubles the capacity. Changing instance_count clears the GPU data, so the
## buffer is resent on the next frame.
func _grow() -> void:
	var capacity := maxi(256, multimesh.instance_count * 2)
	multimesh.instance_count = capacity
	_buffer.resize(capacity * STRIDE)
	_id_at.resize(capacity)
	multimesh.visible_instance_count = _count
	_dirty = true

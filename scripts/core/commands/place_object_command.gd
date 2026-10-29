extends "res://scripts/core/commands/game_command.gd"
## Places a new object (checklist step 11).

var def_id: StringName
## Exact position and rotation (the tool snaps them to the grid first).
var position := Vector3.ZERO
var rotation := 0.0
var floor_index := 0
## The placed object's ID: set by the first execute(), then reused on redo or replay.
var object_id := 0


func _init(p_def_id := &"", p_position := Vector3.ZERO, p_rotation := 0.0, p_floor := 0) -> void:
	def_id = p_def_id
	position = p_position
	rotation = p_rotation
	floor_index = p_floor


func get_type() -> String:
	return "place_object"


func execute(world: Node) -> bool:
	var objects: Node = world.placed_objects
	var def := ObjectCatalog.get_def(def_id)
	if def == null:
		error = "Unknown object %s" % def_id
		return false
	if object_id > 0 and objects.get_object(object_id) != null:
		error = "ID %d is already in use" % object_id
		return false
	error = objects.check_placement(def, position, rotation, floor_index)
	if error != "":
		return false
	object_id = objects.add_object(def_id, position, rotation, floor_index, object_id)
	return object_id > 0


func undo(world: Node) -> void:
	world.placed_objects.remove_object(object_id)


func describe() -> String:
	return "place %s #%d" % [def_id, object_id]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"def": String(def_id),
		"position": vec3_to_array(position),
		"rotation": rotation,
		"floor": floor_index,
		"id": object_id,
	}


func load_dict(data: Dictionary) -> void:
	def_id = StringName(data.def)
	position = array_to_vec3(data.position)
	rotation = float(data.rotation)
	floor_index = int(data.floor)
	object_id = int(data.id)

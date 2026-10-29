extends "res://scripts/core/commands/game_command.gd"
## Rotates a placed object (checklist step 11). It carries the new position too,
## because turning an object on the grid can shift its centre by half a tile
## (see PlacedObjects.rotate_in_place()), and free rotation will use it later.

var object_id := 0
var new_position := Vector3.ZERO
var new_rotation := 0.0
# Saved by execute() for undo.
var _old_position := Vector3.ZERO
var _old_rotation := 0.0


func _init(p_id := 0, p_position := Vector3.ZERO, p_rotation := 0.0) -> void:
	object_id = p_id
	new_position = p_position
	new_rotation = p_rotation


func get_type() -> String:
	return "rotate_object"


func execute(world: Node) -> bool:
	var objects: Node = world.placed_objects
	var obj: RefCounted = objects.get_object(object_id)
	if obj == null:
		error = "No object #%d" % object_id
		return false
	var def := ObjectCatalog.get_def(obj.def_id)
	error = objects.check_placement(def, new_position, new_rotation, obj.floor_index, object_id)
	if error != "":
		return false
	_old_position = obj.position
	_old_rotation = obj.rotation
	objects.move_object(object_id, new_position, new_rotation)
	return true


func undo(world: Node) -> void:
	world.placed_objects.move_object(object_id, _old_position, _old_rotation)


func describe() -> String:
	return "rotate #%d to %d degrees" % [object_id, roundi(rad_to_deg(new_rotation))]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"id": object_id,
		"position": vec3_to_array(new_position),
		"rotation": new_rotation,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	object_id = int(data.id)
	new_position = array_to_vec3(data.position)
	new_rotation = float(data.rotation)
	player_id = int(data.get("player", 1))

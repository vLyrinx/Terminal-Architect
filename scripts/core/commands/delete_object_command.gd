extends "res://scripts/core/commands/game_command.gd"
## Deletes a placed object (checklist step 11). Undo puts it back with the same ID.

var object_id := 0
# Saved by execute() for undo.
var _def_id: StringName
var _position := Vector3.ZERO
var _rotation := 0.0
var _floor_index := 0


func _init(p_id := 0) -> void:
	object_id = p_id


func get_type() -> String:
	return "delete_object"


func execute(world: Node) -> bool:
	var obj: RefCounted = world.placed_objects.get_object(object_id)
	if obj == null:
		error = "No object #%d" % object_id
		return false
	_def_id = obj.def_id
	_position = obj.position
	_rotation = obj.rotation
	_floor_index = obj.floor_index
	world.placed_objects.remove_object(object_id)
	return true


func undo(world: Node) -> void:
	world.placed_objects.add_object(_def_id, _position, _rotation, _floor_index, object_id)


func describe() -> String:
	return "delete #%d" % object_id


func to_dict() -> Dictionary:
	return {"type": get_type(), "id": object_id}


func load_dict(data: Dictionary) -> void:
	object_id = int(data.id)

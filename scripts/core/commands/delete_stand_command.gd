extends "res://scripts/core/commands/game_command.gd"
## Removes an aircraft stand (checklist step 18), refunding part of its price
## (EconomySettings.sale_refund). Undo puts it back with the same ID.

var stand_id := 0
# Saved by execute() for undo.
var _def_id: StringName
var _anchor := Vector2i.ZERO
var _facing := 0


func _init(p_id := 0) -> void:
	stand_id = p_id


func get_type() -> String:
	return "delete_stand"


## Money back for removing it now (0 if there is no such stand).
func preview(world: Node) -> int:
	var stand: RefCounted = world.stands.get_stand(stand_id)
	if stand == null:
		return 0
	var def := StandCatalog.get_def(stand.def_id)
	return Money.refund_for(def.cost if def else 0)


func execute(world: Node) -> bool:
	var stand: RefCounted = world.stands.get_stand(stand_id)
	if stand == null:
		error = "No stand #%d" % stand_id
		return false
	var refund := preview(world)
	_def_id = stand.def_id
	_anchor = stand.anchor
	_facing = stand.facing
	world.stands.remove_stand(stand_id)
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	world.stands.add_stand(_def_id, _anchor, _facing, stand_id)
	unpay()


func describe() -> String:
	return "delete stand #%d" % stand_id


func to_dict() -> Dictionary:
	return {"type": get_type(), "id": stand_id, "player": player_id}


func load_dict(data: Dictionary) -> void:
	stand_id = int(data.id)
	player_id = int(data.get("player", 1))

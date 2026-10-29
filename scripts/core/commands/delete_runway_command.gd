extends "res://scripts/core/commands/game_command.gd"
## Removes a runway (checklist step 16), refunding part of its price
## (EconomySettings.sale_refund). Undo puts it back with the same ID.

var runway_id := 0
# Saved by execute() for undo.
var _def_id: StringName
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO


func _init(p_id := 0) -> void:
	runway_id = p_id


func get_type() -> String:
	return "delete_runway"


## Money back for removing it now (0 if there is no such runway).
func preview(world: Node) -> int:
	var runway: RefCounted = world.runways.get_runway(runway_id)
	if runway == null:
		return 0
	var def := RunwayCatalog.get_def(runway.def_id)
	return Money.refund_for(def.get_cost(runway.length) if def else 0)


func execute(world: Node) -> bool:
	var runway: RefCounted = world.runways.get_runway(runway_id)
	if runway == null:
		error = "No runway #%d" % runway_id
		return false
	var refund := preview(world)
	_def_id = runway.def_id
	_start = runway.start
	_end = runway.end
	world.runways.remove_runway(runway_id)
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	world.runways.add_runway(_def_id, _start, _end, runway_id)
	unpay()


func describe() -> String:
	return "delete runway #%d" % runway_id


func to_dict() -> Dictionary:
	return {"type": get_type(), "id": runway_id, "player": player_id}


func load_dict(data: Dictionary) -> void:
	runway_id = int(data.id)
	player_id = int(data.get("player", 1))

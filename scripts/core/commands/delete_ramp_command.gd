extends "res://scripts/core/commands/game_command.gd"
## Removes a runway ramp, refunding part of its price
## (EconomySettings.sale_refund). Undo puts it back with the same ID.

var ramp_id := 0
# Saved by execute() for undo.
var _def_id: StringName
var _runway_id := 0
var _anchor := Vector2i.ZERO
var _lean := 1


func _init(p_id := 0) -> void:
	ramp_id = p_id


func get_type() -> String:
	return "delete_ramp"


## Money back for removing it now (0 if there is no such ramp).
func preview(world: Node) -> int:
	var ramp: RefCounted = world.ramps.get_ramp(ramp_id)
	if ramp == null:
		return 0
	var def := RampCatalog.get_def(ramp.def_id)
	return Money.refund_for(def.cost if def else 0)


func execute(world: Node) -> bool:
	var ramp: RefCounted = world.ramps.get_ramp(ramp_id)
	if ramp == null:
		error = "No ramp #%d" % ramp_id
		return false
	var refund := preview(world)
	_def_id = ramp.def_id
	_runway_id = ramp.runway_id
	_anchor = ramp.anchor
	_lean = ramp.lean
	world.ramps.remove_ramp(ramp_id)
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	world.ramps.add_ramp(_def_id, _runway_id, _anchor, _lean, ramp_id)
	unpay()


func describe() -> String:
	return "delete ramp #%d" % ramp_id


func to_dict() -> Dictionary:
	return {"type": get_type(), "id": ramp_id, "player": player_id}


func load_dict(data: Dictionary) -> void:
	ramp_id = int(data.id)
	player_id = int(data.get("player", 1))

extends "res://scripts/core/commands/game_command.gd"
## Removes a taxiway piece (checklist step 17), refunding part of its price
## (EconomySettings.sale_refund). Undo puts it back with the same ID.

var taxiway_id := 0
# Saved by execute() for undo.
var _def_id: StringName
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO


func _init(p_id := 0) -> void:
	taxiway_id = p_id


func get_type() -> String:
	return "delete_taxiway"


## Money back for removing it now (0 if there is no such taxiway).
func preview(world: Node) -> int:
	var taxiway: RefCounted = world.taxiways.get_taxiway(taxiway_id)
	if taxiway == null:
		return 0
	var def := TaxiwayCatalog.get_def(taxiway.def_id)
	return Money.refund_for(def.get_cost(taxiway.length) if def else 0)


func execute(world: Node) -> bool:
	var taxiway: RefCounted = world.taxiways.get_taxiway(taxiway_id)
	if taxiway == null:
		error = "No taxiway #%d" % taxiway_id
		return false
	var refund := preview(world)
	_def_id = taxiway.def_id
	_start = taxiway.start
	_end = taxiway.end
	world.taxiways.remove_taxiway(taxiway_id)
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	world.taxiways.add_taxiway(_def_id, _start, _end, taxiway_id)
	unpay()


func describe() -> String:
	return "delete taxiway #%d" % taxiway_id


func to_dict() -> Dictionary:
	return {"type": get_type(), "id": taxiway_id, "player": player_id}


func load_dict(data: Dictionary) -> void:
	taxiway_id = int(data.id)
	player_id = int(data.get("player", 1))

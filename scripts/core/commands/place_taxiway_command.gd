extends "res://scripts/core/commands/game_command.gd"
## Builds a straight taxiway piece (checklist step 17) and pays for its length
## (TaxiwayDef.cost_per_metre). Undo removes it and gives the money back.

var def_id: StringName
## Grid corners on the centreline at each end (see taxiway.gd).
var start := Vector2i.ZERO
var end := Vector2i.ZERO
## The taxiway's ID: set by the first execute(), then reused on redo or replay.
var taxiway_id := 0


func _init(p_def_id := &"", p_start := Vector2i.ZERO, p_end := Vector2i.ZERO) -> void:
	def_id = p_def_id
	start = p_start
	end = p_end


func get_type() -> String:
	return "place_taxiway"


## What execute() would do now: {"error": why it can't ("" if it can),
## "length": metres, "cost": price}.
func preview(world: Node) -> Dictionary:
	var def := TaxiwayCatalog.get_def(def_id)
	if def == null:
		return {"error": "Unknown taxiway size %s" % def_id, "length": 0, "cost": 0}
	var length := maxi(absi(end.x - start.x), absi(end.y - start.y))
	var reason: String = world.taxiways.check_placement(def, start, end)
	if reason == "" and world.terminal_walls \
			and world.terminal_walls.count_pieces_in(world.taxiways.footprint(def, start, end)) > 0:
		reason = "Blocked by walls"
	return {"error": reason, "length": length, "cost": def.get_cost(length)}


func execute(world: Node) -> bool:
	var p := preview(world)
	if p.error != "":
		error = p.error
		return false
	if taxiway_id > 0 and world.taxiways.get_taxiway(taxiway_id) != null:
		error = "ID %d is already in use" % taxiway_id
		return false
	if not can_pay(p.cost):
		return false
	taxiway_id = world.taxiways.add_taxiway(def_id, start, end, taxiway_id)
	pay(-p.cost, &"construction")
	return true


func undo(world: Node) -> void:
	world.taxiways.remove_taxiway(taxiway_id)
	unpay()


func describe() -> String:
	return "place %s taxiway #%d from %s to %s" % [def_id, taxiway_id, start, end]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"def": String(def_id),
		"start": [start.x, start.y],
		"end": [end.x, end.y],
		"id": taxiway_id,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	def_id = StringName(data.def)
	start = Vector2i(int(data.start[0]), int(data.start[1]))
	end = Vector2i(int(data.end[0]), int(data.end[1]))
	taxiway_id = int(data.get("id", 0))
	player_id = int(data.get("player", 1))

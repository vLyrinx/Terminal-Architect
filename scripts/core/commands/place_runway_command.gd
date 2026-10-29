extends "res://scripts/core/commands/game_command.gd"
## Builds a runway (checklist step 16) and pays for its length
## (RunwayDef.cost_per_metre). Undo removes it and gives the money back.

var def_id: StringName
## Grid corners on the centreline at each end (see runway.gd).
var start := Vector2i.ZERO
var end := Vector2i.ZERO
## The runway's ID: set by the first execute(), then reused on redo or replay.
var runway_id := 0


func _init(p_def_id := &"", p_start := Vector2i.ZERO, p_end := Vector2i.ZERO) -> void:
	def_id = p_def_id
	start = p_start
	end = p_end


func get_type() -> String:
	return "place_runway"


## What execute() would do now: {"error": why it can't ("" if it can),
## "length": metres, "cost": price}.
func preview(world: Node) -> Dictionary:
	var def := RunwayCatalog.get_def(def_id)
	if def == null:
		return {"error": "Unknown runway size %s" % def_id, "length": 0, "cost": 0}
	var length := maxi(absi(end.x - start.x), absi(end.y - start.y))
	var reason: String = world.runways.check_placement(def, start, end)
	if reason == "" and world.terminal_walls \
			and world.terminal_walls.count_pieces_in(world.runways.footprint(def, start, end)) > 0:
		reason = "Blocked by walls"
	return {"error": reason, "length": length, "cost": def.get_cost(length)}


func execute(world: Node) -> bool:
	var p := preview(world)
	if p.error != "":
		error = p.error
		return false
	if runway_id > 0 and world.runways.get_runway(runway_id) != null:
		error = "ID %d is already in use" % runway_id
		return false
	if not can_pay(p.cost):
		return false
	runway_id = world.runways.add_runway(def_id, start, end, runway_id)
	pay(-p.cost, &"construction")
	return true


func undo(world: Node) -> void:
	world.runways.remove_runway(runway_id)
	unpay()


func describe() -> String:
	return "place %s runway #%d from %s to %s" % [def_id, runway_id, start, end]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"def": String(def_id),
		"start": [start.x, start.y],
		"end": [end.x, end.y],
		"id": runway_id,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	def_id = StringName(data.def)
	start = Vector2i(int(data.start[0]), int(data.start[1]))
	end = Vector2i(int(data.end[0]), int(data.end[1]))
	runway_id = int(data.get("id", 0))
	player_id = int(data.get("player", 1))

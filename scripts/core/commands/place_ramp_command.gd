extends "res://scripts/core/commands/game_command.gd"
## Builds a runway ramp and pays its price (RampDef.cost). Undo removes it and
## gives the money back.

var def_id: StringName
var runway_id := 0
## Grid corner in the middle of the ramp's outer end (see ramp.gd).
var anchor := Vector2i.ZERO
## Angled ramps: which way along the runway they lean (+1 or -1).
var lean := 1
## The ramp's ID: set by the first execute(), then reused on redo or replay.
var ramp_id := 0


func _init(p_def_id := &"", p_runway_id := 0, p_anchor := Vector2i.ZERO, p_lean := 1) -> void:
	def_id = p_def_id
	runway_id = p_runway_id
	anchor = p_anchor
	lean = p_lean


func get_type() -> String:
	return "place_ramp"


## What execute() would do now: {"error": why it can't ("" if it can), "cost": price}.
func preview(world: Node) -> Dictionary:
	var def := RampCatalog.get_def(def_id)
	if def == null:
		return {"error": "Unknown ramp %s" % def_id, "cost": 0}
	var reason: String = world.ramps.check_placement(def, runway_id, anchor, lean)
	if reason == "" and world.terminal_walls:
		var ramp: RefCounted = world.ramps.make_ramp(def, world.runways.get_runway(runway_id), anchor, lean)
		if world.terminal_walls.count_pieces_in(ramp.rect) > 0:
			reason = "Blocked by walls"
	return {"error": reason, "cost": def.cost}


func execute(world: Node) -> bool:
	var p := preview(world)
	if p.error != "":
		error = p.error
		return false
	if ramp_id > 0 and world.ramps.get_ramp(ramp_id) != null:
		error = "ID %d is already in use" % ramp_id
		return false
	if not can_pay(p.cost):
		return false
	ramp_id = world.ramps.add_ramp(def_id, runway_id, anchor, lean, ramp_id)
	pay(-p.cost, &"construction")
	return true


func undo(world: Node) -> void:
	world.ramps.remove_ramp(ramp_id)
	unpay()


func describe() -> String:
	return "place %s ramp #%d on runway #%d at %s" % [def_id, ramp_id, runway_id, anchor]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"def": String(def_id),
		"runway": runway_id,
		"anchor": [anchor.x, anchor.y],
		"lean": lean,
		"id": ramp_id,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	def_id = StringName(data.def)
	runway_id = int(data.runway)
	anchor = Vector2i(int(data.anchor[0]), int(data.anchor[1]))
	lean = int(data.get("lean", 1))
	ramp_id = int(data.get("id", 0))
	player_id = int(data.get("player", 1))

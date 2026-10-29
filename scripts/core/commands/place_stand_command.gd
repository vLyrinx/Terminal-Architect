extends "res://scripts/core/commands/game_command.gd"
## Builds an aircraft stand (checklist step 18) and pays its price
## (StandDef.cost). Undo removes it and gives the money back.

var def_id: StringName
## Grid corner in the middle of the entry edge, and the way the edge faces
## (an index into Stands.FACINGS). See stand.gd.
var anchor := Vector2i.ZERO
var facing := 0
## The stand's ID: set by the first execute(), then reused on redo or replay.
var stand_id := 0


func _init(p_def_id := &"", p_anchor := Vector2i.ZERO, p_facing := 0) -> void:
	def_id = p_def_id
	anchor = p_anchor
	facing = p_facing


func get_type() -> String:
	return "place_stand"


## What execute() would do now: {"error": why it can't ("" if it can),
## "cost": price, "taxiway_id": the taxiway it would open onto (0 if none)}.
func preview(world: Node) -> Dictionary:
	var def := StandCatalog.get_def(def_id)
	if def == null:
		return {"error": "Unknown stand size %s" % def_id, "cost": 0, "taxiway_id": 0}
	var reason: String = world.stands.check_placement(def, anchor, facing)
	if reason == "" and world.terminal_walls \
			and world.terminal_walls.count_pieces_in(world.stands.footprint(def, anchor, facing)) > 0:
		reason = "Blocked by walls"
	return {"error": reason, "cost": def.cost, "taxiway_id": world.stands.find_connection(def, anchor, facing)}


func execute(world: Node) -> bool:
	var p := preview(world)
	if p.error != "":
		error = p.error
		return false
	if stand_id > 0 and world.stands.get_stand(stand_id) != null:
		error = "ID %d is already in use" % stand_id
		return false
	if not can_pay(p.cost):
		return false
	stand_id = world.stands.add_stand(def_id, anchor, facing, stand_id)
	pay(-p.cost, &"construction")
	return true


func undo(world: Node) -> void:
	world.stands.remove_stand(stand_id)
	unpay()


func describe() -> String:
	return "place %s stand #%d at %s facing %d" % [def_id, stand_id, anchor, facing]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"def": String(def_id),
		"anchor": [anchor.x, anchor.y],
		"facing": facing,
		"id": stand_id,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	def_id = StringName(data.def)
	anchor = Vector2i(int(data.anchor[0]), int(data.anchor[1]))
	facing = int(data.get("facing", 0))
	stand_id = int(data.get("id", 0))
	player_id = int(data.get("player", 1))

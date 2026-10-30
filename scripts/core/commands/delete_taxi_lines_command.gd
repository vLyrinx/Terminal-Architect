extends "res://scripts/core/commands/game_command.gd"
## Removes taxi lines, refunding part of their price
## (EconomySettings.sale_refund). Undo paints them back with the same IDs.

var line_ids: Array[int] = []
# Saved by execute() for undo: ID -> [a, b].
var _saved := {}


func _init(p_ids: Array[int] = []) -> void:
	line_ids = p_ids.duplicate()


func get_type() -> String:
	return "delete_taxi_lines"


## Money back for removing them now.
func preview(world: Node) -> int:
	var metres := 0
	for id in line_ids:
		var line: RefCounted = world.taxi_lines.get_line(id)
		if line:
			metres += ceili(line.length)
	return Money.refund_for(metres * Money.settings.taxi_line_cost_per_metre)


func execute(world: Node) -> bool:
	var refund := preview(world)
	_saved.clear()
	for id in line_ids:
		var line: RefCounted = world.taxi_lines.get_line(id)
		if line:
			_saved[id] = [line.a, line.b]
	if _saved.is_empty():
		error = "No taxi lines to remove"
		return false
	for id: int in _saved:
		world.taxi_lines.remove_line(id)
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	for id: int in _saved:
		world.taxi_lines.add_line(_saved[id][0], _saved[id][1], id)
	unpay()


func describe() -> String:
	return "delete taxi lines %s" % [line_ids]


func to_dict() -> Dictionary:
	return {"type": get_type(), "ids": line_ids.duplicate(), "player": player_id}


func load_dict(data: Dictionary) -> void:
	line_ids.clear()
	for id in data.ids:
		line_ids.append(int(id))
	player_id = int(data.get("player", 1))

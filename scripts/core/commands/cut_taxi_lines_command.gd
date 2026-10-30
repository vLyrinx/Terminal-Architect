extends "res://scripts/core/commands/game_command.gd"
## Removes the parts of taxi lines within reach of a dragged segment
## (TaxiLines.cut_plan()), leaving the rest of each line in place as new lines,
## and refunds part of the price of the metres taken away
## (EconomySettings.sale_refund). Undo puts the original lines back with their
## IDs.

var a := Vector2i.ZERO
var b := Vector2i.ZERO
var reach := 0.75
## IDs of the pieces left over: set by the first execute(), then reused on
## redo or replay.
var piece_ids: Array[int] = []
# Saved by execute() for undo: ID -> [a, b].
var _saved := {}


func _init(p_a := Vector2i.ZERO, p_b := Vector2i.ZERO, p_reach := 0.75) -> void:
	a = p_a
	b = p_b
	reach = p_reach


func get_type() -> String:
	return "cut_taxi_lines"


## What execute() would do now: {"lines": how many lines are cut, "metres":
## metres removed, "refund": money back}.
func preview(world: Node) -> Dictionary:
	var plans: Array[Dictionary] = world.taxi_lines.cut_plan(Vector2(a), Vector2(b), reach)
	var metres := 0.0
	for plan in plans:
		metres += plan.removed
	return {"lines": plans.size(), "metres": metres,
		"refund": Money.refund_for(ceili(metres - 0.01) * Money.settings.taxi_line_cost_per_metre)}


func execute(world: Node) -> bool:
	var plans: Array[Dictionary] = world.taxi_lines.cut_plan(Vector2(a), Vector2(b), reach)
	if plans.is_empty():
		error = "No taxi lines to remove"
		return false
	var refund: int = preview(world).refund
	_saved.clear()
	var reuse := piece_ids.duplicate()
	piece_ids.clear()
	for plan in plans:
		var line: RefCounted = world.taxi_lines.get_line(plan.id)
		_saved[plan.id] = [line.a, line.b]
		world.taxi_lines.remove_line(plan.id)
		for piece: Array in plan.pieces:
			var id: int = reuse.pop_front() if not reuse.is_empty() else 0
			piece_ids.append(world.taxi_lines.add_line(piece[0], piece[1], id))
	pay(refund, &"sale")
	return true


func undo(world: Node) -> void:
	for id in piece_ids:
		world.taxi_lines.remove_line(id)
	for id: int in _saved:
		world.taxi_lines.add_line(_saved[id][0], _saved[id][1], id)
	unpay()


func describe() -> String:
	return "cut taxi lines from %s to %s" % [a, b]


func to_dict() -> Dictionary:
	return {"type": get_type(), "a": [a.x, a.y], "b": [b.x, b.y], "reach": reach, "pieces": piece_ids.duplicate(),
		"player": player_id}


func load_dict(data: Dictionary) -> void:
	a = Vector2i(int(data.a[0]), int(data.a[1]))
	b = Vector2i(int(data.b[0]), int(data.b[1]))
	reach = float(data.get("reach", 0.75))
	piece_ids.clear()
	for id in data.get("pieces", []):
		piece_ids.append(int(id))
	player_id = int(data.get("player", 1))

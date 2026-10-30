extends "res://scripts/core/commands/game_command.gd"
## Paints a taxi line on taxiway or ramp paving and pays for its length
## (EconomySettings.taxi_line_cost_per_metre). Undo removes it and gives the
## money back.

var a := Vector2i.ZERO
var b := Vector2i.ZERO
## The line's ID: set by the first execute(), then reused on redo or replay.
var line_id := 0


func _init(p_a := Vector2i.ZERO, p_b := Vector2i.ZERO) -> void:
	a = p_a
	b = p_b


func get_type() -> String:
	return "place_taxi_line"


## What execute() would do now: {"error": why it can't ("" if it can),
## "length": metres, "size_class", "cost": price}.
func preview(world: Node) -> Dictionary:
	var check: Dictionary = world.taxi_lines.check_line(a, b)
	check.cost = ceili(check.length) * Money.settings.taxi_line_cost_per_metre
	return check


func execute(world: Node) -> bool:
	var p := preview(world)
	if p.error != "":
		error = p.error
		return false
	if line_id > 0 and world.taxi_lines.get_line(line_id) != null:
		error = "ID %d is already in use" % line_id
		return false
	if not can_pay(p.cost):
		return false
	line_id = world.taxi_lines.add_line(a, b, line_id)
	pay(-p.cost, &"construction")
	return true


func undo(world: Node) -> void:
	world.taxi_lines.remove_line(line_id)
	unpay()


func describe() -> String:
	return "paint taxi line #%d from %s to %s" % [line_id, a, b]


func to_dict() -> Dictionary:
	return {"type": get_type(), "a": [a.x, a.y], "b": [b.x, b.y], "id": line_id, "player": player_id}


func load_dict(data: Dictionary) -> void:
	a = Vector2i(int(data.a[0]), int(data.a[1]))
	b = Vector2i(int(data.b[0]), int(data.b[1]))
	line_id = int(data.get("id", 0))
	player_id = int(data.get("player", 1))

extends "res://scripts/core/commands/game_command.gd"
## Turns a wall piece into a doorway, or a doorway back into wall (door tool,
## checklist step 14). Adding a door pays EconomySettings.door_cost; turning it
## back into wall refunds part of that.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")

var corner := Vector2i.ZERO
var horizontal := true
## True to add a door, false to turn a door back into wall.
var door := true
var floor_index := 0


func _init(p_corner := Vector2i.ZERO, p_horizontal := true, p_door := true, p_floor := 0) -> void:
	corner = p_corner
	horizontal = p_horizontal
	door = p_door
	floor_index = p_floor


func get_type() -> String:
	return "set_door"


## What execute() would do now: {"ok": the edge holds the right piece,
## "amount": money change, negative when it costs}.
func preview(world: Node) -> Dictionary:
	var piece: int = world.terminal_walls.get_edge(corner, horizontal, floor_index)
	var needed := TerminalWallsScript.Piece.WALL if door else TerminalWallsScript.Piece.DOOR
	var cost: int = Money.settings.door_cost
	return {"ok": piece == needed, "amount": -cost if door else Money.refund_for(cost)}


func execute(world: Node) -> bool:
	var p := preview(world)
	if not p.ok:
		error = "Needs a wall" if door else "No door here"
		return false
	if not can_pay(-p.amount):
		return false
	world.terminal_walls.set_door(corner, horizontal, door, floor_index)
	pay(p.amount, &"construction" if door else &"sale")
	return true


func undo(world: Node) -> void:
	world.terminal_walls.set_door(corner, horizontal, not door, floor_index)
	unpay()


func describe() -> String:
	return "%s at corner %s, %s" % ["add door" if door else "remove door", corner,
		"horizontal" if horizontal else "vertical"]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"corner": [corner.x, corner.y],
		"horizontal": horizontal,
		"door": door,
		"floor": floor_index,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	corner = Vector2i(int(data.corner[0]), int(data.corner[1]))
	horizontal = bool(data.horizontal)
	door = bool(data.door)
	floor_index = int(data.floor)
	player_id = int(data.get("player", 1))

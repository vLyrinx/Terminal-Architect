extends "res://scripts/core/commands/game_command.gd"
## Lays or removes terminal floor in a rectangle (floor tool, checklist step 14).
## Laying pays for each new tile; removing refunds part of each tile's price.
## Undo puts back exactly the tiles the rectangle had before, and the zones
## that removing the floor cleared.

var rect := Rect2i()
## True to lay floor, false to remove it.
var filled := true
var floor_index := 0

# Saved by execute() for undo.
var _before := PackedByteArray()
var _before_zones := PackedByteArray()
var _changed := 0


func _init(p_rect := Rect2i(), p_filled := true, p_floor := 0) -> void:
	rect = p_rect
	filled = p_filled
	floor_index = p_floor


func get_type() -> String:
	return "set_floor"


## What execute() would do now: {"tiles": tiles that would change,
## "amount": money change, negative when it costs}.
func preview(world: Node) -> Dictionary:
	var tiles: int = world.terminal_floor.count_changes(rect, filled, floor_index)
	var value := tiles * Money.settings.floor_tile_cost
	return {"tiles": tiles, "amount": -value if filled else Money.refund_for(value)}


func execute(world: Node) -> bool:
	var p := preview(world)
	_changed = p.tiles
	if p.tiles == 0:
		error = "Nothing to change"
		return false
	if not can_pay(-p.amount):
		return false
	_before = world.terminal_floor.get_rect_state(rect, floor_index)
	_before_zones = PackedByteArray()
	if not filled and world.terminal_zones:
		_before_zones = world.terminal_zones.get_rect_state(rect, floor_index)
	world.terminal_floor.set_rect(rect, filled, floor_index)
	pay(p.amount, &"construction" if filled else &"sale")
	return true


func undo(world: Node) -> void:
	world.terminal_floor.set_rect_state(rect, _before, floor_index)
	if not _before_zones.is_empty():
		world.terminal_zones.set_rect_state(rect, _before_zones, floor_index)
	unpay()


func describe() -> String:
	return "%s %d floor tiles" % ["lay" if filled else "remove", _changed]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"filled": filled,
		"floor": floor_index,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	var r: Array = data.rect
	rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	filled = bool(data.filled)
	floor_index = int(data.floor)
	player_id = int(data.get("player", 1))

extends "res://scripts/core/commands/game_command.gd"
## Lays or removes taxiway paving in a rectangle (taxiway tool). Laying pays
## for each new tile (EconomySettings.taxiway_tile_cost); removing refunds part
## of each tile's price. Undo puts back exactly the tiles the rectangle had.

var rect := Rect2i()
## True to lay paving, false to remove it.
var paved := true

# Saved by execute() for undo.
var _before := PackedByteArray()
var _changed := 0


func _init(p_rect := Rect2i(), p_paved := true) -> void:
	rect = p_rect
	paved = p_paved


func get_type() -> String:
	return "set_paving"


## What execute() would do now: {"tiles": tiles that would change,
## "amount": money change, negative when it costs}.
func preview(world: Node) -> Dictionary:
	var tiles: int = world.taxiways.count_changes(rect, paved)
	var value := tiles * Money.settings.taxiway_tile_cost
	return {"tiles": tiles, "amount": -value if paved else Money.refund_for(value)}


func execute(world: Node) -> bool:
	var p := preview(world)
	_changed = p.tiles
	if p.tiles == 0:
		error = "Nothing to change"
		return false
	if not can_pay(-p.amount):
		return false
	_before = world.taxiways.get_rect_state(rect)
	world.taxiways.set_rect(rect, paved)
	pay(p.amount, &"construction" if paved else &"sale")
	return true


func undo(world: Node) -> void:
	world.taxiways.set_rect_state(rect, _before)
	unpay()


func describe() -> String:
	return "%s %d taxiway paving tiles" % ["lay" if paved else "remove", _changed]


func to_dict() -> Dictionary:
	return {
		"type": get_type(),
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"paved": paved,
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	var r: Array = data.rect
	rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	paved = bool(data.paved)
	player_id = int(data.get("player", 1))

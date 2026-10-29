extends "res://scripts/core/commands/game_command.gd"
## Builds or removes walls along straight runs (wall tool, checklist step 14).
## A Line drag is one run; a Room drag is the four sides plus the floor inside.
## Building pays for each new wall piece and floor tile. Removing refunds part
## of the price of each piece taken away (a door counts as wall + door).
## Undo puts back exactly the pieces and tiles there were before.

const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")

## Runs as [from corner, to corner] pairs (Vector2i), each on one grid line.
var runs: Array = []
## True to build walls, false to remove walls and doors.
var place := true
var floor_index := 0
## Floor laid inside a room before its walls go up. Size 0 for none; ignored when removing.
var room_rect := Rect2i()

# Saved by execute() for undo.
var _before_pieces: Array[PackedByteArray] = []
var _before_floor := PackedByteArray()
var _walls_changed := 0
var _floor_changed := 0


func _init(p_runs := [], p_place := true, p_floor := 0, p_room := Rect2i()) -> void:
	runs = p_runs
	place = p_place
	floor_index = p_floor
	room_rect = p_room


func get_type() -> String:
	return "set_walls"


## What execute() would do now: {"walls": wall pieces that would change,
## "floor": floor tiles that would be laid, "amount": money change, negative
## when it costs}.
func preview(world: Node) -> Dictionary:
	var walls: Node3D = world.terminal_walls
	var prices := Money.settings
	var wall_changes := 0
	var removed_value := 0
	for run: Array in runs:
		wall_changes += walls.count_run_changes(run[0], run[1], place, floor_index)
		if not place:
			for piece in walls.get_run_pieces(run[0], run[1], floor_index):
				if piece == TerminalWallsScript.Piece.WALL:
					removed_value += prices.wall_cost
				elif piece == TerminalWallsScript.Piece.DOOR:
					removed_value += prices.wall_cost + prices.door_cost
	var floor_changes := 0
	if _lays_floor():
		floor_changes = world.terminal_floor.count_changes(room_rect, true, floor_index)
	var amount: int = -(wall_changes * prices.wall_cost + floor_changes * prices.floor_tile_cost) if place \
		else Money.refund_for(removed_value)
	return {"walls": wall_changes, "floor": floor_changes, "amount": amount}


func execute(world: Node) -> bool:
	var p := preview(world)
	_walls_changed = p.walls
	_floor_changed = p.floor
	if p.walls + p.floor == 0:
		error = "Nothing to change"
		return false
	if not can_pay(-p.amount):
		return false
	_before_pieces.clear()
	for run: Array in runs:
		_before_pieces.append(world.terminal_walls.get_run_pieces(run[0], run[1], floor_index))
	_before_floor = PackedByteArray()
	if _lays_floor():
		# Floor first, so the new walls know which side is inside.
		_before_floor = world.terminal_floor.get_rect_state(room_rect, floor_index)
		world.terminal_floor.set_rect(room_rect, true, floor_index)
	for run: Array in runs:
		world.terminal_walls.set_run(run[0], run[1], place, floor_index)
	pay(p.amount, &"construction" if place else &"sale")
	return true


func undo(world: Node) -> void:
	for i in range(runs.size() - 1, -1, -1):
		world.terminal_walls.set_run_pieces(runs[i][0], runs[i][1], _before_pieces[i], floor_index)
	if not _before_floor.is_empty():
		world.terminal_floor.set_rect_state(room_rect, _before_floor, floor_index)
	unpay()


func describe() -> String:
	var text := "%s %d wall pieces" % ["build" if place else "remove", _walls_changed]
	if _floor_changed > 0:
		text += " and %d floor tiles" % _floor_changed
	return text


func to_dict() -> Dictionary:
	var run_data := []
	for run: Array in runs:
		run_data.append([run[0].x, run[0].y, run[1].x, run[1].y])
	return {
		"type": get_type(),
		"runs": run_data,
		"place": place,
		"floor": floor_index,
		"room": [room_rect.position.x, room_rect.position.y, room_rect.size.x, room_rect.size.y],
		"player": player_id,
	}


func load_dict(data: Dictionary) -> void:
	runs = []
	for r: Array in data.runs:
		runs.append([Vector2i(int(r[0]), int(r[1])), Vector2i(int(r[2]), int(r[3]))])
	place = bool(data.place)
	floor_index = int(data.floor)
	var room: Array = data.get("room", [0, 0, 0, 0])
	room_rect = Rect2i(int(room[0]), int(room[1]), int(room[2]), int(room[3]))
	player_id = int(data.get("player", 1))


func _lays_floor() -> bool:
	return place and room_rect.size.x > 0 and room_rect.size.y > 0

extends Node3D
## Automatic test for money and construction costs (checklist step 14).
## Run this scene on its own (F6). It builds floor, walls, doors and objects
## through commands with a small balance, checks what each costs, that building
## is refused without enough money, that removing refunds part of the price
## and that undo gives exact money back, then prints PASS or FAIL for each check.
## Prices come from data/economy.tres, so the test still works if they change.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceCmd := preload("res://scripts/core/commands/place_object_command.gd")
const DeleteCmd := preload("res://scripts/core/commands/delete_object_command.gd")
const FloorCmd := preload("res://scripts/core/commands/set_floor_command.gd")
const WallsCmd := preload("res://scripts/core/commands/set_walls_command.gd")
const DoorCmd := preload("res://scripts/core/commands/set_door_command.gd")
const START := 10000

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _objects: PlacedObjectsScript
var _zones: TerminalZonesScript
var _runner: CommandRunnerScript
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | money and construction costs")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_objects = PlacedObjectsScript.new()
	_floor.placed_objects = _objects
	_walls = TerminalWallsScript.new()
	_walls.placed_objects = _objects
	_walls.terminal_floor = _floor
	add_child(_walls)
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = _objects
	_runner.terminal_floor = _floor
	_runner.terminal_walls = _walls
	_runner.terminal_zones = _zones
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)

	var prices := Money.settings
	var bench := ObjectCatalog.get_def(&"test_bench")
	var scanner := ObjectCatalog.get_def(&"security_scanner")

	Money.reset(START)
	_expect("starts with %s and one starting_money transaction" % Money.format(START),
		Money.balance == START and Money.transactions.size() == 1
		and Money.transactions[0].category == &"starting_money")

	var balance := START
	_runner.submit(FloorCmd.new(Rect2i(10, 10, 10, 10), true))
	balance -= 100 * prices.floor_tile_cost
	_expect("10 x 10 floor costs %s" % Money.format(100 * prices.floor_tile_cost), Money.balance == balance)
	var t: Dictionary = Money.transactions[-1]
	_expect("it is logged as construction by player 1 with today's date",
		t.category == &"construction" and t.player == 1 and t.amount == -100 * prices.floor_tile_cost
		and t.day == GameClock.get_day_number() and t.time == GameClock.game_time)

	var bench_pos: Vector3 = _objects.snap_position(bench, _corner(12, 12) + Vector3(0, 0, 0.5), 0.0)
	_expect("bench placed for %s" % Money.format(bench.cost),
		_runner.submit(PlaceCmd.new(bench.id, bench_pos, 0.0)) and Money.balance == balance - bench.cost)
	balance -= bench.cost
	var bench_id: int = _runner.history[-1].object_id

	_runner.submit(WallsCmd.new([[Vector2i(10, 10), Vector2i(15, 10)]], true))
	balance -= 5 * prices.wall_cost
	_expect("5 m wall costs %s" % Money.format(5 * prices.wall_cost), Money.balance == balance)
	_runner.submit(DoorCmd.new(Vector2i(12, 10), true, true))
	balance -= prices.door_cost
	_expect("door costs %s" % Money.format(prices.door_cost), Money.balance == balance
		and _walls.get_edge(Vector2i(12, 10), true) == TerminalWallsScript.Piece.DOOR)

	# Not enough money.
	var count := Money.transactions.size()
	var scanner_pos: Vector3 = _objects.snap_position(scanner, _corner(16, 14), 0.0)
	_expect("scanner (%s) refused with %s left" % [Money.format(scanner.cost), Money.format(balance)],
		not _runner.submit(PlaceCmd.new(scanner.id, scanner_pos, 0.0))
		and _last_error().begins_with("Not enough money") and _objects.get_count() == 1)
	_expect("refusal shows the price and the balance: \"%s\"" % _last_error(),
		Money.format(scanner.cost) in _last_error() and Money.format(balance) in _last_error())
	_expect("huge floor refused and nothing laid",
		not _runner.submit(FloorCmd.new(Rect2i(100, 100, 100, 100), true))
		and _floor.get_floor_tile_count() == 100)
	_expect("long wall refused and nothing built",
		not _runner.submit(WallsCmd.new([[Vector2i(0, 50), Vector2i(300, 50)]], true))
		and _walls.get_piece_counts().walls == 4)
	_expect("refusals change nothing: balance and log the same",
		Money.balance == balance and Money.transactions.size() == count)

	# Selling and undo.
	_runner.submit(DeleteCmd.new(bench_id))
	balance += Money.refund_for(bench.cost)
	_expect("deleting the bench refunds %s as a sale" % Money.format(Money.refund_for(bench.cost)),
		Money.balance == balance and Money.transactions[-1].category == &"sale")
	_runner.undo_last()
	balance -= Money.refund_for(bench.cost)
	_expect("undoing the delete takes the refund back", Money.balance == balance and _objects.get_count() == 1)
	_runner.undo_last()
	balance += prices.door_cost
	_expect("undoing the door gives %s back and leaves wall" % Money.format(prices.door_cost),
		Money.balance == balance and _walls.get_edge(Vector2i(12, 10), true) == TerminalWallsScript.Piece.WALL)
	_runner.undo_last()
	balance += 5 * prices.wall_cost
	_expect("undoing the wall run removes it and refunds it in full",
		Money.balance == balance and _walls.get_piece_counts().walls == 0)

	_zones.paint_rect(Rect2i(14, 14, 3, 3), TerminalZonesScript.Zone.LANDSIDE)
	_runner.submit(FloorCmd.new(Rect2i(10, 10, 10, 10), false))
	balance += Money.refund_for(98 * prices.floor_tile_cost)
	_expect("removing the floor refunds 98 tiles (2 stay under the bench)",
		Money.balance == balance and _floor.get_floor_tile_count() == 2)
	_expect("and clears the zones painted on it", _zones.count_zone(TerminalZonesScript.Zone.LANDSIDE) == 0)
	_runner.undo_last()
	balance -= Money.refund_for(98 * prices.floor_tile_cost)
	_expect("undo puts all 100 tiles back", Money.balance == balance and _floor.get_floor_tile_count() == 100)
	_expect("and the 9 landside tiles", _zones.count_zone(TerminalZonesScript.Zone.LANDSIDE) == 9)

	# Room mode: floor and four walls in one command and one transaction.
	Money.reset(START)
	count = Money.transactions.size()
	var room := WallsCmd.new(_room_sides(Vector2i(30, 10), Vector2i(36, 14)), true, 0, Rect2i(30, 10, 6, 4))
	var room_cost: int = 24 * prices.floor_tile_cost + 20 * prices.wall_cost
	_expect("preview of a 6 x 4 room: 24 tiles, 20 walls, %s" % Money.format(room_cost),
		room.preview(_runner) == {"walls": 20, "floor": 24, "amount": -room_cost})
	_expect("room built as one transaction", _runner.submit(room)
		and Money.balance == START - room_cost and Money.transactions.size() == count + 1)
	_runner.submit(DoorCmd.new(Vector2i(32, 10), true, true))
	var removed_value: int = 19 * prices.wall_cost + prices.wall_cost + prices.door_cost
	var before := Money.balance
	_runner.submit(WallsCmd.new(_room_sides(Vector2i(30, 10), Vector2i(36, 14)), false))
	_expect("removing the room walls refunds %s (the door counts too)" % Money.format(Money.refund_for(removed_value)),
		Money.balance == before + Money.refund_for(removed_value) and _walls.get_piece_counts().walls == 0
		and _walls.get_piece_counts().doors == 0)
	_runner.undo_last()
	_expect("undo brings back 19 walls and the door",
		Money.balance == before and _walls.get_piece_counts().walls == 19 and _walls.get_piece_counts().doors == 1)

	# Players and data.
	var other := FloorCmd.new(Rect2i(50, 50, 2, 2), true)
	other.player_id = 2
	_runner.submit(other)
	_expect("transaction records the player who caused it (2)", Money.transactions[-1].player == 2)
	var copy: RefCounted = CommandRunnerScript.command_from_dict(other.to_dict())
	_expect("commands keep their player in saved data", copy.player_id == 2 and copy.rect == other.rect)
	var walls_copy: RefCounted = CommandRunnerScript.command_from_dict(room.to_dict())
	_expect("wall commands save and load runs and the room",
		walls_copy.runs == room.runs and walls_copy.room_rect == room.room_rect and walls_copy.place)

	var total := 0
	for transaction in Money.transactions:
		total += transaction.amount
	_expect("the log adds up to the balance (%s)" % Money.format(Money.balance), total == Money.balance)
	_expect("totals by category add up too", Money.get_totals().values().reduce(
		func(a: int, b: int) -> int: return a + b, 0) == Money.balance)

	Money.reset(Money.settings.starting_money)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))


func _corner(x: int, y: int) -> Vector3:
	return BuildGrid.tile_corner_to_world(Vector2i(x, y))


## The four sides of a room between two corners, as the wall tool makes them.
func _room_sides(lo: Vector2i, hi: Vector2i) -> Array:
	return [[lo, Vector2i(hi.x, lo.y)], [Vector2i(hi.x, lo.y), hi], [hi, Vector2i(lo.x, hi.y)], [Vector2i(lo.x, hi.y), lo]]


func _last_error() -> String:
	return _last_failed.error if _last_failed else ""


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

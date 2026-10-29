extends Node3D
## Automatic test for runway placement (checklist step 16).
## Run this scene on its own (F6). It builds runways through commands, checks
## their size rules, footprint, ends, designators and cost, that they can't
## overlap floor, walls or each other, that floor isn't laid on them, that
## deleting refunds and undo restores, and that commands save and load, then
## prints PASS or FAIL for each check. Sizes and prices come from data/runways/.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const RunwayScript := preload("res://scripts/airside/runway.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")
const DeleteRunwayCmd := preload("res://scripts/core/commands/delete_runway_command.gd")
const FloorCmd := preload("res://scripts/core/commands/set_floor_command.gd")
const WallsCmd := preload("res://scripts/core/commands/set_walls_command.gd")

var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _runways: RunwaysScript
var _runner: CommandRunnerScript
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | runway placement")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	var objects := PlacedObjectsScript.new()
	_floor.placed_objects = objects
	_walls = TerminalWallsScript.new()
	_walls.placed_objects = objects
	_walls.terminal_floor = _floor
	add_child(_walls)
	objects.terminal_floor = _floor
	objects.terminal_walls = _walls
	add_child(objects)
	_runways = RunwaysScript.new()
	_runways.terminal_floor = _floor
	_floor.runways = _runways
	add_child(_runways)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = objects
	_runner.terminal_floor = _floor
	_runner.terminal_walls = _walls
	_runner.runways = _runways
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)
	Money.reset(1000000)

	var small := RunwayCatalog.get_def(&"small")
	var medium := RunwayCatalog.get_def(&"medium")
	var large := RunwayCatalog.get_def(&"large")
	_expect("three runway sizes load, smallest first", RunwayCatalog.get_all().size() == 3
		and RunwayCatalog.get_all()[0] == small and RunwayCatalog.get_all()[2] == large)
	_expect("widths are 30, 46 and 60 m (even)", small.width == 30 and medium.width == 46 and large.width == 60)
	_expect("medium handles small and medium aircraft, not large",
		medium.handles("small") and medium.handles("medium") and not medium.handles("large"))
	_expect("a large runway fits on the plot east-west",
		BuildGrid.PLOT_TILES.x >= large.max_length + large.width)

	# Medium runway, 2,000 m west to east along the corner line y = 1000.
	var start := Vector2i(1000, 1000)
	var end := Vector2i(3000, 1000)
	var before := Money.balance
	var place := PlaceRunwayCmd.new(&"medium", start, end)
	_expect("medium runway 2,000 m is built", _runner.submit(place) and _runways.get_count() == 1)
	var runway: RefCounted = _runways.get_runway(place.runway_id)
	_expect("it costs 2,000 m x the price per metre", before - Money.balance == 2000 * medium.cost_per_metre)
	_expect("length 2,000 m, width 46 m", runway.length == 2000 and runway.width == 46)
	_expect("footprint covers 2,000 x 46 tiles, centred on the grid line", runway.rect == Rect2i(1000, 977, 2000, 46))
	var a: Dictionary = runway.ends[0]
	var b: Dictionary = runway.ends[1]
	var west := BuildGrid.tile_corner_to_world(start)
	_expect("end A is the west threshold, on the centreline",
		a.position.is_equal_approx(Vector3(west.x, 0.0, west.z)))
	_expect("end A faces east (heading 90, runway 09)", a.direction.is_equal_approx(Vector3.RIGHT)
		and is_equal_approx(a.heading, 90.0) and a.designator == "09")
	_expect("end B faces west (heading 270, runway 27)", b.direction.is_equal_approx(Vector3.LEFT)
		and is_equal_approx(b.heading, 270.0) and b.designator == "27")
	_expect("ends are 2,000 m apart", is_equal_approx(a.position.distance_to(b.position), 2000.0))
	var ends := _runways.get_ends()
	_expect("get_ends() lists both ends with the runway ID and size class", ends.size() == 2
		and ends[0].runway_id == runway.id and ends[0].size_class == "medium")
	_expect("tiles under it belong to the runway", _runways.get_runway_at(Vector2i(2000, 990)) == runway.id
		and _runways.get_runway_at(Vector2i(2000, 1030)) == 0)
	_expect("the runway mesh and two designators exist", runway.node.get_node("Mesh").mesh != null
		and runway.node.get_children().filter(func(n: Node) -> bool: return n is Label3D).size() == 2)

	# Size rules
	_expect("too short is refused", not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(100, 100), Vector2i(1000, 100)))
		and _last_failed.error.begins_with("Too short"))
	_expect("too long is refused", not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(100, 100), Vector2i(2000, 100)))
		and _last_failed.error.begins_with("Too long"))
	_expect("diagonal is refused", not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(100, 100), Vector2i(1400, 600))))
	_expect("off the 10 m grid is refused",
		not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(105, 100), Vector2i(1405, 100)))
		and _last_failed.error.begins_with("Runways start and end on the 10 m grid"))
	_expect("off the plot is refused", not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(10, 10), Vector2i(1310, 10)))
		and _last_failed.error == "Doesn't fit on the plot")
	_expect("overlapping is refused", not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(2000, 500), Vector2i(2000, 1700)))
		and _last_failed.error == "Overlaps another runway")

	# North-south runway, flipped: dragged from south to north.
	var ns := PlaceRunwayCmd.new(&"small", Vector2i(500, 1700), Vector2i(500, 300))
	_expect("north-south small runway is built", _runner.submit(ns))
	var ns_runway: RefCounted = _runways.get_runway(ns.runway_id)
	_expect("dragged northwards: end A is 36, end B is 18",
		ns_runway.ends[0].designator == "36" and ns_runway.ends[1].designator == "18")

	# Floor and walls
	# 20 x 40 floor rect; its last 23 rows (y 977 to 999) are runway.
	var floor_rect := Rect2i(1990, 960, 20, 40)
	_expect("floor preview skips runway tiles (340 of 800)", _floor.count_changes(floor_rect, true) == 340)
	_expect("floor is not laid on a runway", _floor.set_rect(floor_rect, true) == 340)
	_expect("no floor ends up under the runway", _floor.count_floor_tiles(runway.rect) == 0)
	_expect("a runway over floor is refused",
		not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(1500, 960), Vector2i(2800, 960)))
		and _last_failed.error == "Blocked by terminal floor")
	_runner.submit(WallsCmd.new([[Vector2i(1200, 1600), Vector2i(1210, 1600)]], true))
	_expect("a runway over walls is refused",
		not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(1000, 1600), Vector2i(2300, 1600)))
		and _last_failed.error == "Blocked by walls")
	_expect("count_pieces_in finds the 10 wall pieces", _walls.count_pieces_in(Rect2i(1190, 1590, 30, 20)) == 10)

	# Not enough money
	Money.reset(1000)
	_expect("not enough money is refused",
		not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(3000, 1900), Vector2i(4300, 1900)))
		and _last_failed.error.begins_with("Not enough money"))
	Money.reset(1000000)

	# Delete, undo
	before = Money.balance
	_expect("deleting refunds part of the price", _runner.submit(DeleteRunwayCmd.new(runway.id))
		and Money.balance - before == Money.refund_for(2000 * medium.cost_per_metre) and _runways.get_count() == 1)
	_runner.undo_last()
	_expect("undo puts it back with the same ID and ends", _runways.get_runway(runway.id) != null
		and _runways.get_runway(runway.id).ends[0].designator == "09" and Money.balance == before)

	# Save and load
	var data := place.to_dict()
	var loaded: RefCounted = CommandRunnerScript.command_from_dict(data)
	_expect("place_runway command saves and loads", loaded != null and loaded.def_id == &"medium"
		and loaded.start == start and loaded.end == end and loaded.runway_id == runway.id)
	var del: RefCounted = CommandRunnerScript.command_from_dict(DeleteRunwayCmd.new(7).to_dict())
	_expect("delete_runway command saves and loads", del != null and del.runway_id == 7)

	_expect("designators wrap: heading 0 and 360 are 36, 5 is 01",
		RunwayScript.designator_of(0.0) == "36" and RunwayScript.designator_of(360.0) == "36"
		and RunwayScript.designator_of(5.0) == "01")

	Money.reset(Money.settings.starting_money)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

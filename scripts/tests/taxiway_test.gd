extends Node3D
## Automatic test for taxiways and the route graph (checklist step 17).
## Run this scene on its own (F6). It builds a runway and taxiways through
## commands: one crossing the runway, one ending at the runway's edge, one
## meeting that at an L corner and one on its own. It checks the graph's nodes,
## edges and routes after each, that the graph rebuilds when a taxiway is
## removed, the placement rules, floor, the overlay and saving, then prints
## PASS or FAIL for each check.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const RouteGraphScript := preload("res://scripts/airside/route_graph.gd")
const OverlayScript := preload("res://scripts/debug/route_graph_overlay.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")
const PlaceTaxiwayCmd := preload("res://scripts/core/commands/place_taxiway_command.gd")
const DeleteTaxiwayCmd := preload("res://scripts/core/commands/delete_taxiway_command.gd")

var _failures := 0
var _floor: TerminalFloorScript
var _runways: RunwaysScript
var _taxiways: TaxiwaysScript
var _graph: RouteGraphScript
var _runner: CommandRunnerScript
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | taxiways and route graph")
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	var objects := PlacedObjectsScript.new()
	_floor.placed_objects = objects
	var walls := TerminalWallsScript.new()
	walls.placed_objects = objects
	walls.terminal_floor = _floor
	add_child(walls)
	objects.terminal_floor = _floor
	objects.terminal_walls = walls
	add_child(objects)
	_runways = RunwaysScript.new()
	_runways.terminal_floor = _floor
	add_child(_runways)
	_taxiways = TaxiwaysScript.new()
	_taxiways.terminal_floor = _floor
	_taxiways.runways = _runways
	add_child(_taxiways)
	_floor.runways = _runways
	_floor.taxiways = _taxiways
	_graph = RouteGraphScript.new()
	_graph.runways = _runways
	_graph.taxiways = _taxiways
	add_child(_graph)
	var overlay := OverlayScript.new()
	overlay.route_graph = _graph
	add_child(overlay)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = objects
	_runner.terminal_floor = _floor
	_runner.terminal_walls = walls
	_runner.runways = _runways
	_runner.taxiways = _taxiways
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)
	Money.reset(1000000)

	_expect("three taxiway sizes load: 16, 24 and 26 m wide (even)", TaxiwayCatalog.get_all().map(
		func(d: Resource) -> int: return d.width) == [16, 24, 26])
	_expect("empty graph to start", _graph.get_node_count() == 0 and _graph.get_edge_count() == 0)
	_expect("tools snap to the 10 m airside grid", BuildGrid.snap_to_airside(Vector2i(1234, 1006)) == Vector2i(1230, 1010)
		and BuildGrid.snap_to_airside(Vector2i(4498, -3)) == Vector2i(4500, 0)
		and BuildGrid.is_on_airside_grid(Vector2i(20, 1990)) and not BuildGrid.is_on_airside_grid(Vector2i(25, 1990)))

	# Runway 09/27 along y = 1000 (paving y 977 to 1022).
	_runner.submit(PlaceRunwayCmd.new(&"medium", Vector2i(1000, 1000), Vector2i(3000, 1000)))
	await _rebuilt()
	_expect("runway alone: 2 nodes (09 and 27), 1 edge", _counts(2, 1))
	var end09 := _graph.find_runway_end("09")
	var end27 := _graph.find_runway_end("27")
	_expect("runway end nodes are marked 09 and 27", end09 > 0 and end27 > 0 and end09 != end27)

	# 1. Taxiway crossing the runway north to south at x = 1500.
	var before := Money.balance
	var t1 := PlaceTaxiwayCmd.new(&"medium", Vector2i(1500, 900), Vector2i(1500, 1100))
	_expect("crossing taxiway is built", _runner.submit(t1))
	_expect("it costs 200 m x the price per metre",
		before - Money.balance == 200 * TaxiwayCatalog.get_def(&"medium").cost_per_metre)
	await _rebuilt()
	_expect("crossing: 5 nodes, 4 edges (runway and taxiway both split)", _counts(5, 4))
	var crossing := _graph.nearest_node(_world(Vector2i(1500, 1000)))
	_expect("crossing node is exactly on the grid crossing (1500, 1000)",
		(_graph.nodes[crossing].position as Vector3).is_equal_approx(_world(Vector2i(1500, 1000))))
	_expect("crossing node is on the runway and the taxiway", _graph.nodes[crossing].on_runway
		and _graph.nodes[crossing].on_taxiway and _graph.get_neighbours(crossing).size() == 4)

	# 2. Taxiway from the north ending on the 10 m grid line just inside the runway edge (y = 1020).
	var t2 := PlaceTaxiwayCmd.new(&"medium", Vector2i(2000, 1200), Vector2i(2000, 1020))
	_expect("taxiway ending inside the runway edge is built", _runner.submit(t2))
	await _rebuilt()
	_expect("T at the runway: 8 nodes, 7 edges (joined through to the centreline)", _counts(8, 7))
	var far_end := _graph.nearest_node(_world(Vector2i(2000, 1200)))
	_expect("route from its far end to runway 09", _graph.find_path(far_end, _graph.find_runway_end("09")).size() >= 3)

	# 3. Taxiway east from that one's far end: an L corner.
	_expect("L-corner taxiway is built",
		_runner.submit(PlaceTaxiwayCmd.new(&"medium", Vector2i(2000, 1200), Vector2i(2500, 1200))))
	await _rebuilt()
	_expect("L corner: 9 nodes, 8 edges (the corner is one node)", _counts(9, 8))
	var corner_end := _graph.nearest_node(_world(Vector2i(2500, 1200)))
	end27 = _graph.find_runway_end("27")  # node IDs change on every rebuild
	var path := _graph.find_path(corner_end, end27)
	_expect("route from the L's end to runway 27", not path.is_empty() and path[0] == corner_end
		and path[-1] == end27)
	print("INFO | route L end -> 27: %d nodes, %.0f m: %s" % [path.size(), _graph.path_length(path),
		path.map(func(id: int) -> Vector3: return _graph.nodes[id].position)])
	_expect("route length is exactly 500 + 200 + 1,000 m", absf(_graph.path_length(path) - 1700.0) < 0.01)

	# 4. Taxiway on its own, far away.
	var t4 := PlaceTaxiwayCmd.new(&"small", Vector2i(100, 100), Vector2i(300, 100))
	_runner.submit(t4)
	await _rebuilt()
	_expect("lone taxiway: 11 nodes, 9 edges", _counts(11, 9))
	_expect("no route from the lone taxiway to the runway",
		_graph.find_path(_graph.nearest_node(_world(Vector2i(100, 100))), _graph.find_runway_end("09")).is_empty())

	# Removing rebuilds
	_runner.submit(DeleteTaxiwayCmd.new(t4.taxiway_id))
	await _rebuilt()
	_expect("removing the lone taxiway rebuilds: 9 nodes, 8 edges", _counts(9, 8))
	_runner.undo_last()
	await _rebuilt()
	_expect("undo puts it back: 11 nodes, 9 edges", _counts(11, 9))

	# Placement rules
	_expect("off the 10 m grid is refused", not _runner.submit(PlaceTaxiwayCmd.new(&"small", Vector2i(50, 50), Vector2i(55, 50)))
		and _last_failed.error.begins_with("Taxiways start and end on the 10 m grid"))
	_expect("diagonal is refused", not _runner.submit(PlaceTaxiwayCmd.new(&"small", Vector2i(50, 50), Vector2i(90, 80))))
	_expect("along inside the runway is refused",
		not _runner.submit(PlaceTaxiwayCmd.new(&"small", Vector2i(1200, 1010), Vector2i(1400, 1010)))
		and _last_failed.error.begins_with("Taxiways can cross a runway"))
	_expect("off the plot is refused", not _runner.submit(PlaceTaxiwayCmd.new(&"small", Vector2i(0, 50), Vector2i(0, 200)))
		and _last_failed.error == "Doesn't fit on the plot")

	# Floor and taxiways
	_expect("floor preview skips taxiway tiles (240 of 400)", _floor.count_changes(Rect2i(1480, 1030, 40, 10), true) == 160)
	_expect("floor preview counts runway and taxiway overlap once (488 of 600)",
		_floor.count_changes(Rect2i(1480, 1015, 40, 15), true) == 112)
	_floor.set_rect(Rect2i(600, 600, 30, 30), true)
	_expect("taxiway over floor is refused",
		not _runner.submit(PlaceTaxiwayCmd.new(&"small", Vector2i(610, 500), Vector2i(610, 700)))
		and _last_failed.error == "Blocked by terminal floor")

	# Overlay
	overlay.set_forced(true)
	_expect("overlay draws the graph while forced on", overlay.visible and overlay.mesh.get_surface_count() == 1)
	overlay.set_forced(false)
	_expect("overlay hides again", not overlay.visible)

	# Save and load
	var loaded: RefCounted = CommandRunnerScript.command_from_dict(t1.to_dict())
	_expect("place_taxiway command saves and loads", loaded != null and loaded.def_id == &"medium"
		and loaded.start == t1.start and loaded.end == t1.end and loaded.taxiway_id == t1.taxiway_id)
	var del: RefCounted = CommandRunnerScript.command_from_dict(DeleteTaxiwayCmd.new(5).to_dict())
	_expect("delete_taxiway command saves and loads", del != null and del.taxiway_id == 5)

	Money.reset(Money.settings.starting_money)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


## Waits for the graph's deferred rebuild after a change.
func _rebuilt() -> void:
	await get_tree().process_frame


func _counts(node_count: int, edge_count: int) -> bool:
	var ok := _graph.get_node_count() == node_count and _graph.get_edge_count() == edge_count
	if not ok:
		print("INFO | graph has %d nodes, %d edges" % [_graph.get_node_count(), _graph.get_edge_count()])
	return ok


func _world(corner: Vector2i) -> Vector3:
	return BuildGrid.tile_corner_to_world(corner)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

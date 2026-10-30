extends Node3D
## Automatic test for medium stands (checklist step 18).
## Run this scene on its own (F6). It lays a medium and a small taxiway, then
## places stands through commands: snapped flush against the medium taxiway on
## each side, and refused where they don't open onto a taxiway, where the
## taxiway is too small, or where they overlap. It checks the stand's size
## class, the A320 and 737-800 fitting, the route graph lead-ins, the
## connection status when the taxiway is removed and put back, and saving,
## then prints PASS or FAIL for each check.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const RouteGraphScript := preload("res://scripts/airside/route_graph.gd")
const TaxiLinesScript := preload("res://scripts/airside/taxi_lines.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceTaxiLineCmd := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const SetPavingCmd := preload("res://scripts/core/commands/set_paving_command.gd")
const PlaceStandCmd := preload("res://scripts/core/commands/place_stand_command.gd")
const DeleteStandCmd := preload("res://scripts/core/commands/delete_stand_command.gd")
## 24 m of taxiway paving along y = 1000, the width a medium stand needs.
const MEDIUM_PAVING := Rect2i(1000, 988, 400, 24)

var _failures := 0
var _floor: TerminalFloorScript
var _taxiways: TaxiwaysScript
var _stands: StandsScript
var _graph: RouteGraphScript
var _runner: CommandRunnerScript
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | medium stands")
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
	var runways := RunwaysScript.new()
	runways.terminal_floor = _floor
	add_child(runways)
	_taxiways = TaxiwaysScript.new()
	_taxiways.terminal_floor = _floor
	_taxiways.runways = runways
	add_child(_taxiways)
	_stands = StandsScript.new()
	_stands.terminal_floor = _floor
	_stands.runways = runways
	_stands.taxiways = _taxiways
	add_child(_stands)
	_taxiways.stands = _stands
	runways.stands = _stands
	_floor.runways = runways
	_floor.taxiways = _taxiways
	_floor.stands = _stands
	var lines := TaxiLinesScript.new()
	lines.taxiways = _taxiways
	lines.runways = runways
	add_child(lines)
	_graph = RouteGraphScript.new()
	_graph.runways = runways
	_graph.taxi_lines = lines
	_graph.stands = _stands
	add_child(_graph)
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = objects
	_runner.terminal_floor = _floor
	_runner.terminal_walls = walls
	_runner.runways = runways
	_runner.taxiways = _taxiways
	_runner.stands = _stands
	_runner.taxi_lines = lines
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)
	Money.reset(1000000)

	var def := StandCatalog.get_def(&"medium")
	_expect("medium stand loads: narrow-body class, 50 x 70 m, needs a medium taxiway", def != null
		and def.size_class == "narrow_body" and def.get_size() == Vector2i(50, 70) and def.get_taxiway_class() == "medium")
	_expect("A320 and 737-800 fit the medium stand", def.takes(&"a320") and def.takes(&"b738")
		and def.get_fitting_types().size() == 2)

	# Paving 24 m wide along y = 1000 (y 988 to 1012), and 16 m wide along y = 1500.
	_runner.submit(SetPavingCmd.new(MEDIUM_PAVING, true))
	_runner.submit(SetPavingCmd.new(Rect2i(1000, 1492, 400, 16), true))
	# Aircraft follow taxi lines, so paint one down the middle of each.
	_runner.submit(PlaceTaxiLineCmd.new(Vector2i(1000, 1000), Vector2i(1400, 1000)))
	_runner.submit(PlaceTaxiLineCmd.new(Vector2i(1000, 1500), Vector2i(1400, 1500)))
	await _rebuilt()

	# Snapping: entry edge flush with the taxiway's near edge, centreline on the 10 m grid.
	var south := _stands.snap_anchor(def, _world(Vector2i(1203, 950)), 0)
	_expect("stand south of the taxiway snaps flush to its edge (1200, 988)", south == Vector2i(1200, 988))
	var north := _stands.snap_anchor(def, _world(Vector2i(1298, 1052)), 2)
	_expect("stand north of the taxiway snaps flush to its edge (1300, 1012)", north == Vector2i(1300, 1012))
	_expect("footprint: 50 wide along the taxiway, 70 deep behind it",
		StandsScript.footprint(def, south, 0) == Rect2i(1175, 918, 50, 70)
		and StandsScript.footprint(def, Vector2i(1500, 700), 3) == Rect2i(1430, 675, 70, 50))

	var money_before := Money.balance
	var s1 := PlaceStandCmd.new(&"medium", south, 0)
	_expect("stand facing the medium taxiway is placed", _runner.submit(s1))
	_expect("it costs %s" % Money.format(def.cost), Money.balance == money_before - def.cost)
	var stand: RefCounted = _stands.get_stand(s1.stand_id)
	_expect("it is connected to the taxiway", stand.has_taxiway())
	_expect("label shows number, size class and connection", stand.label.text.contains("Stand %d" % stand.id)
		and stand.label.text.contains("narrow-body") and stand.label.text.contains("Connected to a taxiway"))
	await _rebuilt()
	# Taxi line: 1000, 1200 (joins the lead-in), 1400. Stand: stop bar and entry edge.
	_expect("graph: 5 nodes, 4 edges with one stand (plus the small taxiway's 2 and 1)", _counts(7, 5))
	var stop_node := _graph.find_stand(stand.id)
	var end_node := _graph.nearest_node(_world(Vector2i(1400, 1000)))
	_expect("stand's stop bar is a graph node", stop_node >= 0)
	_expect("route from the stand to the end of the taxiway", not _graph.find_path(stop_node, end_node).is_empty())
	_expect("lead-in edges are kind 'stand'", _graph.edges.values().filter(
		func(e: Dictionary) -> bool: return e.kind == "stand").size() == 2)

	var s2 := PlaceStandCmd.new(&"medium", north, 2)
	_expect("stand on the other side of the taxiway is placed", _runner.submit(s2))
	await _rebuilt()
	_expect("graph: second stand adds 3 nodes and 3 edges", _counts(10, 8))

	# Placement rules
	var medium_def := StandCatalog.get_def(&"medium")
	_expect("a stand away from any taxiway would not be connected",
		_stands.connection_problem(medium_def, Vector2i(2000, 500), 0) == "Entry doesn't open onto a taxiway")
	_expect("a stand facing a small taxiway would not be connected",
		_stands.connection_problem(medium_def, Vector2i(1200, 1492), 0) == "Needs 24 m of taxiway in front (16 m here)")
	var free := PlaceStandCmd.new(&"medium", Vector2i(2000, 500), 0)
	_expect("a stand away from any taxiway can still be placed, not connected",
		_runner.submit(free) and not _stands.get_stand(free.stand_id).has_taxiway()
		and _stands.get_stand(free.stand_id).label.text.contains("Not connected"))
	await _rebuilt()
	_expect("it has no route to a taxiway", _graph.get_neighbours(_graph.find_stand(free.stand_id)).size() == 1)
	_runner.undo_last()
	await _rebuilt()
	_expect("stand overlapping another stand is refused",
		not _runner.submit(PlaceStandCmd.new(&"medium", Vector2i(1220, 988), 0))
		and _last_failed.error == "Overlaps another stand")
	_expect("stand overlapping a taxiway is refused",
		not _runner.submit(PlaceStandCmd.new(&"medium", Vector2i(1100, 1010), 0))
		and _last_failed.error == "Overlaps a taxiway")
	_expect("paving skips stand tiles", _taxiways.count_changes(stand.rect, true) == 0)
	_expect("no floor is laid on a stand", _floor.set_rect(stand.rect, true) == 0)

	# Taxiway removed: stand stays, not connected; put back: connected again.
	_runner.submit(SetPavingCmd.new(MEDIUM_PAVING, false))
	await _rebuilt()
	_expect("removing the taxiway leaves the stand not connected", _stands.get_count() == 2
		and not stand.has_taxiway() and stand.label.text.contains("Not connected"))
	_expect("unconnected stand has no route", _graph.find_stand(stand.id) >= 0
		and _graph.get_neighbours(_graph.find_stand(stand.id)).size() == 1)
	_runner.undo_last()
	await _rebuilt()
	_expect("putting the taxiway back reconnects it", stand.has_taxiway() and _counts(10, 8))

	# Delete
	money_before = Money.balance
	_expect("stand can be deleted", _runner.submit(DeleteStandCmd.new(s2.stand_id)) and _stands.get_count() == 1)
	_expect("deleting refunds part of the price", Money.balance == money_before + Money.refund_for(def.cost))
	await _rebuilt()
	_expect("graph drops its lead-in", _counts(7, 5))

	# Save and load
	var loaded: RefCounted = CommandRunnerScript.command_from_dict(s1.to_dict())
	_expect("place_stand command saves and loads", loaded != null and loaded.def_id == &"medium"
		and loaded.anchor == s1.anchor and loaded.facing == 0 and loaded.stand_id == s1.stand_id)
	var del: RefCounted = CommandRunnerScript.command_from_dict(DeleteStandCmd.new(5).to_dict())
	_expect("delete_stand command saves and loads", del != null and del.stand_id == 5)

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

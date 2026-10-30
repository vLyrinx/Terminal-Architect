extends Node3D
## Automatic test for taxiway paving, runway ramps, taxi lines and the route
## graph (checklist step 17, reworked to Airport CEO style).
## Run this scene on its own (F6). It builds a runway, then through commands: a
## straight ramp, taxiway paving laid tile by tile (which adds nothing to the
## graph on its own), taxi lines on the paving (which do, sized by how wide the
## paving is), a 45 degree line, an angled ramp, and removes paving to check
## lines on it stop being used. It checks the
## graph's nodes, edges and routes after each, the placement rules, floor,
## the overlay and saving, then prints PASS or FAIL for each check.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const RampsScript := preload("res://scripts/airside/ramps.gd")
const TaxiLinesScript := preload("res://scripts/airside/taxi_lines.gd")
const RouteGraphScript := preload("res://scripts/airside/route_graph.gd")
const OverlayScript := preload("res://scripts/debug/route_graph_overlay.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")
const SetPavingCmd := preload("res://scripts/core/commands/set_paving_command.gd")
const PlaceRampCmd := preload("res://scripts/core/commands/place_ramp_command.gd")
const DeleteRampCmd := preload("res://scripts/core/commands/delete_ramp_command.gd")
const PlaceTaxiLineCmd := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const DeleteTaxiLinesCmd := preload("res://scripts/core/commands/delete_taxi_lines_command.gd")
const CutTaxiLinesCmd := preload("res://scripts/core/commands/cut_taxi_lines_command.gd")

var _failures := 0
var _floor: TerminalFloorScript
var _runways: RunwaysScript
var _taxiways: TaxiwaysScript
var _ramps: RampsScript
var _lines: TaxiLinesScript
var _graph: RouteGraphScript
var _runner: CommandRunnerScript
var _last_failed: RefCounted


func _ready() -> void:
	print("TEST START | taxiways, ramps, taxi lines and route graph")
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
	_ramps = RampsScript.new()
	_ramps.terminal_floor = _floor
	_ramps.runways = _runways
	add_child(_ramps)
	_lines = TaxiLinesScript.new()
	_lines.taxiways = _taxiways
	_lines.ramps = _ramps
	_lines.runways = _runways
	add_child(_lines)
	_floor.runways = _runways
	_floor.taxiways = _taxiways
	_floor.ramps = _ramps
	_taxiways.ramps = _ramps
	_runways.taxiways = _taxiways
	_graph = RouteGraphScript.new()
	_graph.runways = _runways
	_graph.ramps = _ramps
	_graph.taxi_lines = _lines
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
	_runner.ramps = _ramps
	_runner.taxi_lines = _lines
	add_child(_runner)
	_runner.command_failed.connect(func(command: RefCounted) -> void: _last_failed = command)
	Money.reset(1000000)

	_expect("three taxiway sizes load: 5, 24 and 26 m wide", TaxiwayCatalog.get_all().map(
		func(d: Resource) -> int: return d.width) == [5, 24, 26])
	_expect("six ramps load: straight and angled in each taxiway size", RampCatalog.get_all().size() == 6
		and RampCatalog.get_def(&"medium_angled").shape == "angled" and RampCatalog.get_def(&"medium_straight").width == 24)
	_expect("empty graph to start", _graph.get_node_count() == 0 and _graph.get_edge_count() == 0)

	# Runway 09/27 along y = 1000 (paving y 977 to 1023).
	_runner.submit(PlaceRunwayCmd.new(&"medium", Vector2i(1000, 1000), Vector2i(3000, 1000)))
	await _rebuilt()
	_expect("runway alone: 2 nodes (09 and 27), 1 edge", _counts(2, 1))
	var runway_id: int = _runways.get_ids()[0]

	# Straight ramp south of the runway at x = 1500: outer end 23 + 40 m out, rounded to 70.
	var straight := RampCatalog.get_def(&"medium_straight")
	var target := _ramps.snap(straight, Vector2(1503, 1040))
	_expect("ramp snaps to the runway's south side, outer end on the grid at (1500, 1070)",
		target.get("runway_id", 0) == runway_id and target.get("anchor") == Vector2i(1500, 1070))
	_expect("on the north side it goes to (1500, 930)", _ramps.snap(straight, Vector2(1497, 960)).get("anchor")
		== Vector2i(1500, 930))
	var before := Money.balance
	var r1 := PlaceRampCmd.new(&"medium_straight", runway_id, Vector2i(1500, 1070), 1)
	_expect("straight ramp is built", _runner.submit(r1))
	_expect("it costs %s" % Money.format(straight.cost), before - Money.balance == straight.cost)
	await _rebuilt()
	_expect("ramp line joins the runway centreline: 4 nodes, 3 edges", _counts(4, 3))
	var join := _graph.nearest_node(_world(Vector2i(1500, 1000)))
	_expect("join node is on the runway and the ramp", _graph.nodes[join].on_runway and _graph.nodes[join].on_taxiway
		and (_graph.nodes[join].position as Vector3).is_equal_approx(_world(Vector2i(1500, 1000))))
	_expect("ramp has a RWY AHEAD sign", _ramps.get_ramp(r1.ramp_id).node.get_node("Sign").text == "RWY AHEAD")

	# Paving on its own adds nothing. 24 m wide, from the ramp's end south to y = 1300.
	before = Money.balance
	var south_paving := Rect2i(1488, 1070, 24, 230)
	_expect("paving is laid tile by tile", _runner.submit(SetPavingCmd.new(south_paving, true))
		and _taxiways.count_paved_in(south_paving) == 24 * 230)
	_expect("it costs %s a tile" % Money.format(Money.settings.taxiway_tile_cost),
		before - Money.balance == 24 * 230 * Money.settings.taxiway_tile_cost)
	await _rebuilt()
	_expect("taxiway paving alone adds nothing to the graph", _counts(4, 3))
	_expect("paving can be trimmed 1 m at a time",
		_runner.submit(SetPavingCmd.new(Rect2i(1488, 1299, 24, 1), false)) and not _taxiways.is_paved(Vector2i(1500, 1299)))
	_runner.undo_last()
	_expect("line ends snap to the ramp's end nearby", _lines.snap_end(Vector2i(1502, 1068), 4.0) == Vector2i(1500, 1070))

	# Taxi line down the middle of it, from the ramp's end.
	before = Money.balance
	var l1 := PlaceTaxiLineCmd.new(Vector2i(1500, 1070), Vector2i(1500, 1300))
	_expect("taxi line on the paving is painted", _runner.submit(l1))
	_expect("it costs 230 m x %s" % Money.format(Money.settings.taxi_line_cost_per_metre),
		before - Money.balance == 230 * Money.settings.taxi_line_cost_per_metre)
	_expect("24 m of paving takes medium aircraft", _lines.get_line(l1.line_id).size_class == "medium")
	await _rebuilt()
	_expect("taxi line joins the ramp: 5 nodes, 4 edges", _counts(5, 4))
	var line_end := _graph.nearest_node(_world(Vector2i(1500, 1300)))
	var path := _graph.find_path(line_end, _graph.find_runway_end("09"))
	_expect("route from the line's end to runway 09 is 230 + 70 + 500 m",
		not path.is_empty() and absf(_graph.path_length(path) - 800.0) < 0.01)

	# L corner: paving and a line east along y = 1300.
	_runner.submit(SetPavingCmd.new(Rect2i(1500, 1288, 300, 24), true))
	var l2 := PlaceTaxiLineCmd.new(Vector2i(1500, 1300), Vector2i(1800, 1300))
	_expect("line round the L corner is painted", _runner.submit(l2))
	await _rebuilt()
	_expect("L corner: 6 nodes, 5 edges (the corner is one node)", _counts(6, 5))

	# 45 degree line cutting the corner.
	var l3 := PlaceTaxiLineCmd.new(Vector2i(1500, 1290), Vector2i(1510, 1300))
	_expect("45 degree line across the corner is painted", _runner.submit(l3))
	await _rebuilt()
	_expect("it splits both lines it meets: 8 nodes, 8 edges", _counts(8, 8))

	# Line rules
	_expect("line off the paving is refused",
		not _runner.submit(PlaceTaxiLineCmd.new(Vector2i(1600, 1100), Vector2i(1700, 1100)))
		and _last_failed.error == "Taxi lines go on taxiway paving")
	_expect("line onto the runway is refused",
		not _runner.submit(PlaceTaxiLineCmd.new(Vector2i(1500, 1070), Vector2i(1500, 990)))
		and _last_failed.error.begins_with("Taxi lines can't go on a runway"))
	_runner.submit(SetPavingCmd.new(Rect2i(2000, 1500, 200, 4), true))
	_expect("line on paving only 4 m wide is refused",
		not _runner.submit(PlaceTaxiLineCmd.new(Vector2i(2000, 1502), Vector2i(2200, 1502)))
		and _last_failed.error.begins_with("Paving is only 4 m wide here"))
	_runner.submit(SetPavingCmd.new(Rect2i(2000, 1504, 200, 1), true))
	var narrow := PlaceTaxiLineCmd.new(Vector2i(2000, 1502), Vector2i(2200, 1502))
	_expect("widened to 5 m it takes a line for small aircraft, off the 10 m grid",
		_runner.submit(narrow) and _lines.get_line(narrow.line_id).size_class == "small")
	_runner.undo_last()
	_expect("line at an odd angle is refused",
		not _runner.submit(PlaceTaxiLineCmd.new(Vector2i(1500, 1100), Vector2i(1510, 1130)))
		and _last_failed.error.begins_with("Taxi lines run along the grid or at 45 degrees"))

	# Paving removed under a line: it stays but isn't used; put back: used again.
	_runner.submit(SetPavingCmd.new(Rect2i(1512, 1288, 288, 24), false))
	await _rebuilt()
	_expect("line off its paving is kept but not usable", _lines.get_count() == 3
		and not _lines.get_line(l2.line_id).is_usable() and _lines.get_line(l3.line_id).is_usable())
	_expect("graph drops it: 7 nodes, 6 edges", _counts(7, 6))
	_runner.undo_last()
	await _rebuilt()
	_expect("paving back: line usable again, 8 nodes, 8 edges", _lines.get_line(l2.line_id).is_usable() and _counts(8, 8))

	# Removing lines
	before = Money.balance
	_expect("lines near a drag are found and removed", _runner.submit(DeleteTaxiLinesCmd.new(
		_lines.get_lines_near(Vector2(1600, 1302), Vector2(1700, 1302), 3.0))) and _lines.get_line(l2.line_id) == null)
	_expect("removing refunds part of the price", Money.balance - before == Money.refund_for(
		300 * Money.settings.taxi_line_cost_per_metre))
	_runner.undo_last()
	await _rebuilt()
	_expect("undo paints it back with the same ID", _lines.get_line(l2.line_id) != null and _counts(8, 8))

	# Cutting part of a line: drag along it, or click on it.
	before = Money.balance
	var cut := CutTaxiLinesCmd.new(Vector2i(1600, 1300), Vector2i(1610, 1300))
	_expect("dragging along a line removes only the 10 m dragged over",
		_runner.submit(cut) and _lines.get_line(l2.line_id) == null and cut.piece_ids.size() == 2
		and _has_line(Vector2i(1500, 1300), Vector2i(1600, 1300)) and _has_line(Vector2i(1610, 1300), Vector2i(1800, 1300)))
	_expect("cutting refunds part of the price of 10 m", Money.balance - before == Money.refund_for(
		10 * Money.settings.taxi_line_cost_per_metre))
	await _rebuilt()
	_expect("the gap splits the route: no path from the far piece to runway 09", _graph.find_path(
		_graph.nearest_node(_world(Vector2i(1800, 1300))), _graph.find_runway_end("09")).is_empty())
	var click := CutTaxiLinesCmd.new(Vector2i(1700, 1300), Vector2i(1700, 1300))
	_expect("clicking on a line removes the 2 m around the click",
		_runner.submit(click) and _has_line(Vector2i(1610, 1300), Vector2i(1699, 1300))
		and _has_line(Vector2i(1701, 1300), Vector2i(1800, 1300)))
	_runner.undo_last()
	_runner.undo_last()
	await _rebuilt()
	_expect("undo puts the whole line back with its ID", _lines.get_line(l2.line_id) != null
		and _lines.get_line(l2.line_id).a == Vector2i(1500, 1300) and _counts(8, 8))
	_expect("a cut away from any line does nothing",
		not _runner.submit(CutTaxiLinesCmd.new(Vector2i(1700, 1200), Vector2i(1720, 1200))))
	_expect("removing a drag snaps to the nearest line", _lines.snap_to_line(Vector2i(1650, 1302), 3.0) == Vector2i(1650, 1300))

	# Ramp removed: the network is cut off from the runway; undo joins it again.
	_runner.submit(DeleteRampCmd.new(r1.ramp_id))
	await _rebuilt()
	_expect("without the ramp there is no route to the runway",
		_graph.find_path(_graph.nearest_node(_world(Vector2i(1500, 1300))), _graph.find_runway_end("09")).is_empty())
	_runner.undo_last()
	await _rebuilt()
	_expect("ramp back: route to the runway again",
		not _graph.find_path(_graph.nearest_node(_world(Vector2i(1500, 1300))), _graph.find_runway_end("09")).is_empty())

	# Angled ramp north of the runway, leaning east: rapid exit for aircraft landing on 09.
	var angled := RampCatalog.get_def(&"medium_angled")
	var a_anchor: Vector2i = _ramps.snap(angled, Vector2(2502, 950)).anchor
	_expect("angled ramp's outer end is 23 + 60 m out, rounded to 90: (2500, 910)", a_anchor == Vector2i(2500, 910))
	var r2 := PlaceRampCmd.new(&"medium_angled", runway_id, a_anchor, 1)
	_expect("angled ramp is built", _runner.submit(r2))
	await _rebuilt()
	var exit_end := _graph.nearest_node(_world(a_anchor))
	var turn_off := _graph.nearest_node(_world(Vector2i(2390, 1000)))
	_expect("its line starts on the runway centreline 110 m before the exit",
		(_graph.nodes[turn_off].position as Vector3).is_equal_approx(_world(Vector2i(2390, 1000)))
		and _graph.nodes[turn_off].on_runway and _graph.nodes[turn_off].on_taxiway)
	_expect("route from its outer end to runway 27", not _graph.find_path(exit_end, _graph.find_runway_end("27")).is_empty())
	var ramp_line: PackedVector2Array = _ramps.get_ramp(r2.ramp_id).get_corner_points()
	var longest := Vector2.ZERO
	for i in range(1, ramp_line.size()):
		if ramp_line[i].distance_to(ramp_line[i - 1]) > longest.length():
			longest = ramp_line[i] - ramp_line[i - 1]
	_expect("its longest part runs north-east at 45 degrees", longest.x > 0.0 and longest.y < 0.0
		and absf(absf(longest.x) - absf(longest.y)) < 0.01)

	# Ramp rules
	_expect("ramp on top of another is refused",
		not _runner.submit(PlaceRampCmd.new(&"medium_straight", runway_id, Vector2i(1500, 1070), 1))
		and _last_failed.error == "Overlaps another ramp")
	_expect("ramp not against the runway is refused",
		not _runner.submit(PlaceRampCmd.new(&"medium_straight", runway_id, Vector2i(1800, 1080), 1))
		and _last_failed.error == "Ramps sit against the side of a runway")
	_expect("ramp at the very end of the runway is refused",
		not _runner.submit(PlaceRampCmd.new(&"medium_straight", runway_id, Vector2i(1010, 1070), 1))
		and _last_failed.error == "Too close to the end of the runway")
	_runner.submit(SetPavingCmd.new(Rect2i(1190, 900, 20, 200), true))
	var runway_rect: Rect2i = _runways.get_runway(runway_id).rect
	_expect("paving skips runway tiles", _taxiways.count_paved_in(runway_rect) == 0
		and _taxiways.is_paved(Vector2i(1195, 960)) and _taxiways.is_paved(Vector2i(1195, 1050)))
	_expect("paving skips ramp tiles", _taxiways.count_changes(Rect2i(1495, 1030, 10, 30), true) == 0)
	_expect("a runway over paving is refused",
		not _runner.submit(PlaceRunwayCmd.new(&"small", Vector2i(1000, 1300), Vector2i(2600, 1300)))
		and _last_failed.error == "Blocked by taxiway paving")

	# Floor
	var ramp_rect: Rect2i = _ramps.get_ramp(r1.ramp_id).rect
	_expect("no floor is laid on a ramp", _floor.count_changes(ramp_rect, true) == 0)

	# Overlay
	overlay.set_forced(true)
	_expect("overlay draws the graph while forced on", overlay.visible and overlay.mesh.get_surface_count() == 1)
	overlay.set_forced(false)
	_expect("overlay hides again", not overlay.visible)

	# Save and load
	var loaded: RefCounted = CommandRunnerScript.command_from_dict(r2.to_dict())
	_expect("place_ramp command saves and loads", loaded != null and loaded.def_id == &"medium_angled"
		and loaded.runway_id == runway_id and loaded.anchor == a_anchor and loaded.lean == 1 and loaded.ramp_id == r2.ramp_id)
	loaded = CommandRunnerScript.command_from_dict(DeleteRampCmd.new(4).to_dict())
	_expect("delete_ramp command saves and loads", loaded != null and loaded.ramp_id == 4)
	loaded = CommandRunnerScript.command_from_dict(l3.to_dict())
	_expect("place_taxi_line command saves and loads", loaded != null and loaded.a == l3.a and loaded.b == l3.b
		and loaded.line_id == l3.line_id)
	loaded = CommandRunnerScript.command_from_dict(DeleteTaxiLinesCmd.new([2, 5] as Array[int]).to_dict())
	_expect("delete_taxi_lines command saves and loads", loaded != null and loaded.line_ids == [2, 5])
	var saved_cut := CutTaxiLinesCmd.new(Vector2i(1, 2), Vector2i(3, 2))
	saved_cut.piece_ids = [7, 8] as Array[int]
	loaded = CommandRunnerScript.command_from_dict(saved_cut.to_dict())
	_expect("cut_taxi_lines command saves and loads", loaded != null and loaded.a == Vector2i(1, 2)
		and loaded.b == Vector2i(3, 2) and loaded.piece_ids == [7, 8])
	loaded = CommandRunnerScript.command_from_dict(SetPavingCmd.new(south_paving, false).to_dict())
	_expect("set_paving command saves and loads", loaded != null and loaded.rect == south_paving and not loaded.paved)

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


## True if a line runs from a to b (either way round).
func _has_line(a: Vector2i, b: Vector2i) -> bool:
	for line: RefCounted in _lines.get_all():
		if (line.a == a and line.b == b) or (line.a == b and line.b == a):
			return true
	return false


func _world(corner: Vector2i) -> Vector3:
	return BuildGrid.tile_corner_to_world(corner)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

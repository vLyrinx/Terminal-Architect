extends Node
## Basic alerts (checklist step 38): watches for problems and raises them on
## the Alerts list (alerts.gd).
##
## Flight problems come from signals, one alert per flight:
##   no free stand    (StandAllocator.allocation_failed)
##   no runway        (AirTraffic.runway_missing)
##   no taxi route    (AirTraffic.taxi_route_missing)
## Terminal problems are checked every CHECK_MINUTES game minutes, but only
## while passengers are expected (a departure with passengers within
## LOOKAHEAD, or passengers in the terminal):
##   no terminal entrance, no check-in desk, no security scanner, no gate desk,
##   no path from an entrance through security to a gate, and no way out from
##   the apron doors to an entrance (arriving and missed passengers walk out
##   that way, and scanners block the doors they stand in).
## A terminal problem is resolved once it is fixed, so it alerts again if it
## comes back.

const AlertsScript := preload("res://scripts/ui/alerts.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const Level := AlertsScript.Level
const LANDSIDE := TerminalPathsScript.Access.LANDSIDE
const AIRSIDE := TerminalPathsScript.Access.AIRSIDE
const ARRIVALS := TerminalPathsScript.Access.ARRIVALS

const CHECK_MINUTES := 10
const LOOKAHEAD := 3 * 3600

@export var alerts: AlertsScript
## All optional.
@export var stand_allocator: Node
@export var air_traffic: Node
@export var terminal_paths: TerminalPathsScript
@export var placed_objects: Node3D
@export var spawner: Node
@export var check_in: Node
@export var security: Node
@export var gates: Node
@export var floor_index := 0

## Gate id -> true if passengers can get there from an entrance, worked out
## again when the layout changes.
var _routes := {}
## False if no apron door leads through the building to an entrance.
var _way_out := true
var _routes_dirty := true


func _ready() -> void:
	if stand_allocator != null:
		stand_allocator.allocation_failed.connect(func(f: FlightScript) -> void:
			alerts.raise_alert("stand:%s" % f.flight_number, "No free stand for %s (%s) arriving %s" % [
				f.flight_number, _type_name(f), f.get_time_string()], Level.PROBLEM))
	if air_traffic != null:
		air_traffic.runway_missing.connect(func(f: FlightScript) -> void:
			alerts.raise_alert("runway:%s" % f.flight_number, "No runway long enough for %s (%s)" % [
				f.flight_number, _type_name(f)], Level.PROBLEM))
		air_traffic.taxi_route_missing.connect(func(f: FlightScript) -> void:
			alerts.raise_alert("taxi:%s" % f.flight_number, "No taxi route for %s between the runway and stand %s" % [
				f.flight_number, str(f.stand_id) if f.stand_id >= 0 else "-"], Level.PROBLEM))
	if terminal_paths != null:
		terminal_paths.paths_changed.connect(func() -> void: _routes_dirty = true)
	if placed_objects != null:
		for s: Signal in [placed_objects.object_added, placed_objects.object_removed, placed_objects.object_moved]:
			s.connect(func(_id: int) -> void: _routes_dirty = true)
	GameClock.minute_passed.connect(func(minute: int) -> void:
		if minute % CHECK_MINUTES == 0:
			check_terminal())


## Checks the terminal now and raises or resolves its alerts.
func check_terminal() -> void:
	if not _passengers_expected():
		return
	var entrances: Array = spawner.get_entrances() if spawner != null else []
	var desks: Array = check_in.get_desks() if check_in != null else []
	var scanners: Array = security.get_scanners() if security != null else []
	var gate_list: Array = gates.get_gates() if gates != null else []
	_set_problem("no_entrance", entrances.is_empty() and spawner != null,
		"No terminal entrance: build a door from outside into landside floor")
	_set_problem("no_checkin", desks.is_empty() and check_in != null,
		"No check-in desk: passengers can't check in")
	_set_problem("no_security", scanners.is_empty() and security != null,
		"No security scanner: passengers can't get airside")
	_set_problem("no_gate", gate_list.is_empty() and gates != null,
		"No gate desk on airside: passengers can't board")
	if entrances.is_empty() or scanners.is_empty() or gate_list.is_empty() or terminal_paths == null:
		return
	if _routes_dirty:
		_routes_dirty = false
		_routes = {}
		for gate in gate_list:
			_routes[gate.id] = _can_reach(gate, entrances, scanners)
		_way_out = _has_way_out(entrances)
	for gate in gate_list:
		_set_problem("path:%d" % gate.id, not _routes.get(gate.id, true),
			"No path from the entrance to gate #%d" % gate.id)
	_set_problem("way_out", not _way_out,
		"No way out from the apron doors to an exit: arriving passengers are stuck (build a door from airside to landside that no scanner stands in)")


## True if a passenger can walk from some entrance to some scanner on
## landside, and from that scanner's exit to the gate on airside.
func _can_reach(gate: RefCounted, entrances: Array, scanners: Array) -> bool:
	for s in scanners:
		if not terminal_paths.can_reach(s.exit, gate.board_point, AIRSIDE):
			continue
		for e: Dictionary in entrances:
			var inside := BuildGrid.tile_to_world(e.inside, floor_index)
			if not terminal_paths.find_path(inside, s.service, LANDSIDE).is_empty():
				return true
	return false


## True if there is no apron door, or one of them leads to an entrance.
func _has_way_out(entrances: Array) -> bool:
	var doors: Array = gates.get_apron_doors() if gates != null else []
	if doors.is_empty():
		return true
	for door: Dictionary in doors:
		var from := BuildGrid.tile_to_world(door.inside, floor_index)
		for e: Dictionary in entrances:
			if terminal_paths.can_reach(from, BuildGrid.tile_to_world(e.inside, floor_index), ARRIVALS):
				return true
	return false


func _set_problem(key: String, problem: bool, text: String) -> void:
	if problem:
		alerts.raise_alert(key, text, Level.WARNING)
	else:
		alerts.resolve(key)


## A departure with passengers is due within LOOKAHEAD, or passengers are in the terminal.
func _passengers_expected() -> bool:
	var now := GameClock.game_time
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.scheduled_time > now + LOOKAHEAD:
			break
		if not f.is_arrival() and f.scheduled_time >= now and not f.passengers.is_empty():
			return true
	return spawner != null and not spawner.get_all_passengers().is_empty()


func _type_name(f: FlightScript) -> String:
	var type: Resource = AircraftCatalog.get_type(f.aircraft_type)
	return type.display_name if type else String(f.aircraft_type)

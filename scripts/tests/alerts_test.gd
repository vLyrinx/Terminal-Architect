extends Node3D
## Test for basic alerts (checklist step 38).
## Run this scene on its own (F6). It builds the 40 x 24 m terminal of the
## security test (landside, security, airside, entrance in the south wall)
## with nothing in it, then adds things step by step and runs the terminal
## check each time. Stand-ins for StandAllocator and AirTraffic send their
## "no free stand" and "no runway" signals.
## It checks that empty terminals raise "no check-in desk", "no security
## scanner" and "no gate desk", that a gate desk walled off in its own room
## raises "no path from the entrance to gate #N" and that a door fixes it,
## that fixed problems are resolved, that the same alert isn't repeated, and
## that alerts show on screen (at most 5), fade out, and can be dismissed.
## Prints PASS or FAIL for each check.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const TerminalPathsScript := preload("res://scripts/passengers/terminal_paths.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const CheckInScript := preload("res://scripts/passengers/check_in.gd")
const SecurityScript := preload("res://scripts/passengers/security.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const AlertsScript := preload("res://scripts/ui/alerts.gd")
const AirportChecksScript := preload("res://scripts/ui/airport_checks.gd")
const UITheme := preload("res://scripts/ui/ui_theme.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone

const B := Vector2i(2240, 990)
const SIZE := Vector2i(40, 24)
const SECURITY_X := 20
const AIRSIDE_X := 28
const BACK_WALL_X := 26
const ENTRANCE := Vector2i(10, 24)
const DESK := Vector2i(3, 6)
const SCANNER := Vector2i(24, 12)
## A room on airside (corners) holding the gate desk, and the door that opens it up.
const ROOM_MIN := Vector2i(31, 2)
const ROOM_MAX := Vector2i(40, 10)
const ROOM_DOOR := Vector2i(31, 6)
const GATE := Vector2(35.5, 6.0)


class FakeAllocator:
	extends Node
	@warning_ignore("unused_signal")
	signal allocation_failed(flight: FlightScript)


class FakeAirTraffic:
	extends Node
	@warning_ignore("unused_signal")
	signal runway_missing(flight: FlightScript)
	@warning_ignore("unused_signal")
	signal taxi_route_missing(flight: FlightScript)


var _failures := 0
var _floor: TerminalFloorScript
var _walls: TerminalWallsScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _paths: TerminalPathsScript
var _alerts: AlertsScript
var _checks: AirportChecksScript
var _raised: Array[String] = []


func _ready() -> void:
	print("TEST START | basic alerts")
	GameClock.set_paused(true)
	_build_terminal()
	_paths = TerminalPathsScript.new()
	_paths.terminal_floor = _floor
	_paths.terminal_walls = _walls
	_paths.terminal_zones = _zones
	_paths.placed_objects = _objects
	add_child(_paths)
	var crowd := PassengerCrowdScript.new()
	add_child(crowd)
	var spawner := PassengerSpawnerScript.new()
	spawner.terminal_floor = _floor
	spawner.terminal_walls = _walls
	spawner.terminal_zones = _zones
	spawner.terminal_paths = _paths
	spawner.crowd = crowd
	add_child(spawner)
	var check_in := CheckInScript.new()
	check_in.placed_objects = _objects
	check_in.terminal_floor = _floor
	check_in.terminal_walls = _walls
	check_in.terminal_zones = _zones
	check_in.terminal_paths = _paths
	check_in.spawner = spawner
	add_child(check_in)
	var security := SecurityScript.new()
	security.placed_objects = _objects
	security.terminal_floor = _floor
	security.terminal_walls = _walls
	security.terminal_zones = _zones
	security.terminal_paths = _paths
	security.spawner = spawner
	security.check_in = check_in
	add_child(security)
	var gates := GatesScript.new()
	gates.placed_objects = _objects
	gates.terminal_floor = _floor
	gates.terminal_walls = _walls
	gates.terminal_zones = _zones
	gates.terminal_paths = _paths
	gates.spawner = spawner
	gates.security = security
	add_child(gates)
	var allocator := FakeAllocator.new()
	add_child(allocator)
	var air := FakeAirTraffic.new()
	add_child(air)

	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.build()
	ui.add_child(root)
	_alerts = AlertsScript.new()
	root.add_child(_alerts)
	_alerts.alert_raised.connect(func(key: String, _text: String, _level: int) -> void: _raised.append(key))
	_checks = AirportChecksScript.new()
	_checks.alerts = _alerts
	_checks.stand_allocator = allocator
	_checks.air_traffic = air
	_checks.terminal_paths = _paths
	_checks.placed_objects = _objects
	_checks.spawner = spawner
	_checks.check_in = check_in
	_checks.security = security
	_checks.gates = gates
	add_child(_checks)
	var camera := Camera3D.new()
	add_child(camera)
	var centre := BuildGrid.tile_corner_to_world(B + Vector2i(20, 12))
	camera.global_position = centre + Vector3(0, 45, 30)
	camera.look_at(centre)
	await get_tree().process_frame

	# Empty terminal.
	_checks.check_terminal()
	_expect("empty terminal raises: %s" % ", ".join(_raised), _raised == ["no_checkin", "no_security", "no_gate"])
	var shown := _alerts.get_shown_texts()
	_expect("they show on screen: %s" % " / ".join(shown), shown.size() == 3 and "No check-in desk" in shown[2]
		and "No gate desk" in shown[0])
	_raised.clear()
	_checks.check_terminal()
	_expect("checking again doesn't repeat them", _raised.is_empty())

	# Desk, scanner and a walled-off gate.
	_add_object(CheckInScript.DESK_ID, Vector2(DESK), PI / 2.0)
	_walls.set_door(B + Vector2i(BACK_WALL_X, SCANNER.y), false, true)
	_add_object(SecurityScript.SCANNER_ID, Vector2(SCANNER), -PI / 2.0)
	_walls.set_run(B + ROOM_MIN, B + Vector2i(ROOM_MAX.x, ROOM_MIN.y), true)
	_walls.set_run(B + Vector2i(ROOM_MIN.x, ROOM_MAX.y), B + ROOM_MAX, true)
	_walls.set_run(B + ROOM_MIN, B + Vector2i(ROOM_MIN.x, ROOM_MAX.y), true)
	var gate_id := _add_object(GatesScript.GATE_ID, GATE, -PI / 2.0)
	await get_tree().process_frame
	_expect("desk, scanner and gate are in use", check_in.get_desks().size() == 1 and security.get_scanners().size() == 1
		and gates.get_gates().size() == 1)
	_checks.check_terminal()
	_expect("the walled-off gate raises: %s" % ", ".join(_raised), _raised == ["path:%d" % gate_id])
	_expect("on screen: %s" % _alerts.get_shown_texts()[0],
		"No path from the entrance to gate #%d" % gate_id in _alerts.get_shown_texts()[0])
	_expect("the fixed problems are resolved", not _alerts.is_raised("no_checkin")
		and not _alerts.is_raised("no_security") and not _alerts.is_raised("no_gate"))

	# A door into the gate room fixes the path.
	_raised.clear()
	_walls.set_door(B + ROOM_DOOR, false, true)
	await get_tree().process_frame
	_checks.check_terminal()
	_expect("with a door the path alert is resolved", _raised.is_empty() and not _alerts.is_raised("path:%d" % gate_id))

	# Flight alerts.
	var arrival := _first_arrival()
	allocator.allocation_failed.emit(arrival)
	_expect("no free stand: %s" % _alerts.get_shown_texts()[0], _raised == ["stand:%s" % arrival.flight_number]
		and ("No free stand for %s" % arrival.flight_number) in _alerts.get_shown_texts()[0])
	allocator.allocation_failed.emit(arrival)
	_expect("not repeated for the same flight", _raised.size() == 1)
	air.runway_missing.emit(arrival)
	air.taxi_route_missing.emit(arrival)
	_expect("no runway and no taxi route alerts too", _raised.size() == 3)
	_expect("at most %d on screen (%d)" % [AlertsScript.MAX_SHOWN, _alerts.get_shown_texts().size()],
		_alerts.get_shown_texts().size() == AlertsScript.MAX_SHOWN)

	# Clicking dismisses one; the rest fade out.
	var panel: Control = _alerts.get_child(0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.gui_input.emit(click)
	await get_tree().process_frame
	_expect("clicking an alert dismisses it", _alerts.get_shown_texts().size() == AlertsScript.MAX_SHOWN - 1)
	await get_tree().create_timer(AlertsScript.SHOW_TIME + 0.5).timeout
	_expect("the others fade out after %d s" % AlertsScript.SHOW_TIME, _alerts.get_shown_texts().is_empty())

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))


func _build_terminal() -> void:
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_walls = TerminalWallsScript.new()
	_walls.terminal_floor = _floor
	add_child(_walls)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)
	_objects = PlacedObjectsScript.new()
	_objects.terminal_floor = _floor
	_objects.terminal_walls = _walls
	add_child(_objects)
	_floor.placed_objects = _objects
	_walls.placed_objects = _objects
	_floor.set_roof_visible(false)
	_floor.set_rect(Rect2i(B, SIZE), true)
	_zones.paint_rect(Rect2i(B, Vector2i(SECURITY_X, SIZE.y)), Zone.LANDSIDE)
	_zones.paint_rect(Rect2i(B + Vector2i(SECURITY_X, 0), Vector2i(AIRSIDE_X - SECURITY_X, SIZE.y)), Zone.SECURITY)
	_zones.paint_rect(Rect2i(B + Vector2i(AIRSIDE_X, 0), Vector2i(SIZE.x - AIRSIDE_X, SIZE.y)), Zone.AIRSIDE)
	var c0 := B
	var c1 := B + SIZE
	_walls.set_run(c0, Vector2i(c1.x, c0.y), true)
	_walls.set_run(Vector2i(c0.x, c1.y), c1, true)
	_walls.set_run(c0, Vector2i(c0.x, c1.y), true)
	_walls.set_run(Vector2i(c1.x, c0.y), c1, true)
	_walls.set_run(B + Vector2i(BACK_WALL_X, 0), B + Vector2i(BACK_WALL_X, SIZE.y), true)
	_walls.set_door(B + ENTRANCE, true, true)


func _add_object(def_id: StringName, corner: Vector2, yaw: float) -> int:
	var pos := BuildGrid.tile_corner_to_world(B) + Vector3(corner.x, 0.0, corner.y)
	pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(pos))
	return _objects.add_object(def_id, pos, yaw)


func _first_arrival() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.is_arrival():
			return f
	return null


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

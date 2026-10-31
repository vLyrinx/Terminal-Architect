extends Node3D
## Test for click to inspect (checklist step 36).
## Run this scene on its own (F6). It builds a 20 x 12 m airside floor with a
## gate desk, puts two passengers on it (one off BQ 101, one waiting for
## BQ 102 at the gate) and a stand-in aircraft for BQ 101 on the ground to the
## east, under a fixed camera looking down.
## It checks that clicking each of them opens the info panel with what it is
## and what it is doing, that a real mouse click works the same way, that
## clicking empty ground or pressing Esc closes the panel, that clicks are
## ignored while a build tool is in use, and that the panel closes when the
## passenger it shows leaves.
## Prints PASS or FAIL for each check, then keeps running so you can click
## around yourself (the clock is paused).

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const PassengerCrowdScript := preload("res://scripts/passengers/passenger_crowd.gd")
const PassengerSpawnerScript := preload("res://scripts/passengers/passenger_spawner.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const InspectorScript := preload("res://scripts/ui/inspector.gd")
const UITheme := preload("res://scripts/ui/ui_theme.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State
const Kind := InspectorScript.Kind

const B := Vector2i(2240, 990)
const SIZE := Vector2i(20, 12)
const GATE := Vector2(10.5, 3.0)
const ARRIVING_SPOT := Vector2(5.0, 8.0)
const DEPARTING_SPOT := Vector2(14.0, 8.0)
const AIRCRAFT_SPOT := Vector2(45.0, 6.0)
const EMPTY_SPOT := Vector2(28.0, 20.0)


## Stand-in for AirTraffic: just the aircraft list.
class FakeAirTraffic:
	extends Node
	var aircraft: Array = []

	func get_aircraft() -> Array:
		return aircraft


## Stand-in for an aircraft: a box with its flight.
class FakeAircraft:
	extends Node3D
	var flight: FlightScript


## Stand-in for BuildManager: whether a tool is in use.
class FakeBuildManager:
	extends Node
	@warning_ignore("unused_signal")
	signal tool_changed(tool: Node)
	var building := false

	func is_building() -> bool:
		return building


var _failures := 0
var _floor: TerminalFloorScript
var _zones: TerminalZonesScript
var _objects: PlacedObjectsScript
var _crowd: PassengerCrowdScript
var _spawner: PassengerSpawnerScript
var _gates: GatesScript
var _inspector: InspectorScript
var _build: FakeBuildManager
var _camera: Camera3D
var _gate_id := 0


func _ready() -> void:
	print("TEST START | click to inspect")
	GameClock.set_paused(true)
	_floor = TerminalFloorScript.new()
	add_child(_floor)
	_zones = TerminalZonesScript.new()
	_zones.terminal_floor = _floor
	add_child(_zones)
	_objects = PlacedObjectsScript.new()
	_objects.terminal_floor = _floor
	add_child(_objects)
	_floor.placed_objects = _objects
	_floor.set_roof_visible(false)
	_floor.set_rect(Rect2i(B, SIZE), true)
	_zones.paint_rect(Rect2i(B, SIZE), Zone.AIRSIDE)
	_crowd = PassengerCrowdScript.new()
	add_child(_crowd)
	_spawner = PassengerSpawnerScript.new()
	_spawner.terminal_floor = _floor
	_spawner.terminal_zones = _zones
	_spawner.crowd = _crowd
	add_child(_spawner)
	_gates = GatesScript.new()
	_gates.placed_objects = _objects
	_gates.terminal_floor = _floor
	_gates.terminal_zones = _zones
	_gates.spawner = _spawner
	add_child(_gates)
	var air := FakeAirTraffic.new()
	add_child(air)
	_build = FakeBuildManager.new()
	add_child(_build)
	_add_view()

	var gate_pos: Vector3 = _objects.snap_position(ObjectCatalog.get_def(GatesScript.GATE_ID), _world(GATE), 0.0)
	gate_pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(gate_pos))
	_gate_id = _objects.add_object(GatesScript.GATE_ID, gate_pos, 0.0)

	var departure := _first_departure()
	var arrival := departure.pair
	var arriving: PassengerScript = _spawner.add_arriving(arrival, _world(ARRIVING_SPOT), 0.0)
	var waiting: PassengerScript = _spawner.add_arriving(departure, _world(DEPARTING_SPOT), 0.0)
	waiting.state = State.AT_GATE
	waiting.gate_id = _gate_id
	var plane := FakeAircraft.new()
	plane.flight = arrival
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(34.0, 4.0, 36.0)
	box.mesh = mesh
	box.position.y = 2.0
	plane.add_child(box)
	add_child(plane)
	plane.global_position = _world(AIRCRAFT_SPOT)
	air.aircraft.append(plane)

	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.build()
	ui.add_child(root)
	_inspector = InspectorScript.new()
	_inspector.build_manager = _build
	_inspector.spawner = _spawner
	_inspector.air_traffic = air
	_inspector.placed_objects = _objects
	_inspector.gates = _gates
	root.add_child(_inspector)
	await get_tree().process_frame
	await get_tree().process_frame

	# Passenger off an arrival.
	_inspector.click(_screen(_world(ARRIVING_SPOT) + Vector3(0.0, 0.9, 0.0)))
	var info := _inspector.get_info()
	_expect("clicking the arriving passenger selects them", _inspector.kind == Kind.PASSENGER
		and _inspector.passenger_id == arriving.id and _inspector.visible)
	_expect("panel: %s" % _flat(info), info.get("title", "") == "Passenger %d" % arriving.id
		and _has(info, "Arrived on %s" % arrival.flight_number) and _has(info, "Going to: the exit"))

	# Passenger waiting at the gate.
	_inspector.click(_screen(_world(DEPARTING_SPOT) + Vector3(0.0, 0.9, 0.0)))
	info = _inspector.get_info()
	_expect("panel: %s" % _flat(info), _inspector.passenger_id == waiting.id
		and _has(info, "Flight %s to %s" % [departure.flight_number, departure.route])
		and _has(info, "Now: Waiting at the gate") and _has(info, "Going to: gate #%d" % _gate_id))

	# Gate desk.
	_inspector.click(_screen(_world(GATE) + Vector3(0.0, 0.5, 0.0)))
	info = _inspector.get_info()
	_expect("clicking the gate desk selects it", _inspector.kind == Kind.OBJECT and _inspector.object_id == _gate_id)
	_expect("panel: %s" % _flat(info), info.get("title", "").ends_with("#%d" % _gate_id) and _has(info, "Seats:")
		and _has(info, "Value: $"))

	# Aircraft.
	_inspector.click(_screen(_world(AIRCRAFT_SPOT) + Vector3(6.0, 3.0, 4.0)))
	info = _inspector.get_info()
	_expect("clicking the aircraft selects it", _inspector.kind == Kind.AIRCRAFT and _inspector.aircraft == plane)
	_expect("panel: %s" % _flat(info), info.get("title", "") == "Aircraft %s" % arrival.flight_number
		and _has(info, AirlineCatalog.get_airline(arrival.airline_id).display_name) and _has(info, "Status: ")
		and _has(info, "Next: %s" % departure.flight_number))

	# Empty ground closes it.
	_inspector.click(_screen(_world(EMPTY_SPOT)))
	_expect("clicking empty ground closes the panel", _inspector.kind == Kind.NONE and not _inspector.visible)

	# A real mouse click.
	await _mouse_click(_screen(_world(ARRIVING_SPOT) + Vector3(0.0, 0.9, 0.0)))
	_expect("a real left click on a passenger opens the panel", _inspector.kind == Kind.PASSENGER
		and _inspector.passenger_id == arriving.id)
	await get_tree().create_timer(0.4).timeout
	_expect("the panel shows the text on screen", _inspector._title.text == "Passenger %d" % arriving.id)

	# Esc closes it.
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	_expect("Esc closes the panel", _inspector.kind == Kind.NONE)

	# Ignored while building.
	_build.building = true
	await _mouse_click(_screen(_world(GATE) + Vector3(0.0, 0.5, 0.0)))
	_expect("clicks are ignored while a build tool is in use", _inspector.kind == Kind.NONE)
	_build.building = false

	# Closes when the passenger leaves.
	_inspector.select_passenger(arriving.id)
	_spawner.remove_passenger(arriving)
	await get_tree().create_timer(0.4).timeout
	_expect("the panel closes when the passenger leaves", _inspector.kind == Kind.NONE)

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_inspector.select_passenger(waiting.id)


func _mouse_click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _world(local: Vector2) -> Vector3:
	return BuildGrid.tile_corner_to_world(B) + Vector3(local.x, 0.0, local.y)


func _screen(world: Vector3) -> Vector2:
	return _camera.unproject_position(world)


func _first_departure() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and f.pair != null:
			return f
	return null


func _has(info: Dictionary, text: String) -> bool:
	for line: String in info.get("lines", []):
		if text in line:
			return true
	return false


func _flat(info: Dictionary) -> String:
	return "%s | %s" % [info.get("title", ""), " / ".join(info.get("lines", [])).replace("\n", " / ")]


func _add_view() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.78, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 100)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	plane.material = mat
	ground.mesh = plane
	ground.position = _world(Vector2(30.0, 6.0)) + Vector3(0.0, -0.01, 0.0)
	add_child(ground)
	_camera = Camera3D.new()
	add_child(_camera)
	var target := _world(Vector2(30.0, 8.0))
	_camera.global_position = target + Vector3(0.0, 55.0, 30.0)
	_camera.look_at(target)
	_camera.current = true


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

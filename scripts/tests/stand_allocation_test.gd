extends Node3D
## Test for stand allocation (checklist step 23).
## Run this scene on its own (F6). It builds a medium taxiway with two medium
## stands, creates Friday's Brightwater flights, and checks that arrivals get
## a free stand of the right size ahead of time, that both flights of a
## rotation share it, that overlapping turnarounds use different stands, that
## a warning comes (once) when none is free, and that removing a stand,
## releasing a flight and time passing free stands again. Prints PASS or FAIL
## for each check, then shows the two stands with their reservations.

const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const PlacedObjectsScript := preload("res://scripts/objects/placed_objects.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const CommandRunnerScript := preload("res://scripts/core/command_runner.gd")
const SetPavingCmd := preload("res://scripts/core/commands/set_paving_command.gd")
const PlaceStandCmd := preload("res://scripts/core/commands/place_stand_command.gd")
const DeleteStandCmd := preload("res://scripts/core/commands/delete_stand_command.gd")
const StandAllocatorScript := preload("res://scripts/flights/stand_allocator.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const DAY := 86400

var _failures := 0
var _stands: StandsScript
var _runner: CommandRunnerScript
var _allocator: StandAllocatorScript
var _failed: Array = []


func _ready() -> void:
	print("TEST START | stand allocation")
	GameClock.set_paused(true)
	_build_world()
	Money.reset(1000000)
	_allocator = StandAllocatorScript.new()
	_allocator.automatic = false
	_allocator.stands = _stands
	add_child(_allocator)
	_allocator.allocation_failed.connect(func(f: FlightScript) -> void: _failed.append(f))

	# 24 m of taxiway paving along y = 1000 with two medium stands side by side south of it.
	_runner.submit(SetPavingCmd.new(Rect2i(1000, 988, 400, 24), true))
	await get_tree().process_frame
	var def := StandCatalog.get_def(&"medium")
	var c1 := PlaceStandCmd.new(&"medium", _stands.snap_anchor(def, _world(Vector2i(1200, 950)), 0), 0)
	var c2 := PlaceStandCmd.new(&"medium", _stands.snap_anchor(def, _world(Vector2i(1250, 950)), 0), 0)
	_expect("two connected medium stands are built", _runner.submit(c1) and _runner.submit(c2)
		and _stands.get_stand(c1.stand_id).has_taxiway() and _stands.get_stand(c2.stand_id).has_taxiway())
	var s1 := c1.stand_id
	var s2 := c2.stand_id

	# Friday's flights, at 06:00.
	var friday := GameClock.game_time - GameClock.game_time % DAY
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	GameClock.game_time = friday + 6 * 3600
	var a101 := _find("BQ 101")
	var a211 := _find("BQ 211")
	_allocator.allocate_upcoming()
	_expect("BQ 101 (07:15) gets a stand 2 hours ahead", a101.stand_id == s1)
	_expect("its departure BQ 102 shares the stand", a101.pair.stand_id == s1)
	_expect("BQ 211 (09:40) isn't allocated yet", a211.stand_id == -1)
	_expect("the stand is reserved 07:05-08:15", not _allocator.is_free(s1, friday + 7 * 3600 + 300, friday + 7 * 3600 + 360)
		and not _allocator.is_free(s1, friday + 8 * 3600 + 840, friday + 8 * 3600 + 900)
		and _allocator.is_free(s1, friday + 8 * 3600 + 900, friday + 9 * 3600))
	_expect("the stand label shows the reservation", _stands.get_stand(s1).label.text.contains("BQ 101/102"))

	GameClock.game_time = friday + 8 * 3600
	_allocator.allocate_upcoming()
	_expect("BQ 211 reuses stand %d once BQ 102 has gone" % s1, a211.stand_id == s1)

	# Three aircraft on the ground at once on Saturday, two stands.
	var sat := friday + DAY
	var r1 := _rotation("XX 1", sat + 14 * 3600, sat + 15 * 3600, &"a320")
	var r2 := _rotation("XX 3", sat + 14 * 3600 + 600, sat + 15 * 3600, &"b738")
	var r3 := _rotation("XX 5", sat + 14 * 3600 + 1200, sat + 15 * 3600, &"a320")
	_expect("overlapping turnarounds get different stands", _allocator.allocate(r1) == s1 and _allocator.allocate(r2) == s2)
	_expect("with every stand taken there is none", _allocator.allocate(r3) == -1 and r3.stand_id == -1)
	_expect("a warning is raised for it", _failed.size() == 1 and _failed[0] == r3)
	_allocator.allocate(r3)
	_expect("the warning isn't repeated", _failed.size() == 1)
	var odd := _rotation("XX 7", sat + 18 * 3600, sat + 19 * 3600, &"no_such_type")
	_expect("an aircraft no stand fits gets none", _allocator.allocate(odd) == -1)

	_allocator.release(r1)
	_expect("releasing a flight frees its stand", r1.stand_id == -1 and r1.pair.stand_id == -1
		and _allocator.is_free(s1, sat + 14 * 3600, sat + 15 * 3600))
	_expect("the waiting flight can now have it", _allocator.allocate(r3) == s1)

	_runner.submit(DeleteStandCmd.new(s2))
	_expect("removing a stand takes it from its flights", r2.stand_id == -1 and r2.pair.stand_id == -1)

	# Time passing ends reservations.
	GameClock.game_time = sat + 16 * 3600
	_allocator._on_minute()
	_expect("finished turnarounds free the stand", _allocator.get_reservations(s1).is_empty()
		and _stands.get_stand(s1).label.text.contains("Free"))

	_add_view(_stands.get_stand(s1).stop)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open with the stands on screen. Close the window when done.


## An arrival and departure pair made by hand.
func _rotation(number: String, arrives: int, departs: int, type_id: StringName) -> FlightScript:
	var a := FlightScript.new()
	a.id = 9000 + number.hash() % 1000
	a.flight_number = number
	a.aircraft_type = type_id
	a.scheduled_time = arrives
	var d := FlightScript.new()
	d.id = a.id + 1
	d.flight_number = number.get_slice(" ", 0) + " " + str(number.get_slice(" ", 1).to_int() + 1)
	d.direction = FlightScript.Direction.DEPARTURE
	d.aircraft_type = type_id
	d.scheduled_time = departs
	a.pair = d
	d.pair = a
	return a


func _find(number: String) -> FlightScript:
	for f in FlightSchedule.get_all_flights():
		if f.flight_number == number:
			return f
	return null


func _world(corner: Vector2i) -> Vector3:
	return BuildGrid.tile_corner_to_world(corner)


func _build_world() -> void:
	var terminal_floor := TerminalFloorScript.new()
	add_child(terminal_floor)
	var objects := PlacedObjectsScript.new()
	terminal_floor.placed_objects = objects
	var walls := TerminalWallsScript.new()
	walls.placed_objects = objects
	walls.terminal_floor = terminal_floor
	add_child(walls)
	objects.terminal_floor = terminal_floor
	objects.terminal_walls = walls
	add_child(objects)
	var runways := RunwaysScript.new()
	runways.terminal_floor = terminal_floor
	add_child(runways)
	var taxiways := TaxiwaysScript.new()
	taxiways.terminal_floor = terminal_floor
	taxiways.runways = runways
	add_child(taxiways)
	_stands = StandsScript.new()
	_stands.terminal_floor = terminal_floor
	_stands.runways = runways
	_stands.taxiways = taxiways
	add_child(_stands)
	taxiways.stands = _stands
	runways.stands = _stands
	terminal_floor.runways = runways
	terminal_floor.taxiways = taxiways
	terminal_floor.stands = _stands
	_runner = CommandRunnerScript.new()
	_runner.placed_objects = objects
	_runner.terminal_floor = terminal_floor
	_runner.terminal_walls = walls
	_runner.runways = runways
	_runner.taxiways = taxiways
	_runner.stands = _stands
	add_child(_runner)


func _add_view(target: Vector3) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = target + Vector3(25, 70, 90)
	camera.look_at(target + Vector3(25, 0, 0))
	camera.current = true


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

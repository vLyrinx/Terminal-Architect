extends Node3D
## Test for the flight list screen (checklist step 37).
## Run this scene on its own (F6). It opens the flight list with today's
## schedule, sets some flights to different statuses by hand (landed,
## boarding, departed, and late ones), and uses stand-ins for AirTraffic,
## Stands and the inspector to check what pressing a status button does.
## It checks that the Flights button and F5 open and close the screen, that
## every one of today's flights has a row with time, number, ARR / DEP,
## aircraft, route, stand and status, that late flights show as Delayed, and
## that pressing a status moves the camera to the flight's aircraft (and opens
## it in the inspector) or to its stand.
## Prints PASS or FAIL for each check, then leaves the screen open.

const FlightListScript := preload("res://scripts/ui/flight_list.gd")
const TopBarScript := preload("res://scripts/ui/top_bar.gd")
const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")
const UITheme := preload("res://scripts/ui/ui_theme.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Status := FlightScript.Status


class FakeAirTraffic:
	extends Node
	var by_flight := {}

	func get_aircraft_for(f: FlightScript) -> Node3D:
		return by_flight.get(f.id)


class FakeStand:
	extends RefCounted
	var stop := Vector3.ZERO


class FakeStands:
	extends Node3D
	var by_id := {}

	func get_stand(id: int) -> FakeStand:
		return by_id.get(id)


class FakeInspector:
	extends Control
	var selected: Node3D

	func select_aircraft(node: Node3D) -> void:
		selected = node


var _failures := 0


func _ready() -> void:
	print("TEST START | flight list")
	GameClock.set_paused(true)
	var camera := OrbitCameraScript.new()
	add_child(camera)
	camera.current = true
	var air := FakeAirTraffic.new()
	add_child(air)
	var stands := FakeStands.new()
	add_child(stands)
	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.build()
	ui.add_child(root)
	var inspector := FakeInspector.new()
	root.add_child(inspector)
	var list := FlightListScript.new()
	list.air_traffic = air
	list.stands = stands
	list.inspector = inspector
	list.camera = camera
	var bar := TopBarScript.new()
	bar.flight_list = list
	root.add_child(bar)
	root.add_child(list)
	await get_tree().process_frame

	# Opening and closing.
	var button := _find_button(bar, "Flights")
	_expect("the top bar has a Flights button", button != null)
	_expect("the list starts closed", not list.visible)
	button.pressed.emit()
	_expect("the Flights button opens it (and shows pressed)", list.visible and button.button_pressed)
	await _press_f5()
	_expect("F5 closes it (button no longer pressed)", not list.visible and not button.button_pressed)
	await _press_f5()
	_expect("F5 opens it again", list.visible)

	# Set up some statuses.
	var today := FlightSchedule.get_today_flights()
	var arr := _nth(today, true, 0)
	var dep := arr.pair
	var arr2 := _nth(today, true, 1)
	var dep2 := arr2.pair
	var arr3 := _nth(today, true, 2)
	var dep3 := arr3.pair
	var late_arr := _nth(today, true, 3)
	arr.status = Status.ON_STAND
	arr.stand_id = 4
	dep.status = Status.DEPARTED
	dep.stand_id = 4
	arr2.status = Status.TAXIING
	arr2.stand_id = 5
	dep2.stand_id = 5
	arr3.status = Status.ON_STAND
	arr3.stand_id = 6
	dep3.status = Status.BOARDING
	dep3.stand_id = 6
	# Move the clock to just after dep3 was due, so it and late_arr (not yet landed) are late.
	GameClock.game_time = maxi(dep3.scheduled_time, late_arr.scheduled_time) + 300
	list._refresh = 0.0
	await get_tree().process_frame

	var rows := list.get_row_texts()
	_expect("%d rows for today's %d flights" % [rows.size(), today.size()], rows.size() == today.size()
		and not today.is_empty())
	var row := _row_of(list, today, dep3)
	var type: Resource = AircraftCatalog.get_type(dep3.aircraft_type)
	_expect("row: %s" % " | ".join(row), row.size() == 7 and row[0] == dep3.get_time_string()
		and row[1] == dep3.flight_number and row[2] == "DEP" and row[3] == type.display_name
		and row[4] == dep3.route and row[5] == "6")
	_expect("%s is %s" % [arr.flight_number, _row_of(list, today, arr)[6]], _row_of(list, today, arr)[6] == "On stand")
	_expect("%s is %s" % [dep.flight_number, _row_of(list, today, dep)[6]], _row_of(list, today, dep)[6] == "Departed")
	_expect("%s (taxiing in) is %s" % [arr2.flight_number, _row_of(list, today, arr2)[6]],
		_row_of(list, today, arr2)[6] == "Landed")
	_expect("%s (boarding, past its time) is %s" % [dep3.flight_number, _row_of(list, today, dep3)[6]],
		_row_of(list, today, dep3)[6] == "Delayed (boarding)")
	_expect("%s (not landed, past its time) is %s" % [late_arr.flight_number, _row_of(list, today, late_arr)[6]],
		_row_of(list, today, late_arr)[6] == "Delayed")
	var last := today[-1]
	_expect("%s (later today) is %s" % [last.flight_number, _row_of(list, today, last)[6]],
		_row_of(list, today, last)[6] == "Scheduled")
	_expect("summary: %s" % list._summary.text, "delayed" in list._summary.text)

	# Pressing a status.
	var plane := Node3D.new()
	add_child(plane)
	plane.global_position = Vector3(30.0, 0.0, -20.0)
	air.by_flight[arr3.id] = plane
	list.get_status_button(dep3).pressed.emit()
	_expect("pressing %s's status opens its aircraft in the inspector" % dep3.flight_number,
		inspector.selected == plane)
	_expect("and moves the camera there", camera._target_focus.distance_to(Vector3(30.0, 0.0, -20.0)) < 1.0)
	var stand := FakeStand.new()
	stand.stop = Vector3(-15.0, 0.0, 12.0)
	stands.by_id[5] = stand
	_expect("a flight with only a stand shows the stand", list.show_flight(dep2) == &"stand"
		and camera._target_focus.distance_to(stand.stop) < 1.0)
	_expect("a flight with neither says it isn't here yet", list.show_flight(last) == &""
		and "isn't at the airport yet" in list._summary.text)

	# Esc closes.
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	_expect("Esc closes it", not list.visible)

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	list.set_open(true)


func _press_f5() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F5
		key.keycode = KEY_F5
		key.pressed = pressed
		Input.parse_input_event(key)
		await get_tree().process_frame


func _nth(flights: Array[FlightScript], arrival: bool, n: int) -> FlightScript:
	var i := 0
	for f in flights:
		if f.is_arrival() == arrival and f.pair != null:
			if i == n:
				return f
			i += 1
	return null


func _row_of(list: FlightListScript, today: Array[FlightScript], f: FlightScript) -> PackedStringArray:
	var rows := list.get_row_texts()
	var i := today.find(f)
	return rows[i] if i >= 0 and i < rows.size() else PackedStringArray()


func _find_button(node: Node, text: String) -> Button:
	for child in node.find_children("*", "Button", true, false):
		if child.text == text:
			return child
	return null


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

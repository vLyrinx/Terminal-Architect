extends PanelContainer
## Click to inspect (checklist step 36).
##
## Outside build mode, a left click on a passenger, a placed object or an
## aircraft selects it and opens this panel (bottom left) showing what it is
## and what it is doing now, kept up to date while it is open. Passengers are
## picked within PASSENGER_PICK_PX of where they are on screen, objects by
## the tile under the mouse, aircraft within AIRCRAFT_PICK_RADIUS metres of
## the mouse ray; when several are under the mouse a passenger wins, then an
## object, then an aircraft. A ring marks the selected passenger or aircraft;
## a selected object is highlighted.
##
## Click empty ground, press Esc or the X to close. Picking a build tool closes it too.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const State := PassengerScript.State

enum Kind { NONE, PASSENGER, AIRCRAFT, OBJECT }

## A click is a click (not a camera drag) if the mouse moves less than this, in pixels.
const CLICK_TOLERANCE := 6.0
const PASSENGER_PICK_PX := 14.0
## Passengers are picked around this height (roughly their chest).
const PASSENGER_HEIGHT := 0.9
const AIRCRAFT_PICK_RADIUS := 16.0
## Objects are picked a little above the floor, roughly where their tops are.
const OBJECT_PICK_HEIGHT := 0.5
const REFRESH_TIME := 0.25
const WIDTH := 300.0

signal selection_changed(kind: Kind)

@export var build_manager: Node
@export var spawner: Node
@export var air_traffic: Node
@export var placed_objects: Node3D
@export var check_in: Node
@export var security: Node
@export var gates: Node
@export var floor_index := 0

var kind := Kind.NONE
## Passenger id, aircraft node or placed object id of the selection.
var passenger_id := 0
var aircraft: Node3D
var object_id := 0

var _title: Label
var _body: Label
var _marker: MeshInstance3D
var _highlight: StandardMaterial3D
var _press_pos := Vector2.ZERO
var _pressed := false
var _refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # inspecting works while the clock is paused
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.RADIUS, 14, 10))
	custom_minimum_size.x = WIDTH
	var box := VBoxContainer.new()
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UITheme.label("", UITheme.FONT_SIZE_LARGE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(clear)
	header.add_child(close)
	_body = UITheme.label("", UITheme.FONT_SIZE, UITheme.TEXT_DIM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = WIDTH - 28.0
	box.add_child(_body)
	visible = false

	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = UITheme.WARNING
	ring.material = mat
	_marker.mesh = ring
	_marker.visible = false
	add_child(_marker)
	_highlight = StandardMaterial3D.new()
	_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.albedo_color = Color(1.0, 0.85, 0.25, 0.45)

	if build_manager != null:
		build_manager.tool_changed.connect(func(tool: Node) -> void:
			if tool != null:
				clear())
	if placed_objects != null:
		placed_objects.object_removed.connect(func(id: int) -> void:
			if kind == Kind.OBJECT and id == object_id:
				object_id = 0
				clear())


# --- Selecting --------------------------------------------------------------------

## What is under a screen point: {kind, passenger_id, aircraft, object_id} (kind NONE if nothing).
func pick_at(screen_pos: Vector2) -> Dictionary:
	var result := {"kind": Kind.NONE, "passenger_id": 0, "aircraft": null, "object_id": 0}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return result
	# Passengers: the nearest on screen.
	if spawner != null:
		var best := PASSENGER_PICK_PX
		for p: PassengerScript in spawner.get_all_passengers():
			if p.crowd_id < 0:
				continue
			var pos: Vector3 = spawner.crowd.get_passenger_position(p.crowd_id) + Vector3(0.0, PASSENGER_HEIGHT, 0.0)
			if camera.is_position_behind(pos):
				continue
			var d := camera.unproject_position(pos).distance_to(screen_pos)
			if d < best:
				best = d
				result.kind = Kind.PASSENGER
				result.passenger_id = p.id
	if result.kind != Kind.NONE:
		return result
	# Objects: the one on the tile under the mouse.
	if placed_objects != null:
		var pick := BuildGrid.screen_to_tile(camera, screen_pos, floor_index, OBJECT_PICK_HEIGHT)
		if pick.hit:
			var id: int = placed_objects.get_object_at(pick.tile, floor_index)
			if id != 0:
				result.kind = Kind.OBJECT
				result.object_id = id
				return result
	# Aircraft: the nearest to the mouse ray.
	if air_traffic != null:
		var origin := camera.project_ray_origin(screen_pos)
		var dir := camera.project_ray_normal(screen_pos)
		var best := AIRCRAFT_PICK_RADIUS
		for a: Node3D in air_traffic.get_aircraft():
			var centre := a.global_position + Vector3(0.0, 2.0, 0.0)
			var along := (centre - origin).dot(dir)
			if along <= 0.0:
				continue
			var d := centre.distance_to(origin + dir * along)
			if d < best:
				best = d
				result.kind = Kind.AIRCRAFT
				result.aircraft = a
	return result


## Selects whatever is under a screen point, or closes the panel if nothing is.
func click(screen_pos: Vector2) -> void:
	var pick := pick_at(screen_pos)
	match pick.kind:
		Kind.PASSENGER: select_passenger(pick.passenger_id)
		Kind.OBJECT: select_object(pick.object_id)
		Kind.AIRCRAFT: select_aircraft(pick.aircraft)
		_: clear()


func select_passenger(id: int) -> void:
	_set_selection(Kind.PASSENGER)
	passenger_id = id


func select_aircraft(node: Node3D) -> void:
	_set_selection(Kind.AIRCRAFT)
	aircraft = node


func select_object(id: int) -> void:
	_set_selection(Kind.OBJECT)
	object_id = id
	placed_objects.set_highlight(id, _highlight)


## Closes the panel.
func clear() -> void:
	_set_selection(Kind.NONE)


func _set_selection(new_kind: Kind) -> void:
	if kind == Kind.OBJECT and object_id != 0 and placed_objects.get_object(object_id) != null:
		placed_objects.set_highlight(object_id, null)
	kind = new_kind
	passenger_id = 0
	aircraft = null
	object_id = 0
	visible = kind != Kind.NONE
	_marker.visible = false
	_refresh = 0.0
	selection_changed.emit(kind)


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if build_manager != null and build_manager.is_building():
		_pressed = false
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE \
			and kind != Kind.NONE:
		clear()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_pressed = true
		_press_pos = button.position
	elif _pressed:
		_pressed = false
		if button.position.distance_to(_press_pos) < CLICK_TOLERANCE:
			click(button.position)
			get_viewport().set_input_as_handled()


# --- Showing ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if kind == Kind.NONE:
		return
	_update_marker()
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_TIME
	var info := get_info()
	if info.is_empty():
		clear()  # it has gone (left the airport, taken off, removed)
		return
	_title.text = info.title
	_body.text = "\n".join(info.lines)
	reset_size()
	position = Vector2(12.0, get_viewport_rect().size.y - size.y - 12.0)


## What the panel shows now: {title, lines}, or {} if the selection has gone.
func get_info() -> Dictionary:
	match kind:
		Kind.PASSENGER: return _passenger_info()
		Kind.AIRCRAFT: return _aircraft_info()
		Kind.OBJECT: return _object_info()
	return {}


func _update_marker() -> void:
	var pos := Vector3.INF
	var radius := 0.5
	if kind == Kind.PASSENGER:
		var p: PassengerScript = spawner.get_passenger(passenger_id)
		if p != null and p.crowd_id >= 0:
			pos = spawner.crowd.get_passenger_position(p.crowd_id)
	elif kind == Kind.AIRCRAFT and is_instance_valid(aircraft):
		pos = aircraft.global_position
		pos.y = maxf(pos.y - 2.0, 0.0) if pos.y > 3.0 else 0.0
		radius = 22.0
	_marker.visible = pos.is_finite()
	if _marker.visible:
		_marker.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radius), pos + Vector3(0.0, 0.08, 0.0))


func _passenger_info() -> Dictionary:
	var p: PassengerScript = spawner.get_passenger(passenger_id) if spawner != null else null
	if p == null:
		return {}
	var f := p.flight
	var lines: Array[String] = []
	if f != null and f.is_arrival():
		lines.append("Arrived on %s from %s" % [f.flight_number, f.route])
	elif f != null:
		lines.append("Flight %s to %s, departs %s" % [f.flight_number, f.route, f.get_time_string()])
		lines.append("Flight status: %s" % f.get_status_name())
	lines.append("Now: %s" % p.get_state_name())
	var going := _passenger_going(p)
	if going != "":
		lines.append("Going to: %s" % going)
	if p.entered_time >= 0:
		lines.append("In the terminal since %s" % _clock(p.entered_time))
	return {"title": "Passenger %d" % p.id, "lines": lines}


## Where a passenger is heading, in words.
func _passenger_going(p: PassengerScript) -> String:
	match p.state:
		State.EXPECTED: return "the airport (due %s)" % _clock(p.arrival_time)
		State.ARRIVING, State.AT_ENTRANCE, State.WAITING_CHECKIN: return "check-in"
		State.TO_CHECKIN, State.QUEUING_CHECKIN, State.CHECKING_IN: return "check-in desk #%d" % p.desk_id
		State.CHECKED_IN: return "security"
		State.TO_SECURITY, State.QUEUING_SECURITY, State.SCREENING: return "security scanner #%d" % p.scanner_id
		State.AIRSIDE: return "their gate (none yet)" if p.gate_id == 0 else "gate #%d" % p.gate_id
		State.TO_GATE, State.AT_GATE, State.BOARDING: return "gate #%d" % p.gate_id
		State.TO_AIRCRAFT: return "the aircraft on stand %d" % p.flight.stand_id
		State.BOARDED: return "%s" % p.flight.route
		State.TO_EXIT, State.MISSED: return "the exit"
	return ""


func _aircraft_info() -> Dictionary:
	if not is_instance_valid(aircraft) or aircraft.flight == null:
		return {}
	var f: FlightScript = aircraft.flight
	var type: Resource = AircraftCatalog.get_type(f.aircraft_type)
	var airline = AirlineCatalog.get_airline(f.airline_id)
	var lines: Array[String] = []
	lines.append("%s %s" % [airline.display_name if airline else String(f.airline_id),
		type.display_name if type else String(f.aircraft_type)])
	if f.is_arrival():
		lines.append("Arriving from %s, due %s" % [f.route, f.get_time_string()])
	else:
		lines.append("Departing to %s at %s" % [f.route, f.get_time_string()])
	lines.append("Status: %s" % f.get_status_name())
	lines.append("Stand: %s" % (str(f.stand_id) if f.stand_id >= 0 else "none"))
	var departure: FlightScript = f if not f.is_arrival() else f.pair
	if departure != null and departure != f:
		lines.append("Next: %s to %s at %s" % [departure.flight_number, departure.route, departure.get_time_string()])
	if departure != null and not departure.passengers.is_empty():
		var on_board := 0
		for p: PassengerScript in departure.passengers:
			if p.state == State.BOARDED:
				on_board += 1
		lines.append("%s passengers: %d booked, %d on board" % [departure.flight_number, departure.passengers.size(),
			on_board])
	return {"title": "Aircraft %s" % f.flight_number, "lines": lines}


func _object_info() -> Dictionary:
	var obj = placed_objects.get_object(object_id) if placed_objects != null else null
	if obj == null:
		return {}
	var def := ObjectCatalog.get_def(obj.def_id)
	var lines: Array[String] = []
	match obj.def_id:
		&"checkin_desk":
			var d = check_in.get_desk(object_id) if check_in != null else null
			lines.append(_service_line(d, "checking in"))
		&"security_scanner":
			var s = security.get_scanner(object_id) if security != null else null
			lines.append(_service_line(s, "being screened"))
		&"gate_desk":
			lines.append_array(_gate_lines())
		&"seat_row":
			lines.append(_seat_line())
	if def != null:
		lines.append("Value: %s" % Money.format(def.cost))
	return {"title": "%s #%d" % [def.display_name if def else String(obj.def_id), object_id], "lines": lines}


## Queue and service for a check-in desk or scanner (null if it isn't working).
func _service_line(record: RefCounted, serving_word: String) -> String:
	if record == null:
		return "Not in use (needs to face open floor in the right zone)"
	var line := "Queue: %d of %d" % [record.queue.size(), record.spots.size()]
	line += "\nNow: %s" % ("passenger %d %s" % [record.serving.id, serving_word] if record.serving != null else "idle")
	line += "\nServed so far: %d" % record.served
	return line


func _gate_lines() -> Array[String]:
	var lines: Array[String] = []
	var gate = gates.get_gate(object_id) if gates != null else null
	if gate == null:
		lines.append("Not in use (needs airside floor in front)")
		return lines
	var taken := 0
	for seat in gate.seats:
		if seat.taken != null:
			taken += 1
	lines.append("Seats: %d of %d taken" % [taken, gate.seats.size()])
	lines.append("Door to the apron: %s" % ("yes" if gate.has_exit else "none"))
	var now := GameClock.game_time
	for f: FlightScript in FlightSchedule.get_all_flights():
		if f.is_arrival() or f.scheduled_time < now - 3600:
			continue
		if gates.get_gate_for(f) != gate:
			continue
		var b = gates.get_boarding(f)
		var status := "waiting"
		if b != null and b.finished:
			status = "boarding finished, %d on board" % b.boarded
		elif b != null and b.open:
			status = "boarding, %d on board, closes %s" % [b.boarded, _clock(b.closes_at)]
		lines.append("Flight: %s to %s at %s (%s)" % [f.flight_number, f.route, f.get_time_string(), status])
		break
	return lines


func _seat_line() -> String:
	if gates == null:
		return ""
	for gate in gates.get_gates():
		var taken := 0
		var total := 0
		for seat in gate.seats:
			if seat.object_id == object_id:
				total += 1
				if seat.taken != null:
					taken += 1
		if total > 0:
			return "Gate #%d seating: %d of %d taken" % [gate.id, taken, total]
	return "Not near a gate desk on airside"


static func _clock(time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]

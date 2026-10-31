extends PanelContainer
## Flight list screen (checklist step 37), opened with the Flights button in
## the top bar or F5: today's arrivals and departures in time order with
## time, flight number, arrival or departure, aircraft, from / to, stand and
## status. A flight is shown as Delayed once its time has passed and it
## hasn't landed (arrivals) or taken off (departures).
##
## Each status is a button: pressing it shows that flight, moving the camera
## to its aircraft and opening it in the inspector (or to its stand if the
## aircraft isn't moving yet). Rows are built when the day's flights change
## and their text refreshed every REFRESH_TIME while the screen is open.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const Status := FlightScript.Status
const ACTION_TOGGLE := "toggle_flight_list"
const REFRESH_TIME := 0.5
const COLUMNS := ["Time", "Flight", "", "Aircraft", "From / to", "Stand", "Status"]
const MAX_HEIGHT := 520.0

## Emitted when the screen opens or closes.
signal toggled(open: bool)
## Emitted when a flight's status button is pressed.
signal flight_shown(flight: FlightScript)

## Optional: where pressing a status button takes you.
@export var air_traffic: Node
@export var stands: Node3D
@export var inspector: Control
@export var camera: Camera3D

var _title: Label
var _summary: Label
var _grid: GridContainer
var _scroll: ScrollContainer
## One entry per row: {flight, labels (Array[Label]), status (Button)}.
var _rows: Array[Dictionary] = []
var _row_day := -1
var _refresh := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F5
		InputMap.action_add_event(ACTION_TOGGLE, key)
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.RADIUS, 16, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = UITheme.label("", UITheme.FONT_SIZE_LARGE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.tooltip_text = "Close (F5)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: set_open(false))
	header.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 4)
	_scroll.add_child(_grid)
	_summary = UITheme.label("", UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	box.add_child(_summary)
	visible = false
	FlightSchedule.flights_created.connect(func(_day: int, _flights: Array) -> void: _row_day = -1)
	GameClock.day_passed.connect(func(_dt: Dictionary) -> void: _row_day = -1)


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	_refresh = 0.0
	if open:
		_update()
	print("FLIGHT LIST | %s" % ("open" if open else "closed"))
	toggled.emit(open)


func toggle() -> void:
	set_open(not visible)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_TIME
		_update()


# --- Content ----------------------------------------------------------------------

## The status shown for a flight: its own status, or Delayed once it is late.
static func get_display_status(f: FlightScript, now: int) -> String:
	if f.status == Status.CANCELLED or f.status == Status.DEPARTED:
		return f.get_status_name()
	if f.is_arrival():
		if now > f.scheduled_time and (f.status == Status.SCHEDULED or f.status == Status.APPROACHING):
			return "Delayed"
		if f.status == Status.TAXIING or f.status == Status.LANDED:
			return "Landed"
		return f.get_status_name()
	if now > f.scheduled_time:
		return "Delayed (%s)" % f.get_status_name().to_lower()
	return f.get_status_name()


## Rows as text, one per flight, columns as in COLUMNS (also used by the test).
func get_row_texts() -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for row in _rows:
		var line := PackedStringArray()
		for l: Label in row.labels:
			line.append(l.text)
		line.append(row.status.text)
		out.append(line)
	return out


## The status button of a flight's row, or null.
func get_status_button(f: FlightScript) -> Button:
	for row in _rows:
		if row.flight == f:
			return row.status
	return null


func _update() -> void:
	if _row_day != GameClock.get_day_number():
		_build_rows()
	var now := GameClock.game_time
	var arrivals := 0
	var late := 0
	for row in _rows:
		var f: FlightScript = row.flight
		if f.is_arrival():
			arrivals += 1
		var labels: Array = row.labels
		labels[5].text = str(f.stand_id) if f.stand_id >= 0 else "-"
		var status := get_display_status(f, now)
		if status.begins_with("Delayed"):
			late += 1
		var b: Button = row.status
		b.text = status
		b.add_theme_color_override("font_color", _status_colour(status))
		var dim := f.status == Status.DEPARTED or f.status == Status.CANCELLED \
			or (f.is_arrival() and f.status == Status.ON_STAND)
		for l: Label in labels:
			l.add_theme_color_override("font_color", UITheme.TEXT_DIM if dim else UITheme.TEXT)
	_title.text = "Today's flights   %s   %s" % [GameClock.get_date_string(), GameClock.get_time_string()]
	_summary.text = "%d arrivals, %d departures, %d delayed   Press a status to see the flight" % [arrivals,
		_rows.size() - arrivals, late] if not _rows.is_empty() else "No flights today"
	reset_size()
	_scroll.custom_minimum_size = Vector2(_grid.get_combined_minimum_size().x,
		minf(_grid.get_combined_minimum_size().y, MAX_HEIGHT))
	reset_size()
	position = (get_viewport_rect().size - size) * 0.5


func _build_rows() -> void:
	_row_day = GameClock.get_day_number()
	for child in _grid.get_children():
		child.queue_free()
	_rows.clear()
	for heading: String in COLUMNS:
		_grid.add_child(UITheme.label(heading, UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM))
	for f: FlightScript in FlightSchedule.get_today_flights():
		var type: Resource = AircraftCatalog.get_type(f.aircraft_type)
		var texts := [f.get_time_string(), f.flight_number, "ARR" if f.is_arrival() else "DEP",
			type.display_name if type else String(f.aircraft_type), f.route, "-"]
		var labels: Array[Label] = []
		for t: String in texts:
			var l := UITheme.label(t, UITheme.FONT_SIZE)
			_grid.add_child(l)
			labels.append(l)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 150.0
		b.tooltip_text = "Show %s" % f.flight_number
		b.pressed.connect(show_flight.bind(f))
		_grid.add_child(b)
		_rows.append({"flight": f, "labels": labels, "status": b})


func _status_colour(status: String) -> Color:
	if status.begins_with("Delayed"):
		return UITheme.WARNING
	match status:
		"Boarding", "Pushback": return UITheme.ACCENT_HOVER
		"Departed", "On stand", "Cancelled": return UITheme.TEXT_DIM
		"Landed", "Approaching", "Taxiing": return UITheme.MONEY
	return UITheme.TEXT


# --- Showing a flight -------------------------------------------------------------

## Moves the camera to a flight's aircraft (opening it in the inspector), or
## to its stand if its aircraft isn't moving. Returns what it found:
## &"aircraft", &"stand" or &"" (nothing to show yet).
func show_flight(f: FlightScript) -> StringName:
	flight_shown.emit(f)
	var aircraft: Node3D = null
	if air_traffic != null:
		aircraft = air_traffic.get_aircraft_for(f)
		if aircraft == null and f.pair != null:
			aircraft = air_traffic.get_aircraft_for(f.pair)
	if aircraft != null:
		_focus(aircraft.global_position)
		if inspector != null:
			inspector.select_aircraft(aircraft)
		print("FLIGHT LIST | showing %s's aircraft" % f.flight_number)
		return &"aircraft"
	if stands != null and f.stand_id >= 0:
		var stand = stands.get_stand(f.stand_id)
		if stand != null:
			_focus(stand.stop)
			print("FLIGHT LIST | showing %s's stand %d" % [f.flight_number, f.stand_id])
			return &"stand"
	_summary.text = "%s isn't at the airport yet" % f.flight_number
	_refresh = 2.0
	return &""


func _focus(point: Vector3) -> void:
	if camera != null and camera.has_method(&"focus_on"):
		camera.focus_on(Vector3(point.x, 0.0, point.z))

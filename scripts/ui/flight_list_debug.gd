extends PanelContainer
## Debug list of today's flights (checklist step 22), toggled with F5:
## time, flight number, arrival or departure, aircraft type, route and status.
## Hidden by default and only refreshed while shown. Replaced later by the
## proper flight list screen.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const ACTION_TOGGLE := "toggle_flight_list"
## Text refreshes this often while shown, in real seconds.
const REFRESH_TIME := 0.5

var _label: Label
var _refresh_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F5
		InputMap.action_add_event(ACTION_TOGGLE, key)
	add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.7), 4, 10, 8))
	_label = UITheme.label("", UITheme.FONT_SIZE_SMALL)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	_label.add_theme_font_override(&"font", mono)
	add_child(_label)
	visible = false
	FlightSchedule.flights_created.connect(func(_day: int, _flights: Array) -> void: _refresh_timer = 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		visible = not visible
		_refresh_timer = 0.0
		print("DEBUG | flight list %s" % ("shown" if visible else "hidden"))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_TIME
	_label.text = build_text()


## The list as text (also used by the test).
func build_text() -> String:
	var flights := FlightSchedule.get_today_flights()
	var lines := PackedStringArray()
	lines.append("TODAY'S FLIGHTS  %s  (F5)" % GameClock.get_date_string())
	lines.append("%-5s  %-7s  %-3s  %-4s  %-12s  %-5s  %s" % ["Time", "Flight", "", "Type", "From / to", "Stand", "Status"])
	if flights.is_empty():
		lines.append("No flights today")
	var now := GameClock.game_time
	for f in flights:
		var marker := " " if f.scheduled_time > now else "*"
		lines.append("%-5s%s %-7s  %-3s  %-4s  %-12s  %-5s  %s" % [f.get_time_string(), marker, f.flight_number,
			"ARR" if f.is_arrival() else "DEP", String(f.aircraft_type).to_upper(), f.route.left(12),
			str(f.stand_id) if f.stand_id != -1 else "-", f.get_status_name()])
	var arrivals := flights.filter(func(f) -> bool: return f.is_arrival()).size()
	lines.append("%d arrivals, %d departures   * = time passed" % [arrivals, flights.size() - arrivals])
	return "\n".join(lines)

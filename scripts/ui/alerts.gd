extends VBoxContainer
## Alerts (checklist step 38): short messages about problems, stacked down
## the right of the screen under the top bar. Each shows the game time and
## the problem, fades out after SHOW_TIME real seconds and can be clicked
## away. At most MAX_SHOWN are on screen; the newest is at the top.
##
## Alerts have a key (such as "stand:BQ 101" or "no_checkin"): one already
## raised isn't shown again until REPEAT_AFTER game seconds have passed or
## it has been resolved (resolve(key)), so a lasting problem doesn't flood the
## screen but comes back if it is still there later.
## AirportChecks (airport_checks.gd) raises them.

const UITheme := preload("res://scripts/ui/ui_theme.gd")

enum Level { WARNING, PROBLEM }

const SHOW_TIME := 8.0
const FADE_TIME := 1.0
const MAX_SHOWN := 5
const REPEAT_AFTER := 3 * 3600
const WIDTH := 340.0
const TOP := 48.0

## Emitted for every alert shown.
signal alert_raised(key: String, text: String, level: Level)

## Key -> game time it was last shown.
var _raised := {}
## Alerts on screen, newest first: {key, panel, timer}.
var _shown: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	custom_minimum_size.x = WIDTH


## Shows an alert unless the same key was shown less than REPEAT_AFTER game
## seconds ago and hasn't been resolved. Returns true if it was shown.
func raise_alert(key: String, text: String, level := Level.WARNING) -> bool:
	var now := GameClock.game_time
	if _raised.has(key) and now - int(_raised[key]) < REPEAT_AFTER:
		return false
	_raised[key] = now
	print("ALERT | %s %s" % [GameClock.get_time_string(), text])
	_show(key, "%s  %s" % [GameClock.get_time_string(), text], level)
	alert_raised.emit(key, text, level)
	return true


## The problem behind key is fixed: it will be shown again straight away if it comes back.
func resolve(key: String) -> void:
	_raised.erase(key)


func is_raised(key: String) -> bool:
	return _raised.has(key)


## Texts on screen, newest first (also used by the test).
func get_shown_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for a in _shown:
		out.append(a.label.text)
	return out


func dismiss_all() -> void:
	for a in _shown.duplicate():
		_remove(a)


func _show(key: String, text: String, level: Level) -> void:
	var panel := PanelContainer.new()
	var colour := UITheme.DANGER if level == Level.PROBLEM else UITheme.WARNING
	var style := UITheme.panel_style(UITheme.PANEL, UITheme.RADIUS, 12, 8)
	style.border_width_left = 4
	style.border_color = colour
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.tooltip_text = "Click to dismiss"
	var label := UITheme.label(text, UITheme.FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 30.0
	panel.add_child(label)
	add_child(panel)
	move_child(panel, 0)
	var a := {"key": key, "panel": panel, "label": label, "timer": SHOW_TIME}
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_remove(a))
	_shown.push_front(a)
	while _shown.size() > MAX_SHOWN:
		_remove(_shown[-1])
	_place()


func _remove(a: Dictionary) -> void:
	_shown.erase(a)
	if is_instance_valid(a.panel):
		a.panel.queue_free()


func _process(delta: float) -> void:
	for a in _shown.duplicate():
		a.timer -= delta
		a.panel.modulate.a = clampf(a.timer / FADE_TIME, 0.0, 1.0)
		if a.timer <= 0.0:
			_remove(a)
	_place()


func _place() -> void:
	reset_size()
	position = Vector2(get_viewport_rect().size.x - WIDTH - 12.0, TOP)

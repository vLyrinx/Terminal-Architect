extends PanelContainer
## Top bar (checklist step 15): money on the left, in-game date and time in the
## middle, game speed buttons on the right. The buttons and the keyboard
## shortcuts (Space, 1, 2, 3) both go through GameClock, so they stay in step.
## Text only changes on signals, never every frame.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const PAUSE_ICON := preload("res://ui/icons/pause.svg")
const SPEED_LABELS := ["1x", "2x", "4x"]
const SPEED_KEYS := ["1", "2", "3"]
## How long the last money change stays next to the balance, in real seconds.
const CHANGE_SHOW_TIME := 2.5
const HEIGHT := 40.0

## The flight list screen (flight_list.gd), opened by the Flights button (step 37).
@export var flight_list: Control

var _balance: Label
var _change: Label
var _change_timer := 0.0
var _date: Label
var _time: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size.y = HEIGHT
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BAR, 0, 14, 4))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# Left: money
	var left := HBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	_balance = UITheme.label("", UITheme.FONT_SIZE_LARGE, UITheme.MONEY)
	_balance.tooltip_text = "Balance"
	_balance.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(_balance)
	_change = UITheme.label("", UITheme.FONT_SIZE)
	_change.modulate.a = 0.0
	left.add_child(_change)

	# Middle: date and time
	var middle := HBoxContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_theme_constant_override("separation", 12)
	row.add_child(middle)
	_date = UITheme.label("", UITheme.FONT_SIZE, UITheme.TEXT_DIM)
	middle.add_child(_date)
	_time = UITheme.label("", UITheme.FONT_SIZE_LARGE)
	middle.add_child(_time)

	# Right: game speed
	var right := HBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	if flight_list != null:
		var flights := _make_button("Flights", "Today's flights (F5)")
		flights.custom_minimum_size.x = 72
		flights.pressed.connect(flight_list.toggle)
		flight_list.toggled.connect(flights.set_pressed_no_signal)
		right.add_child(flights)
		var gap := Control.new()
		gap.custom_minimum_size.x = 12
		right.add_child(gap)
	_pause_button = _make_button("", "Pause (Space)")
	_pause_button.icon = PAUSE_ICON
	_pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Amber while paused, so it reads differently from the selected speed.
	_pause_button.add_theme_stylebox_override("pressed", UITheme.flat(UITheme.WARNING))
	_pause_button.add_theme_stylebox_override("hover_pressed", UITheme.flat(UITheme.WARNING.lightened(0.15)))
	_pause_button.pressed.connect(GameClock.toggle_pause)
	right.add_child(_pause_button)
	for i in GameClock.SPEED_STEPS.size():
		var b := _make_button(SPEED_LABELS[i], "Speed %s (%s)" % [SPEED_LABELS[i], SPEED_KEYS[i]])
		var step: float = GameClock.SPEED_STEPS[i]
		b.pressed.connect(func() -> void: GameClock.set_speed(step))
		right.add_child(b)
		_speed_buttons.append(b)

	Money.balance_changed.connect(_on_balance_changed)
	GameClock.minute_passed.connect(_on_minute_passed)
	GameClock.speed_changed.connect(_on_speed_changed)
	_balance.text = Money.format(Money.balance)
	_update_clock()
	_on_speed_changed(GameClock.speed, GameClock.paused)


func _process(delta: float) -> void:
	if _change_timer <= 0.0:
		return
	_change_timer -= delta
	_change.modulate.a = clampf(_change_timer / 0.5, 0.0, 1.0)  # fades over the last half second


func _make_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(40, 30)
	b.add_theme_constant_override("icon_max_width", 14)
	# No keyboard focus, so Space always goes to the pause shortcut
	# instead of pressing whichever button was clicked last.
	b.focus_mode = Control.FOCUS_NONE
	return b


func _update_clock() -> void:
	var dt := GameClock.get_datetime()
	_date.text = "%s %d %s %d" % [GameClock.WEEKDAY_NAMES[dt.weekday].left(3), dt.day,
		GameClock.MONTH_NAMES[dt.month - 1].left(3), dt.year]
	_time.text = GameClock.get_time_string()


func _on_minute_passed(_minute: int) -> void:
	_update_clock()


func _on_speed_changed(speed: float, paused: bool) -> void:
	_pause_button.set_pressed_no_signal(paused)
	_pause_button.tooltip_text = "Resume (Space)" if paused else "Pause (Space)"
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(not paused and is_equal_approx(speed, GameClock.SPEED_STEPS[i]))
	_time.add_theme_color_override("font_color", UITheme.WARNING if paused else UITheme.TEXT)


func _on_balance_changed(balance: int, change: int) -> void:
	_balance.text = Money.format(balance)
	_balance.add_theme_color_override("font_color", UITheme.DANGER if balance < 0 else UITheme.MONEY)
	_change.text = ("+" if change > 0 else "") + Money.format(change)
	_change.add_theme_color_override("font_color", UITheme.MONEY if change > 0 else UITheme.DANGER)
	_change.modulate.a = 1.0
	_change_timer = CHANGE_SHOW_TIME

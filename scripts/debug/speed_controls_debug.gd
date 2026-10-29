extends HBoxContainer
## Temporary game speed buttons (checklist step 4).
## The top bar in step 15 will replace these.

const LABELS := ["1x", "2x", "4x"]

var _pause_button: Button
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_pause_button = _make_button("Pause")
	_pause_button.pressed.connect(GameClock.toggle_pause)
	for i in GameClock.SPEED_STEPS.size():
		var b := _make_button(LABELS[i])
		var step: float = GameClock.SPEED_STEPS[i]
		b.pressed.connect(func() -> void: GameClock.set_speed(step))
		_speed_buttons.append(b)
	GameClock.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(GameClock.speed, GameClock.paused)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(64, 36)
	# No keyboard focus, so Space always goes to the pause shortcut
	# instead of pressing whichever button was clicked last.
	b.focus_mode = Control.FOCUS_NONE
	add_child(b)
	return b


func _on_speed_changed(speed: float, paused: bool) -> void:
	_pause_button.set_pressed_no_signal(paused)
	_pause_button.text = "Resume" if paused else "Pause"
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(not paused and is_equal_approx(speed, GameClock.SPEED_STEPS[i]))
	print("CLOCK SPEED | %s" % ("paused" if paused else "%dx" % int(speed)))

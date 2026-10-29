extends VBoxContainer
## Temporary money readout (checklist step 14), top right: the balance, and
## under it the last change for a moment (red when spent, green when earned).
## Will move into the top bar in step 15.

## How long the last change stays on screen, in real seconds.
const CHANGE_SHOW_TIME := 2.5
const SPEND_COLOR := Color(1.0, 0.55, 0.5)
const EARN_COLOR := Color(0.55, 0.95, 0.6)

var _balance: Label
var _change: Label
var _change_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_balance = _make_label(26)
	_change = _make_label(18)
	_change.modulate.a = 0.0
	Money.balance_changed.connect(_on_balance_changed)
	_balance.text = Money.format(Money.balance)


func _process(delta: float) -> void:
	if _change_timer <= 0.0:
		return
	_change_timer -= delta
	_change.modulate.a = clampf(_change_timer / 0.5, 0.0, 1.0)  # fades over the last half second


func _on_balance_changed(balance: int, change: int) -> void:
	_balance.text = Money.format(balance)
	_balance.modulate = Color(1.0, 0.75, 0.75) if balance < 0 else Color.WHITE
	_change.text = ("+" if change > 0 else "") + Money.format(change)
	_change.add_theme_color_override("font_color", EARN_COLOR if change > 0 else SPEND_COLOR)
	_change.modulate.a = 1.0
	_change_timer = CHANGE_SHOW_TIME


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

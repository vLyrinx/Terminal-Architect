extends PanelContainer
## Temporary message box (checklist step 14), top centre: shows why the last
## command was refused, such as "Not enough money: needs $15,000, you have
## $9,200", then fades out. Proper alerts come in step 38.

## How long a message stays on screen, in real seconds.
const SHOW_TIME := 3.0

## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _label: Label
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.72, 0.2, 0.2, 0.92)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	visible = false
	command_runner.command_failed.connect(_on_command_failed)


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	modulate.a = clampf(_timer / 0.5, 0.0, 1.0)
	if _timer <= 0.0:
		visible = false


## Shows a message for SHOW_TIME seconds.
func show_message(text: String) -> void:
	_label.text = text
	_timer = SHOW_TIME
	modulate.a = 1.0
	visible = true
	reset_size()  # shrink to the new text, then centre it below the top edge
	position.x = (get_viewport_rect().size.x - size.x) * 0.5


func _on_command_failed(command: RefCounted) -> void:
	if command.error != "":
		show_message(command.error)

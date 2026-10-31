extends PanelContainer
## Message box (checklist step 14, restyled in step 15), top centre just under
## the top bar: shows why the last command was refused, such as "Not enough
## money: needs $15,000, you have $9,200", then fades out. Problems in the
## airport go to the Alerts list instead (alerts.gd, step 38).

const UITheme := preload("res://scripts/ui/ui_theme.gd")
## Distance from the top of the screen, below the top bar.
const TOP := 48.0

## How long a message stays on screen, in real seconds.
const SHOW_TIME := 3.0

## The CommandRunner node (command_runner.gd).
@export var command_runner: Node

var _label: Label
var _timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.DANGER_BG, UITheme.RADIUS, 16, 7))
	_label = UITheme.label("", UITheme.FONT_SIZE)
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
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, TOP)


func _on_command_failed(command: RefCounted) -> void:
	if command.error != "":
		show_message(command.error)

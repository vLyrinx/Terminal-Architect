extends VBoxContainer
## Temporary build bar (checklist step 7): one button per build tool and a hint line.
## The real build menu comes later.

## The BuildManager node (build_manager.gd).
@export var build_manager: Node3D

var _hint: Label
var _buttons := {}


func _ready() -> void:
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	add_child(_hint)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for tool in build_manager.tools:
		var b := Button.new()
		var key_name := OS.get_keycode_string(tool.shortcut) if tool.shortcut != KEY_NONE else ""
		b.text = "%s (%s)" % [tool.tool_name, key_name] if key_name else tool.tool_name
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(build_manager.toggle_tool.bind(tool))
		row.add_child(b)
		_buttons[tool] = b

	build_manager.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(build_manager.active_tool)


func _on_tool_changed(tool: Node) -> void:
	for t: Node in _buttons:
		_buttons[t].set_pressed_no_signal(t == tool)
	if tool:
		_hint.text = "Building: %s   |   %s" % [tool.tool_name, tool.get_hint()]
	else:
		_hint.text = "Build mode off. Pick a tool below."

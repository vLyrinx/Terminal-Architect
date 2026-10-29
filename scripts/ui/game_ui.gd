extends Control
## Root of the game UI (checklist step 15). Fills the screen without taking the
## mouse, and gives every UI control under it the shared flat theme (ui_theme.gd).

const UITheme := preload("res://scripts/ui/ui_theme.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.build()

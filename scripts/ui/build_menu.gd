extends Control
## Bottom build menu (checklist step 15), in the style of Airport CEO.
##
## A bar of category buttons along the bottom. Clicking one opens a panel of
## its items (icon, name and cost); clicking an item selects its build tool,
## and a strip above shows the selected tool and its controls. Items come from
## each BuildTool's get_menu_items() (objects from their data files), sorted
## into the categories in build_categories.gd, so new tools appear on their own.
## Categories with no items are greyed out.
##
##   Esc / right click   cancel the tool and close the panel
## Picking a tool by its shortcut key opens its category too.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const BuildCategories := preload("res://scripts/ui/build_categories.gd")
## A right click counts as a click (not a camera drag) if the mouse moves less than this, in pixels.
const CLICK_TOLERANCE := 6.0
const CARD_SIZE := Vector2(108, 100)
const CARD_ICON_SIZE := Vector2(34, 34)

## The BuildManager node (build_manager.gd).
@export var build_manager: Node3D

## Category ID -> Array of menu item Dictionaries (see BuildTool.get_menu_items()).
var _items := {}
var _category_buttons := {}
## Item ID -> card Button, for the open panel only.
var _cards := {}
var _open_category := ""
var _keep_panel := false
var _right_press_pos := Vector2.ZERO
var _right_pressed := false

var _tool_info: PanelContainer
var _tool_title: Label
var _tool_hint: Label
var _item_panel: PanelContainer
var _item_title: Label
var _item_row: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -8

	# Selected tool and its controls
	_tool_info = PanelContainer.new()
	_tool_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tool_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tool_info.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.BAR, 0.92), UITheme.RADIUS, 14, 5))
	column.add_child(_tool_info)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 0)
	_tool_info.add_child(info)
	_tool_title = UITheme.label("", UITheme.FONT_SIZE)
	_tool_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_tool_title)
	_tool_hint = UITheme.label("", UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	_tool_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(_tool_hint)

	# Item panel for the open category
	_item_panel = PanelContainer.new()
	_item_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_item_panel)
	var panel_box := VBoxContainer.new()
	panel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_box.add_theme_constant_override("separation", 6)
	_item_panel.add_child(panel_box)
	_item_title = UITheme.label("", UITheme.FONT_SIZE_SMALL, UITheme.TEXT_DIM)
	panel_box.add_child(_item_title)
	_item_row = HBoxContainer.new()
	_item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_row.add_theme_constant_override("separation", 6)
	panel_box.add_child(_item_row)

	# Category bar
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.BAR, UITheme.RADIUS + 2, 6, 6))
	column.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_theme_constant_override("separation", 6)
	bar.add_child(bar_row)
	for category: Dictionary in BuildCategories.LIST:
		var b := Button.new()
		b.text = category.name
		b.icon = category.icon
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 58)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 26)
		b.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		b.pressed.connect(_on_category_pressed.bind(category.id))
		bar_row.add_child(b)
		_category_buttons[category.id] = b

	_collect_items()
	build_manager.tool_changed.connect(_on_tool_changed)
	_close_panel()
	_on_tool_changed(build_manager.active_tool)


func _unhandled_input(event: InputEvent) -> void:
	# With a tool active the BuildManager handles Esc; closing the panel follows from tool_changed.
	if _open_category != "" and build_manager.active_tool == null \
			and event.is_action_pressed(build_manager.ACTION_CANCEL):
		_close_panel()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if event.pressed:
		_right_pressed = true
		_right_press_pos = event.position
	elif _right_pressed:
		_right_pressed = false
		if build_manager.active_tool == null and _open_category != "" \
				and event.position.distance_to(_right_press_pos) < CLICK_TOLERANCE:
			_close_panel()


## Rebuilds the item lists from the tools, and greys out empty categories.
func _collect_items() -> void:
	_items.clear()
	for category: Dictionary in BuildCategories.LIST:
		_items[category.id] = []
	for tool in build_manager.tools:
		for item: Dictionary in tool.get_menu_items():
			if _items.has(item.category):
				_items[item.category].append(item)
			else:
				push_warning("BuildMenu: %s has unknown category '%s'" % [item.id, item.category])
	for id: String in _category_buttons:
		var b: Button = _category_buttons[id]
		var empty: bool = _items[id].is_empty()
		b.disabled = empty
		b.tooltip_text = "Nothing to build here yet" if empty else ""


func _open_panel(category_id: String) -> void:
	_collect_items()
	_open_category = category_id
	for id: String in _category_buttons:
		_category_buttons[id].set_pressed_no_signal(id == category_id)
	for child in _item_row.get_children():
		child.queue_free()
	_cards.clear()
	for category: Dictionary in BuildCategories.LIST:
		if category.id == category_id:
			_item_title.text = category.name.to_upper()
	for item: Dictionary in _items[category_id]:
		var card := _make_card(item)
		_item_row.add_child(card)
		_cards[item.id] = card
	_item_panel.visible = true
	_update_card_states()


func _close_panel() -> void:
	_open_category = ""
	for id: String in _category_buttons:
		_category_buttons[id].set_pressed_no_signal(false)
	_item_panel.visible = false


func _make_card(item: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = item.tooltip
	card.pressed.connect(_on_item_pressed.bind(item))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = 4
	box.offset_bottom = -4

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = item.icon
	icon.custom_minimum_size = CARD_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var name_label := UITheme.label(item.name, UITheme.FONT_SIZE_SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	box.add_child(name_label)

	if item.cost != "":
		var cost_label := UITheme.label(item.cost, UITheme.FONT_SIZE_SMALL, UITheme.MONEY)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cost_label)
	return card


## Highlights the card of the item the active tool is set to.
func _update_card_states() -> void:
	var tool: Node = build_manager.active_tool
	var active_id: String = tool.get_active_item_id() if tool else ""
	for id: String in _cards:
		var item_tool: Node = null
		for item: Dictionary in _items[_open_category]:
			if item.id == id:
				item_tool = item.tool
		_cards[id].set_pressed_no_signal(tool != null and item_tool == tool and id == active_id)


func _on_category_pressed(category_id: String) -> void:
	if _open_category == category_id:
		_close_panel()
	else:
		_open_panel(category_id)


func _on_item_pressed(item: Dictionary) -> void:
	var tool: Node = item.tool
	if build_manager.active_tool == tool and tool.get_active_item_id() == item.id:
		_keep_panel = true  # clicking the selected item puts the tool away but keeps the panel
		build_manager.select_tool(null)
		_keep_panel = false
	else:
		build_manager.select_item(tool, item.id)


func _on_tool_changed(tool: Node) -> void:
	_tool_info.visible = tool != null
	if tool == null:
		if _keep_panel:
			_update_card_states()
		else:
			_close_panel()
		return
	var cost: String = tool.get_cost_text()
	_tool_title.text = tool.get_title() if cost == "" else "%s   %s" % [tool.get_title(), cost]
	_tool_hint.text = tool.get_hint()
	# Open the category of the item the tool is set to (for shortcut keys and Tab).
	var category := _find_category(tool, tool.get_active_item_id())
	if category != "" and category != _open_category:
		_open_panel(category)
	else:
		_update_card_states()


func _find_category(tool: Node, item_id: String) -> String:
	for category: String in _items:
		for item: Dictionary in _items[category]:
			if item.tool == tool and item.id == item_id:
				return category
	return ""

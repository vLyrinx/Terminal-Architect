class_name BuildManager
extends Node3D
## Build mode framework (checklist step 7).
##
## Knows the active build tool and feeds it mouse input in tiles.
## Tools are BuildTool child nodes, registered automatically, so new tools
## (floors, walls, objects, runways) are added by dropping a node in the scene.
##
##   Left click / drag   build with the active tool
##   Right click         cancel the current drag, or leave build mode
##                       (a right drag still rotates the camera)
##   Esc                 same as right click
##   Tool shortcut key   pick that tool (press again to put it away)

## Emitted when the active tool changes (null when build mode is left).
signal tool_changed(tool: Node)

## Loaded by path so this works before the editor has registered class names.
const BuildToolScript := preload("res://scripts/building/build_tool.gd")

const ACTION_CANCEL := "build_cancel"
## A right click counts as a click (not a camera drag) if the mouse moves less than this, in pixels.
const CLICK_TOLERANCE := 6.0

## Floor that building happens on (only floor 0 for now).
@export var floor_index := 0

var tools: Array[BuildToolScript] = []
var active_tool: BuildToolScript
## Node that built things are added to.
var built_root: Node3D

var _dragging := false
var _hover_tile := Vector2i(-1, -1)
var _hover_in_plot := false
var _right_press_pos := Vector2.ZERO
var _right_pressed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # building works while the clock is paused
	if not InputMap.has_action(ACTION_CANCEL):
		InputMap.add_action(ACTION_CANCEL)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(ACTION_CANCEL, key)

	built_root = Node3D.new()
	built_root.name = "Built"
	add_child(built_root)

	for child in get_children():
		if child is BuildToolScript:
			child.manager = self
			tools.append(child)


# --- Tool selection -----------------------------------------------------------

## Makes a tool active, or leaves build mode when tool is null.
func select_tool(tool: BuildToolScript) -> void:
	if tool == active_tool:
		return
	if active_tool:
		if _dragging:
			active_tool.cancel_drag()
		active_tool.deactivate()
	_dragging = false
	active_tool = tool
	_hover_tile = Vector2i(-1, -1)
	_hover_in_plot = false
	if active_tool:
		active_tool.activate()
	tool_changed.emit(active_tool)
	print("BUILD | %s" % (active_tool.tool_name if active_tool else "no tool"))


## Picks one build menu entry of a tool (checklist step 15), such as one
## object type of the object tool, and makes that tool active.
func select_item(tool: BuildToolScript, item_id: String) -> void:
	if _dragging and tool == active_tool:
		_dragging = false
		active_tool.cancel_drag()
	tool.select_item(item_id)
	if tool == active_tool:
		tool_changed.emit(tool)  # same tool, new entry: refresh the menu and hint
		print("BUILD | %s" % tool.get_title())
	else:
		select_tool(tool)


## Picks the tool, or puts it away if it is already active.
func toggle_tool(tool: BuildToolScript) -> void:
	select_tool(null if tool == active_tool else tool)


## Cancels the current drag, or leaves build mode if nothing is being dragged.
func cancel() -> void:
	if active_tool == null:
		return
	if _dragging:
		_dragging = false
		active_tool.cancel_drag()
		_send_hover()
	else:
		select_tool(null)


func is_building() -> bool:
	return active_tool != null


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for tool in tools:
			if tool.shortcut != KEY_NONE and event.physical_keycode == tool.shortcut:
				toggle_tool(tool)
				get_viewport().set_input_as_handled()
				return
	if active_tool == null:
		return
	if event.is_action_pressed(ACTION_CANCEL):
		cancel()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_update_hover()
		if _hover_in_plot:
			_dragging = true
			active_tool.press(_hover_tile)
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Releases are read here so they still count when the mouse is over UI.
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_pressed = true
			_right_press_pos = event.position
		elif _right_pressed:
			_right_pressed = false
			if active_tool and event.position.distance_to(_right_press_pos) < CLICK_TOLERANCE:
				cancel()
	elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_dragging = false
		_update_hover()
		active_tool.release(_hover_tile, _hover_in_plot)
		_send_hover()


func _process(_delta: float) -> void:
	if active_tool:
		_update_hover()


func _update_hover() -> void:
	var viewport := get_viewport()
	var tile := Vector2i(-1, -1)
	var in_plot := false
	if viewport.gui_get_hovered_control() == null:
		var pick := BuildGrid.screen_to_tile(viewport.get_camera_3d(), viewport.get_mouse_position(), floor_index)
		if pick.hit:
			tile = pick.tile
			in_plot = pick.in_plot
	if tile == _hover_tile and in_plot == _hover_in_plot:
		return
	_hover_tile = tile
	_hover_in_plot = in_plot
	_send_hover()


## Tells the active tool where the mouse is: drag() while dragging, otherwise hover().
func _send_hover() -> void:
	if active_tool == null:
		return
	if _dragging:
		active_tool.drag(_hover_tile, _hover_in_plot)
	else:
		active_tool.hover(_hover_tile, _hover_in_plot)

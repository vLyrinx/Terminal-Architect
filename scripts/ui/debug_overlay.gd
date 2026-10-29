extends PanelContainer
## Debug overlay (checklist step 15), toggled with F3: frame rate, draw calls,
## the tile under the mouse and the simulation tick counter. Hidden by default
## and only updated while shown. It also writes clock events to the output log
## (CLOCK START / SPEED / HOUR / DAY lines), shown or not.

const UITheme := preload("res://scripts/ui/ui_theme.gd")
const ACTION_TOGGLE := "toggle_debug_overlay"
## Text refreshes this often while shown, in real seconds.
const REFRESH_TIME := 0.25

## The TileHighlight node (tile_highlighter.gd), for the hovered tile.
@export var tile_highlighter: Node3D
## Optional RouteGraph node (route_graph.gd), for its node and edge counts.
@export var route_graph: Node

var _label: Label
var _refresh_timer := 0.0
var _tile_text := "none"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F3
		InputMap.action_add_event(ACTION_TOGGLE, key)

	add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.6), 4, 8, 6))
	_label = UITheme.label("", UITheme.FONT_SIZE_SMALL)
	add_child(_label)
	visible = false

	if tile_highlighter:
		tile_highlighter.hovered_tile_changed.connect(_on_hovered_tile_changed)
	GameClock.hour_passed.connect(_on_hour_passed)
	GameClock.day_passed.connect(_on_day_passed)
	GameClock.speed_changed.connect(_on_speed_changed)
	print("CLOCK START | %s %s" % [GameClock.get_date_string(), GameClock.get_time_string()])
	_on_speed_changed(GameClock.speed, GameClock.paused)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		visible = not visible
		_refresh_timer = 0.0
		print("DEBUG | overlay %s" % ("shown" if visible else "hidden"))
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_TIME
	_label.text = "FPS %d (%.1f ms)   draw calls %d\nTile %s\nDay %d   ticks %d (%d per second)" % [
		Engine.get_frames_per_second(),
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		_tile_text,
		GameClock.get_day_number(),
		GameClock.tick_count,
		GameClock.ticks_last_second,
	]
	if route_graph:
		_label.text += "\nRoute graph %d nodes, %d edges (F4 to draw)" % [
			route_graph.get_node_count(), route_graph.get_edge_count()]


func _on_hovered_tile_changed(tile: Vector2i, in_plot: bool) -> void:
	_tile_text = "%d, %d" % [tile.x, tile.y] if in_plot else "none"


func _on_hour_passed(hour: int) -> void:
	print("CLOCK HOUR | %02d:00 | ticks=%d | real_time=%.1fs" % [
		hour, GameClock.tick_count, Time.get_ticks_msec() / 1000.0])


func _on_day_passed(_datetime: Dictionary) -> void:
	print("CLOCK DAY | %s" % GameClock.get_date_string())


func _on_speed_changed(speed: float, paused: bool) -> void:
	print("CLOCK SPEED | %s" % ("paused" if paused else "%dx" % int(speed)))

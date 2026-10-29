extends "res://scripts/building/build_tool.gd"
## Zone tool (checklist step 10): drag a rectangle to paint one zone onto floor
## tiles, like the floor tool. The scene has one of these per zone (landside,
## security, airside).
##
##   Left drag            paint the zone in the rectangle (floor tiles only)
##   Shift + left drag    erase zones in the rectangle
## The ghost shows the zone colour, or red when erasing, and a label shows the
## rectangle size. Shift is read when the mouse button is released, so it can
## be pressed or let go mid-drag. The zone overlay shows while a zone tool is in use.

const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const GHOST_HEIGHT := 0.06
const NO_TILE := Vector2i(-1, -1)

## Zone this tool paints.
@export_enum("Landside:1", "Security:2", "Airside:3") var zone := 1
## The TerminalZones node (terminal_zones.gd).
@export var terminal_zones: Node3D

var _ghost: MeshInstance3D
var _paint_material: StandardMaterial3D
var _label: Label3D
var _dragging := false
var _start := Vector2i.ZERO
var _end := Vector2i.ZERO
var _hover_tile := NO_TILE
var _hover_in_plot := false
var _removing := false


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = make_ghost(box)
	_paint_material = ghost_material(true).duplicate() as StandardMaterial3D
	var color: Color = TerminalZonesScript.ZONE_COLORS[zone]
	_paint_material.albedo_color = Color(color, 0.6)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0015
	_label.font_size = 28
	_label.outline_size = 8
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	if not is_active():
		return
	var removing := Input.is_physical_key_pressed(KEY_SHIFT)
	if removing != _removing:
		_removing = removing
		_update_ghost()


func activate() -> void:
	terminal_zones.set_overlay_forced(true)


func deactivate() -> void:
	terminal_zones.set_overlay_forced(false)
	_dragging = false
	_ghost.visible = false
	_label.visible = false


func hover(tile: Vector2i, in_plot: bool) -> void:
	_hover_tile = tile
	_hover_in_plot = in_plot
	_update_ghost()


func press(tile: Vector2i) -> void:
	_dragging = true
	_start = tile
	_end = tile
	_update_ghost()


func drag(tile: Vector2i, in_plot: bool) -> void:
	# Off the plot the rectangle stops at the plot edge; over the UI it keeps its last size.
	if in_plot:
		_end = tile
	elif tile != NO_TILE:
		_end = BuildGrid.clamp_to_plot(tile)
	_update_ghost()


func release(tile: Vector2i, in_plot: bool) -> void:
	drag(tile, in_plot)
	_dragging = false
	_removing = Input.is_physical_key_pressed(KEY_SHIFT)
	var rect := BuildGrid.rect_from_tiles(_start, _end)
	var value: int = TerminalZonesScript.Zone.NONE if _removing else zone
	var changed: int = terminal_zones.paint_rect(rect, value, get_floor())
	print("BUILD | zones %s: %d tiles in %d x %d (landside %d, security %d, airside %d)" % [
		"erased" if _removing else "painted %s" % _zone_name(), changed, rect.size.x, rect.size.y,
		terminal_zones.count_zone(TerminalZonesScript.Zone.LANDSIDE, get_floor()),
		terminal_zones.count_zone(TerminalZonesScript.Zone.SECURITY, get_floor()),
		terminal_zones.count_zone(TerminalZonesScript.Zone.AIRSIDE, get_floor())])
	_hover_tile = tile
	_hover_in_plot = in_plot
	_update_ghost()


func cancel_drag() -> void:
	_dragging = false
	_update_ghost()


func get_hint() -> String:
	return "Drag on floor: paint %s   Shift + drag: erase   Right click / Esc: cancel" % _zone_name()


func _zone_name() -> String:
	return TerminalZonesScript.ZONE_NAMES[zone]


func _update_ghost() -> void:
	var shown := _dragging or _hover_in_plot
	_ghost.visible = shown
	_label.visible = shown and _dragging
	if not shown:
		return
	var rect := BuildGrid.rect_from_tiles(_start, _end) if _dragging else Rect2i(_hover_tile, Vector2i.ONE)
	var corner := BuildGrid.tile_corner_to_world(rect.position, get_floor())
	var size := Vector3(rect.size.x, 0.0, rect.size.y) * BuildGrid.TILE_SIZE
	var top := TerminalFloorScript.THICKNESS
	_ghost.global_position = corner + size * 0.5 + Vector3.UP * (top + GHOST_HEIGHT * 0.5)
	_ghost.scale = Vector3(size.x, GHOST_HEIGHT, size.z)
	_ghost.material_override = ghost_material(false) if _removing else _paint_material

	if _dragging:
		var value: int = TerminalZonesScript.Zone.NONE if _removing else zone
		var changes: int = terminal_zones.count_paint_changes(rect, value, get_floor())
		_label.text = "%d x %d   %s %d" % [rect.size.x, rect.size.y,
			"erase" if _removing else _zone_name().to_lower(), changes]
		_label.modulate = Color(1.0, 0.75, 0.75) if _removing else Color.WHITE
		_label.global_position = corner + size * 0.5 + Vector3.UP * 1.5

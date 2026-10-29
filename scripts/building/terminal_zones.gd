class_name TerminalZones
extends Node3D
## Terminal zones (checklist step 10).
##
## Stores one zone per floor tile: landside, security or airside. Zones can only
## be painted on terminal floor, and are cleared when that floor is removed.
## Pathfinding will read them with get_zone() to decide where people may walk.
##
## The overlay (Z key) tints tiles by zone. It is one plane over the plot whose
## shader reads a texture with one pixel per tile, so it costs a single draw
## call. It also shows while a zone tool is in use.
##
## Keep this node at the world origin.

## Emitted after zones change. rect is the area that was edited, in tiles.
signal zones_changed(rect: Rect2i, floor_index: int)
signal overlay_visibility_changed(overlay_visible: bool)

enum Zone { NONE, LANDSIDE, SECURITY, AIRSIDE }

const ZONE_NAMES := ["None", "Landside", "Security", "Airside"]
## Same colours as the overlay shader, for UI and tool previews.
const ZONE_COLORS := [Color.TRANSPARENT, Color(0.30, 0.62, 0.96), Color(0.98, 0.72, 0.20), Color(0.64, 0.42, 0.92)]
const OVERLAY_SHADER := preload("res://materials/zone_overlay.gdshader")
const TerminalFloorScript := preload("res://scripts/building/terminal_floor.gd")
const ACTION_TOGGLE_OVERLAY := "toggle_zone_overlay"
## Overlay height above the floor surface, so it never flickers into it.
const OVERLAY_LIFT := 0.015

## The TerminalFloor node (terminal_floor.gd). Zones need floor under them.
@export var terminal_floor: Node3D
## Floor whose zones the overlay shows (only floor 0 for now).
@export var overlay_floor := 0

## Overlay switched on with the Z key.
var overlay_visible := false

## Per floor index: one byte per plot tile holding a Zone value.
var _zones := {}
## Number of tools currently forcing the overlay on.
var _overlay_forced := 0
var _overlay: MeshInstance3D
var _overlay_image: Image
var _overlay_texture: ImageTexture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the overlay toggles while paused
	if not InputMap.has_action(ACTION_TOGGLE_OVERLAY):
		InputMap.add_action(ACTION_TOGGLE_OVERLAY)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_Z
		InputMap.action_add_event(ACTION_TOGGLE_OVERLAY, key)

	var plot := BuildGrid.PLOT_TILES
	_overlay_image = Image.create(plot.x, plot.y, false, Image.FORMAT_R8)
	_overlay_texture = ImageTexture.create_from_image(_overlay_image)

	var rect := BuildGrid.get_plot_rect()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	var material := ShaderMaterial.new()
	material.shader = OVERLAY_SHADER
	material.set_shader_parameter("zone_map", _overlay_texture)
	material.set_shader_parameter("plot_min", rect.position)
	material.set_shader_parameter("tile_size", BuildGrid.TILE_SIZE)
	_overlay = MeshInstance3D.new()
	_overlay.name = "Overlay"
	_overlay.mesh = plane
	_overlay.material_override = material
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.position = Vector3(rect.get_center().x,
		BuildGrid.get_floor_height(overlay_floor) + TerminalFloorScript.THICKNESS + OVERLAY_LIFT,
		rect.get_center().y)
	add_child(_overlay)
	_update_overlay_visibility()

	if terminal_floor:
		terminal_floor.floor_changed.connect(_on_floor_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE_OVERLAY):
		set_overlay_visible(not overlay_visible)
		get_viewport().set_input_as_handled()


# --- Queries --------------------------------------------------------------------

## Zone of a tile (Zone.NONE if it has none or is outside the plot).
func get_zone(tile: Vector2i, floor_index := 0) -> int:
	var index := BuildGrid.tile_to_index(tile)
	if index < 0 or not _zones.has(floor_index):
		return Zone.NONE
	return _zones[floor_index][index]


## Number of tiles in a zone on a floor.
func count_zone(zone: int, floor_index := 0) -> int:
	if not _zones.has(floor_index):
		return 0
	return (_zones[floor_index] as PackedByteArray).count(zone)


## How many tiles paint_rect() would change.
func count_paint_changes(rect: Rect2i, zone: int, floor_index := 0) -> int:
	rect = rect.intersection(Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES))
	var count := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			if get_zone(tile, floor_index) != zone and (zone == Zone.NONE or can_zone(tile, floor_index)):
				count += 1
	return count


## True if the tile could be painted (it has terminal floor).
func can_zone(tile: Vector2i, floor_index := 0) -> bool:
	return terminal_floor != null and terminal_floor.has_floor(tile, floor_index)


# --- Editing --------------------------------------------------------------------

## Sets every floor tile in rect to zone (Zone.NONE erases). Tiles without
## floor are skipped. Returns how many tiles changed.
func paint_rect(rect: Rect2i, zone: int, floor_index := 0) -> int:
	rect = rect.intersection(Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return 0
	var zones := _get_zones(floor_index)
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if zones[row + x] == zone:
				continue
			if zone != Zone.NONE and not can_zone(Vector2i(x, y), floor_index):
				continue
			zones[row + x] = zone
			changed += 1
	_zones[floor_index] = zones  # packed arrays are copied on write, so store it back
	if changed > 0:
		_after_change(rect, floor_index)
	return changed


# --- Overlay --------------------------------------------------------------------

func set_overlay_visible(value: bool) -> void:
	if value == overlay_visible:
		return
	overlay_visible = value
	_update_overlay_visibility()
	print("ZONES | overlay %s" % ("shown" if overlay_visible else "hidden"))


## Tools call this with true while active and false when done, so the overlay
## shows while painting even if Z has it switched off.
func set_overlay_forced(forced: bool) -> void:
	_overlay_forced = maxi(_overlay_forced + (1 if forced else -1), 0)
	_update_overlay_visibility()


func is_overlay_shown() -> bool:
	return _overlay.visible


## The per-tile zone texture the overlay draws from (for tests and debugging).
func get_overlay_texture() -> ImageTexture:
	return _overlay_texture


func _update_overlay_visibility() -> void:
	var shown := overlay_visible or _overlay_forced > 0
	if _overlay.visible != shown:
		_overlay.visible = shown
		overlay_visibility_changed.emit(shown)


# --- Internals ------------------------------------------------------------------

func _get_zones(floor_index: int) -> PackedByteArray:
	if not _zones.has(floor_index):
		var zones := PackedByteArray()
		zones.resize(BuildGrid.get_tile_count())
		_zones[floor_index] = zones
	return _zones[floor_index]


func _after_change(rect: Rect2i, floor_index: int) -> void:
	if floor_index == overlay_floor:
		var plot := BuildGrid.PLOT_TILES
		_overlay_image.set_data(plot.x, plot.y, false, Image.FORMAT_R8, _zones[floor_index])
		_overlay_texture.update(_overlay_image)
	zones_changed.emit(rect, floor_index)


## Floor was laid or removed: clear zones from tiles that lost their floor.
func _on_floor_changed(rect: Rect2i, floor_index: int) -> void:
	if not _zones.has(floor_index):
		return
	var zones: PackedByteArray = _zones[floor_index]
	var changed := 0
	for y in range(rect.position.y, rect.end.y):
		var row := y * BuildGrid.PLOT_TILES.x
		for x in range(rect.position.x, rect.end.x):
			if zones[row + x] != Zone.NONE and not terminal_floor.has_floor(Vector2i(x, y), floor_index):
				zones[row + x] = Zone.NONE
				changed += 1
	_zones[floor_index] = zones
	if changed > 0:
		print("ZONES | %d zoned tiles cleared with their floor" % changed)
		_after_change(rect, floor_index)

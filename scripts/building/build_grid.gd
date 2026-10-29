extends Node
## BuildGrid (autoload). The square build grid every building system uses.
##
## Tiles are addressed with Vector2i(x, y), where x runs along world X and
## y runs along world Z. Tile (0, 0) is the corner of the plot at the most
## negative X and Z. The plot is centred on the world origin.
##
## Every query takes a floor index (0 = ground floor) so a second floor can be
## added later without changing callers. Only floor 0 exists for now.

## Emitted when the grid overlay is shown or hidden (G key).
signal grid_visibility_changed(grid_visible: bool)

## Size of one tile in metres.
const TILE_SIZE := 1.0
## Plot size in tiles.
const PLOT_TILES := Vector2i(400, 400)
## Height of one floor in metres (used once multiple floors exist).
const FLOOR_HEIGHT := 4.0
const ACTION_TOGGLE_GRID := "toggle_grid"

## World position of the outer corner of tile (0, 0).
var origin := Vector3(-PLOT_TILES.x * TILE_SIZE * 0.5, 0.0, -PLOT_TILES.y * TILE_SIZE * 0.5)
## Whether the grid overlay is shown.
var grid_visible := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action(ACTION_TOGGLE_GRID):
		InputMap.add_action(ACTION_TOGGLE_GRID)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_G
		InputMap.action_add_event(ACTION_TOGGLE_GRID, key)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE_GRID):
		set_grid_visible(not grid_visible)
		get_viewport().set_input_as_handled()


func set_grid_visible(value: bool) -> void:
	if value == grid_visible:
		return
	grid_visible = value
	grid_visibility_changed.emit(grid_visible)


# --- Tile and world conversion -------------------------------------------------

## World position of the centre of a tile, at floor level.
func tile_to_world(tile: Vector2i, floor_index := 0) -> Vector3:
	return origin + Vector3(
		(tile.x + 0.5) * TILE_SIZE,
		get_floor_height(floor_index),
		(tile.y + 0.5) * TILE_SIZE)


## World position of a tile's corner with the lowest X and Z (a grid line crossing).
func tile_corner_to_world(tile: Vector2i, floor_index := 0) -> Vector3:
	return origin + Vector3(tile.x * TILE_SIZE, get_floor_height(floor_index), tile.y * TILE_SIZE)


## Tile that contains a world position (height is ignored). May be outside the plot.
func world_to_tile(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_pos.x - origin.x) / TILE_SIZE),
		floori((world_pos.z - origin.z) / TILE_SIZE))


## Floor index nearest to a world height.
func world_to_floor(world_y: float) -> int:
	return maxi(roundi((world_y - origin.y) / FLOOR_HEIGHT), 0)


func get_floor_height(floor_index: int) -> float:
	return origin.y + floor_index * FLOOR_HEIGHT


# --- Plot queries -------------------------------------------------------------

func is_in_plot(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < PLOT_TILES.x and tile.y < PLOT_TILES.y


func clamp_to_plot(tile: Vector2i) -> Vector2i:
	return Vector2i(clampi(tile.x, 0, PLOT_TILES.x - 1), clampi(tile.y, 0, PLOT_TILES.y - 1))


## Index of a tile in a flat array of PLOT_TILES.x * PLOT_TILES.y entries
## (for per-tile data such as floors, zones and occupancy). -1 if outside the plot.
func tile_to_index(tile: Vector2i) -> int:
	if not is_in_plot(tile):
		return -1
	return tile.x + tile.y * PLOT_TILES.x


func index_to_tile(index: int) -> Vector2i:
	@warning_ignore("integer_division")  # whole-row maths is intended
	var row := index / PLOT_TILES.x
	return Vector2i(index % PLOT_TILES.x, row)


## Rectangle of tiles spanning two corner tiles (inclusive, in any order).
func rect_from_tiles(a: Vector2i, b: Vector2i) -> Rect2i:
	var top_left := a.min(b)
	return Rect2i(top_left, (a - b).abs() + Vector2i.ONE)


func get_tile_count() -> int:
	return PLOT_TILES.x * PLOT_TILES.y


## The plot on the ground as a rectangle in world X/Z.
func get_plot_rect() -> Rect2:
	return Rect2(origin.x, origin.z, PLOT_TILES.x * TILE_SIZE, PLOT_TILES.y * TILE_SIZE)


# --- Mouse picking --------------------------------------------------------------

## Casts a ray from the camera through a screen position onto a floor's level.
## Returns {"hit": bool, "tile": Vector2i, "position": Vector3, "in_plot": bool}.
## This is a ray-plane test, so it needs no physics colliders and stays cheap.
## Picking on top of objects will use physics raycasts once objects exist.
func screen_to_tile(camera: Camera3D, screen_pos: Vector2, floor_index := 0) -> Dictionary:
	var result := {"hit": false, "tile": Vector2i.ZERO, "position": Vector3.ZERO, "in_plot": false}
	if camera == null:
		return result
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, get_floor_height(floor_index))
	var hit: Variant = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return result
	var tile := world_to_tile(hit)
	result.hit = true
	result.tile = tile
	result.position = hit
	result.in_plot = is_in_plot(tile)
	return result

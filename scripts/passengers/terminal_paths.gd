extends Node
## Terminal pathfinding for people (checklist step 28).
##
## Finds walking paths on one floor that go around walls, through doors and
## around placed objects, and only cross the zones a person may enter:
##   Access.LANDSIDE  landside and unzoned floor, the security zone, and the
##                    ground just outside the terminal (where people arrive)
##   Access.AIRSIDE   the security zone and airside
## So a passenger who hasn't been through security can't reach airside, and
## one who has can't walk back landside.
##
## Walls stand on tile edges, so paths are searched on a half-tile grid: one
## cell per tile centre, one per tile edge and one per grid corner. A wall
## makes its edge cell solid; a doorway leaves it open. Corner cells are open
## only in open floor, so paths never cut past a wall end or a door jamb.
## Each access level has its own AStarGrid2D (built the first time it is
## asked for), covering the floor's bounding box plus OUTDOOR_MARGIN tiles.
##
## Paths update when the layout changes: floor, wall, zone and object edits
## mark their area dirty, the grids are patched there before the next search,
## and paths_changed is emitted so people walking can ask for a new path.

## Emitted (once per frame at most) after the layout changed and the grids
## were updated. Anyone following a path should ask for a new one.
signal paths_changed

enum Access { LANDSIDE, AIRSIDE }

const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const TerminalWallsScript := preload("res://scripts/building/terminal_walls.gd")
const Zone := TerminalZonesScript.Zone
## Ground around the terminal that landside people may walk on, in tiles.
const OUTDOOR_MARGIN := 8
## How far (in tiles) a start point off the walkable area looks for a way in.
const SNAP_RADIUS := 4
## Spacing of line-of-sight samples when straightening paths, in half-tile cells.
const SIGHT_STEP := 0.2

@export var terminal_floor: Node3D
@export var terminal_walls: Node3D
@export var terminal_zones: Node3D
## Optional PlacedObjects node: objects block the tiles under them.
@export var placed_objects: Node3D
@export var floor_index := 0

## Tiles the grids cover.
var _region := Rect2i()
## Access -> AStarGrid2D, built on first use.
var _grids := {}
## Area waiting to be patched, in tiles, and whether the whole region needs it.
var _dirty := Rect2i()
var _has_dirty := false
var _rebuild_all := false
var _notify := false
## Object id -> its tiles, so a removed object's tiles can be freed.
var _object_tiles := {}


func _ready() -> void:
	if terminal_floor != null:
		terminal_floor.floor_changed.connect(_on_floor_changed)
		_region = _grow_region(terminal_floor.get_floor_bounds(floor_index))
	if terminal_walls != null:
		terminal_walls.walls_changed.connect(_on_walls_changed)
	if terminal_zones != null:
		terminal_zones.zones_changed.connect(_on_area_changed)
	if placed_objects != null:
		placed_objects.object_added.connect(_on_object_changed)
		placed_objects.object_moved.connect(_on_object_changed)
		placed_objects.object_removed.connect(_on_object_removed)
		for id in placed_objects.get_ids():
			_on_object_changed(id)


func _process(_delta: float) -> void:
	_apply_changes()
	if _notify:
		_notify = false
		paths_changed.emit()


## A walking path from one world point to another for an access level, as
## world points from start to finish (straightened, on the floor surface).
## Empty if there is no way there. With allow_partial, an unreachable target
## (say, a desk itself) gives a path to the nearest point that can be reached.
func find_path(from: Vector3, to: Vector3, access: int, allow_partial := false) -> PackedVector3Array:
	_apply_changes()
	var result := PackedVector3Array()
	var grid := _get_grid(access)
	if grid == null:
		return result
	var start := _snap_to_walkable(grid, _world_to_cell(from))
	var goal := _world_to_cell(to)
	if start.x < 0 or not grid.is_in_boundsv(goal):
		return result
	var cells := grid.get_id_path(start, goal, allow_partial)
	if cells.is_empty():
		return result
	var reached := cells[cells.size() - 1] == goal
	cells = _straighten(grid, cells)
	result.append(_surface(from) if start == _world_to_cell(from) else _cell_to_world(start))
	for i in range(1, cells.size() - 1):
		result.append(_cell_to_world(cells[i]))
	result.append(_surface(to) if reached else _cell_to_world(cells[cells.size() - 1]))
	return result


## True if a person with this access may stand on the tile.
func is_walkable(tile: Vector2i, access: int) -> bool:
	_apply_changes()
	var grid := _get_grid(access)
	if grid == null:
		return false
	var cell := _tile_cell(tile)
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)


## Tiles the grids cover (the floor's bounding box plus the outdoor margin).
func get_region() -> Rect2i:
	return _region


## True if the tile counts as allowed for an access level by its zone alone.
static func zone_allows(zone: int, has_floor: bool, access: int) -> bool:
	if access == Access.AIRSIDE:
		return has_floor and (zone == Zone.SECURITY or zone == Zone.AIRSIDE)
	return not has_floor or zone == Zone.NONE or zone == Zone.LANDSIDE or zone == Zone.SECURITY


# --- Grid building ----------------------------------------------------------------

func _get_grid(access: int) -> AStarGrid2D:
	if not _region.has_area():
		return null
	if not _grids.has(access):
		var grid := AStarGrid2D.new()
		_grids[access] = grid
		_reset_grid(grid, access)
	return _grids[access]


func _reset_grid(grid: AStarGrid2D, access: int) -> void:
	var size := _region.size * 2 + Vector2i.ONE
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.jumping_enabled = true
	grid.update()
	grid.fill_solid_region(grid.region, true)
	_update_cells(grid, access, _region)


## Recomputes every cell belonging to the tiles in rect: each tile's centre,
## its west and north edges and its north-west corner.
func _update_cells(grid: AStarGrid2D, access: int, rect: Rect2i) -> void:
	rect = rect.grow(1).intersection(_region)
	# Walkability of the tiles in rect plus a one-tile border, row by row.
	var area := rect.grow(1)
	var open := PackedByteArray()
	open.resize(area.size.x * area.size.y)
	for y in area.size.y:
		for x in area.size.x:
			var tile := area.position + Vector2i(x, y)
			open[x + y * area.size.x] = 1 if _tile_open(tile, access) else 0
	var w := area.size.x
	for ty in range(rect.position.y, rect.end.y):
		for tx in range(rect.position.x, rect.end.x):
			var i := (tx - area.position.x) + (ty - area.position.y) * w
			var here := open[i] == 1
			var west := open[i - 1] == 1
			var north := open[i - w] == 1
			var north_west := open[i - w - 1] == 1
			var c := (Vector2i(tx, ty) - _region.position) * 2
			grid.set_point_solid(c + Vector2i.ONE, not here)
			var corner := Vector2i(tx, ty)
			var v_piece := _edge(corner, false)
			var h_piece := _edge(corner, true)
			grid.set_point_solid(c + Vector2i(0, 1), not (here and west and v_piece != TerminalWallsScript.Piece.WALL))
			grid.set_point_solid(c + Vector2i(1, 0), not (here and north and h_piece != TerminalWallsScript.Piece.WALL))
			var corner_open := here and west and north and north_west \
				and v_piece == TerminalWallsScript.Piece.NONE and h_piece == TerminalWallsScript.Piece.NONE \
				and _edge(corner + Vector2i(-1, 0), true) == TerminalWallsScript.Piece.NONE \
				and _edge(corner + Vector2i(0, -1), false) == TerminalWallsScript.Piece.NONE
			grid.set_point_solid(c, not corner_open)


func _tile_open(tile: Vector2i, access: int) -> bool:
	if not _region.has_point(tile):
		return false
	var has_floor: bool = terminal_floor.has_floor(tile, floor_index)
	var zone: int = terminal_zones.get_zone(tile, floor_index) if terminal_zones != null else Zone.NONE
	if not zone_allows(zone, has_floor, access):
		return false
	return placed_objects == null or placed_objects.get_object_at(tile, floor_index) == 0


func _edge(corner: Vector2i, horizontal: bool) -> int:
	if terminal_walls == null:
		return TerminalWallsScript.Piece.NONE
	return terminal_walls.get_edge(corner, horizontal, floor_index)


func _grow_region(bounds: Rect2i) -> Rect2i:
	if not bounds.has_area():
		return Rect2i()
	var plot := Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES)
	return bounds.grow(OUTDOOR_MARGIN).intersection(plot)


# --- Layout changes ---------------------------------------------------------------

func _apply_changes() -> void:
	if _rebuild_all:
		for access in _grids:
			_reset_grid(_grids[access], access)
	elif _has_dirty:
		var rect := _dirty.intersection(_region)
		if rect.has_area():
			for access in _grids:
				_update_cells(_grids[access], access, rect)
	if _rebuild_all or _has_dirty:
		_notify = true
	_rebuild_all = false
	_has_dirty = false


func _mark_dirty(rect: Rect2i) -> void:
	_dirty = _dirty.merge(rect) if _has_dirty else rect
	_has_dirty = true


func _on_floor_changed(rect: Rect2i, changed_floor: int) -> void:
	if changed_floor != floor_index:
		return
	if terminal_floor.count_floor_tiles(rect, floor_index) > 0:
		var grown := _grow_region(rect)
		var merged := grown if not _region.has_area() else _region.merge(grown)
		if merged != _region:
			_region = merged
			_rebuild_all = true
	_mark_dirty(rect)


func _on_walls_changed(from_corner: Vector2i, to_corner: Vector2i, changed_floor: int) -> void:
	if changed_floor != floor_index:
		return
	var lo := Vector2i(mini(from_corner.x, to_corner.x), mini(from_corner.y, to_corner.y))
	var hi := Vector2i(maxi(from_corner.x, to_corner.x), maxi(from_corner.y, to_corner.y))
	# Tiles on both sides of the edges.
	_mark_dirty(Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(2, 2)))


func _on_area_changed(rect: Rect2i, changed_floor: int) -> void:
	if changed_floor == floor_index:
		_mark_dirty(rect)


func _on_object_changed(id: int) -> void:
	_on_object_removed(id)
	var obj = placed_objects.get_object(id)
	if obj == null or obj.floor_index != floor_index:
		return
	_object_tiles[id] = obj.tiles.duplicate()
	_mark_tiles(obj.tiles)


func _on_object_removed(id: int) -> void:
	if _object_tiles.has(id):
		_mark_tiles(_object_tiles[id])
		_object_tiles.erase(id)


func _mark_tiles(tiles: Array) -> void:
	for tile: Vector2i in tiles:
		_mark_dirty(Rect2i(tile, Vector2i.ONE))


# --- Cells and points -------------------------------------------------------------

func _tile_cell(tile: Vector2i) -> Vector2i:
	return (tile - _region.position) * 2 + Vector2i.ONE


func _world_to_cell(world: Vector3) -> Vector2i:
	return _tile_cell(BuildGrid.world_to_tile(world))


func _cell_to_world(cell: Vector2i) -> Vector3:
	var corner := BuildGrid.tile_corner_to_world(_region.position)
	var p := corner + Vector3(cell.x, 0.0, cell.y) * (BuildGrid.TILE_SIZE * 0.5)
	return _surface(p)


## A world point on the walking surface of its tile.
func _surface(world: Vector3) -> Vector3:
	var tile := BuildGrid.world_to_tile(world)
	return Vector3(world.x, terminal_floor.get_surface_height(tile, floor_index), world.z)


## The cell itself if it is open, else the nearest open tile cell within
## SNAP_RADIUS tiles; (-1, -1) if there is none.
func _snap_to_walkable(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
		return cell
	var best := Vector2i(-1, -1)
	var best_dist := INF
	for dy in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
		for dx in range(-SNAP_RADIUS, SNAP_RADIUS + 1):
			var c := cell + Vector2i(dx, dy) * 2
			if grid.is_in_boundsv(c) and not grid.is_point_solid(c):
				var d := Vector2(dx, dy).length_squared()
				if d < best_dist:
					best_dist = d
					best = c
	return best


## Drops cells that a straight line can skip: from each kept cell, the next
## kept one is the furthest cell along the path still in clear sight.
func _straighten(grid: AStarGrid2D, cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells
	var out: Array[Vector2i] = [cells[0]]
	var anchor := 0
	while anchor < cells.size() - 1:
		var next := anchor + 1
		for j in range(cells.size() - 1, anchor + 1, -1):
			if _in_sight(grid, cells[anchor], cells[j]):
				next = j
				break
		out.append(cells[next])
		anchor = next
	return out


func _in_sight(grid: AStarGrid2D, a: Vector2i, b: Vector2i) -> bool:
	var delta := Vector2(b - a)
	var steps := ceili(delta.length() / SIGHT_STEP)
	for s in range(1, steps):
		var p := Vector2(a) + delta * (float(s) / steps)
		if grid.is_point_solid(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true

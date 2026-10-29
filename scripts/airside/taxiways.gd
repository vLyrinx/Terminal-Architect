extends Node3D
## Taxiways (checklist step 17): stores every taxiway piece and draws it.
##
## Each piece is straight along world X or Z, placed by grid corners on its
## centreline with the same footprint rule as runways (runways.gd footprint()),
## so a taxiway lines up with runways and other taxiways of the same width
## parity. Pieces may overlap each other and cross runways; they may not cover
## terminal floor or walls, or run along inside a runway. The paving sits a
## little lower than runway paving, so where a taxiway crosses a runway the
## runway and its markings stay on top. A yellow centreline is drawn on each piece.
## Changes come from PlaceTaxiwayCommand and DeleteTaxiwayCommand; the
## RouteGraph listens to taxiway_added / taxiway_removed.
##
## Keep this node at the world origin.

signal taxiway_added(id: int)
signal taxiway_removed(id: int)

const TaxiwayScript := preload("res://scripts/airside/taxiway.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

## Lower than runway paving (RunwaysScript.PAVING_HEIGHT), so runways draw on top.
const PAVING_HEIGHT := 0.025
## The centreline stays below runway paving, so it is hidden where it crosses a runway.
const MARKING_LIFT := 0.01
const PAVING_COLOR := Color(0.33, 0.35, 0.38)
const PAVING_SIDE_COLOR := Color(0.25, 0.27, 0.3)
const CENTRELINE_COLOR := Color(0.95, 0.76, 0.19)
const CENTRELINE_WIDTH := 0.5

## The TerminalFloor node (terminal_floor.gd). Taxiways can't go over floor.
@export var terminal_floor: Node3D
## The Runways node (runways.gd). Taxiways may cross runways but not run along inside them.
@export var runways: Node3D
## Optional Stands node (stands.gd). Taxiways can't go over stands (checklist step 18).
@export var stands: Node3D

var _taxiways := {}
var _next_id := 1
static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95


# --- Queries --------------------------------------------------------------------

func get_taxiway(id: int) -> TaxiwayScript:
	return _taxiways.get(id)


func get_ids() -> Array:
	return _taxiways.keys()


func get_count() -> int:
	return _taxiways.size()


func get_all() -> Array:
	return _taxiways.values()


## ID of a taxiway covering a tile, or 0.
func get_taxiway_at(tile: Vector2i) -> int:
	for taxiway: TaxiwayScript in _taxiways.values():
		if taxiway.rect.has_point(tile):
			return taxiway.id
	return 0


## IDs of taxiways that cover any tile of rect.
func get_taxiways_in(rect: Rect2i) -> Array[int]:
	var ids: Array[int] = []
	for taxiway: TaxiwayScript in _taxiways.values():
		if taxiway.rect.intersects(rect):
			ids.append(taxiway.id)
	return ids


## Paved rectangles overlapping rect (they may overlap each other).
func get_rects_in(rect: Rect2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for taxiway: TaxiwayScript in _taxiways.values():
		if taxiway.rect.intersects(rect):
			rects.append(taxiway.rect)
	return rects


## Tiles a taxiway of this size would cover between two centreline corners.
static func footprint(def: Resource, start: Vector2i, end: Vector2i) -> Rect2i:
	return RunwaysScript.footprint(def, start, end)


## Why a taxiway can't be built between start and end, or "" if it can.
## (Walls in the way are checked by PlaceTaxiwayCommand, which knows the walls.)
func check_placement(def: Resource, start: Vector2i, end: Vector2i) -> String:
	if def == null:
		return "Unknown taxiway size"
	if start.x != end.x and start.y != end.y:
		return "Taxiways run straight along the grid"
	if not BuildGrid.is_on_airside_grid(start) or not BuildGrid.is_on_airside_grid(end):
		return "Taxiways start and end on the %d m grid" % BuildGrid.AIRSIDE_SNAP
	var length := maxi(absi(end.x - start.x), absi(end.y - start.y))
	if length < def.min_length:
		return "Too short: at least %d m" % def.min_length
	var rect := footprint(def, start, end)
	if not Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES).encloses(rect):
		return "Doesn't fit on the plot"
	if runways:
		# Overlapping a parallel runway means running along inside it (touching is fine).
		var along_x := end.x != start.x
		for id: int in runways.get_runways_in(rect):
			if (runways.get_runway(id).get_axis().x != 0) == along_x:
				return "Taxiways can cross a runway, not run along it"
	if terminal_floor and terminal_floor.count_floor_tiles(rect) > 0:
		return "Blocked by terminal floor"
	if stands and not stands.get_stands_in(rect).is_empty():
		return "Blocked by a stand"
	return ""


# --- Editing --------------------------------------------------------------------

## Adds a taxiway (no checks: use check_placement() first). id 0 picks a new ID.
## Returns the taxiway's ID.
func add_taxiway(def_id: StringName, start: Vector2i, end: Vector2i, id := 0) -> int:
	var def := TaxiwayCatalog.get_def(def_id)
	if def == null:
		push_warning("Taxiways: unknown taxiway size %s" % def_id)
		return 0
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)

	var taxiway := TaxiwayScript.new()
	taxiway.id = id
	taxiway.def_id = def_id
	taxiway.start = start
	taxiway.end = end
	taxiway.rect = footprint(def, start, end)
	taxiway.width = def.width
	taxiway.length = maxi(absi(end.x - start.x), absi(end.y - start.y))
	taxiway.a = centreline_point(taxiway.rect, taxiway.get_axis().x != 0, start)
	taxiway.b = centreline_point(taxiway.rect, taxiway.get_axis().x != 0, end)
	taxiway.node = _build_node(taxiway)
	add_child(taxiway.node)
	_taxiways[id] = taxiway
	taxiway_added.emit(id)
	return id


func remove_taxiway(id: int) -> TaxiwayScript:
	var taxiway: TaxiwayScript = _taxiways.get(id)
	if taxiway == null:
		return null
	_taxiways.erase(id)
	taxiway.node.queue_free()
	taxiway.node = null
	taxiway_removed.emit(id)
	return taxiway


## World position on the centreline of a paved rect at the grid line of a corner.
static func centreline_point(rect: Rect2i, along_x: bool, corner: Vector2i) -> Vector3:
	var lo := BuildGrid.tile_corner_to_world(rect.position)
	var hi := BuildGrid.tile_corner_to_world(rect.end)
	var p := BuildGrid.tile_corner_to_world(corner)
	if along_x:
		return Vector3(p.x, 0.0, (lo.z + hi.z) * 0.5)
	return Vector3((lo.x + hi.x) * 0.5, 0.0, p.z)


# --- Mesh -----------------------------------------------------------------------

func _build_node(taxiway: TaxiwayScript) -> Node3D:
	var root := Node3D.new()
	root.name = "Taxiway_%d" % taxiway.id
	var builder := MeshBuilderScript.new()
	var lo := BuildGrid.tile_corner_to_world(taxiway.rect.position)
	var hi := BuildGrid.tile_corner_to_world(taxiway.rect.end)
	builder.add_box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, PAVING_HEIGHT, hi.z), PAVING_SIDE_COLOR, PAVING_COLOR)

	# Centreline, from end to end (it runs on into crossings, as at a real junction).
	var along := (taxiway.b - taxiway.a).normalized()
	var across := along.cross(Vector3.UP) * CENTRELINE_WIDTH * 0.5
	var y := Vector3.UP * (PAVING_HEIGHT + MARKING_LIFT)
	builder.add_quad([taxiway.a + y - across, taxiway.b + y - across, taxiway.b + y + across, taxiway.a + y + across],
		Vector3.UP, CENTRELINE_COLOR)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = builder.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

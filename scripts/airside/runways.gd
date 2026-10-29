extends Node3D
## Runways (checklist step 16): stores every built runway and draws it.
##
## Runways run along world X or world Z and are placed by grid corners on the
## centreline (see runway.gd). Each runway is one mesh: dark paving with white
## markings (threshold stripes and a designator at each end, a dashed
## centreline and edge lines). Other systems ask get_ends() where aircraft can
## land and take off, and get_runway_at() / count_tiles_in() what is paved.
## Changes come from PlaceRunwayCommand and DeleteRunwayCommand.
##
## Keep this node at the world origin.

signal runway_added(id: int)
signal runway_removed(id: int)

const RunwayScript := preload("res://scripts/airside/runway.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

const PAVING_HEIGHT := 0.04
## Markings sit this far above the paving, so they never flicker into it.
const MARKING_LIFT := 0.02
const PAVING_COLOR := Color(0.29, 0.31, 0.34)
const PAVING_SIDE_COLOR := Color(0.22, 0.24, 0.27)
const MARKING_COLOR := Color(0.95, 0.95, 0.93)
## Threshold stripes ("piano keys"), metres from the end of the paving.
const THRESHOLD_FROM := 6.0
const THRESHOLD_LENGTH := 30.0
const STRIPE_WIDTH := 1.8
## Designator number: centre distance from the end, and letter height.
const DESIGNATOR_AT := 50.0
const DESIGNATOR_HEIGHT := 9.0
## Dashed centreline.
const CENTRELINE_FROM := 70.0
const DASH_LENGTH := 30.0
const DASH_GAP := 20.0
const LINE_WIDTH := 0.9
## Edge lines sit this far in from the side of the paving.
const EDGE_INSET := 1.0

## The TerminalFloor node (terminal_floor.gd). Runways can't go over floor.
@export var terminal_floor: Node3D
## Optional Stands node (stands.gd). Runways can't go over stands (checklist step 18).
@export var stands: Node3D

var _runways := {}
var _next_id := 1
static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95


# --- Queries --------------------------------------------------------------------

func get_runway(id: int) -> RunwayScript:
	return _runways.get(id)


func get_ids() -> Array:
	return _runways.keys()


func get_count() -> int:
	return _runways.size()


## ID of the runway covering a tile, or 0.
func get_runway_at(tile: Vector2i) -> int:
	for runway: RunwayScript in _runways.values():
		if runway.rect.has_point(tile):
			return runway.id
	return 0


## IDs of runways that cover any tile of rect.
func get_runways_in(rect: Rect2i) -> Array[int]:
	var ids: Array[int] = []
	for runway: RunwayScript in _runways.values():
		if runway.rect.intersects(rect):
			ids.append(runway.id)
	return ids


## Paved rectangles overlapping rect.
func get_rects_in(rect: Rect2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for runway: RunwayScript in _runways.values():
		if runway.rect.intersects(rect):
			rects.append(runway.rect)
	return rects


func get_all() -> Array:
	return _runways.values()


## How many tiles of rect are paved runway.
func count_tiles_in(rect: Rect2i) -> int:
	var count := 0
	for runway: RunwayScript in _runways.values():
		count += runway.rect.intersection(rect).get_area()
	return count


## Every runway end aircraft can use: the end Dictionaries from runway.gd plus
## "runway_id" and "size_class" (the largest aircraft class it handles).
func get_ends() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for runway: RunwayScript in _runways.values():
		var def := RunwayCatalog.get_def(runway.def_id)
		for runway_end in runway.ends:
			var e: Dictionary = runway_end.duplicate()
			e.runway_id = runway.id
			e.size_class = def.size_class if def else ""
			result.append(e)
	return result


## Tiles a runway of this size would cover between two centreline corners.
## Widths are even, so the centreline is on the dragged grid line and both
## edges are on whole tiles.
static func footprint(def: Resource, start: Vector2i, end: Vector2i) -> Rect2i:
	var lo := start.min(end)
	var length := (end - start).abs()
	var half := floori(def.width * 0.5)
	if length.x > 0 or length.y == 0:
		return Rect2i(lo.x, start.y - half, length.x, def.width)
	return Rect2i(start.x - half, lo.y, def.width, length.y)


## Why a runway can't be built between start and end, or "" if it can.
## (Walls in the way are checked by PlaceRunwayCommand, which knows the walls.)
func check_placement(def: Resource, start: Vector2i, end: Vector2i, ignore_id := 0) -> String:
	if def == null:
		return "Unknown runway size"
	if start.x != end.x and start.y != end.y:
		return "Runways run straight along the grid"
	if not BuildGrid.is_on_airside_grid(start) or not BuildGrid.is_on_airside_grid(end):
		return "Runways start and end on the %d m grid" % BuildGrid.AIRSIDE_SNAP
	var length := maxi(absi(end.x - start.x), absi(end.y - start.y))
	if length < def.min_length:
		return "Too short: a %s needs at least %s m" % [def.display_name.to_lower(), _number(def.min_length)]
	if length > def.max_length:
		return "Too long: a %s is at most %s m" % [def.display_name.to_lower(), _number(def.max_length)]
	var rect := footprint(def, start, end)
	if not Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES).encloses(rect):
		return "Doesn't fit on the plot"
	for id in get_runways_in(rect):
		if id != ignore_id:
			return "Overlaps another runway"
	if terminal_floor and terminal_floor.count_floor_tiles(rect) > 0:
		return "Blocked by terminal floor"
	if stands and not stands.get_stands_in(rect).is_empty():
		return "Blocked by a stand"
	return ""


# --- Editing --------------------------------------------------------------------

## Adds a runway (no checks: use check_placement() first). id 0 picks a new ID.
## Returns the runway's ID.
func add_runway(def_id: StringName, start: Vector2i, end: Vector2i, id := 0) -> int:
	var def := RunwayCatalog.get_def(def_id)
	if def == null:
		push_warning("Runways: unknown runway size %s" % def_id)
		return 0
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)

	var runway := RunwayScript.new()
	runway.id = id
	runway.def_id = def_id
	runway.start = start
	runway.end = end
	runway.rect = footprint(def, start, end)
	runway.width = def.width
	runway.length = maxi(absi(end.x - start.x), absi(end.y - start.y))
	var axis := runway.get_axis()
	var direction := Vector3(axis.x, 0.0, axis.y)
	var a := _centreline_point(runway, start)
	var b := _centreline_point(runway, end)
	runway.ends = [RunwayScript.make_end(a, direction), RunwayScript.make_end(b, -direction)]
	runway.node = _build_node(runway)
	add_child(runway.node)
	_runways[id] = runway
	runway_added.emit(id)
	return id


func remove_runway(id: int) -> RunwayScript:
	var runway: RunwayScript = _runways.get(id)
	if runway == null:
		return null
	_runways.erase(id)
	runway.node.queue_free()
	runway.node = null
	runway_removed.emit(id)
	return runway


# --- Mesh -----------------------------------------------------------------------

## World position on the centreline at the grid line of a corner.
func _centreline_point(runway: RunwayScript, corner: Vector2i) -> Vector3:
	var lo := BuildGrid.tile_corner_to_world(runway.rect.position)
	var hi := BuildGrid.tile_corner_to_world(runway.rect.end)
	var p := BuildGrid.tile_corner_to_world(corner)
	if runway.get_axis().x != 0:
		return Vector3(p.x, 0.0, (lo.z + hi.z) * 0.5)
	return Vector3((lo.x + hi.x) * 0.5, 0.0, p.z)


func _build_node(runway: RunwayScript) -> Node3D:
	var root := Node3D.new()
	root.name = "Runway_%d" % runway.id
	var builder := MeshBuilderScript.new()

	var lo := BuildGrid.tile_corner_to_world(runway.rect.position)
	var hi := BuildGrid.tile_corner_to_world(runway.rect.end)
	builder.add_box(Vector3(lo.x, 0.0, lo.z), Vector3(hi.x, PAVING_HEIGHT, hi.z), PAVING_SIDE_COLOR, PAVING_COLOR)

	var half_width := runway.width * 0.5
	var y := PAVING_HEIGHT + MARKING_LIFT
	for runway_end in runway.ends:
		var threshold: Vector3 = runway_end.position
		var inward: Vector3 = runway_end.direction
		# Threshold stripes, evenly spread across the runway with a stripe's gap between.
		var stripes := floori(((runway.width - 2.0) / STRIPE_WIDTH + 1.0) * 0.5)
		var span := (stripes * 2 - 1) * STRIPE_WIDTH
		for s in stripes:
			var v := -span * 0.5 + s * STRIPE_WIDTH * 2.0
			_add_marking(builder, threshold, inward, THRESHOLD_FROM, THRESHOLD_FROM + THRESHOLD_LENGTH, v, v + STRIPE_WIDTH, y)
		root.add_child(_make_designator(runway_end, threshold + inward * DESIGNATOR_AT + Vector3.UP * y))

	# Dashed centreline between the two designators.
	var origin: Vector3 = runway.ends[0].position
	var along: Vector3 = runway.ends[0].direction
	var u := CENTRELINE_FROM
	while u + DASH_LENGTH <= runway.length - CENTRELINE_FROM:
		_add_marking(builder, origin, along, u, u + DASH_LENGTH, -LINE_WIDTH * 0.5, LINE_WIDTH * 0.5, y)
		u += DASH_LENGTH + DASH_GAP
	# Edge lines along both sides.
	for side: float in [-1.0, 1.0]:
		var v := side * (half_width - EDGE_INSET)
		_add_marking(builder, origin, along, 0.0, runway.length, v - LINE_WIDTH * 0.5, v + LINE_WIDTH * 0.5, y)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = builder.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


## Adds a flat white rectangle in runway coordinates: u along the runway from
## origin, v across it (to the right of along).
func _add_marking(builder: RefCounted, origin: Vector3, along: Vector3, u0: float, u1: float,
		v0: float, v1: float, y: float) -> void:
	var across := along.cross(Vector3.UP)
	var base := Vector3(origin.x, y, origin.z)
	builder.add_quad([base + along * u0 + across * v0, base + along * u1 + across * v0,
		base + along * u1 + across * v1, base + along * u0 + across * v1], Vector3.UP, MARKING_COLOR)


## The runway number, lying flat and readable to an aircraft landing at that end.
func _make_designator(runway_end: Dictionary, pos: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = runway_end.designator
	label.font_size = 64
	label.pixel_size = DESIGNATOR_HEIGHT / 64.0
	label.modulate = MARKING_COLOR
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = pos
	# Lie flat (text faces up, its top towards -Z), then turn its top to point down the runway.
	var d: Vector3 = runway_end.direction
	label.basis = Basis(Vector3.UP, atan2(-d.x, -d.z)) * Basis(Vector3.RIGHT, -PI * 0.5)
	return label


static func _number(n: int) -> String:
	return Money.format(n).trim_prefix("$")

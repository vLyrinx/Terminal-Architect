extends Node3D
## TaxiLines: stores the yellow taxi lines the player paints on taxiway and
## ramp paving, and draws them. As in Airport CEO, paving and lines are built
## separately: taxiway paving on its own goes nowhere, and aircraft only follow
## taxi lines (and the lines that come with runway ramps and stands). The
## RouteGraph is built from the usable lines and rebuilds on lines_changed.
##
## A line runs between two corners of the 10 m airside grid, along X, along Z
## or at 45 degrees, at least MIN_LENGTH long, all on paving and never on a
## runway. Lines may cross and overlap; the route graph joins them wherever
## they meet. When paving is built or removed every line is checked again (see
## taxi_line.gd). Changes come from PlaceTaxiLineCommand and DeleteTaxiLinesCommand.
##
## Keep this node at the world origin.

signal line_added(id: int)
signal line_removed(id: int)
## A line was added or removed, or became usable or unusable.
signal lines_changed

const TaxiLineScript := preload("res://scripts/airside/taxi_line.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const TaxiwayDefScript := preload("res://scripts/airside/taxiway_def.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

const HEIGHT := TaxiwaysScript.PAVING_HEIGHT + TaxiwaysScript.MARKING_LIFT
const LINE_WIDTH := 0.5
const LINE_COLOR := Color(0.95, 0.76, 0.19)
## Lines whose paving has gone.
const BROKEN_COLOR := Color(0.85, 0.3, 0.25)
const MIN_LENGTH := 10
## Paving is checked this often along a line, in metres.
const SAMPLE_STEP := 1.0

## The Taxiways node (taxiways.gd).
@export var taxiways: Node3D
## The Ramps node (ramps.gd).
@export var ramps: Node3D
## The Runways node (runways.gd). Lines can't go on runways.
@export var runways: Node3D

var _lines := {}
var _next_id := 1
static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if taxiways:
		taxiways.taxiway_added.connect(_recheck.unbind(1))
		taxiways.taxiway_removed.connect(_recheck.unbind(1))
	if ramps:
		ramps.ramp_added.connect(_recheck.unbind(1))
		ramps.ramp_removed.connect(_recheck.unbind(1))


# --- Queries --------------------------------------------------------------------

func get_line(id: int) -> TaxiLineScript:
	return _lines.get(id)


func get_ids() -> Array:
	return _lines.keys()


func get_count() -> int:
	return _lines.size()


func get_all() -> Array:
	return _lines.values()


## IDs of lines that come within distance metres of the segment from a to b
## (grid-corner positions).
func get_lines_near(a: Vector2, b: Vector2, distance: float) -> Array[int]:
	var ids: Array[int] = []
	for line: TaxiLineScript in _lines.values():
		if _segment_distance(a, b, Vector2(line.a), Vector2(line.b)) <= distance:
			ids.append(line.id)
	return ids


## IDs of lines that pass through any tile of rect.
func get_lines_in(rect: Rect2i) -> Array[int]:
	var ids: Array[int] = []
	var r := Rect2(rect)
	for line: TaxiLineScript in _lines.values():
		var a := Vector2(line.a)
		var b := Vector2(line.b)
		if r.has_point(a) or r.has_point(b) or _segment_hits_rect(a, b, r):
			ids.append(line.id)
	return ids


## What a line from a to b would be: {"error": why it can't be painted ("" if
## it can), "size_class", "length"}.
func check_line(a: Vector2i, b: Vector2i) -> Dictionary:
	var d := b - a
	var length := Vector2(d).length()
	var result := {"error": "", "size_class": "", "length": length}
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		result.error = "Taxi lines run along the grid or at 45 degrees"
	elif not BuildGrid.is_on_airside_grid(a) or not BuildGrid.is_on_airside_grid(b):
		result.error = "Taxi lines start and end on the %d m grid" % BuildGrid.AIRSIDE_SNAP
	elif length < MIN_LENGTH:
		result.error = "Too short: at least %d m" % MIN_LENGTH
	else:
		var classes := _paving_along(Vector2(a), Vector2(b))
		result.error = classes.error
		result.size_class = classes.size_class
	return result


## Largest taxiway size class of paving at a grid-corner position (an index
## into TaxiwayDef.SIZE_CLASSES), or -1 if it isn't paved.
func paving_class_at(corner: Vector2) -> int:
	var best := -1
	if taxiways:
		for taxiway: RefCounted in taxiways.get_all():
			var r: Rect2i = taxiway.rect
			if corner.x >= r.position.x - 0.01 and corner.x <= r.end.x + 0.01 \
					and corner.y >= r.position.y - 0.01 and corner.y <= r.end.y + 0.01:
				var def := TaxiwayCatalog.get_def(taxiway.def_id)
				if def:
					best = maxi(best, TaxiwayDefScript.SIZE_CLASSES.find(def.size_class))
	if ramps:
		var ramp_class: String = ramps.paving_class_at(corner)
		if ramp_class != "":
			best = maxi(best, TaxiwayDefScript.SIZE_CLASSES.find(ramp_class))
	return best


# --- Editing --------------------------------------------------------------------

## Adds a line (no checks: use check_line() first). id 0 picks a new ID.
## Returns the line's ID.
func add_line(a: Vector2i, b: Vector2i, id := 0) -> int:
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)
	var line := TaxiLineScript.new()
	line.id = id
	line.a = a
	line.b = b
	var check := check_line(a, b)
	line.length = check.length
	line.size_class = check.size_class if check.error == "" else ""
	line.node = _build_node(line)
	add_child(line.node)
	_lines[id] = line
	line_added.emit(id)
	lines_changed.emit()
	return id


func remove_line(id: int) -> TaxiLineScript:
	var line: TaxiLineScript = _lines.get(id)
	if line == null:
		return null
	_lines.erase(id)
	line.node.queue_free()
	line.node = null
	line_removed.emit(id)
	lines_changed.emit()
	return line


## Checks every line again after paving changed.
func _recheck() -> void:
	var changed := false
	for line: TaxiLineScript in _lines.values():
		var check := check_line(line.a, line.b)
		var size_class: String = check.size_class if check.error == "" else ""
		if size_class == line.size_class:
			continue
		line.size_class = size_class
		line.node.queue_free()
		line.node = _build_node(line)
		add_child(line.node)
		changed = true
		print("TAXI LINE | line #%d %s" % [line.id, "takes %s aircraft" % size_class if size_class != "" else
			"is off the paving"])
	if changed:
		lines_changed.emit()


## {"error", "size_class"} for the paving under a line: the smallest class
## along it, or why it can't go there.
func _paving_along(a: Vector2, b: Vector2) -> Dictionary:
	var smallest := TaxiwayDefScript.SIZE_CLASSES.size()
	var steps := maxi(ceili(a.distance_to(b) / SAMPLE_STEP), 1)
	var runway_rects: Array[Rect2] = []
	if runways:
		for runway: RefCounted in runways.get_all():
			runway_rects.append(Rect2(runway.rect).grow(-0.5))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		for r in runway_rects:
			if r.has_point(p):
				return {"error": "Taxi lines can't go on a runway: use a runway ramp", "size_class": ""}
		var c := paving_class_at(p)
		if c < 0:
			return {"error": "Taxi lines go on taxiway paving", "size_class": ""}
		smallest = mini(smallest, c)
	return {"error": "", "size_class": TaxiwayDefScript.SIZE_CLASSES[smallest]}


static func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a),
		Geometry2D.get_closest_point_to_segment(b, c, d).distance_to(b)),
		minf(Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c),
		Geometry2D.get_closest_point_to_segment(d, a, b).distance_to(d)))


static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[k], corners[(k + 1) % 4]) != null:
			return true
	return false


# --- Mesh -----------------------------------------------------------------------

func _build_node(line: TaxiLineScript) -> Node3D:
	var root := Node3D.new()
	root.name = "TaxiLine_%d" % line.id
	var builder := MeshBuilderScript.new()
	var color := LINE_COLOR if line.is_usable() else BROKEN_COLOR
	var a := BuildGrid.tile_corner_to_world(line.a) + Vector3.UP * HEIGHT
	var b := BuildGrid.tile_corner_to_world(line.b) + Vector3.UP * HEIGHT
	add_strip(builder, a, b, LINE_WIDTH, color)
	# Round ends, so lines meeting at an angle join without a notch.
	for p in [a, b]:
		add_dot(builder, p, LINE_WIDTH * 0.5, color)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = builder.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


static func add_strip(builder: RefCounted, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var side := (b - a).normalized().cross(Vector3.UP) * width * 0.5
	builder.add_quad([a - side, b - side, b + side, a + side], Vector3.UP, color)


static func add_dot(builder: RefCounted, centre: Vector3, radius: float, color: Color) -> void:
	var steps := 8
	for s in steps:
		var p0 := centre + Vector3(cos(TAU * s / steps), 0.0, sin(TAU * s / steps)) * radius
		var p1 := centre + Vector3(cos(TAU * (s + 1) / steps), 0.0, sin(TAU * (s + 1) / steps)) * radius
		builder.add_quad([centre, p0, p1, p1], Vector3.UP, color)

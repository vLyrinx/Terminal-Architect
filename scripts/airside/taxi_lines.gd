extends Node3D
## TaxiLines: stores the yellow taxi lines the player paints on taxiway and
## ramp paving, and draws them. As in Airport CEO, paving and lines are built
## separately: taxiway paving on its own goes nowhere, and aircraft only follow
## taxi lines (and the lines that come with runway ramps and stands). The
## RouteGraph is built from the usable lines and rebuilds on lines_changed.
##
## A line runs between two grid corners, along X, along Z or at 45 degrees,
## at least MIN_LENGTH long, all on paving (taxiway tiles or a runway ramp)
## and never on a runway. How wide the paving is across the line, at its
## narrowest, decides the largest aircraft it takes (TaxiwayDef.width). Lines
## may cross and overlap; the route graph joins them wherever they meet. When
## paving changes, the lines near it are checked again (see taxi_line.gd).
## Changes come from PlaceTaxiLineCommand, DeleteTaxiLinesCommand and
## CutTaxiLinesCommand (which takes away part of a line and keeps the rest).
##
## Keep this node at the world origin.

signal line_added(id: int)
signal line_removed(id: int)
## A line was added or removed, or became usable or unusable.
signal lines_changed

const TaxiLineScript := preload("res://scripts/airside/taxi_line.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

const HEIGHT := TaxiwaysScript.PAVING_HEIGHT + TaxiwaysScript.MARKING_LIFT
const LINE_WIDTH := 0.5
const LINE_COLOR := Color(0.95, 0.76, 0.19)
## Lines whose paving has gone.
const BROKEN_COLOR := Color(0.85, 0.3, 0.25)
const MIN_LENGTH := 2
## Paving is checked this often along a line, in metres.
const SAMPLE_STEP := 1.0
## Paved width is measured up to this many metres each side of a line.
const MAX_SIDE := 20

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
		taxiways.paving_changed.connect(_recheck)
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
## it can), "size_class", "length", "width": paved metres across it at its
## narrowest}.
func check_line(a: Vector2i, b: Vector2i) -> Dictionary:
	var d := b - a
	var length := Vector2(d).length()
	var result := {"error": "", "size_class": "", "length": length, "width": 0}
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		result.error = "Taxi lines run along the grid or at 45 degrees"
	elif length < MIN_LENGTH:
		result.error = "Too short: at least %d m" % MIN_LENGTH
	else:
		var classes := _paving_along(Vector2(a), Vector2(b))
		result.error = classes.error
		result.size_class = classes.size_class
		result.width = classes.width
	return result


## True if a grid-corner position (in tiles, may be fractional) is on taxiway
## or ramp paving.
func is_paved_at(corner: Vector2) -> bool:
	if taxiways and taxiways.is_paved_at(corner):
		return true
	if ramps:
		var tile := Vector2i(corner.floor())
		for ramp: RefCounted in ramps.get_all():
			if ramp.rect.grow(1).has_point(tile) and ramp.covers(corner, 0.0):
				return true
	return false


## Metres of paving across a line at point p (along unit vector across), both
## sides added, each side counted up to MAX_SIDE.
func paved_width_at(p: Vector2, across: Vector2) -> int:
	var total := 0
	for side: float in [1.0, -1.0]:
		var k := 0
		while k < MAX_SIDE and is_paved_at(p + across * side * (k + 0.5)):
			k += 1
		total += k
	return total


## The largest taxiway size (TaxiwayDef) whose width fits in width metres, or null.
static func size_for_width(width: float) -> Resource:
	var best: Resource = null
	for def: Resource in TaxiwayCatalog.get_all():
		if def.width <= width + 0.01:
			best = def
	return best


## The grid corner on a line nearest corner, if a line passes within reach
## metres of it, or corner itself.
func snap_to_line(corner: Vector2i, reach: float) -> Vector2i:
	var best := corner
	var best_distance := reach
	for line: TaxiLineScript in _lines.values():
		var points := line_points(line)
		for p in points:
			var distance := Vector2(p).distance_to(Vector2(corner))
			if distance <= best_distance:
				best = p
				best_distance = distance
	return best


## The grid corners along a line, from a to b, one step (1 m, or one diagonal
## tile) apart.
static func line_points(line: TaxiLineScript) -> Array[Vector2i]:
	var d := line.b - line.a
	var steps := maxi(absi(d.x), absi(d.y))
	var step := Vector2i(signi(d.x), signi(d.y))
	var points: Array[Vector2i] = []
	for k in steps + 1:
		points.append(line.a + step * k)
	return points


## What cutting along the segment from a to b would do: for each line with a
## step whose middle comes within reach metres of the segment, {"id", "pieces":
## [[a, b], ...] the parts left (each at least MIN_LENGTH), "removed": metres
## taken away}. Only steps whose middles lie between the segment's ends
## (measured along it) count, so a cut along a line stops where the drag does.
## A cut on a single point takes the steps either side of it.
func cut_plan(a: Vector2, b: Vector2, reach: float) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	var cut_length := a.distance_to(b)
	var cut_dir := (b - a) / cut_length if cut_length > 0.0 else Vector2.ZERO
	for line: TaxiLineScript in _lines.values():
		if _segment_distance(a, b, Vector2(line.a), Vector2(line.b)) > reach:
			continue
		var points := line_points(line)
		var step_length := Vector2(points[1] - points[0]).length()
		var kept: Array[bool] = []
		var any_cut := false
		for k in points.size() - 1:
			var middle := (Vector2(points[k]) + Vector2(points[k + 1])) * 0.5
			var cut := middle.distance_to(a) <= reach
			if cut_length > 0.0:
				var t := (middle - a).dot(cut_dir)
				cut = t >= -0.01 and t <= cut_length + 0.01 and absf((middle - a).cross(cut_dir)) <= reach
			kept.append(not cut)
			any_cut = any_cut or cut
		if not any_cut:
			continue
		var pieces: Array = []
		var kept_metres := 0.0
		var k := 0
		while k < kept.size():
			if not kept[k]:
				k += 1
				continue
			var first := k
			while k < kept.size() and kept[k]:
				k += 1
			if (k - first) * step_length >= MIN_LENGTH:
				pieces.append([points[first], points[k]])
				kept_metres += (k - first) * step_length
		plans.append({"id": line.id, "pieces": pieces, "removed": line.length - kept_metres})
	return plans


## A corner near corner to snap a line end to: the nearest end of another line
## or outer end of a ramp within reach metres, or corner itself. If from is
## given, only points along X, along Z or at 45 degrees from it count.
func snap_end(corner: Vector2i, reach: float, from := Vector2i(-1, -1)) -> Vector2i:
	var points: Array[Vector2i] = []
	for line: TaxiLineScript in _lines.values():
		points.append(line.a)
		points.append(line.b)
	if ramps:
		for ramp: RefCounted in ramps.get_all():
			points.append(ramp.anchor)
	var best := corner
	var best_distance := reach
	for p in points:
		var distance := Vector2(p).distance_to(Vector2(corner))
		if distance > best_distance or p == from:
			continue
		if from != Vector2i(-1, -1):
			var d := p - from
			if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
				continue
		best = p
		best_distance = distance
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


## Checks lines again after paving changed: those near rect, or all of them
## when rect is empty (a ramp was added or removed).
func _recheck(rect := Rect2i()) -> void:
	var near := Rect2(rect.grow(MAX_SIDE + 1))
	var changed := false
	for line: TaxiLineScript in _lines.values():
		if rect.has_area():
			var bounds := Rect2(Vector2(line.a), Vector2.ZERO).expand(Vector2(line.b))
			if not near.intersects(bounds, true):
				continue
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


## {"error", "size_class", "width"} for the paving under a line: the size
## its narrowest point takes, or why it can't go there. Points are checked
## from half a metre in from each end, so a line may end at the edge of paving.
func _paving_along(a: Vector2, b: Vector2) -> Dictionary:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var across := dir.orthogonal()
	var runway_rects: Array[Rect2] = []
	if runways:
		for runway: RefCounted in runways.get_all():
			runway_rects.append(Rect2(runway.rect))
	var narrowest := MAX_SIDE * 2
	var steps := maxi(ceili((length - 1.0) / SAMPLE_STEP), 1)
	for s in steps + 1:
		var p := a + dir * lerpf(minf(0.5, length * 0.5), maxf(length - 0.5, length * 0.5), float(s) / steps)
		for r in runway_rects:
			if r.has_point(p):
				return {"error": "Taxi lines can't go on a runway: use a runway ramp", "size_class": "", "width": 0}
		if not is_paved_at(p):
			return {"error": "Taxi lines go on taxiway paving", "size_class": "", "width": 0}
		narrowest = mini(narrowest, paved_width_at(p, across))
	var def := size_for_width(narrowest)
	if def == null:
		var smallest: Resource = TaxiwayCatalog.get_all()[0]
		return {"error": "Paving is only %d m wide here: taxi lines need %d m" % [narrowest, smallest.width],
			"size_class": "", "width": narrowest}
	return {"error": "", "size_class": def.size_class, "width": narrowest}


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

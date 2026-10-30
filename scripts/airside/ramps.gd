extends Node3D
## Ramps: stores every runway ramp and draws it.
##
## A ramp attaches to the side of a runway, with its outer end on the 10 m
## airside grid (RampDef.depth past the runway's edge, rounded out), so
## taxiways laid from that end line up with it. It comes with its taxi line,
## which starts on the runway centreline: straight ramps turn straight off it,
## angled ramps follow it for LEAD_ON metres, curve off at 45 degrees and
## curve again to leave straight out. The line is the only way the route graph
## joins a runway (the player's taxi lines can't go on a runway). Each ramp
## also has holding position markings and a red RWY AHEAD sign. The paving
## sits at taxiway height, below the runway, so the runway stays on top where
## they meet; the ramp's line is drawn above the runway.
## Changes come from PlaceRampCommand and DeleteRampCommand; the RouteGraph and
## TaxiLines listen to ramp_added / ramp_removed.
##
## Keep this node at the world origin.

signal ramp_added(id: int)
signal ramp_removed(id: int)

const RampScript := preload("res://scripts/airside/ramp.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")
const TaxiwaysScript := preload("res://scripts/airside/taxiways.gd")
const MeshBuilderScript := preload("res://scripts/building/mesh_builder.gd")

const PAVING_HEIGHT := TaxiwaysScript.PAVING_HEIGHT
## The ramp's taxi line and markings go above runway paving and markings.
const MARKING_HEIGHT := RunwaysScript.PAVING_HEIGHT + RunwaysScript.MARKING_LIFT + 0.005
const LINE_COLOR := Color(0.95, 0.76, 0.19)
const SIGN_COLOR := Color(0.84, 0.16, 0.14)
const LINE_WIDTH := 0.5
## Angled ramps: the line runs this far along the runway centreline before it turns off.
const LEAD_ON := 40.0
## Angled ramps: straight run out at the end, so taxiways meet the ramp square on.
const END_STRAIGHT := 20.0
## Radii of the angled ramp's two bends, in metres.
const TURN_RADIUS := 45.0
const END_RADIUS := 20.0
## Straight ramps widen by this much each side where they meet the runway.
const FLARE := 10.0
## Holding position markings and the sign, metres past the runway's edge.
const HOLD_FROM_EDGE := 6.0
const SIGN_FROM_EDGE := 16.0
const SIGN_SIZE := Vector2(16.0, 4.5)
## The ramp tool looks for a runway within this many metres of the mouse.
const PICK_DISTANCE := 250.0

## The TerminalFloor node (terminal_floor.gd). Ramps can't go over floor.
@export var terminal_floor: Node3D
## The Runways node (runways.gd). Ramps attach to runways.
@export var runways: Node3D
## Optional Stands node (stands.gd). Ramps can't go over stands.
@export var stands: Node3D

var _ramps := {}
var _next_id := 1
static var _material: StandardMaterial3D


func _ready() -> void:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED


# --- Queries --------------------------------------------------------------------

func get_ramp(id: int) -> RampScript:
	return _ramps.get(id)


func get_ids() -> Array:
	return _ramps.keys()


func get_count() -> int:
	return _ramps.size()


func get_all() -> Array:
	return _ramps.values()


## IDs of ramps whose paving box covers any tile of rect.
func get_ramps_in(rect: Rect2i) -> Array[int]:
	var ids: Array[int] = []
	for ramp: RampScript in _ramps.values():
		if ramp.rect.intersects(rect):
			ids.append(ramp.id)
	return ids


## Paving boxes overlapping rect.
func get_rects_in(rect: Rect2i) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	for ramp: RampScript in _ramps.values():
		if ramp.rect.intersects(rect):
			rects.append(ramp.rect)
	return rects


## Distance from a runway's centreline to the outer end of a ramp of this size.
func outer_distance(def: Resource, runway: RefCounted) -> int:
	var step := BuildGrid.AIRSIDE_SNAP
	return ceili((runway.width * 0.5 + def.depth) / float(step)) * step


## Where a ramp goes for a grid-corner position near a runway: {"runway_id",
## "anchor"}, or {} if no runway is near. It goes on the side of the nearest
## runway the position is on, at the nearest 10 m along it.
func snap(def: Resource, corner: Vector2) -> Dictionary:
	if runways == null or def == null:
		return {}
	var best: RefCounted = null
	var best_distance := PICK_DISTANCE
	var best_side := 1
	for runway: RefCounted in runways.get_all():
		var along_x: bool = runway.get_axis().x != 0
		var u := corner.x if along_x else corner.y
		var lo := float(mini(runway.start.x, runway.end.x) if along_x else mini(runway.start.y, runway.end.y))
		var hi := float(maxi(runway.start.x, runway.end.x) if along_x else maxi(runway.start.y, runway.end.y))
		if u < lo or u > hi:
			continue
		var perp: float = (corner.y - runway.start.y) if along_x else (corner.x - runway.start.x)
		if absf(perp) < best_distance:
			best_distance = absf(perp)
			best = runway
			best_side = 1 if perp >= 0.0 else -1
	if best == null:
		return {}
	var v := outer_distance(def, best) * best_side
	var step := BuildGrid.AIRSIDE_SNAP
	var anchor: Vector2i
	if best.get_axis().x != 0:
		anchor = Vector2i(roundi(corner.x / step) * step, best.start.y + v)
	else:
		anchor = Vector2i(best.start.x + v, roundi(corner.y / step) * step)
	return {"runway_id": best.id, "anchor": anchor}


## Why a ramp can't be built here, or "" if it can.
## (Walls in the way are checked by PlaceRampCommand, which knows the walls.)
func check_placement(def: Resource, runway_id: int, anchor: Vector2i, lean: int, ignore_id := 0) -> String:
	if def == null:
		return "Unknown ramp"
	var runway: RefCounted = runways.get_runway(runway_id) if runways else null
	if runway == null:
		return "Ramps attach to a runway"
	if lean != 1 and lean != -1:
		return "Unknown ramp direction"
	var along_x: bool = runway.get_axis().x != 0
	var perp: int = (anchor.y - runway.start.y) if along_x else (anchor.x - runway.start.x)
	if absi(perp) != outer_distance(def, runway) or not BuildGrid.is_on_airside_grid(anchor):
		return "Ramps sit against the side of a runway"
	var ramp := make_ramp(def, runway, anchor, lean)
	var lo := float(mini(runway.start.x, runway.end.x) if along_x else mini(runway.start.y, runway.end.y))
	var hi := float(maxi(runway.start.x, runway.end.x) if along_x else maxi(runway.start.y, runway.end.y))
	var half: float = def.width * 0.5 + (FLARE if def.shape == "straight" else 0.0)
	for p in ramp.get_corner_points():
		var u := p.x if along_x else p.y
		if u < lo + half or u > hi - half:
			return "Too close to the end of the runway"
	if not Rect2i(Vector2i.ZERO, BuildGrid.PLOT_TILES).encloses(ramp.rect):
		return "Doesn't fit on the plot"
	for id in get_ramps_in(ramp.rect):
		if id != ignore_id:
			return "Overlaps another ramp"
	for id: int in runways.get_runways_in(ramp.rect):
		if id != runway_id:
			return "Overlaps another runway"
	if terminal_floor and terminal_floor.count_floor_tiles(ramp.rect) > 0:
		return "Blocked by terminal floor"
	if stands and not stands.get_stands_in(ramp.rect).is_empty():
		return "Blocked by a stand"
	return ""


## A ramp laid out against a runway (not added: used for previews and by add_ramp()).
func make_ramp(def: Resource, runway: RefCounted, anchor: Vector2i, lean: int) -> RampScript:
	var ramp := RampScript.new()
	ramp.def_id = def.id
	ramp.runway_id = runway.id
	ramp.anchor = anchor
	ramp.lean = lean
	ramp.width = def.width
	ramp.half_runway = runway.width * 0.5
	var axis: Vector2i = runway.get_axis()
	ramp.along = Vector2(axis)
	if axis.x != 0:
		var perp: int = anchor.y - runway.start.y
		ramp.out = Vector2(0, signi(perp) if perp != 0 else 1)
		ramp.centre = Vector2(anchor.x, runway.start.y)
		ramp.outer_v = absi(perp)
	else:
		var perp: int = anchor.x - runway.start.x
		ramp.out = Vector2(signi(perp) if perp != 0 else 1, 0)
		ramp.centre = Vector2(runway.start.x, anchor.y)
		ramp.outer_v = absi(perp)

	var v := ramp.outer_v
	if def.shape == "angled":
		var bend := v - END_STRAIGHT
		ramp.points = _rounded([Vector2(-lean * (bend + LEAD_ON), 0.0), Vector2(-lean * bend, 0.0),
			Vector2(0.0, bend), Vector2(0.0, v)], [0.0, TURN_RADIUS, END_RADIUS, 0.0])
	else:
		ramp.points = PackedVector2Array([Vector2.ZERO, Vector2(0.0, v)])

	# Bounding box of the paving beside the runway.
	var u_lo := INF
	var u_hi := -INF
	for p in _densify(ramp.points, 1.0):
		if p.y >= ramp.half_runway - def.width * 0.5:
			u_lo = minf(u_lo, p.x)
			u_hi = maxf(u_hi, p.x)
	var half: float = def.width * 0.5 + (FLARE if def.shape == "straight" else 0.0)
	var a := ramp.to_corner(Vector2(u_lo - half, ramp.half_runway))
	var b := ramp.to_corner(Vector2(u_hi + half, v))
	var lo := Vector2i(floori(minf(a.x, b.x) + 0.001), floori(minf(a.y, b.y) + 0.001))
	var hi := Vector2i(ceili(maxf(a.x, b.x) - 0.001), ceili(maxf(a.y, b.y) - 0.001))
	ramp.rect = Rect2i(lo, hi - lo)
	return ramp


# --- Editing --------------------------------------------------------------------

## Adds a ramp (no checks: use check_placement() first). id 0 picks a new ID.
## Returns the ramp's ID.
func add_ramp(def_id: StringName, runway_id: int, anchor: Vector2i, lean: int, id := 0) -> int:
	var def := RampCatalog.get_def(def_id)
	var runway: RefCounted = runways.get_runway(runway_id) if runways else null
	if def == null or runway == null:
		push_warning("Ramps: unknown ramp %s or runway #%d" % [def_id, runway_id])
		return 0
	if id <= 0:
		id = _next_id
	_next_id = maxi(_next_id, id + 1)
	var ramp := make_ramp(def, runway, anchor, lean)
	ramp.id = id
	ramp.node = build_node(ramp, def)
	add_child(ramp.node)
	_ramps[id] = ramp
	ramp_added.emit(id)
	return id


func remove_ramp(id: int) -> RampScript:
	var ramp: RampScript = _ramps.get(id)
	if ramp == null:
		return null
	_ramps.erase(id)
	ramp.node.queue_free()
	ramp.node = null
	ramp_removed.emit(id)
	return ramp


# --- Geometry -------------------------------------------------------------------

## A polyline with its inner corners rounded (radius per corner; 0 keeps it sharp).
static func _rounded(corners: Array, radii: Array) -> PackedVector2Array:
	var result := PackedVector2Array([corners[0]])
	for i in range(1, corners.size() - 1):
		var b: Vector2 = corners[i]
		var to_a: Vector2 = (corners[i - 1] - b).normalized()
		var to_c: Vector2 = (corners[i + 1] - b).normalized()
		var turn := PI - absf(to_a.angle_to(to_c))
		var d: float = radii[i] * tan(turn * 0.5)
		if d <= 0.0:
			result.append(b)
			continue
		var p1 := b + to_a * d
		var p2 := b + to_c * d
		# Quadratic curve through the corner: smooth, and close to a circular arc for these angles.
		var steps := 8
		for s in steps + 1:
			var t := float(s) / steps
			result.append(p1.lerp(b, t).lerp(b.lerp(p2, t), t))
	result.append(corners[-1])
	return result


## Points along a polyline no more than step apart.
static func _densify(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var result := PackedVector2Array([points[0]])
	for i in range(1, points.size()):
		var n := maxi(ceili(points[i - 1].distance_to(points[i]) / step), 1)
		for s in range(1, n + 1):
			result.append(points[i - 1].lerp(points[i], float(s) / n))
	return result


## Point and direction (towards the outer end) where the line is v from the centreline.
static func _point_at_v(ramp: RampScript, v: float) -> Array:
	for i in range(1, ramp.points.size()):
		var a := ramp.points[i - 1]
		var b := ramp.points[i]
		if (a.y - v) * (b.y - v) <= 0.0 and a.y != b.y:
			var t := (v - a.y) / (b.y - a.y)
			return [a.lerp(b, t), (b - a).normalized()]
	return [Vector2(0.0, v), Vector2(0.0, 1.0)]


# --- Mesh -----------------------------------------------------------------------

func _world(ramp: RampScript, local: Vector2, height: float) -> Vector3:
	var c := ramp.to_corner(local)
	return BuildGrid.origin + Vector3(c.x * BuildGrid.TILE_SIZE, height, c.y * BuildGrid.TILE_SIZE)


## The ramp's paving, markings and sign. Also used for the ramp tool's ghost.
func build_node(ramp: RampScript, def: Resource) -> Node3D:
	var root := Node3D.new()
	root.name = "Ramp_%d" % ramp.id
	var builder := MeshBuilderScript.new()
	var half := ramp.width * 0.5

	# Paving: a strip along the line with round joints, so the bends stay full width.
	for i in range(1, ramp.points.size()):
		_strip(builder, ramp, ramp.points[i - 1], ramp.points[i], half, PAVING_HEIGHT, TaxiwaysScript.PAVING_COLOR)
	for i in range(1, ramp.points.size() - 1):
		_disc(builder, ramp, ramp.points[i], half, PAVING_HEIGHT, TaxiwaysScript.PAVING_COLOR)
	if def.shape == "straight":
		# Rounded flares where the ramp meets the runway's edge.
		for side in [-1.0, 1.0]:
			var corner := Vector2(side * half, ramp.half_runway)
			var centre := Vector2(side * (half + FLARE), ramp.half_runway + FLARE)
			# Arc from the runway edge round to the ramp side, filled from the corner.
			var arc: Array[Vector2] = []
			for s in 9:
				var t := s / 8.0 * PI * 0.5
				arc.append(centre + Vector2(-side * sin(t), -cos(t)) * FLARE)
			for s in range(1, arc.size()):
				_triangle(builder, ramp, corner, arc[s - 1], arc[s], PAVING_HEIGHT, TaxiwaysScript.PAVING_COLOR)

	# Taxi line, from the runway centreline to the outer end.
	for i in range(1, ramp.points.size()):
		_strip(builder, ramp, ramp.points[i - 1], ramp.points[i], LINE_WIDTH * 0.5, MARKING_HEIGHT, LINE_COLOR)

	# Holding position: two dashed lines on the runway side, two solid on the taxiway side.
	var hold := _point_at_v(ramp, ramp.half_runway + HOLD_FROM_EDGE)
	var hold_p: Vector2 = hold[0]
	var dir: Vector2 = hold[1]
	var across := Vector2(-dir.y, dir.x)
	var reach := half - 1.0
	for k in 4:
		var c := hold_p + dir * (k * 0.9)
		if k < 2:
			var dash := -reach
			while dash < reach:
				var dash_end := minf(dash + 1.5, reach)
				_strip(builder, ramp, c + across * dash, c + across * dash_end, 0.15, MARKING_HEIGHT, LINE_COLOR)
				dash += 2.5
		else:
			_strip(builder, ramp, c - across * reach, c + across * reach, 0.15, MARKING_HEIGHT, LINE_COLOR)

	# Red RWY AHEAD sign painted across the line.
	var sign_at := _point_at_v(ramp, ramp.half_runway + SIGN_FROM_EDGE)
	var sign_p: Vector2 = sign_at[0]
	var sign_dir: Vector2 = sign_at[1]
	var sign_across := Vector2(-sign_dir.y, sign_dir.x)
	_strip(builder, ramp, sign_p - sign_across * SIGN_SIZE.x * 0.5, sign_p + sign_across * SIGN_SIZE.x * 0.5,
		SIGN_SIZE.y * 0.5, MARKING_HEIGHT + 0.004, SIGN_COLOR)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = builder.commit()
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	var label := Label3D.new()
	label.name = "Sign"
	label.text = "RWY AHEAD"
	label.font_size = 64
	label.pixel_size = 0.045
	label.outline_size = 0
	label.modulate = Color.WHITE
	label.double_sided = true
	# Lying flat, reading upright for a pilot heading towards the runway.
	var to_runway := ramp.along * -sign_dir.x + ramp.out * -sign_dir.y
	var d := Vector3(to_runway.x, 0.0, to_runway.y).normalized()
	label.basis = Basis(d.cross(Vector3.UP), d, Vector3.UP)
	label.position = _world(ramp, sign_p, MARKING_HEIGHT + 0.05)
	root.add_child(label)
	return root


## A flat strip of half width hw from a to b (in the ramp's frame).
func _strip(builder: RefCounted, ramp: RampScript, a: Vector2, b: Vector2, hw: float, height: float,
		color: Color) -> void:
	var side := (b - a).normalized().orthogonal() * hw
	builder.add_quad([_world(ramp, a - side, height), _world(ramp, b - side, height),
		_world(ramp, b + side, height), _world(ramp, a + side, height)], Vector3.UP, color)


func _disc(builder: RefCounted, ramp: RampScript, centre: Vector2, radius: float, height: float,
		color: Color) -> void:
	var steps := 16
	for s in steps:
		var a0 := TAU * s / steps
		var a1 := TAU * (s + 1) / steps
		_triangle(builder, ramp, centre, centre + Vector2(cos(a0), sin(a0)) * radius,
			centre + Vector2(cos(a1), sin(a1)) * radius, height, color)


func _triangle(builder: RefCounted, ramp: RampScript, a: Vector2, b: Vector2, c: Vector2, height: float,
		color: Color) -> void:
	var wc := _world(ramp, c, height)
	builder.add_quad([_world(ramp, a, height), _world(ramp, b, height), wc, wc], Vector3.UP, color)

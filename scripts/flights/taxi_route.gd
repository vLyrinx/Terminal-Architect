class_name TaxiRoute
extends RefCounted
## A taxi route (checklist step 25): the smooth line an aircraft follows on the
## ground between a runway and a stand, laid out from route graph nodes.
##
## Corners between graph edges are rounded with arcs (up to TURN_RADIUS, less
## where the edges are short), and where the route doubles back on itself
## (backtracking on a runway) the aircraft makes a teardrop U-turn of
## U_TURN_RADIUS. A leg can be driven in reverse (leaving a stand, until
## pushback tugs arrive in step 26); legs are joined with a stop between them.
##
## Every SAMPLE_STEP metres the route stores the position, the way the nose
## points and the highest speed there: slower in turns, on stand lead-ins and in
## reverse, and braking in time for each stop and the end. Speeds are real m/s;
## like FlightPath, a game second moves an aircraft speed / TIME_STRETCH metres.
## The route doesn't move anything itself: FlightAircraft drives along it and
## AirTraffic slows it for traffic ahead and holds it short of runways.

const SAMPLE_STEP := 2.0
## Largest radius of an ordinary corner, in metres.
const TURN_RADIUS := 30.0
## Radius of the arcs of a U-turn.
const U_TURN_RADIUS := 12.0
## Corners sharper than this are driven as a U-turn.
const REVERSAL_DEG := 150.0
## Real m/s.
const TAXI_SPEED := 10.0
const STAND_SPEED := 3.0
const REVERSE_SPEED := 1.5
const MIN_TURN_SPEED := 2.5
## Sideways acceleration allowed in turns, m/s^2 (sets the turn speed).
const TURN_ACCEL := 1.0
const ACCEL := 0.5
const BRAKING := 0.8

## Metres from start to end.
var length := 0.0
## Distance the aircraft must not pass until cleared (short of a runway), or -1.
var hold_at := -1.0

var _points := PackedVector3Array()
## Flat unit vector the nose points along, per point.
var _facings := PackedVector3Array()
## Flat unit vector of travel, per point (opposite the facing when reversing).
var _motions := PackedVector3Array()
var _distances := PackedFloat64Array()
var _limits := PackedFloat64Array()
## Distances where the aircraft comes to a stop on the way (between legs).
var _stops: Array[float] = []


## A route through points (flat world positions), starting with the nose along
## start_facing (Vector3.ZERO: along the first leg). caps[i] is the top speed
## on the leg from points[i] to points[i + 1] (TAXI_SPEED if missing).
static func through(points: Array[Vector3], caps: Array[float] = [], start_facing := Vector3.ZERO) -> TaxiRoute:
	var route := TaxiRoute.new()
	route.add_leg(points, caps, false, start_facing)
	return route


## Appends a leg through points (the first is where the route is now, or its
## start if it is empty). reverse drives it backwards. A new leg after an
## earlier one starts with a stop.
func add_leg(points: Array[Vector3], caps: Array[float] = [], reverse := false, start_facing := Vector3.ZERO) -> void:
	var pts: Array[Vector3] = []
	var leg_caps: Array[float] = []
	for i in points.size():
		var p := Vector3(points[i].x, 0.0, points[i].z)
		if not pts.is_empty() and p.distance_to(pts[-1]) < 0.5:
			continue
		if not pts.is_empty():
			leg_caps.append(caps[i - 1] if i - 1 < caps.size() else TAXI_SPEED)
		pts.append(p)
	if pts.size() < 2:
		return
	var speed_scale := REVERSE_SPEED / TAXI_SPEED if reverse else 1.0
	if _points.is_empty():
		_emit(pts[0], (pts[1] - pts[0]).normalized(), leg_caps[0] * speed_scale, reverse)
	else:
		_stops.append(length)
	var cursor := pts[0]
	var first_dir := (pts[1] - pts[0]).normalized()
	# Facing the wrong way at the start: U-turn first.
	if start_facing != Vector3.ZERO and rad_to_deg(start_facing.angle_to(first_dir)) > REVERSAL_DEG:
		_u_turn(start_facing.normalized(), U_TURN_RADIUS, _side_towards(start_facing, pts[0], pts[1]),
			leg_caps[0] * speed_scale, reverse)
		cursor = _points[_points.size() - 1]
	for i in range(1, pts.size() - 1):
		var a := (pts[i] - pts[i - 1]).normalized()
		var b := (pts[i + 1] - pts[i]).normalized()
		var angle := a.signed_angle_to(b, Vector3.UP)
		var cap := minf(leg_caps[i - 1], leg_caps[i]) * speed_scale
		var len_in := pts[i].distance_to(cursor)
		var len_out := pts[i + 1].distance_to(pts[i]) * (1.0 if i + 1 == pts.size() - 1 else 0.5)
		if rad_to_deg(absf(angle)) > REVERSAL_DEG:
			var u_radius := minf(U_TURN_RADIUS, len_in / 3.0)
			_straight(pts[i] - a * u_radius * 3.0, leg_caps[i - 1] * speed_scale, reverse)
			_u_turn(a, u_radius, _side_towards(a, pts[i], pts[i + 1]), cap, reverse)
			cursor = _points[_points.size() - 1]
			continue
		if absf(angle) < deg_to_rad(1.0):
			continue
		var t := tan(absf(angle) * 0.5)
		var r := minf(TURN_RADIUS, minf(len_in, len_out) / t)
		var d := r * t
		_straight(pts[i] - a * d, leg_caps[i - 1] * speed_scale, reverse)
		var centre := pts[i] - a * d + _left_of(a) * r * signf(angle)
		_arc(centre, angle, r, cap, reverse)
		cursor = _points[_points.size() - 1]
	_straight(pts[-1], leg_caps[-1] * speed_scale, reverse)
	_update_limits()


## Transform of an aircraft at this distance along the route (wheels on the
## ground, nose along the facing).
func sample(s: float) -> Transform3D:
	var i := _index_at(s)
	var w := _weight(i, s)
	var p := _points[i].lerp(_points[i + 1], w)
	var facing := _facings[i].slerp(_facings[i + 1], w) if _facings[i].dot(_facings[i + 1]) > -0.99 else _facings[i + 1]
	return Transform3D(Basis.looking_at(facing, Vector3.UP), Vector3(p.x, FlightPath.GROUND_Y, p.z))


## Flat unit vector of travel at distance s.
func motion_at(s: float) -> Vector3:
	return _motions[_index_at(s)]


## Highest speed at distance s (real m/s), braking for stops and the end.
func speed_limit_at(s: float) -> float:
	var i := _index_at(s)
	return lerpf(_limits[i], _limits[i + 1], _weight(i, s))


## The next place past s the aircraft must stop at: a stop between legs, the
## hold point if not cleared, or the end.
func next_stop(s: float, cleared: bool) -> float:
	var stop := length
	for d in _stops:
		if d > s + 0.01:
			stop = minf(stop, d)
	if not cleared and hold_at >= 0.0 and hold_at > s - 0.01:
		stop = minf(stop, hold_at)
	return stop


## The first distance along the route where test(position) is true, or -1.
func find_distance(test: Callable) -> float:
	for i in _points.size():
		if test.call(_points[i]):
			return _distances[i]
	return -1.0


func get_points() -> PackedVector3Array:
	return _points


## Highest speed that still stops within distance metres.
static func stopping_speed(distance: float) -> float:
	return sqrt(2.0 * BRAKING * maxf(distance, 0.0))


# --- Building -------------------------------------------------------------------

func _emit(p: Vector3, motion: Vector3, cap: float, reverse: bool) -> void:
	if not _points.is_empty():
		length += p.distance_to(_points[_points.size() - 1])
	_points.append(p)
	_motions.append(motion)
	_facings.append(-motion if reverse else motion)
	_distances.append(length)
	_limits.append(cap)


func _straight(to: Vector3, cap: float, reverse: bool) -> void:
	var from := _points[_points.size() - 1]
	var span := from.distance_to(to)
	if span < 0.01:
		return
	var dir := (to - from) / span
	var count := maxi(ceili(span / SAMPLE_STEP), 1)
	for k in range(1, count + 1):
		_emit(from + dir * span * k / count, dir, cap, reverse)


## Turns about centre through angle (radians, positive = left) from the last point.
func _arc(centre: Vector3, angle: float, radius: float, cap: float, reverse: bool) -> void:
	var from := _points[_points.size() - 1] - centre
	var turn_cap := minf(cap, maxf(MIN_TURN_SPEED, sqrt(TURN_ACCEL * radius)))
	var count := maxi(ceili(radius * absf(angle) / SAMPLE_STEP), 1)
	for k in range(1, count + 1):
		var r := from.rotated(Vector3.UP, angle * k / count)
		_emit(centre + r, _left_of(r).normalized() * signf(angle), turn_cap, reverse)


## A teardrop U-turn from the last point, heading along dir: a quarter turn to
## one side, then three quarters back the other way, ending 2 radius further on
## along dir, heading back. side is 1 to swing left first, -1 for right.
func _u_turn(dir: Vector3, radius: float, side: float, cap: float, reverse: bool) -> void:
	var start := _points[_points.size() - 1]
	_arc(start + _left_of(dir) * radius * side, PI * 0.5 * side, radius, cap, reverse)
	_arc(_points[_points.size() - 1] + dir * radius, -PI * 1.5 * side, radius, cap, reverse)


## Swings a U-turn at `at` (heading dir) towards the side `next` is on.
static func _side_towards(dir: Vector3, at: Vector3, next: Vector3) -> float:
	return -1.0 if (next - at).dot(_left_of(dir)) < -0.01 else 1.0


## Brakes in time for each stop and the end.
func _update_limits() -> void:
	var n := _points.size()
	_limits[n - 1] = 0.0
	for d in _stops:
		_limits[_index_near(d)] = 0.0
	for i in range(n - 2, -1, -1):
		var ds := _distances[i + 1] - _distances[i]
		_limits[i] = minf(_limits[i], sqrt(_limits[i + 1] * _limits[i + 1] + 2.0 * BRAKING * ds))


func _index_at(s: float) -> int:
	return clampi(_distances.bsearch(clampf(s, 0.0, length)) - 1, 0, maxi(_points.size() - 2, 0))


func _index_near(s: float) -> int:
	return clampi(_distances.bsearch(s - 0.001), 0, _points.size() - 1)


func _weight(i: int, s: float) -> float:
	var span := _distances[i + 1] - _distances[i]
	return 0.0 if span <= 0.0 else clampf((s - _distances[i]) / span, 0.0, 1.0)


static func _left_of(heading: Vector3) -> Vector3:
	return Vector3(heading.z, 0.0, -heading.x)

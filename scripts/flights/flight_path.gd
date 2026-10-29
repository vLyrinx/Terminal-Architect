class_name FlightPath
extends RefCounted
## A landing or take-off path (checklist step 24): where an aircraft is, and
## how it is turned, at each moment of its approach and landing roll, or of
## its take-off roll and climb-out.
##
## Not simulated physics: the path is laid out once from simple shapes (a base
## leg, a turn onto final, a 3 degree glideslope with a flare, a braking roll;
## or an accelerating roll, rotation and an easing climb with a turn), with a
## believable speed, pitch and bank at every point. Pitch and bank are smoothed
## so nothing snaps. sample() then gives the transform at any time.
##
## Times are game seconds from the start of the path. Aircraft move at their
## real speeds divided by TIME_STRETCH, because the game clock runs 72 times
## faster than real time at 1x: at 1x a landing then plays at about 7 times
## real speed, quick enough to keep up with the schedule but still readable.
##
## Positions are world space; the aircraft model's origin is between its main
## gear, so y = 0 is wheels on the ground and pitching turns about the gear.

const STEP := 10.0
const TIME_STRETCH := 10.0
const GRAVITY := 9.81
## Wheels sit on top of the runway paving (runways.gd PAVING_HEIGHT).
const GROUND_Y := 0.05
## Lowest speed used when timing the path, so a stop takes finite time.
const MIN_SPEED := 1.5
## Smoothing passes over pitch and bank (more passes spread changes further:
## bank rolls in over a few hundred metres, pitch changes over about 100 m).
const PITCH_SMOOTH_PASSES := 10
const BANK_SMOOTH_PASSES := 60
## Distance from the end of the runway an aircraft always keeps clear.
const RUNWAY_MARGIN := 100.0

# --- Approach (all distances in metres, speeds in real m/s) ---
const BASE_LENGTH := 1500.0
const TURN_RADIUS := 1200.0
## Straight final from the end of the turn to the touchdown point.
const FINAL_LENGTH := 4000.0
const GLIDESLOPE_DEG := 3.0
## Touchdown point, past the threshold.
const AIM_POINT := 300.0
const FLARE_LENGTH := 350.0
## Sink rate left at touchdown, as a slope (dh/ds).
const TOUCHDOWN_SLOPE := 0.01
const BASE_SPEED := 85.0
const APPROACH_SPEED := 72.0
const TOUCHDOWN_SPEED := 68.0
## Speed falls from approach to touchdown speed over this last part of final.
const SLOWDOWN_LENGTH := 1500.0
const BRAKING := 2.0
const APPROACH_AOA := 4.5
const FLARE_AOA := 5.5
## The nose wheel comes down over this distance after touchdown.
const DEROTATE_LENGTH := 160.0
## Gear goes down this far before touchdown.
const GEAR_DOWN_DISTANCE := 4500.0

# --- Take-off ---
## Lined up this far past the threshold.
const LINEUP_OFFSET := 40.0
const TAKEOFF_ACCEL := 2.0
const ROTATE_SPEED := 75.0
## Distance between starting to rotate and the wheels leaving the ground.
const ROTATE_LENGTH := 220.0
const CLIMB_AOA := 8.0
const CLIMB_GRADIENT := 0.09
## The climb eases in over about this distance after lift-off.
const CLIMB_EASE := 300.0
const CLIMB_SPEED := 110.0
const CLIMB_STRAIGHT := 3000.0
const CLIMB_TURN_DEG := 40.0
const CLIMB_TURN_RADIUS := 2500.0
const CLIMB_OUT := 3000.0
const GEAR_UP_HEIGHT := 25.0

## Landing or take-off.
var is_landing := true
## Game seconds from the start to the end of the path.
var duration := 0.0
## Named moments: {name, time}. Landing: "gear_down", "touchdown", "stopped".
## Take-off: "lift_off", "gear_up", "end".
var events: Array[Dictionary] = []

var _points := PackedVector3Array()
var _rotations: Array[Quaternion] = []
var _times := PackedFloat64Array()
## Distance along the path of each point (horizontal), and the per-point
## values the profile gives while building.
var _distances := PackedFloat64Array()
var _speeds := PackedFloat64Array()
var _gear_down_from := INF
var _gear_down_until := INF


## A straight-in landing at this runway end (runways.gd get_ends() / runway.ends):
## a base leg and a 90 degree turn onto final from the left (turn_left) or right
## side, a 3 degree glideslope, a flare, touchdown at AIM_POINT and a braking
## roll that stops before the far end of a runway runway_length long.
## hold is extra time standing still at the end.
static func approach(runway_end: Dictionary, runway_length: float, turn_left := true, hold := 0.0) -> FlightPath:
	var path := FlightPath.new()
	path.is_landing = true
	var threshold: Vector3 = runway_end.position
	var dir: Vector3 = runway_end.direction.normalized()
	var touchdown := Vector3(threshold.x, 0.0, threshold.z) + dir * AIM_POINT
	var final_start := touchdown - dir * FINAL_LENGTH
	# The turn ends on the centreline heading dir; side is where it comes from
	# (a left turn onto final comes from the left of the centreline).
	var side := _left_of(dir) * (1.0 if turn_left else -1.0)
	var turn_start := final_start + side * TURN_RADIUS - dir * TURN_RADIUS
	var start := turn_start + side * BASE_LENGTH
	var base_heading := -side

	var xz := PackedVector3Array([start])
	_add_straight(xz, start, base_heading, BASE_LENGTH)
	_add_turn(xz, turn_start, base_heading, turn_left, TURN_RADIUS, PI * 0.5)
	_add_straight(xz, final_start, dir, FINAL_LENGTH)
	var available := maxf(runway_length - AIM_POINT - RUNWAY_MARGIN, 200.0)
	var braking := maxf(BRAKING, TOUCHDOWN_SPEED * TOUCHDOWN_SPEED / (2.0 * available))
	var rollout := TOUCHDOWN_SPEED * TOUCHDOWN_SPEED / (2.0 * braking)
	_add_straight(xz, touchdown, dir, rollout)

	var s_touchdown := BASE_LENGTH + TURN_RADIUS * PI * 0.5 + FINAL_LENGTH
	var before_final := BASE_LENGTH + TURN_RADIUS * PI * 0.5
	var glide := tan(deg_to_rad(GLIDESLOPE_DEG))
	path._build(xz, func(s: float) -> Vector3:
		var d := s_touchdown - s  # distance to touchdown
		if d <= 0.0:
			var x := -d
			var v := sqrt(maxf(TOUCHDOWN_SPEED * TOUCHDOWN_SPEED - 2.0 * braking * x, 0.0))
			return Vector3(0.0, v, lerpf(FLARE_AOA, 0.0, smoothstep(0.0, DEROTATE_LENGTH, x)))
		var h: float
		if d >= FINAL_LENGTH:
			h = glide * FINAL_LENGTH
		elif d >= FLARE_LENGTH:
			h = glide * d
		else:
			h = _flare_height(d / FLARE_LENGTH, glide)
		var speed: float
		if d >= FINAL_LENGTH:
			speed = lerpf(APPROACH_SPEED, BASE_SPEED, clampf((d - FINAL_LENGTH) / before_final, 0.0, 1.0))
		else:
			speed = lerpf(TOUCHDOWN_SPEED, APPROACH_SPEED, clampf(d / SLOWDOWN_LENGTH, 0.0, 1.0))
		var aoa := lerpf(FLARE_AOA, APPROACH_AOA, clampf(d / FLARE_LENGTH, 0.0, 1.0))
		return Vector3(h, speed, aoa))

	var t_touchdown := path.time_at_distance(s_touchdown)
	var t_stopped := path.duration
	path._gear_down_from = path.time_at_distance(s_touchdown - GEAR_DOWN_DISTANCE)
	path.events = [
		{"name": "gear_down", "time": path._gear_down_from},
		{"name": "touchdown", "time": t_touchdown},
		{"name": "stopped", "time": t_stopped},
	]
	path.duration += hold
	return path


## A take-off from this runway end: lined up just past the threshold, an
## accelerating roll, rotation, lift-off, a climb that eases in, then a turn
## to the left or right and a climb away. The roll is shortened (harder
## acceleration) if needed to lift off before the end of the runway.
static func takeoff(runway_end: Dictionary, runway_length: float, turn_left := true) -> FlightPath:
	var path := FlightPath.new()
	path.is_landing = false
	var threshold: Vector3 = runway_end.position
	var dir: Vector3 = runway_end.direction.normalized()
	var start := Vector3(threshold.x, 0.0, threshold.z) + dir * LINEUP_OFFSET

	var available := maxf(runway_length - LINEUP_OFFSET - RUNWAY_MARGIN - ROTATE_LENGTH, 200.0)
	var accel := maxf(TAKEOFF_ACCEL, ROTATE_SPEED * ROTATE_SPEED / (2.0 * available))
	var s_rotate := ROTATE_SPEED * ROTATE_SPEED / (2.0 * accel)
	var s_lift_off := s_rotate + ROTATE_LENGTH

	var xz := PackedVector3Array([start])
	var straight := s_lift_off + CLIMB_STRAIGHT
	_add_straight(xz, start, dir, straight)
	var turn_start := start + dir * straight
	var turn_angle := deg_to_rad(CLIMB_TURN_DEG)
	var turn_end := _add_turn(xz, turn_start, dir, turn_left, CLIMB_TURN_RADIUS, turn_angle)
	_add_straight(xz, turn_end, dir.rotated(Vector3.UP, turn_angle * (1.0 if turn_left else -1.0)), CLIMB_OUT)

	path._build(xz, func(s: float) -> Vector3:
		var speed := minf(sqrt(2.0 * accel * s), CLIMB_SPEED)
		if s <= s_lift_off:
			return Vector3(0.0, speed, CLIMB_AOA * smoothstep(s_rotate, s_lift_off, s))
		var x := s - s_lift_off
		var h := CLIMB_GRADIENT * (x - CLIMB_EASE * (1.0 - exp(-x / CLIMB_EASE)))
		return Vector3(h, speed, CLIMB_AOA))

	var t_lift_off := path.time_at_distance(s_lift_off)
	# Height above lift-off reaches GEAR_UP_HEIGHT: solve on the points.
	var t_gear_up := path.duration
	for i in path._points.size():
		if path._points[i].y - GROUND_Y >= GEAR_UP_HEIGHT:
			t_gear_up = path._times[i]
			break
	path._gear_down_from = 0.0
	path._gear_down_until = t_gear_up
	path.events = [
		{"name": "lift_off", "time": t_lift_off},
		{"name": "gear_up", "time": t_gear_up},
		{"name": "end", "time": path.duration},
	]
	return path


## Transform of the aircraft at time t (clamped to the path).
func sample(t: float) -> Transform3D:
	t = clampf(t, 0.0, _times[_times.size() - 1])
	var i := clampi(_times.bsearch(t) - 1, 0, _times.size() - 2)
	var span := _times[i + 1] - _times[i]
	var w := 0.0 if span <= 0.0 else clampf((t - _times[i]) / span, 0.0, 1.0)
	var q := _rotations[i].slerp(_rotations[i + 1], w)
	return Transform3D(Basis(q), _points[i].lerp(_points[i + 1], w))


## Real-world speed in m/s at time t (for display; screen speed is this
## divided by TIME_STRETCH per game second).
func speed_at(t: float) -> float:
	var i := clampi(_times.bsearch(t) - 1, 0, _times.size() - 2)
	var span := _times[i + 1] - _times[i]
	var w := 0.0 if span <= 0.0 else clampf((t - _times[i]) / span, 0.0, 1.0)
	return lerpf(_speeds[i], _speeds[i + 1], w)


func is_gear_down(t: float) -> bool:
	return t >= _gear_down_from and t < _gear_down_until


## Game seconds from the start until this distance along the path.
func time_at_distance(s: float) -> float:
	var i := clampi(_distances.bsearch(s) - 1, 0, _distances.size() - 2)
	var span := _distances[i + 1] - _distances[i]
	var w := 0.0 if span <= 0.0 else clampf((s - _distances[i]) / span, 0.0, 1.0)
	return lerpf(_times[i], _times[i + 1], w)


func get_event_time(event_name: String) -> float:
	for e in events:
		if e.name == event_name:
			return e.time
	return -1.0


func get_points() -> PackedVector3Array:
	return _points


func get_times() -> PackedFloat64Array:
	return _times


# --- Building -------------------------------------------------------------------

## Lays out positions, timing and turning from the horizontal points xz and a
## profile(distance) -> Vector3(height, real speed, angle of attack in degrees).
## Pitch is the climb or descent angle plus the angle of attack (on the ground
## it is the angle of attack alone); bank is a coordinated turn's bank.
func _build(xz: PackedVector3Array, profile: Callable) -> void:
	var n := xz.size()
	_distances.resize(n)
	_speeds.resize(n)
	_points.resize(n)
	_times.resize(n)
	var aoa := PackedFloat64Array()
	aoa.resize(n)
	var s := 0.0
	for i in n:
		if i > 0:
			s += xz[i].distance_to(xz[i - 1])
		_distances[i] = s
		var p: Vector3 = profile.call(s)
		_points[i] = Vector3(xz[i].x, GROUND_Y + p.x, xz[i].z)
		_speeds[i] = p.y
		aoa[i] = p.z

	var t := 0.0
	for i in n:
		if i > 0:
			var v := maxf((_speeds[i] + _speeds[i - 1]) * 0.5, MIN_SPEED)
			t += (_distances[i] - _distances[i - 1]) / v * TIME_STRETCH
		_times[i] = t
	duration = t

	var headings: Array[Vector3] = []
	var pitch := PackedFloat64Array()
	var bank := PackedFloat64Array()
	headings.resize(n)
	pitch.resize(n)
	bank.resize(n)
	for i in n:
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, n - 1)
		var flat := Vector3(_points[b].x - _points[a].x, 0.0, _points[b].z - _points[a].z)
		var run := flat.length()
		headings[i] = flat / run if run > 0.0 else (headings[i - 1] if i > 0 else Vector3.FORWARD)
		var climb := rad_to_deg(atan2(_points[b].y - _points[a].y, run)) if run > 0.0 else 0.0
		pitch[i] = climb + aoa[i]
	for i in n:
		var a := maxi(i - 1, 0)
		var b := mini(i + 1, n - 1)
		var ds := _distances[b] - _distances[a]
		# Signed turn rate (positive = turning left), radians per metre.
		var turn := headings[a].signed_angle_to(headings[b], Vector3.UP) / ds if ds > 0.0 else 0.0
		bank[i] = rad_to_deg(atan(_speeds[i] * _speeds[i] * turn / GRAVITY))
	_smooth(pitch, PITCH_SMOOTH_PASSES)
	_smooth(bank, BANK_SMOOTH_PASSES)

	_rotations.resize(n)
	for i in n:
		var basis := Basis.looking_at(headings[i], Vector3.UP)
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(pitch[i])) * Basis(Vector3.BACK, deg_to_rad(bank[i]))
		_rotations[i] = basis.get_rotation_quaternion()


static func _smooth(values: PackedFloat64Array, passes: int) -> void:
	var n := values.size()
	for _pass in passes:
		var copy := values.duplicate()
		for i in range(1, n - 1):
			values[i] = copy[i - 1] * 0.25 + copy[i] * 0.5 + copy[i + 1] * 0.25


## Unit vector 90 degrees to the left of a flat heading (seen from above).
static func _left_of(heading: Vector3) -> Vector3:
	return Vector3(heading.z, 0.0, -heading.x)


## Appends points every STEP along a straight line (not the start point).
static func _add_straight(xz: PackedVector3Array, from: Vector3, heading: Vector3, length: float) -> Vector3:
	var count := maxi(ceili(length / STEP), 1)
	for i in range(1, count + 1):
		xz.append(from + heading * length * i / count)
	return from + heading * length


## Appends points every STEP along a turn of radius through angle (radians),
## starting at from with this heading. Returns the end point.
static func _add_turn(xz: PackedVector3Array, from: Vector3, heading: Vector3, left: bool, radius: float,
		angle: float) -> Vector3:
	var turn_sign := 1.0 if left else -1.0
	var centre := from + _left_of(heading) * radius * turn_sign
	var count := maxi(ceili(radius * angle / STEP), 1)
	var end := from
	for i in range(1, count + 1):
		end = centre + (from - centre).rotated(Vector3.UP, angle * turn_sign * i / count)
		xz.append(end)
	return end


## Height in the flare at t = distance to touchdown / FLARE_LENGTH (0 to 1):
## a curve from the glideslope down to a gentle touchdown.
static func _flare_height(t: float, glide: float) -> float:
	# Hermite: h(0) = 0, h'(0) = TOUCHDOWN_SLOPE, h(1) = glide * L, h'(1) = glide.
	var t2 := t * t
	var t3 := t2 * t
	return FLARE_LENGTH * (TOUCHDOWN_SLOPE * (t3 - 2.0 * t2 + t) + glide * (-t3 + 2.0 * t2))

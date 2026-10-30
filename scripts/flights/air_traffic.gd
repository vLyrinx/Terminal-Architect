extends Node3D
## Landing and take-off (checklist step 24). Flies each arriving flight in on
## an approach to a runway so it touches down at its scheduled time, and sends
## each departing flight off down the runway and up into the climb.
##
## The runway is the longest one that takes the aircraft's size class and is
## long enough for the type (AircraftTypeDef.runway_length_needed). Until wind
## exists (milestone 5) every runway is used in one direction, from ends[0].
## Runway uses (an approach's touchdown and roll, a take-off roll) are kept
## SEPARATION apart; a movement that would clash waits for the next minute.
## No runway: a warning (toast and log) once per flight, and retries each minute.
##
## Taxiing (checklist step 25): once an arrival has stopped on the runway it
## takes the best exit (the runway/ramp join that gives the shortest way to
## its stand, preferring ones ahead; one behind means a U-turn) and taxis
## along the route graph (TaxiRoute) to its stand, where it parks. At its
## departure time the aircraft backs out of the stand (pushback tugs come in
## step 26), taxis to its runway's threshold and holds HOLD_SHORT before the
## runway until the runway is free for it to enter, line up and take off.
## Taxiing aircraft keep SAFE_DISTANCE behind aircraft in front of them; when
## two face each other the one with the lower flight ID goes first.
## Without a stand or a route an arrival waits VACATE_HOLD on the runway and
## is removed, and its departure starts lined up on the runway, as before.
## Moving and parked aircraft are children of this node.

const FlightScript := preload("res://scripts/flights/flight.gd")
const FlightAircraftScript := preload("res://scripts/flights/flight_aircraft.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")

## Centre-to-centre gap kept behind an aircraft ahead, in metres.
const SAFE_DISTANCE := 70.0
## Aircraft further ahead than this, or further to the side, are ignored.
const LOOK_AHEAD := 160.0
const LOOK_SIDE := 25.0
## Departures wait this far before the runway's edge until cleared on.
const HOLD_SHORT := 25.0
## Radius of the turn backing out of a stand onto the taxi line.
const PUSH_RADIUS := 20.0

## Approaches are started (or planned) this far ahead of the arrival time.
const LOOKAHEAD := 3600
## Game seconds between two uses of the same runway.
const SEPARATION := 60
## Game seconds a landed aircraft waits on the runway before it is removed.
const VACATE_HOLD := 60.0
## A late arrival never joins its approach closer than this to touchdown.
const MIN_APPROACH_LEFT := 120.0
## Arrivals without a runway are warned about this long before they are due.
const WARN_AHEAD := 1800

signal approach_started(flight: FlightScript, aircraft: Node3D)
signal touched_down(flight: FlightScript, aircraft: Node3D)
## The aircraft has stopped on the runway (taxiing takes over here from step 25).
signal rollout_finished(flight: FlightScript, aircraft: Node3D)
signal took_off(flight: FlightScript, aircraft: Node3D)
## No runway can take this flight's aircraft.
signal runway_missing(flight: FlightScript)
## Started taxiing: an arrival off the runway to its stand, or a departure off its stand.
signal taxi_started(flight: FlightScript, aircraft: Node3D)
signal arrived_on_stand(flight: FlightScript, aircraft: Node3D)
## A departure was cleared from its hold point onto the runway.
signal cleared_onto_runway(flight: FlightScript, aircraft: Node3D)
## No taxi route between the runway and this flight's stand.
signal taxi_route_missing(flight: FlightScript)

## The Runways node (runways.gd).
@export var runways: RunwaysScript
## The RouteGraph node (route_graph.gd). Without it aircraft don't taxi.
@export var route_graph: Node
## Optional MessageToast (message_toast.gd) for the "no runway" warning.
@export var message_toast: Control
## If false, nothing moves unless update() and advance() are called (tests).
@export var automatic := true

## flight ID -> aircraft node, for every flight moving now.
var _moving := {}
## runway ID -> Array of Vector2i(from, to) game times the runway is in use.
var _slots := {}
## Flight IDs already warned about.
var _warned := {}
## Arrival IDs that were held back (no runway or a clash): they fly the whole approach.
var _delayed := {}
## Flight IDs already warned about a missing taxi route.
var _taxi_warned := {}
## Departure ID -> game seconds from lining up to lift-off.
var _lift_off_times := {}


func _ready() -> void:
	if runways:
		runways.runway_removed.connect(_on_runway_removed)
	if automatic:
		GameClock.ticked.connect(advance)
		GameClock.minute_passed.connect(func(_m: int) -> void: update())


## Starts the approaches and take-offs that are due now.
func update() -> void:
	var now := GameClock.game_time
	for runway_id: int in _slots:
		_slots[runway_id] = _slots[runway_id].filter(func(slot: Vector2i) -> bool: return slot.y > now)
	for f in FlightSchedule.get_all_flights():
		if f.scheduled_time > now + LOOKAHEAD:
			break
		if f.status != FlightScript.Status.SCHEDULED or _moving.has(f.id):
			continue
		if f.is_arrival():
			_try_approach(f, now)
		elif f.scheduled_time <= now:
			var parked := _parked_for(f)
			if parked:
				_try_taxi_out(f, parked)
			elif f.pair == null or not _moving.has(f.pair.id):
				_try_takeoff(f, now)


## Moves every aircraft on by game_seconds (one simulation tick).
func advance(game_seconds: float) -> void:
	var now := GameClock.game_time
	var all := _moving.values()
	for aircraft: Node3D in all:
		if aircraft.is_taxiing():
			if aircraft.is_waiting_at_hold():
				_try_enter_runway(aircraft, now)
			aircraft.traffic_limit = _traffic_limit(aircraft)
	for aircraft: Node3D in all:
		if is_instance_valid(aircraft):
			aircraft.advance(game_seconds)


## The runway and end this aircraft type would use: {runway, end}, or empty.
func pick_runway(type_id: StringName) -> Dictionary:
	var type_def: Resource = AircraftCatalog.get_type(type_id)
	var size_class: Resource = AircraftCatalog.get_class_of(type_id)
	if runways == null or type_def == null or size_class == null:
		return {}
	var best: RefCounted = null
	for runway: RefCounted in runways.get_all():
		var def := RunwayCatalog.get_def(runway.def_id)
		if def == null or not def.handles(size_class.runway_class) or runway.length < type_def.runway_length_needed:
			continue
		if best == null or runway.length > best.length or (runway.length == best.length and runway.id < best.id):
			best = runway
	if best == null:
		return {}
	return {"runway": best, "end": best.ends[0]}


## Every aircraft moving now.
func get_aircraft() -> Array:
	return _moving.values()


func get_aircraft_for(flight: FlightScript) -> Node3D:
	return _moving.get(flight.id)


## True if the runway is free from `from` to `to` (game seconds), with separation.
func is_runway_free(runway_id: int, from: int, to: int) -> bool:
	for slot: Vector2i in _slots.get(runway_id, []):
		if slot.x < to + SEPARATION and from < slot.y + SEPARATION:
			return false
	return true


# --- Starting movements ------------------------------------------------------

func _try_approach(arrival: FlightScript, now: int) -> void:
	var leaves := arrival.pair.scheduled_time if arrival.pair else arrival.scheduled_time
	if leaves < now:
		return
	var choice := pick_runway(arrival.aircraft_type)
	if choice.is_empty():
		if arrival.scheduled_time <= now + WARN_AHEAD:
			_delayed[arrival.id] = true
			_warn_no_runway(arrival)
		return
	var runway: RefCounted = choice.runway
	var path := FlightPath.approach(choice.end, runway.length, arrival.id % 2 == 0, VACATE_HOLD)
	var t_touchdown := path.get_event_time("touchdown")
	var start := arrival.scheduled_time - int(t_touchdown)
	if start > now:
		return
	# Join part-way along (game start, or the minute boundary), unless it was held back.
	var skip := 0.0 if _delayed.has(arrival.id) else clampf(now - start, 0.0, t_touchdown - MIN_APPROACH_LEFT)
	var began := now - int(skip)
	var slot := Vector2i(began + int(t_touchdown) - SEPARATION, began + int(path.duration))
	if not is_runway_free(runway.id, slot.x, slot.y):
		_delayed[arrival.id] = true
		return
	_add_slot(runway.id, slot)
	var aircraft := _spawn(arrival, path, runway.id, choice.end, skip)
	arrival.status = FlightScript.Status.APPROACHING
	_delayed.erase(arrival.id)
	_warned.erase(arrival.id)
	print("AIR | %s approaching runway %s (touchdown %s)" % [arrival.flight_number, choice.end.designator,
		_clock(began + int(t_touchdown))])
	approach_started.emit(arrival, aircraft)


func _try_takeoff(departure: FlightScript, now: int) -> void:
	# Only an aircraft that came in can leave (the arrival flew, or there is none).
	if departure.pair and departure.pair.status == FlightScript.Status.SCHEDULED:
		return
	var choice := pick_runway(departure.aircraft_type)
	if choice.is_empty():
		_warn_no_runway(departure)
		return
	var runway: RefCounted = choice.runway
	var path := FlightPath.takeoff(choice.end, runway.length, departure.id % 2 == 0)
	var slot := Vector2i(now, now + int(path.get_event_time("lift_off")))
	if not is_runway_free(runway.id, slot.x, slot.y):
		return
	_add_slot(runway.id, slot)
	_spawn(departure, path, runway.id, choice.end)
	_warned.erase(departure.id)
	print("AIR | %s taking off from runway %s" % [departure.flight_number, choice.end.designator])


func _spawn(flight: FlightScript, path: FlightPath, runway_id: int, runway_end: Dictionary,
		start_at := 0.0) -> Node3D:
	var aircraft := FlightAircraftScript.new()
	aircraft.runway_id = runway_id
	aircraft.runway_end = runway_end
	aircraft.setup(flight, path, AirlineCatalog.make_aircraft_model(flight.airline_id, flight.aircraft_type), start_at)
	aircraft.path_event.connect(_on_path_event)
	aircraft.path_finished.connect(_on_path_finished)
	aircraft.taxi_finished.connect(_on_taxi_finished)
	add_child(aircraft)
	_moving[flight.id] = aircraft
	return aircraft


func _add_slot(runway_id: int, slot: Vector2i) -> void:
	if not _slots.has(runway_id):
		_slots[runway_id] = []
	_slots[runway_id].append(slot)


# --- Events ------------------------------------------------------------------

func _on_path_event(aircraft: Node3D, event_name: String) -> void:
	var f: FlightScript = aircraft.flight
	match event_name:
		"touchdown":
			f.status = FlightScript.Status.LANDED
			print("AIR | %s landed %s" % [f.flight_number, GameClock.get_time_string()])
			touched_down.emit(f, aircraft)
		"stopped":
			rollout_finished.emit(f, aircraft)
			_start_taxi_in(aircraft)
		"lift_off":
			f.status = FlightScript.Status.DEPARTED
			print("AIR | %s took off %s" % [f.flight_number, GameClock.get_time_string()])
			took_off.emit(f, aircraft)


func _on_path_finished(aircraft: Node3D) -> void:
	_remove(aircraft)


func _remove(aircraft: Node3D) -> void:
	_moving.erase(aircraft.flight.id)
	aircraft.queue_free()


func _on_runway_removed(runway_id: int) -> void:
	# Aircraft using it are taken away; arrivals still in the air come round
	# again, and departures still on the ground try again (from another runway).
	for aircraft: Node3D in _moving.values():
		if aircraft.runway_id != runway_id:
			continue
		var f: FlightScript = aircraft.flight
		if f.status == FlightScript.Status.APPROACHING:
			f.status = FlightScript.Status.SCHEDULED
			_delayed[f.id] = true
		elif not f.is_arrival() and f.status == FlightScript.Status.TAXIING:
			f.status = FlightScript.Status.SCHEDULED
		_remove(aircraft)
	_slots.erase(runway_id)


# --- Taxiing -----------------------------------------------------------------

## After the landing roll: taxi to the flight's stand, if there is a route.
## Without one the aircraft waits out VACATE_HOLD and is removed.
func _start_taxi_in(aircraft: Node3D) -> void:
	var f: FlightScript = aircraft.flight
	if route_graph == null or f.stand_id < 0:
		return
	var runway: RefCounted = runways.get_runway(aircraft.runway_id)
	var route := _route_to_stand(aircraft, runway) if runway else null
	if route == null:
		_warn_taxi(f, "No taxi route from the runway to stand %d for %s" % [f.stand_id, f.flight_number])
		return
	# Keep the runway for the time it takes to get off it.
	var off := route.find_distance(func(p: Vector3) -> bool: return not _on_runway(runway, p))
	var vacate := (off if off >= 0.0 else route.length) / TaxiRoute.TAXI_SPEED * FlightPath.TIME_STRETCH * 1.5
	var now := GameClock.game_time
	_add_slot(runway.id, Vector2i(now, now + int(vacate)))
	aircraft.runway_id = 0
	f.status = FlightScript.Status.TAXIING
	aircraft.start_taxi(route)
	print("TAXI | %s taxiing to stand %d (%d m)" % [f.flight_number, f.stand_id, roundi(route.length)])
	taxi_started.emit(f, aircraft)


## Leaves the stand for the runway, if there is a route.
func _try_taxi_out(departure: FlightScript, aircraft: Node3D) -> void:
	var choice := pick_runway(departure.aircraft_type)
	if choice.is_empty():
		_warn_no_runway(departure)
		return
	var route := _route_to_runway(departure.stand_id, choice)
	if route == null:
		_warn_taxi(departure, "No taxi route from stand %d to runway %s for %s" % [departure.stand_id,
			choice.end.designator, departure.flight_number])
		return
	_moving.erase(aircraft.flight.id)
	aircraft.set_flight(departure)
	_moving[departure.id] = aircraft
	aircraft.runway_id = choice.runway.id
	aircraft.runway_end = choice.end
	_lift_off_times[departure.id] = FlightPath.takeoff(choice.end, choice.runway.length).get_event_time("lift_off")
	departure.status = FlightScript.Status.TAXIING
	_warned.erase(departure.id)
	_taxi_warned.erase(departure.id)
	aircraft.start_taxi(route)
	print("TAXI | %s leaving stand %d for runway %s (%d m)" % [departure.flight_number, departure.stand_id,
		choice.end.designator, roundi(route.length)])
	taxi_started.emit(departure, aircraft)


## A departure waiting at its hold point goes on once the runway is free for
## it to line up and take off.
func _try_enter_runway(aircraft: Node3D, now: int) -> void:
	var runway: RefCounted = runways.get_runway(aircraft.runway_id)
	if runway == null:
		return
	var route: TaxiRoute = aircraft.taxi
	var to_lineup := (route.length - route.hold_at) / TaxiRoute.TAXI_SPEED * FlightPath.TIME_STRETCH * 1.5
	var slot := Vector2i(now, now + int(to_lineup + _lift_off_times.get(aircraft.flight.id, 300.0)))
	if not is_runway_free(runway.id, slot.x, slot.y):
		return
	_add_slot(runway.id, slot)
	aircraft.hold_cleared = true
	print("TAXI | %s cleared onto runway %s" % [aircraft.flight.flight_number, aircraft.runway_end.designator])
	cleared_onto_runway.emit(aircraft.flight, aircraft)


func _on_taxi_finished(aircraft: Node3D) -> void:
	var f: FlightScript = aircraft.flight
	if f.is_arrival():
		aircraft.park()
		f.status = FlightScript.Status.ON_STAND
		print("TAXI | %s on stand %d %s" % [f.flight_number, f.stand_id, GameClock.get_time_string()])
		arrived_on_stand.emit(f, aircraft)
		if f.pair == null:
			_remove(aircraft)
		return
	# Lined up: take off.
	var runway: RefCounted = runways.get_runway(aircraft.runway_id)
	if runway == null:
		f.status = FlightScript.Status.SCHEDULED
		_remove(aircraft)
		return
	_lift_off_times.erase(f.id)
	aircraft.start_path(FlightPath.takeoff(aircraft.runway_end, runway.length, f.id % 2 == 0))
	print("AIR | %s taking off from runway %s" % [f.flight_number, aircraft.runway_end.designator])


## The parked aircraft of a departure's arrival, or null.
func _parked_for(departure: FlightScript) -> Node3D:
	if departure.pair == null:
		return null
	var aircraft: Node3D = _moving.get(departure.pair.id)
	return aircraft if aircraft and aircraft.parked else null


## From where the aircraft stopped on the runway to its stand: off at the
## runway/ramp join giving the shortest trip (one behind costs extra and means
## a U-turn first), then along the graph.
func _route_to_stand(aircraft: Node3D, runway: RefCounted) -> TaxiRoute:
	var stand_node: int = route_graph.find_stand(aircraft.flight.stand_id)
	if stand_node < 0:
		return null
	var dir: Vector3 = aircraft.runway_end.direction.normalized()
	var p := Vector3(aircraft.position.x, 0.0, aircraft.position.z)
	var best: Array[int] = []
	var best_cost := INF
	for node: Dictionary in route_graph.nodes.values():
		if not node.on_runway or not node.on_taxiway or not _on_runway(runway, node.position):
			continue
		var path: Array[int] = route_graph.find_path(node.id, stand_node)
		if path.is_empty():
			continue
		var along: float = (node.position - p).dot(dir)
		var cost: float = route_graph.path_length(path) + (along if along >= 0.0 else 200.0 - 3.0 * along)
		if cost < best_cost:
			best_cost = cost
			best = path
	if best.is_empty():
		return null
	var points: Array[Vector3] = [p]
	var caps: Array[float] = [TaxiRoute.TAXI_SPEED]
	for i in best.size():
		points.append(route_graph.nodes[best[i]].position)
		if i + 1 < best.size():
			caps.append(_edge_cap(best[i], best[i + 1]))
	return TaxiRoute.through(points, caps, dir)


## From a stand to the line-up point on a runway: back out of the stand,
## turning onto the taxi line to face the way out, then along the graph to the
## threshold, holding HOLD_SHORT before the runway.
func _route_to_runway(stand_id: int, choice: Dictionary) -> TaxiRoute:
	if route_graph == null:
		return null
	var stand_node: int = route_graph.find_stand(stand_id)
	var threshold: int = route_graph.find_runway_end(choice.end.designator)
	if stand_node < 0 or threshold < 0:
		return null
	var path: Array[int] = route_graph.find_path(stand_node, threshold)
	if path.size() < 3:
		return null
	var nodes: Dictionary = route_graph.nodes
	var stop: Vector3 = nodes[path[0]].position
	var join: Vector3 = nodes[path[1]].position
	var out := (join - stop).normalized()
	var onward: Vector3 = (nodes[path[2]].position - join).normalized()
	var dir: Vector3 = choice.end.direction.normalized()
	var end_pos: Vector3 = choice.end.position
	var lineup := Vector3(end_pos.x, 0.0, end_pos.z) + dir * FlightPath.LINEUP_OFFSET

	var route := TaxiRoute.new()
	var points: Array[Vector3] = []
	var start_facing := Vector3.ZERO
	if absf(out.dot(onward)) < 0.7:
		# Back out and swing the tail round onto the taxi line.
		var turn_end := join - onward * minf(PUSH_RADIUS, stop.distance_to(join))
		route.add_leg([stop, join, turn_end] as Array[Vector3], [], true)
		points.append(turn_end)
	else:
		route.add_leg([stop, join] as Array[Vector3], [], true)
		start_facing = -out
	var caps: Array[float] = []
	for i in range(1, path.size()):
		if not points.is_empty():
			caps.append(TaxiRoute.TAXI_SPEED if i == 1 else _edge_cap(path[i - 1], path[i]))
		points.append(nodes[path[i]].position)
	caps.append(TaxiRoute.TAXI_SPEED)
	points.append(lineup)
	route.add_leg(points, caps, false, start_facing)
	var runway: RefCounted = choice.runway
	var on := route.find_distance(func(p: Vector3) -> bool: return _on_runway(runway, p))
	if on >= 0.0:
		route.hold_at = maxf(on - HOLD_SHORT, 0.0)
	return route


## Top speed on the graph edge between two nodes.
func _edge_cap(a: int, b: int) -> float:
	for edge_id: int in route_graph.nodes[a].edges:
		var edge: Dictionary = route_graph.edges[edge_id]
		if edge.a == b or edge.b == b:
			return TaxiRoute.STAND_SPEED if edge.kind == "stand" else TaxiRoute.TAXI_SPEED
	return TaxiRoute.TAXI_SPEED


## Highest speed a taxiing aircraft may go to stay SAFE_DISTANCE behind any
## aircraft on the ground ahead of it.
func _traffic_limit(aircraft: Node3D) -> float:
	var limit := INF
	for other: Node3D in _moving.values():
		if other == aircraft or other.get_height() > 2.0:
			continue
		var ahead := _ahead_of(aircraft, other)
		if ahead < 0.0:
			continue
		# Facing each other: the lower flight ID goes first.
		if other.is_taxiing() and _ahead_of(other, aircraft) >= 0.0 and aircraft.flight.id < other.flight.id:
			continue
		limit = minf(limit, TaxiRoute.stopping_speed(ahead - SAFE_DISTANCE))
	return limit


## How far other is ahead of aircraft along the way it is moving, or -1 if it
## isn't in front within LOOK_AHEAD and LOOK_SIDE.
static func _ahead_of(aircraft: Node3D, other: Node3D) -> float:
	var d := other.position - aircraft.position
	d.y = 0.0
	var motion: Vector3 = aircraft.get_motion()
	var ahead := d.dot(motion)
	if ahead <= 0.0 or ahead > LOOK_AHEAD or absf(d.dot(Vector3(motion.z, 0.0, -motion.x))) > LOOK_SIDE:
		return -1.0
	return ahead


static func _on_runway(runway: RefCounted, p: Vector3) -> bool:
	return runway.rect.has_point(BuildGrid.world_to_tile(p))


func _warn_taxi(flight: FlightScript, text: String) -> void:
	if _taxi_warned.has(flight.id):
		return
	_taxi_warned[flight.id] = true
	print("TAXI WARNING | %s" % text)
	if message_toast:
		message_toast.show_message(text)
	taxi_route_missing.emit(flight)


func _warn_no_runway(flight: FlightScript) -> void:
	if _warned.has(flight.id):
		return
	_warned[flight.id] = true
	var type_def: Resource = AircraftCatalog.get_type(flight.aircraft_type)
	var text := "No runway for %s (%s): needs %s m" % [flight.flight_number,
		type_def.display_name if type_def else String(flight.aircraft_type),
		Money.format(type_def.runway_length_needed if type_def else 0).trim_prefix("$")]
	print("RUNWAY WARNING | %s" % text)
	if message_toast:
		message_toast.show_message(text)
	runway_missing.emit(flight)


static func _clock(time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]

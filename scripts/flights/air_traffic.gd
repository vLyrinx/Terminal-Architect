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
## Until taxiing exists (step 25) an arrival stops on the runway, waits
## VACATE_HOLD and is removed, and a departure starts lined up on the runway.
## Moving aircraft are children of this node.

const FlightScript := preload("res://scripts/flights/flight.gd")
const FlightAircraftScript := preload("res://scripts/flights/flight_aircraft.gd")
const RunwaysScript := preload("res://scripts/airside/runways.gd")

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

## The Runways node (runways.gd).
@export var runways: RunwaysScript
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
			_try_takeoff(f, now)


## Moves every aircraft on by game_seconds (one simulation tick).
func advance(game_seconds: float) -> void:
	for aircraft: Node3D in _moving.values():
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
	var aircraft := _spawn(arrival, path, runway.id, skip)
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
	_spawn(departure, path, runway.id)
	_warned.erase(departure.id)
	print("AIR | %s taking off from runway %s" % [departure.flight_number, choice.end.designator])


func _spawn(flight: FlightScript, path: FlightPath, runway_id: int, start_at := 0.0) -> Node3D:
	var aircraft := FlightAircraftScript.new()
	aircraft.runway_id = runway_id
	aircraft.setup(flight, path, AirlineCatalog.make_aircraft_model(flight.airline_id, flight.aircraft_type), start_at)
	aircraft.path_event.connect(_on_path_event)
	aircraft.path_finished.connect(_on_path_finished)
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
		_remove(aircraft)
	_slots.erase(runway_id)


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

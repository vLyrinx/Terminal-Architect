extends Node
## Stand allocation (checklist step 23). Before each arrival, gives the flight
## a free stand that its aircraft fits, connected to a taxiway, and reserves
## the stand from just before arrival until just after its paired departure
## (the turnaround). Both flights of the rotation get the stand_id.
## The smallest stand size that fits is preferred, so big stands stay free for
## big aircraft. If no stand is free a warning is shown once per flight, and
## allocation keeps retrying (a stand may be built or freed in time).
## Reservations end on their own once the departure time has passed, or as
## soon as the aircraft has been pushed back off the stand (free_stand).

const FlightScript := preload("res://scripts/flights/flight.gd")
const StandsScript := preload("res://scripts/airside/stands.gd")
const SizeClassDefScript := preload("res://scripts/aircraft/size_class_def.gd")

## Arrivals get a stand this many minutes ahead of their scheduled time.
const LOOKAHEAD_MINUTES := 120
## Reservations start this long before arrival and end this long after departure.
const BUFFER_MINUTES := 10

signal stand_assigned(flight: FlightScript, stand_id: int)
## No suitable stand was free for this arrival.
signal allocation_failed(flight: FlightScript)

## The Stands node (stands.gd).
@export var stands: StandsScript
## Optional MessageToast (message_toast.gd) for the "no stand free" warning.
@export var message_toast: Control
## If false, allocation only happens when allocate_upcoming() is called (tests).
@export var automatic := true

## stand_id -> Array of reservations {from, to, arrival}, ordered by start.
var _reservations := {}
## Arrival flight IDs already warned about.
var _warned := {}


func _ready() -> void:
	if stands:
		stands.stand_added.connect(func(_id: int) -> void: _request())
		stands.stand_changed.connect(func(_id: int) -> void: _request())
		stands.stand_removed.connect(_on_stand_removed)
	if automatic:
		GameClock.minute_passed.connect(func(_m: int) -> void: _on_minute())
		FlightSchedule.flights_created.connect(func(_d: int, _f: Array) -> void: _request())
		_request()


## Tries to give a stand to every arrival due within LOOKAHEAD_MINUTES that
## doesn't have one yet (also late ones whose departure hasn't gone).
func allocate_upcoming() -> void:
	var now := GameClock.game_time
	var horizon := now + LOOKAHEAD_MINUTES * 60
	for f in FlightSchedule.get_all_flights():
		if f.scheduled_time > horizon:
			break
		if not f.is_arrival() or f.stand_id != -1 or f.status != FlightScript.Status.SCHEDULED:
			continue
		var leaves := f.pair.scheduled_time if f.pair else f.scheduled_time
		if leaves < now:
			continue
		allocate(f)


## Gives this arrival (and its departure) a free stand. Returns the stand ID,
## or -1 if none is free (and warns, once per flight).
func allocate(arrival: FlightScript) -> int:
	if arrival.stand_id != -1:
		return arrival.stand_id
	var window := get_reservation_window(arrival)
	var stand_id := find_free_stand(arrival.aircraft_type, window.x, window.y)
	if stand_id == -1:
		if not _warned.has(arrival.id):
			_warned[arrival.id] = true
			var type_def: Resource = AircraftCatalog.get_type(arrival.aircraft_type)
			var text := "No free stand for %s (%s) arriving %s" % [arrival.flight_number,
				type_def.display_name if type_def else String(arrival.aircraft_type), arrival.get_time_string()]
			print("STAND WARNING | %s" % text)
			if message_toast:
				message_toast.show_message(text)
			allocation_failed.emit(arrival)
		return -1
	_reserve(stand_id, window, arrival)
	arrival.stand_id = stand_id
	if arrival.pair:
		arrival.pair.stand_id = stand_id
	_warned.erase(arrival.id)
	print("STAND | %s -> stand %d, reserved %s-%s" % [_rotation_name(arrival), stand_id,
		_clock(window.x), _clock(window.y)])
	stand_assigned.emit(arrival, stand_id)
	return stand_id


## Frees the stand held by this arrival's rotation.
func release(arrival: FlightScript) -> void:
	for stand_id: int in _reservations:
		var list: Array = _reservations[stand_id]
		for r: Dictionary in list.duplicate():
			if r.arrival == arrival:
				list.erase(r)
				_update_note(stand_id)
	arrival.stand_id = -1
	if arrival.pair:
		arrival.pair.stand_id = -1


## Ends the reservation of this arrival's rotation now (its aircraft has left
## the stand). The flights keep their stand_id.
func free_stand(arrival: FlightScript) -> void:
	for stand_id: int in _reservations:
		var list: Array = _reservations[stand_id]
		for r: Dictionary in list.duplicate():
			if r.arrival == arrival:
				list.erase(r)
				_update_note(stand_id)
	_request()


## Reserved time of an arrival's rotation, Vector2i(from, to) in game seconds.
func get_reservation_window(arrival: FlightScript) -> Vector2i:
	var departs := arrival.pair.scheduled_time if arrival.pair else arrival.scheduled_time
	return Vector2i(arrival.scheduled_time - BUFFER_MINUTES * 60, departs + BUFFER_MINUTES * 60)


## The best free, connected stand for this aircraft type between from and to,
## or -1: the smallest size that fits, then the lowest stand number.
func find_free_stand(type_id: StringName, from: int, to: int) -> int:
	var best := -1
	var best_rank := 1 << 30
	for stand: RefCounted in stands.get_all():
		var def: Resource = StandCatalog.get_def(stand.def_id)
		if def == null or not def.takes(type_id) or not stand.has_taxiway():
			continue
		if not is_free(stand.id, from, to):
			continue
		var rank: int = SizeClassDefScript.IDS.find(def.size_class)
		if rank < best_rank or (rank == best_rank and stand.id < best):
			best = stand.id
			best_rank = rank
	return best


## True if nothing is reserved on the stand between from and to.
func is_free(stand_id: int, from: int, to: int) -> bool:
	for r: Dictionary in _reservations.get(stand_id, []):
		if r.from < to and from < r.to:
			return false
	return true


## The stand's reservations as {from, to, arrival}, ordered by start.
func get_reservations(stand_id: int) -> Array:
	return _reservations.get(stand_id, []).duplicate()


func _reserve(stand_id: int, window: Vector2i, arrival: FlightScript) -> void:
	if not _reservations.has(stand_id):
		_reservations[stand_id] = []
	var list: Array = _reservations[stand_id]
	list.append({"from": window.x, "to": window.y, "arrival": arrival})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.from < b.from)
	_update_note(stand_id)


func _on_minute() -> void:
	# Drop reservations whose time is over, then look ahead again.
	var now := GameClock.game_time
	for stand_id: int in _reservations:
		var list: Array = _reservations[stand_id]
		var before := list.size()
		_reservations[stand_id] = list.filter(func(r: Dictionary) -> bool: return r.to > now)
		if _reservations[stand_id].size() != before:
			_update_note(stand_id)
	allocate_upcoming()


func _on_stand_removed(stand_id: int) -> void:
	# Flights that held the removed stand need another one.
	for r: Dictionary in _reservations.get(stand_id, []):
		var arrival: FlightScript = r.arrival
		arrival.stand_id = -1
		if arrival.pair:
			arrival.pair.stand_id = -1
		print("STAND | %s lost stand %d (removed)" % [_rotation_name(arrival), stand_id])
	_reservations.erase(stand_id)
	_request()


## Runs allocate_upcoming once at the end of the frame, however many
## changes asked for it.
func _request() -> void:
	if automatic and not is_queued_for_deletion():
		if not has_meta(&"queued"):
			set_meta(&"queued", true)
			_run_queued.call_deferred()


func _run_queued() -> void:
	remove_meta(&"queued")
	allocate_upcoming()


## Shows the stand's next reservation on its label.
func _update_note(stand_id: int) -> void:
	if stands == null or stands.get_stand(stand_id) == null:
		return
	var list: Array = _reservations.get(stand_id, [])
	if list.is_empty():
		stands.set_note(stand_id, "Free")
		return
	var r: Dictionary = list[0]
	var more := "  (+%d)" % (list.size() - 1) if list.size() > 1 else ""
	stands.set_note(stand_id, "Next: %s %s-%s%s" % [_rotation_name(r.arrival), _clock(r.from), _clock(r.to), more])


func _rotation_name(arrival: FlightScript) -> String:
	return "%s/%s" % [arrival.flight_number, arrival.pair.flight_number.get_slice(" ", 1)] if arrival.pair \
		else arrival.flight_number


static func _clock(time: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(time)
	return "%02d:%02d" % [dt.hour, dt.minute]

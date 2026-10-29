extends Node
## FlightSchedule (autoload, checklist step 22). Turns every airline's weekly
## rotations (AirlineDef.weekly_flights) into Flight instances, one day at a
## time, for other systems to use. Today and tomorrow always exist, so systems
## can plan ahead (stand allocation reserves stands before arrival). When a
## flight's scheduled minute comes, flight_due is emitted.

const FlightScript := preload("res://scripts/flights/flight.gd")
const DAY := 86400

## A day's flights were created. day_start is midnight of that day (game seconds).
signal flights_created(day_start: int, flights: Array)
## The clock reached a flight's scheduled time.
signal flight_due(flight: FlightScript)

## Every flight kept, ordered by scheduled time.
var _flights: Array[FlightScript] = []
## day_start -> true for days already created.
var _created_days := {}
var _next_id := 1


func _ready() -> void:
	GameClock.minute_passed.connect(_on_minute_passed)
	GameClock.day_passed.connect(_on_day_passed)
	var today := get_today_start()
	# Rotations that would already have arrived before the game starts are skipped.
	create_day(today, GameClock.game_time)
	create_day(today + DAY)


## Midnight of the current in-game day, in game seconds.
func get_today_start() -> int:
	return GameClock.game_time - GameClock.game_time % DAY


## Creates the flights for the day starting at day_start. Rotations arriving
## before not_before are left out. Returns the new flights (empty if the day
## was already created).
func create_day(day_start: int, not_before := 0) -> Array[FlightScript]:
	var created: Array[FlightScript] = []
	if _created_days.has(day_start):
		return created
	_created_days[day_start] = true
	var weekday: int = Time.get_datetime_dict_from_unix_time(day_start).weekday
	for airline: Resource in AirlineCatalog.get_all_airlines():
		for rotation: Resource in airline.weekly_flights:
			if not rotation.operates_on(weekday):
				continue
			var arr_minute: int = rotation.get_arrival_minute()
			var dep_minute: int = rotation.get_departure_minute()
			if arr_minute < 0 or dep_minute < 0:
				continue
			var arrival_time := day_start + arr_minute * 60
			if arrival_time < not_before:
				continue
			var departure_time := day_start + dep_minute * 60 + (DAY if rotation.departs_next_day() else 0)
			var arrival := _make_flight(airline, rotation.arrival_number, FlightScript.Direction.ARRIVAL,
				rotation.aircraft_type, arrival_time, rotation.origin)
			var departure := _make_flight(airline, rotation.departure_number, FlightScript.Direction.DEPARTURE,
				rotation.aircraft_type, departure_time, rotation.destination)
			arrival.pair = departure
			departure.pair = arrival
			created.append(arrival)
			created.append(departure)
	_flights.append_array(created)
	_flights.sort_custom(_earlier)
	created.sort_custom(_earlier)
	var arrivals := created.filter(func(f: FlightScript) -> bool: return f.is_arrival()).size()
	print("SCHEDULE | %s: %d flights created (%d arrivals, %d departures)" % [
		_date_string(day_start), created.size(), arrivals, created.size() - arrivals])
	flights_created.emit(day_start, created)
	return created


## Flights scheduled on the day starting at day_start, by time.
func get_flights_on_day(day_start: int) -> Array[FlightScript]:
	var day: Array[FlightScript] = []
	for f in _flights:
		if f.scheduled_time >= day_start and f.scheduled_time < day_start + DAY:
			day.append(f)
	return day


## Today's flights, by time.
func get_today_flights() -> Array[FlightScript]:
	return get_flights_on_day(get_today_start())


## Every flight kept (today, tomorrow and anything from yesterday), by time.
func get_all_flights() -> Array[FlightScript]:
	return _flights.duplicate()


func get_flight(id: int) -> FlightScript:
	for f in _flights:
		if f.id == id:
			return f
	return null


## Removes every flight and created day (tests and new games).
func clear() -> void:
	_flights.clear()
	_created_days.clear()


func _make_flight(airline: Resource, number: int, direction: FlightScript.Direction, type_id: StringName,
		time: int, route: String) -> FlightScript:
	var f := FlightScript.new()
	f.id = _next_id
	_next_id += 1
	f.airline_id = airline.id
	f.flight_number = "%s %d" % [airline.short_code, number]
	f.direction = direction
	f.aircraft_type = type_id
	f.scheduled_time = time
	f.route = route
	return f


func _on_minute_passed(_minute_of_day: int) -> void:
	var now := GameClock.game_time - GameClock.game_time % 60
	for f in _flights:
		if f.scheduled_time > now:
			break
		if f.scheduled_time == now:
			print("FLIGHT DUE | %s" % f)
			flight_due.emit(f)


func _on_day_passed(_datetime: Dictionary) -> void:
	var today := get_today_start()
	# Keep one day ahead, and drop flights from before yesterday.
	create_day(today + DAY)
	var kept: Array[FlightScript] = []
	for f in _flights:
		if f.scheduled_time >= today - DAY or (f.pair != null and f.pair.scheduled_time >= today):
			kept.append(f)
	_flights = kept
	for day: int in _created_days.keys():
		if day < today - DAY:
			_created_days.erase(day)


static func _earlier(a: FlightScript, b: FlightScript) -> bool:
	return a.scheduled_time < b.scheduled_time if a.scheduled_time != b.scheduled_time else a.id < b.id


func _date_string(day_start: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(day_start)
	return "%s %d %s" % [GameClock.WEEKDAY_NAMES[dt.weekday], dt.day, GameClock.MONTH_NAMES[dt.month - 1]]

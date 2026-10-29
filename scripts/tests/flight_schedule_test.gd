extends Control
## Test for the flight schedule (checklist step 22).
## Run this scene on its own (F6). It checks Brightwater's weekly rotations,
## creates flights for a Friday, Sunday and Monday and checks which run and
## at what times, the overnight rotation, arrival/departure pairs, flights
## coming due on the clock and the next day being created at midnight, and
## the F5 debug list. Prints PASS or FAIL for each check, then leaves the
## debug list of today's flights on screen.

const FlightScript := preload("res://scripts/flights/flight.gd")
const WeeklyFlightDefScript := preload("res://scripts/flights/weekly_flight_def.gd")
const FlightListDebugScript := preload("res://scripts/ui/flight_list_debug.gd")
const DAY := 86400

var _failures := 0
var _due: Array = []


func _ready() -> void:
	print("TEST START | flight schedule")
	GameClock.set_paused(true)
	var start_time := GameClock.game_time
	var friday := start_time - start_time % DAY  # 1 January 2027

	# Weekly data
	var airline: Resource = AirlineCatalog.get_airline(&"brightwater")
	_expect("airline has weekly rotations", airline != null and airline.weekly_flights.size() == 6)
	_expect("times parse", WeeklyFlightDefScript.parse_time("07:15") == 435
		and WeeklyFlightDefScript.parse_time("00:00") == 0 and WeeklyFlightDefScript.parse_time("23:59") == 1439)
	_expect("bad times are refused", WeeklyFlightDefScript.parse_time("24:00") == -1
		and WeeklyFlightDefScript.parse_time("7.15") == -1 and WeeklyFlightDefScript.parse_time("") == -1)
	_expect("startup created today's flights", FlightSchedule.get_today_flights().size() > 0)

	# Friday: every rotation runs (211 on weekdays, 417 Fri to Sun).
	FlightSchedule.clear()
	var fri := FlightSchedule.create_day(friday)
	_expect("Friday creates 12 flights (6 arrivals, 6 departures)", fri.size() == 12 and _arrivals(fri) == 6)
	var a101 := _find(fri, "BQ 101")
	var d102 := _find(fri, "BQ 102")
	_expect("BQ 101 arrives at 07:15", a101 != null and a101.is_arrival() and a101.scheduled_time == friday + 435 * 60)
	_expect("BQ 102 departs at 08:05", d102 != null and not d102.is_arrival() and d102.scheduled_time == friday + 485 * 60)
	_expect("arrival and departure are paired", a101 != null and a101.pair == d102 and d102.pair == a101)
	_expect("flights carry type and route", a101 != null and a101.aircraft_type == &"a320"
		and a101.route == "Port Ellery" and a101.airline_id == &"brightwater")
	_expect("new flights are scheduled", fri.all(func(f: FlightScript) -> bool:
		return f.status == FlightScript.Status.SCHEDULED))
	var d632 := _find(fri, "BQ 632")
	_expect("overnight BQ 632 departs 06:30 next day", d632 != null
		and d632.scheduled_time == friday + DAY + 390 * 60)
	_expect("Friday list holds 11 flights (BQ 632 is Saturday's)", FlightSchedule.get_flights_on_day(friday).size() == 11)
	_expect("flights are in time order", _sorted(FlightSchedule.get_all_flights()))
	_expect("a day is only created once", FlightSchedule.create_day(friday).is_empty())
	_expect("Saturday list includes BQ 632", _find(FlightSchedule.get_flights_on_day(friday + DAY), "BQ 632") != null)

	# Sunday: no BQ 211. Monday: BQ 211 but no BQ 417.
	var sun := FlightSchedule.create_day(friday + 2 * DAY)
	_expect("Sunday has no BQ 211, has BQ 417", sun.size() == 10 and _find(sun, "BQ 211") == null
		and _find(sun, "BQ 417") != null)
	var mon := FlightSchedule.create_day(friday + 3 * DAY)
	_expect("Monday has BQ 211, no BQ 417", mon.size() == 10 and _find(mon, "BQ 211") != null
		and _find(mon, "BQ 417") == null)

	# Rotations already past are skipped when the game starts mid-day.
	FlightSchedule.clear()
	var late := FlightSchedule.create_day(friday, friday + 12 * 3600)
	_expect("starting at 12:00 skips earlier arrivals", late.size() == 8 and _find(late, "BQ 101") == null)

	# Flights come due on the clock.
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	FlightSchedule.flight_due.connect(func(f: FlightScript) -> void: _due.append(f))
	GameClock.game_time = friday + 7 * 3600 + 14 * 60
	_run_minutes(2)
	_expect("BQ 101 comes due at 07:15", _due.size() == 1 and _due[0].flight_number == "BQ 101")
	_due.clear()
	GameClock.game_time = friday + 8 * 3600
	_run_minutes(6)
	_expect("BQ 102 comes due at 08:05", _due.size() == 1 and _due[0].flight_number == "BQ 102")

	# Midnight creates the day after tomorrow's flights ahead of time.
	GameClock.game_time = friday + DAY - 60
	_run_minutes(2)
	# Sunday's 10 flights, less BQ 632, which leaves on Monday.
	_expect("midnight creates the next day", FlightSchedule.get_flights_on_day(friday + 2 * DAY).size() == 9)
	_expect("the overnight departure stays after midnight", _find(FlightSchedule.get_all_flights(), "BQ 632") != null)

	# Back to the start, with the normal startup schedule.
	GameClock.game_time = start_time
	FlightSchedule.clear()
	FlightSchedule.create_day(friday, start_time)
	FlightSchedule.create_day(friday + DAY)

	# Debug list
	var list := FlightListDebugScript.new()
	list.position = Vector2(16, 16)
	add_child(list)
	var text: String = list.build_text()
	_expect("debug list shows today's flights", text.contains("BQ 101") and text.contains("ARR")
		and text.contains("DEP") and text.contains("Port Ellery"))
	_expect("debug list leaves out tomorrow's departures", not text.contains("BQ 632"))
	var key := InputEventAction.new()
	key.action = FlightListDebugScript.ACTION_TOGGLE
	key.pressed = true
	list._unhandled_input(key)
	_expect("F5 shows the debug list", list.visible)
	print(text)
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open with the list on screen. Close the window when done.


func _run_minutes(minutes: int) -> void:
	for i in floori(minutes * 60 / GameClock.TICK_GAME_SECONDS):
		GameClock._run_tick()


func _find(flights: Array, number: String) -> FlightScript:
	for f: FlightScript in flights:
		if f.flight_number == number:
			return f
	return null


func _arrivals(flights: Array) -> int:
	return flights.filter(func(f: FlightScript) -> bool: return f.is_arrival()).size()


func _sorted(flights: Array) -> bool:
	for i in range(1, flights.size()):
		if flights[i].scheduled_time < flights[i - 1].scheduled_time:
			return false
	return true


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

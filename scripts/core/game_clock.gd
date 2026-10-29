extends Node
@warning_ignore_start("integer_division")  # whole-number time maths is intended here
## GameClock (autoload).
##
## Keeps the in-game date and time and drives the simulation.
## The simulation advances in fixed steps of in-game time (TICK_GAME_SECONDS),
## independent of the frame rate, so results don't depend on how fast the PC is.
## Game speed changes how many ticks run per real second, never the size of a tick.
##
## Other systems should do their simulation work in response to the `ticked`
## signal, and use minute_passed / hour_passed / day_passed for less frequent work.

## Emitted once per simulation tick. game_seconds is the in-game time the tick covers.
signal ticked(game_seconds: float)
## Emitted each time the in-game clock crosses into a new minute.
signal minute_passed(minute_of_day: int)
## Emitted each time the in-game clock crosses into a new hour (0 to 23).
signal hour_passed(hour: int)
## Emitted each time the in-game clock crosses midnight into a new day.
signal day_passed(datetime: Dictionary)

## In-game seconds covered by one simulation tick.
const TICK_GAME_SECONDS := 5.0
## Real seconds an in-game day lasts at 1x speed (GDD: about 20 real minutes).
const REAL_SECONDS_PER_GAME_DAY_AT_1X := 1200.0
## Ratio of in-game time to real time at 1x (86400 / 1200 = 72).
const GAME_SECONDS_PER_REAL_SECOND := 86400.0 / REAL_SECONDS_PER_GAME_DAY_AT_1X
## Safety limit so a long frame stall can't freeze the game catching up.
const MAX_TICKS_PER_FRAME := 200

const START_DATETIME := {"year": 2027, "month": 1, "day": 1, "hour": 6, "minute": 0, "second": 0}
const WEEKDAY_NAMES := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July",
	"August", "September", "October", "November", "December"]

## Speed multiplier (1 = normal). Speed controls come in checklist step 4.
var speed := 1.0
var paused := false

## Current in-game time as seconds since the Unix epoch (whole tick steps only).
var game_time := 0
## Number of simulation ticks run since the game started.
var tick_count := 0
## Ticks run during the last real second (useful to check the tick rate).
var ticks_last_second := 0

var _accumulator := 0.0
var _ticks_this_second := 0
var _second_timer := 0.0


func _ready() -> void:
	# Keep running even if the scene tree is paused, so menus can pause other things.
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_time = Time.get_unix_time_from_datetime_dict(START_DATETIME)


func _process(delta: float) -> void:
	_second_timer += delta
	if _second_timer >= 1.0:
		ticks_last_second = _ticks_this_second
		_ticks_this_second = 0
		_second_timer -= 1.0

	if paused or speed <= 0.0:
		return

	_accumulator += delta * GAME_SECONDS_PER_REAL_SECOND * speed
	var ticks_run := 0
	while _accumulator >= TICK_GAME_SECONDS and ticks_run < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_GAME_SECONDS
		_run_tick()
		ticks_run += 1
	if ticks_run >= MAX_TICKS_PER_FRAME:
		_accumulator = 0.0  # drop the backlog instead of spiralling


func _run_tick() -> void:
	var previous := game_time
	game_time += int(TICK_GAME_SECONDS)
	tick_count += 1
	_ticks_this_second += 1
	ticked.emit(TICK_GAME_SECONDS)
	_emit_boundaries(previous, game_time)


func _emit_boundaries(from_time: int, to_time: int) -> void:
	# Emit one signal for every minute, hour and day boundary crossed in this tick.
	var first_minute := from_time / 60 + 1
	var last_minute := to_time / 60
	for minute_index in range(first_minute, last_minute + 1):
		var t := minute_index * 60
		var minute_of_day := (t % 86400) / 60
		minute_passed.emit(minute_of_day)
		if minute_of_day % 60 == 0:
			hour_passed.emit(minute_of_day / 60)
			if minute_of_day == 0:
				day_passed.emit(Time.get_datetime_dict_from_unix_time(t))


# --- Queries ----------------------------------------------------------------

## Current date and time as a dictionary (year, month, day, weekday, hour, minute, second).
func get_datetime() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(game_time)


## Minutes since midnight (0 to 1439).
func get_minute_of_day() -> int:
	return (game_time % 86400) / 60


## Whole days since the game started (day 1 is the first day).
func get_day_number() -> int:
	var start := Time.get_unix_time_from_datetime_dict(START_DATETIME)
	return (game_time - (start - start % 86400)) / 86400 + 1


## "06:05"
func get_time_string() -> String:
	var dt := get_datetime()
	return "%02d:%02d" % [dt.hour, dt.minute]


## "Friday 1 January 2027"
func get_date_string() -> String:
	var dt := get_datetime()
	return "%s %d %s %d" % [WEEKDAY_NAMES[dt.weekday], dt.day, MONTH_NAMES[dt.month - 1], dt.year]

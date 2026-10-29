class_name WeeklyFlightDef
extends Resource
## One weekly rotation in an airline's schedule (checklist step 22): an
## aircraft arrives as one flight number and leaves as another. Stored inside
## the airline's .tres file (AirlineDef.weekly_flights).

## Arriving flight number, without the airline code (101 -> "BQ 101").
@export var arrival_number := 101
## Departing flight number.
@export var departure_number := 102
## Aircraft type ID (AircraftTypeDef.id).
@export var aircraft_type: StringName = &"a320"
## Arrival time on the day, "HH:MM".
@export var arrival_time := "08:00"
## Departure time, "HH:MM". Earlier than or equal to the arrival time means
## the next day (the aircraft stays overnight).
@export var departure_time := "09:00"
## Days of the week it arrives on: 0 = Sunday ... 6 = Saturday. Empty = every day.
@export var days: Array[int] = []
## Where the arriving flight comes from.
@export var origin := ""
## Where the departing flight goes.
@export var destination := ""


## True if the rotation arrives on this weekday (0 = Sunday).
func operates_on(weekday: int) -> bool:
	return days.is_empty() or days.has(weekday)


## Arrival time in minutes after midnight, or -1 if it isn't valid "HH:MM".
func get_arrival_minute() -> int:
	return parse_time(arrival_time)


## Departure time in minutes after midnight, or -1 if it isn't valid "HH:MM".
func get_departure_minute() -> int:
	return parse_time(departure_time)


## True if the aircraft leaves the day after it arrives.
func departs_next_day() -> bool:
	return get_departure_minute() <= get_arrival_minute()


## Minutes on the ground between arrival and departure.
func get_ground_minutes() -> int:
	var minutes := get_departure_minute() - get_arrival_minute()
	return minutes + 1440 if minutes <= 0 else minutes


## "07:15" -> 435. -1 if the text isn't a valid time.
static func parse_time(text: String) -> int:
	var parts := text.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var h := parts[0].to_int()
	var m := parts[1].to_int()
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m

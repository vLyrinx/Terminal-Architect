class_name Flight
extends RefCounted
## One flight on one day (checklist step 22), created by FlightSchedule from
## an airline's weekly rotations. Arrivals and departures of the same aircraft
## are linked through `pair`. Later systems (stand allocation, landing,
## turnaround, passengers) read and update it.

enum Direction { ARRIVAL, DEPARTURE }
enum Status { SCHEDULED, APPROACHING, LANDED, TAXIING, ON_STAND, BOARDING, DEPARTED, CANCELLED }

const STATUS_NAMES := ["Scheduled", "Approaching", "Landed", "Taxiing", "On stand", "Boarding", "Departed", "Cancelled"]

## Unique for this game session.
var id := 0
var airline_id: StringName
## "BQ 101"
var flight_number := ""
var direction := Direction.ARRIVAL
var aircraft_type: StringName
## Scheduled time, in game seconds since the Unix epoch (like GameClock.game_time).
var scheduled_time := 0
## Where an arrival comes from, or where a departure goes.
var route := ""
var status := Status.SCHEDULED
## The other half of the rotation (arrival <-> departure).
var pair: Flight
## Set by stand allocation (step 23). -1 = none yet.
var stand_id := -1


func is_arrival() -> bool:
	return direction == Direction.ARRIVAL


## "07:15"
func get_time_string() -> String:
	var dt := Time.get_datetime_dict_from_unix_time(scheduled_time)
	return "%02d:%02d" % [dt.hour, dt.minute]


func get_status_name() -> String:
	return STATUS_NAMES[status]


func _to_string() -> String:
	return "%s %s %s %s %s (%s)" % [get_time_string(), flight_number, "ARR" if is_arrival() else "DEP",
		aircraft_type, route, get_status_name()]

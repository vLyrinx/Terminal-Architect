class_name Passenger
extends RefCounted
## One departing passenger (checklist step 29), created by PassengerSpawner
## for a departure flight. Tied to the flight both ways (passenger.flight and
## flight.passengers), so later steps (check-in, security, gate, boarding)
## can route them and know when they need to be where.

enum State { EXPECTED, ARRIVING, AT_ENTRANCE }

const STATE_NAMES := ["Expected", "Arriving", "At entrance"]

## Unique for this game session.
var id := 0
var flight: Flight
## When they reach the terminal entrance, in game seconds (like GameClock.game_time).
var arrival_time := 0
var state := State.EXPECTED
## Id in PassengerCrowd while they are visible, else -1.
var crowd_id := -1
## The entrance they use (index into PassengerSpawner's entrance list).
var entrance := -1
## Game time they stepped inside the entrance, or -1.
var entered_time := -1

## Walking path (world points) and the index of the next point.
var path := PackedVector3Array()
var path_next := 0
var target := Vector3.ZERO


func get_state_name() -> String:
	return STATE_NAMES[state]


func _to_string() -> String:
	var dt := Time.get_datetime_dict_from_unix_time(arrival_time)
	return "Passenger %d (%s, arrives %02d:%02d, %s)" % [id, flight.flight_number if flight else "-", dt.hour,
		dt.minute, get_state_name()]

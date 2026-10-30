class_name Passenger
extends RefCounted
## One departing passenger (checklist step 29), created by PassengerSpawner
## for a departure flight. Tied to the flight both ways (passenger.flight and
## flight.passengers), so later steps (check-in, security, gate, boarding)
## can route them and know when they need to be where.

enum State { EXPECTED, ARRIVING, AT_ENTRANCE, WAITING_CHECKIN, TO_CHECKIN, QUEUING_CHECKIN, CHECKING_IN, CHECKED_IN,
	TO_SECURITY, QUEUING_SECURITY, SCREENING, AIRSIDE, TO_GATE, AT_GATE, BOARDING, TO_AIRCRAFT,
	BOARDED }

const STATE_NAMES := ["Expected", "Arriving", "At entrance", "Waiting for a check-in desk", "Going to check-in",
	"Queuing for check-in", "Checking in", "Checked in", "Going to security", "Queuing for security",
	"Going through security", "Airside", "Going to the gate", "Waiting at the gate", "Boarding", "Walking to the aircraft",
	"On board"]

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
## Where they may walk (TerminalPaths.Access).
var access := 0
## Check-in desk (placed object id) they queue at or checked in at, or 0 (step 30).
var desk_id := 0
## Game time they finished checking in, or -1.
var checked_in_time := -1
## Security scanner (placed object id) they queue at or went through, or 0 (step 31).
var scanner_id := 0
## Game time they came out of security into airside, or -1.
var cleared_time := -1
## Gate desk (placed object id) of their flight, or 0 (step 32).
var gate_id := 0
## The seat they sit on or are heading for (GateSeat), or null; seated once they sit down.
var seat: RefCounted
var seated := false
## Game time they were called to board, and boarded, or -1.
var called_time := -1
var boarded_time := -1

## Walking path (world points), the index of the next point, and where it ends.
var path := PackedVector3Array()
var path_next := 0
var target := Vector3.ZERO
var is_walking := false
## True for short straight moves (stepping up in a queue) that skip pathfinding.
var walk_direct := false
## Called with this passenger when the current walk ends.
var on_arrive := Callable()


func get_state_name() -> String:
	return STATE_NAMES[state]


func _to_string() -> String:
	var dt := Time.get_datetime_dict_from_unix_time(arrival_time)
	return "Passenger %d (%s, arrives %02d:%02d, %s)" % [id, flight.flight_number if flight else "-", dt.hour,
		dt.minute, get_state_name()]

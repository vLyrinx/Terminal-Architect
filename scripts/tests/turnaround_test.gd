extends "res://scripts/tests/taxiing_test.gd"
## Test for the timed turnaround and pushback (checklist step 26).
## Run this scene on its own (F6). It builds the same airport as the taxiing
## test (a 2,400 m runway, two ramps, a taxiway and two medium stands) and
## flies Friday's BQ 101 / BQ 102 rotation twice through AirTraffic:
## - late: BQ 102 is moved to 15 minutes after BQ 101 arrives, shorter than
##   the A320's 40 minute turnaround, so it must wait for the turnaround;
## - on time: BQ 102 is moved to 90 minutes after, so it waits for its time.
## Each time it checks the aircraft stays parked until then, is pushed back
## (status Pushback, reversing, with a tug at the nose gear), stops while the
## tug comes off, frees the stand, then taxis on and takes off. Prints PASS or
## FAIL for each check, then keeps flying the day's schedule so turnarounds
## and pushbacks can be watched (right drag rotates, wheel zooms, WASD pans;
## 1/2/3 speed).


func _ready() -> void:
	print("TEST START | turnaround and pushback")
	GameClock.set_paused(true)
	Money.reset(10000000)
	_build_world()
	_traffic.stand_allocator = _allocator
	for s in ["turnaround_started", "pushback_started", "pushback_finished"]:
		_traffic.connect(s, func(f: FlightScript, _a: Node3D) -> void: _log.append("%s %s" % [s, f.flight_number]))
	await get_tree().process_frame

	_check_rotation_with(15, "late")
	_check_rotation_with(90, "on time")

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	_start_demo()


## Flies BQ 101 / BQ 102 with BQ 102 moved to ground_minutes after BQ 101's arrival.
func _check_rotation_with(ground_minutes: int, label: String) -> void:
	_log.clear()
	var friday := GameClock.game_time - GameClock.game_time % DAY
	FlightSchedule.clear()
	FlightSchedule.create_day(friday)
	GameClock.game_time = friday + 6 * 3600
	var arrival := _find("BQ 101")
	var departure := arrival.pair
	departure.scheduled_time = arrival.scheduled_time + ground_minutes * 60
	_allocator.allocate(arrival)
	var stand: RefCounted = _stands.get_stand(arrival.stand_id)
	var stand_id := arrival.stand_id
	var stop := Vector3(stand.stop.x, 0.0, stand.stop.z)
	var minutes: int = AircraftCatalog.get_type(arrival.aircraft_type).turnaround_minutes
	var turnaround := minutes * 60
	print("INFO | %s: BQ 101 %s, BQ 102 moved to %s, stand %d" % [label, arrival.get_time_string(),
		departure.get_time_string(), stand_id])

	var on_stand_at := -1
	var ready_at := -1
	var moved_while_parked := false
	var pushback_at := -1
	var reversing_ok := true
	var tug_ok := true
	var pushed := 0.0
	var tug_off_at := -1
	var still_while_unhooking := true
	var unhook_start := -1
	var unhook_pos := Vector3.ZERO
	var freed_ok := false
	var tug_gone := false
	var lift_off_at := -1
	var parked_pos := Vector3.ZERO
	var nose_on_bar := INF
	var nose_inside := false
	var end := friday + 11 * 3600
	while GameClock.game_time < end and lift_off_at < 0:
		GameClock.game_time += TICK
		if GameClock.game_time % 60 == 0:
			_traffic.update()
		_traffic.advance(TICK)
		var aircraft: Node3D = _traffic.get_aircraft_for(departure)
		if aircraft == null:
			aircraft = _traffic.get_aircraft_for(arrival)
		if aircraft == null or not is_instance_valid(aircraft):
			continue
		var p := Vector3(aircraft.position.x, 0.0, aircraft.position.z)
		if on_stand_at < 0 and arrival.status == FlightScript.Status.ON_STAND:
			on_stand_at = GameClock.game_time
			ready_at = aircraft.ready_at
			parked_pos = p
			var gear: Vector3 = aircraft.to_global(Vector3(0.0, 0.0, aircraft.model.nose_gear_z))
			nose_on_bar = Vector3(gear.x, 0.0, gear.z).distance_to(stop)
			var rect: Rect2i = StandsScript.footprint(StandCatalog.get_def(stand.def_id), stand.anchor, stand.facing)
			nose_inside = rect.has_point(BuildGrid.world_to_tile(aircraft.to_global(Vector3(0.0, 0.0, aircraft.model.nose_z))))
		if on_stand_at > 0 and pushback_at < 0 and departure.status == FlightScript.Status.SCHEDULED:
			if p.distance_to(parked_pos) > 0.01:
				moved_while_parked = true
		if pushback_at < 0 and departure.status == FlightScript.Status.PUSHBACK:
			pushback_at = GameClock.game_time
		if departure.status == FlightScript.Status.PUSHBACK:
			var facing := -aircraft.global_transform.basis.z
			facing = Vector3(facing.x, 0.0, facing.z).normalized()
			if aircraft.taxi_distance < aircraft.pushback_end - 1.0 and aircraft.taxi_distance > 1.0 \
					and facing.dot(aircraft.get_motion()) > -0.5:
				reversing_ok = false
			if aircraft.tug == null or aircraft.tug.get_parent() != aircraft:
				tug_ok = false
			pushed = maxf(pushed, p.distance_to(stop))
			if aircraft.taxi_distance >= aircraft.pushback_end - 0.01:
				if unhook_start < 0:
					unhook_start = GameClock.game_time
					unhook_pos = p
				elif p.distance_to(unhook_pos) > 0.01:
					still_while_unhooking = false
		if tug_off_at < 0 and _log.has("pushback_finished BQ 102"):
			tug_off_at = GameClock.game_time
			freed_ok = _allocator.get_reservations(stand_id).is_empty() and departure.stand_id == stand_id
			tug_gone = aircraft.tug == null and departure.status == FlightScript.Status.TAXIING
		if departure.status == FlightScript.Status.DEPARTED:
			lift_off_at = GameClock.game_time

	var leave_at := maxi(departure.scheduled_time, ready_at)
	_expect("%s: BQ 101 parks on stand %d at %s and its turnaround starts (ready %s, %d min)" % [label, stand_id,
		_clock(on_stand_at), _clock(ready_at), minutes],
		on_stand_at > 0 and ready_at == on_stand_at + turnaround and _log.has("turnaround_started BQ 101"))
	_expect("%s: its nose wheel is on the stop bar (%.2f m off) and its nose inside the stand" % [label, nose_on_bar],
		nose_on_bar < 0.5 and nose_inside)
	_expect("%s: it stays parked until %s (%s)" % [label, _clock(leave_at),
		"turnaround done" if ready_at > departure.scheduled_time else "BQ 102's time"],
		not moved_while_parked and pushback_at >= leave_at and pushback_at < leave_at + 120)
	_expect("%s: BQ 102 is pushed back at %s, status Pushback" % [label, _clock(pushback_at)],
		_log.has("pushback_started BQ 102"))
	_expect("%s: it reverses off the stand, nose first towards the stand" % label, reversing_ok)
	_expect("%s: with a tug at its nose gear" % label, tug_ok)
	_expect("%s: it is pushed clear of the stand (%.0f m back)" % [label, pushed], pushed > 40.0)
	_expect("%s: it stops while the tug comes off (%d s)" % [label, tug_off_at - unhook_start],
		unhook_start > 0 and still_while_unhooking and tug_off_at - unhook_start >= 110)
	_expect("%s: the tug is gone and the stand reservation is freed at %s" % [label, _clock(tug_off_at)],
		tug_gone and freed_ok)
	_expect("%s: then it taxis to the runway and takes off at %s" % [label, _clock(lift_off_at)],
		lift_off_at > tug_off_at and _log.has("took_off BQ 102"))
	FlightSchedule.clear()
	for a: Node3D in _traffic.get_aircraft():
		_traffic._remove(a)
	_allocator.release(arrival)

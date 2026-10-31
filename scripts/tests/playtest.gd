extends Node3D
## Prototype playtest (checklist step 40).
## Run this scene on its own (F6). It loads the full main scene and builds a
## small airport from scratch with the game's own build commands (so every
## piece is paid for), then runs Brightwater's schedule for three in-game days:
##   airside   2,400 m runway 09/27, two straight ramps, a taxiway with a taxi
##             line, three medium stands north of the terminal
##   terminal  140 x 40 m: airside along the north wall (three gate desks with
##             seats and a door out to each stand), security (two scanners in
##             a wall with doors), landside in the south (eight check-in desks,
##             three entrances, two toilet blocks)
## While it runs it logs every landing, take-off, boarding, missed passenger,
## alert and refused build command, prints a status line every 3 game hours
## and a report at the end of each day, and checks at the end that every
## departure due went out, nothing is stuck and no passenger is lost.
## Prints PASS or FAIL for each check, then keeps running so you can watch:
##   F      fast-forward (FAST_SPEED) / back to 4x
##   Space, 1, 2, 3   pause and game speed as in the game
##   Camera as in the game

const MainScene := preload("res://scenes/main.tscn")
const FlightScript := preload("res://scripts/flights/flight.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const TerminalZonesScript := preload("res://scripts/building/terminal_zones.gd")
const CheckInScript := preload("res://scripts/passengers/check_in.gd")
const SecurityScript := preload("res://scripts/passengers/security.gd")
const GatesScript := preload("res://scripts/passengers/gates.gd")
const PlaceRunwayCmd := preload("res://scripts/core/commands/place_runway_command.gd")
const PlaceRampCmd := preload("res://scripts/core/commands/place_ramp_command.gd")
const SetPavingCmd := preload("res://scripts/core/commands/set_paving_command.gd")
const PlaceTaxiLineCmd := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const PlaceStandCmd := preload("res://scripts/core/commands/place_stand_command.gd")
const SetFloorCmd := preload("res://scripts/core/commands/set_floor_command.gd")
const SetWallsCmd := preload("res://scripts/core/commands/set_walls_command.gd")
const SetDoorCmd := preload("res://scripts/core/commands/set_door_command.gd")
const PlaceObjectCmd := preload("res://scripts/core/commands/place_object_command.gd")
const Zone := TerminalZonesScript.Zone
const State := PassengerScript.State
const Status := FlightScript.Status
const DAY := 86400
const DAYS := 3
const FAST_SPEED := 40.0

## Terminal corner tile and size. Rows from the north wall: airside 0-20,
## security 20-28 (wall at 22, scanners 22-26), landside 28-40.
const B := Vector2i(1830, 1190)
const SIZE := Vector2i(140, 40)
const SECURITY_Y := 20
const SECURITY_WALL_Y := 22
const LANDSIDE_Y := 28
## Stand centres along x (tiles), and the gate desk for each, by x offset from B.
const STAND_XS: Array[int] = [1840, 1900, 1960]
const GATE_XS: Array[int] = [10, 70, 130]
const SCANNER_XS: Array[int] = [56, 62, 78, 84]
const DESK_XS: Array[int] = [40, 44, 48, 52, 88, 92, 96, 100]
const ENTRANCE_XS: Array[int] = [30, 70, 110]
## Door in the security wall with no scanner in it, the way out for arriving
## and missed passengers. Built after the start, to check the alert for it.
const WAY_OUT_X := 70

var _failures := 0
var _main: Node3D
var _commands: Node
var _zones: Node3D
var _objects: Node3D
var _floor: Node3D
var _stands: Node3D
var _ramps: Node3D
var _runways: Node3D
var _traffic: Node3D
var _spawner: Node
var _gates: Node
var _arrivals: Node
var _missed: Node
var _alerts: Node
var _label: Label
var _refused: Array[String] = []
var _start_time := 0
var _end_time := 0
var _done := false

# Counts per day (index 0 = first day) and in total.
var _days: Array[Dictionary] = []
var _alert_log: Array[String] = []
var _boarded_by_flight := {}
## Flight id -> game time it pushed back.
var _off_block := {}
## Departures whose time came during the run (FlightSchedule drops old flights, so they are kept here).
var _due_departures: Array[FlightScript] = []


func _ready() -> void:
	print("TEST START | prototype playtest")
	_main = MainScene.instantiate()
	_main.get_node("Camera3D").start_distance = 260.0
	_main.get_node("Camera3D").start_pitch_deg = 45.0
	add_child(_main)
	_main.get_node("Camera3D").focus_on(BuildGrid.tile_corner_to_world(B + Vector2i(SIZE.x >> 1, -30)))
	_commands = _main.get_node("Commands")
	_zones = _main.get_node("TerminalZones")
	_objects = _main.get_node("PlacedObjects")
	_floor = _main.get_node("TerminalFloor")
	_stands = _main.get_node("Stands")
	_ramps = _main.get_node("Ramps")
	_runways = _main.get_node("Runways")
	_traffic = _main.get_node("AirTraffic")
	_spawner = _main.get_node("PassengerSpawner")
	_gates = _main.get_node("Gates")
	_arrivals = _main.get_node("Arrivals")
	_missed = _main.get_node("MissedFlights")
	_alerts = _main.get_node("UI/Root/Alerts")
	_add_label()
	_commands.command_failed.connect(func(c: RefCounted) -> void:
		_refused.append("%s: %s" % [c.describe(), c.error])
		print("REFUSED | %s: %s" % [c.describe(), c.error]))
	_connect_logs()

	GameClock.set_paused(true)
	var money_before: int = Money.balance
	_build_airside()
	_build_terminal()
	print("BUILT | %d refused commands, spent %s, balance %s" % [_refused.size(),
		Money.format(money_before - Money.balance), Money.format(Money.balance)])
	_check_build()
	await get_tree().process_frame
	await get_tree().process_frame

	_start_time = GameClock.game_time
	_end_time = _start_time - _start_time % DAY + DAYS * DAY
	_new_day()
	GameClock.set_speed(FAST_SPEED)
	GameClock.set_paused(false)
	# The only doors through the security wall are behind scanners: no way out yet.
	while GameClock.game_time < _start_time + 15 * 60:
		await get_tree().process_frame
	_expect("alert: no way out from the apron doors", _alerts.is_raised("way_out"))
	_commands.submit(SetDoorCmd.new(B + Vector2i(WAY_OUT_X, SECURITY_WALL_Y), true, true))
	while GameClock.game_time < _start_time + 30 * 60:
		await get_tree().process_frame
	_expect("the alert clears once there is a door through the security wall", not _alerts.is_raised("way_out"))
	while GameClock.game_time < _end_time:
		await get_tree().process_frame
	GameClock.set_speed(4.0)
	_check_end()
	_done = true
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))


# --- Building ---------------------------------------------------------------------

func _build_airside() -> void:
	# Runway 09/27 along y = 1000, 2,400 m from x = 1000.
	_commands.submit(PlaceRunwayCmd.new(&"medium", Vector2i(1000, 1000), Vector2i(3400, 1000)))
	var runway_id: int = _runways.get_ids()[0] if _runways.get_count() > 0 else 0
	# Taxiway along y = 1100 with a ramp at each end of it.
	var ramp_def := RampCatalog.get_def(&"medium_straight")
	_commands.submit(SetPavingCmd.new(Rect2i(1188, 1088, 1524, 24), true))
	_commands.submit(PlaceTaxiLineCmd.new(Vector2i(1200, 1100), Vector2i(2700, 1100)))
	for x in [1200, 2700]:
		var anchor: Vector2i = _ramps.snap(ramp_def, Vector2(x, 1040)).anchor
		_commands.submit(PlaceRampCmd.new(&"medium_straight", runway_id, anchor, 1))
		_commands.submit(SetPavingCmd.new(Rect2i(x - 12, anchor.y, 24, 1088 - anchor.y), true))
		_commands.submit(PlaceTaxiLineCmd.new(anchor, Vector2i(x, 1100)))
	# Three stands south of the taxiway, entries facing north, backs towards the terminal.
	var stand_def := StandCatalog.get_def(&"medium")
	for x in STAND_XS:
		var anchor: Vector2i = _stands.snap_anchor(stand_def, BuildGrid.tile_corner_to_world(Vector2i(x, 1145)), 2)
		_commands.submit(PlaceStandCmd.new(&"medium", anchor, 2))


func _build_terminal() -> void:
	_commands.submit(SetFloorCmd.new(Rect2i(B, SIZE), true))
	_zones.paint_rect(Rect2i(B, Vector2i(SIZE.x, SECURITY_Y)), Zone.AIRSIDE)
	_zones.paint_rect(Rect2i(B + Vector2i(0, SECURITY_Y), Vector2i(SIZE.x, LANDSIDE_Y - SECURITY_Y)), Zone.SECURITY)
	_zones.paint_rect(Rect2i(B + Vector2i(0, LANDSIDE_Y), Vector2i(SIZE.x, SIZE.y - LANDSIDE_Y)), Zone.LANDSIDE)
	var c0 := B
	var c1 := B + SIZE
	_commands.submit(SetWallsCmd.new([
		[c0, Vector2i(c1.x, c0.y)], [Vector2i(c0.x, c1.y), c1], [c0, Vector2i(c0.x, c1.y)], [Vector2i(c1.x, c0.y), c1],
		[B + Vector2i(0, SECURITY_WALL_Y), B + Vector2i(SIZE.x, SECURITY_WALL_Y)]], true))
	for x in ENTRANCE_XS:
		_commands.submit(SetDoorCmd.new(B + Vector2i(x, SIZE.y), true, true))
	for x in GATE_XS:
		_commands.submit(SetDoorCmd.new(B + Vector2i(x, 0), true, true))
	# Scanners face south (where passengers come from) with the door behind them.
	for x in SCANNER_XS:
		_place(SecurityScript.SCANNER_ID, Vector2(x, SECURITY_WALL_Y + 2), 0.0)
		_commands.submit(SetDoorCmd.new(B + Vector2i(x, SECURITY_WALL_Y), true, true))
	# Check-in desks face south, towards the entrances.
	for x in DESK_XS:
		_place(CheckInScript.DESK_ID, Vector2(x, 33), 0.0)
	# Gate desks face south with their door behind them; seat rows face the desk.
	for x in GATE_XS:
		_place(GatesScript.GATE_ID, Vector2(x, 3.5), 0.0)
		for dx in [-5, 5]:
			for y in [9.5, 11.5, 13.5]:
				_place(GatesScript.SEAT_ROW_ID, Vector2(x + dx, y), PI)
	_place(&"toilet_block", Vector2(40, 16), PI)
	_place(&"toilet_block", Vector2(100, 16), PI)
	_place(&"toilet_block", Vector2(50, 37), 0.0)


## Places an object centred at a tile offset from B, snapped like the object tool.
func _place(def_id: StringName, at: Vector2, yaw: float) -> void:
	var def := ObjectCatalog.get_def(def_id)
	var world := BuildGrid.tile_corner_to_world(B) + Vector3(at.x, 0.0, at.y)
	var pos: Vector3 = _objects.snap_position(def, world, yaw)
	pos.y = _floor.get_surface_height(BuildGrid.world_to_tile(pos))
	_commands.submit(PlaceObjectCmd.new(def_id, pos, yaw))


# --- Logging ----------------------------------------------------------------------

func _connect_logs() -> void:
	_traffic.touched_down.connect(func(_f: FlightScript, _a: Node3D) -> void: _count("landed"))
	_traffic.arrived_on_stand.connect(func(_f: FlightScript, _a: Node3D) -> void: _count("on_stand"))
	# Delays are counted at pushback (off-block), as airlines do.
	_traffic.pushback_started.connect(func(f: FlightScript, _a: Node3D) -> void:
		_off_block[f.id] = GameClock.game_time
		if GameClock.game_time - f.scheduled_time > 15 * 60:
			_count("departed_late"))
	_traffic.took_off.connect(func(f: FlightScript, _a: Node3D) -> void:
		_count("departed")
		var late: int = _off_block.get(f.id, GameClock.game_time) - f.scheduled_time
		var passengers: int = _boarded_by_flight.get(f.id, 0) + _missed.get_missed_for(f)
		_count("seats_booked", passengers)
		print("PLAYTEST | %s %s off block %+d min, took off %s, %d of %d on board, %d missed" % [_day_name(),
			f.flight_number, roundi(late / 60.0), GameClock.get_time_string(), _boarded_by_flight.get(f.id, 0),
			passengers, _missed.get_missed_for(f)]))
	_traffic.runway_missing.connect(func(f: FlightScript) -> void: _count("runway_missing"); print("PLAYTEST | no runway for %s" % f.flight_number))
	_traffic.taxi_route_missing.connect(func(f: FlightScript) -> void: _count("taxi_missing"); print("PLAYTEST | no taxi route for %s" % f.flight_number))
	_gates.passenger_boarded.connect(func(p: PassengerScript) -> void:
		_count("boarded")
		if p.flight:
			_boarded_by_flight[p.flight.id] = _boarded_by_flight.get(p.flight.id, 0) + 1)
	_arrivals.passenger_exited.connect(func(_p: PassengerScript) -> void: _count("arrivals_out"))
	_missed.passenger_missed.connect(func(_p: PassengerScript) -> void: _count("missed"))
	_spawner.passenger_arrived.connect(func(_p: PassengerScript) -> void: _count("came_in"))
	_alerts.alert_raised.connect(func(_key: String, text: String, _level: int) -> void:
		_count("alerts")
		var line := "%s %s %s" % [_day_name(), GameClock.get_time_string(), text]
		_alert_log.append(line)
		print("ALERT RAISED | " + line))
	GameClock.day_passed.connect(func(_d: Dictionary) -> void:
		if _start_time > 0 and not _done:
			_report_day()
			if GameClock.game_time < _end_time:
				_new_day())
	FlightSchedule.flight_due.connect(func(f: FlightScript) -> void:
		if not f.is_arrival() and _start_time > 0 and not _done:
			_due_departures.append(f))
	GameClock.hour_passed.connect(func(hour: int) -> void:
		if _start_time > 0 and not _done and hour % 3 == 0:
			_status_line())


func _new_day() -> void:
	_days.append({"money_start": Money.balance})


func _count(key: String, amount := 1) -> void:
	if _days.is_empty():
		return
	_days[-1][key] = _days[-1].get(key, 0) + amount


func _status_line() -> void:
	var counts: Dictionary = _spawner.get_state_counts()
	var busy := []
	for s: int in counts:
		if counts[s] > 0 and s != State.EXPECTED:
			busy.append("%s %d" % [PassengerScript.STATE_NAMES[s], counts[s]])
	var aircraft := []
	for a: Node3D in _traffic.get_aircraft():
		aircraft.append("%s %s" % [a.flight.flight_number, a.flight.get_status_name()])
	print("STATUS | %s %s | %s %s | passengers: %s | aircraft: %s" % [_day_name(), GameClock.get_time_string(),
		Money.format(Money.balance), "%d fps" % Engine.get_frames_per_second(), ", ".join(busy) if busy else "none",
		", ".join(aircraft) if aircraft else "none"])


func _report_day() -> void:
	var d: Dictionary = _days[-1]
	print("DAY REPORT | day %d: %d landed, %d on stand, %d departed (%d pushed back over 15 min late), %d came in, %d boarded, %d missed, %d arrivals out, %d alerts, money %s -> %s (%s)" % [
		_days.size(), d.get("landed", 0), d.get("on_stand", 0), d.get("departed", 0), d.get("departed_late", 0),
		d.get("came_in", 0), d.get("boarded", 0), d.get("missed", 0), d.get("arrivals_out", 0), d.get("alerts", 0),
		Money.format(d.money_start), Money.format(Money.balance), Money.format(Money.balance - d.money_start)])


func _day_name() -> String:
	return GameClock.get_date_string().get_slice(" ", 0)


# --- Checks -----------------------------------------------------------------------

func _check_build() -> void:
	_expect("every build command was accepted (%d refused)" % _refused.size(), _refused.is_empty())
	_expect("1 runway, 2 ramps, 3 stands", _runways.get_count() == 1 and _ramps.get_ids().size() == 2
		and _stands.get_ids().size() == 3)
	var gates: Array = _gates.get_gates()
	_expect("3 gates", gates.size() == 3)
	var stands_used := {}
	for f: FlightScript in FlightSchedule.get_today_flights():
		if f.stand_id >= 0:
			stands_used[f.stand_id] = true
	print("INFO | %d flights today, %d stands allocated" % [FlightSchedule.get_today_flights().size(), stands_used.size()])


func _check_end() -> void:
	# Departures due in the last 3 hours may still be on their way out.
	var due := 0
	var out := 0
	var stuck: Array[String] = []
	for f in _due_departures:
		if f.scheduled_time > _end_time - 3 * 3600:
			continue
		due += 1
		if f.status == Status.DEPARTED:
			out += 1
		elif f.pair == null or f.pair.scheduled_time >= _start_time:
			stuck.append("%s %s" % [f.flight_number, f])
		else:
			due -= 1  # its aircraft was due in before the game started, so it never came
	_expect("%d of %d departures due over the three days took off" % [out, due], due > 0 and out == due)
	for s in stuck:
		print("INFO | not departed: %s" % s)
	var total := {}
	for d in _days:
		for k: String in d:
			total[k] = total.get(k, 0) + d[k]
	_expect("passengers boarded (%d) and arrivals walked out (%d)" % [total.get("boarded", 0), total.get("arrivals_out", 0)],
		total.get("boarded", 0) > 0 and total.get("arrivals_out", 0) > 0)
	var lost := 0
	for p: PassengerScript in _spawner.get_all_passengers():
		if p.flight and p.flight.status == Status.DEPARTED and not p.flight.is_arrival() and p.state != State.BOARDED \
				and p.state != State.MISSED:
			lost += 1
	_expect("no passenger left behind by a departed flight without being counted missed (%d)" % lost, lost == 0)
	_expect("no flight lacked a runway or taxi route", total.get("runway_missing", 0) == 0 and total.get("taxi_missing", 0) == 0)
	var totals: Dictionary = Money.get_totals()
	print("INFO | money totals by category: %s" % totals)
	print("INFO | %d alerts raised over the three days" % _alert_log.size())


# --- UI -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _label == null:
		return
	var d: Dictionary = _days[-1] if not _days.is_empty() else {}
	_label.text = "Playtest   day %d of %d   %s %s   %s\nlanded %d   departed %d   boarded %d   missed %d   alerts %d\nF: fast-forward" % [
		_days.size(), DAYS, GameClock.get_date_string(), GameClock.get_time_string(),
		"paused" if GameClock.paused else "%dx" % GameClock.speed, d.get("landed", 0), d.get("departed", 0),
		d.get("boarded", 0), d.get("missed", 0), d.get("alerts", 0)]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F:
		GameClock.set_speed(4.0 if GameClock.speed >= FAST_SPEED else FAST_SPEED)


func _add_label() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(16, 60)
	_label.add_theme_font_size_override(&"font_size", 16)
	_label.add_theme_color_override(&"font_color", Color(0.1, 0.12, 0.15))
	ui.add_child(_label)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

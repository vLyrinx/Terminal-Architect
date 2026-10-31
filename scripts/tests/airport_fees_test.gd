extends Node
## Test for basic income and costs (checklist step 35).
## Run this scene on its own (F6). It uses stand-ins for AirTraffic and
## Arrivals and sends their signals for BQ 101 (arrival) and BQ 102
## (departure) by hand, then fast-forwards the clock past midnight.
## It checks that the airline pays one landing fee per arrival, a passenger
## fee for every passenger who got off the arrival and every passenger on
## board the departure (not those who missed it), that the airport pays the
## daily running cost at midnight, and that each payment is in the Money log
## with its own category and the log still adds up to the balance.
## Prints PASS or FAIL for each check.

const AirportFeesScript := preload("res://scripts/economy/airport_fees.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")
const FlightScript := preload("res://scripts/flights/flight.gd")
const START := 1000000
const DEPLANED := 150
const BOARDED := 120
const MISSED := 7


## Stand-in for AirTraffic: just its signals.
class FakeAirTraffic:
	extends Node
	signal touched_down(flight: FlightScript, aircraft: Node3D)
	signal took_off(flight: FlightScript, aircraft: Node3D)


## Stand-in for Arrivals: its signal and the passenger count of each deplaning.
class FakeArrivals:
	extends Node
	signal deplaning_finished(flight: FlightScript)

	class Deplaning:
		extends RefCounted
		var total := 0

	var totals := {}

	func get_deplaning(flight: FlightScript) -> Deplaning:
		var d := Deplaning.new()
		d.total = totals.get(flight.id, 0)
		return d


var _failures := 0


func _ready() -> void:
	print("TEST START | basic income and costs")
	var settings := Money.settings
	Money.reset(START)
	var air := FakeAirTraffic.new()
	add_child(air)
	var arrivals := FakeArrivals.new()
	add_child(arrivals)
	var fees := AirportFeesScript.new()
	fees.air_traffic = air
	fees.arrivals = arrivals
	add_child(fees)

	var departure := _first_departure()
	var arrival := departure.pair
	var airline: String = AirlineCatalog.get_airline(arrival.airline_id).display_name

	# Landing fee.
	var balance := Money.balance
	air.touched_down.emit(arrival, null)
	var t: Dictionary = Money.transactions[-1]
	_expect("%s landing: +%s landing fee" % [arrival.flight_number, Money.format(settings.landing_fee)],
		Money.balance == balance + settings.landing_fee and t.category == &"landing_fees")
	_expect("logged as \"%s\"" % t.description, arrival.flight_number in t.description and airline in t.description)
	balance = Money.balance
	air.touched_down.emit(arrival, null)
	_expect("only charged once per flight", Money.balance == balance)

	# Passenger fee for the arrival.
	arrivals.totals[arrival.id] = DEPLANED
	arrivals.deplaning_finished.emit(arrival)
	t = Money.transactions[-1]
	_expect("%d passengers off %s: +%s passenger fees" % [DEPLANED, arrival.flight_number,
		Money.format(DEPLANED * settings.passenger_fee)], Money.balance == balance + DEPLANED * settings.passenger_fee
		and t.category == &"passenger_fees")
	_expect("logged as \"%s\"" % t.description, arrival.flight_number in t.description and str(DEPLANED) in t.description)

	# Passenger fee for the departure: only those on board.
	departure.passengers.clear()
	for i in BOARDED + MISSED:
		var p := PassengerScript.new()
		p.flight = departure
		p.state = PassengerScript.State.BOARDED if i < BOARDED else PassengerScript.State.MISSED
		departure.passengers.append(p)
	balance = Money.balance
	air.took_off.emit(departure, null)
	t = Money.transactions[-1]
	_expect("%s took off with %d on board (%d missed): +%s passenger fees" % [departure.flight_number, BOARDED, MISSED,
		Money.format(BOARDED * settings.passenger_fee)], Money.balance == balance + BOARDED * settings.passenger_fee
		and t.category == &"passenger_fees")
	_expect("no landing fee for a departure", t.category != &"landing_fees"
		and Money.transactions.filter(func(x: Dictionary) -> bool: return x.category == &"landing_fees").size() == 1)

	# Daily running cost at midnight.
	balance = Money.balance
	var day := GameClock.get_day_number()
	var count := Money.transactions.size()
	GameClock.set_speed(800.0)
	while GameClock.get_day_number() == day:
		await get_tree().process_frame
	GameClock.set_paused(true)
	var running := Money.transactions.slice(count).filter(func(x: Dictionary) -> bool:
		return x.category == &"running_costs")
	_expect("at midnight (%s) the airport paid %s running cost" % [GameClock.get_date_string(),
		Money.format(settings.daily_running_cost)], running.size() == 1
		and running[0].amount == -settings.daily_running_cost)
	_expect("logged as \"%s\"" % (running[0].description if not running.is_empty() else ""), not running.is_empty()
		and str(day) in running[0].description)

	var total := 0
	for x in Money.transactions:
		total += x.amount
	_expect("the log adds up to the balance (%s)" % Money.format(Money.balance), total == Money.balance)
	var totals := Money.get_totals()
	print("TOTALS | landing %s, passengers %s, running %s" % [Money.format(totals.get(&"landing_fees", 0)),
		Money.format(totals.get(&"passenger_fees", 0)), Money.format(totals.get(&"running_costs", 0))])
	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	departure.passengers.clear()
	Money.reset(Money.settings.starting_money)


func _first_departure() -> FlightScript:
	for f: FlightScript in FlightSchedule.get_all_flights():
		if not f.is_arrival() and f.pair != null:
			return f
	return null


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

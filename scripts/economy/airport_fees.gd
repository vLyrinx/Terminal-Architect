extends Node
## Basic income and costs (checklist step 35).
##
## Airlines pay the airport for each flight, recorded in the Money log:
##   landing fee    - when an arrival touches down (AirTraffic.touched_down)
##   passenger fees - per passenger, once an arrival's passengers are all off
##                    (Arrivals.deplaning_finished) and once a departure
##                    takes off with its passengers on board (AirTraffic.took_off)
## The airport pays its daily running cost at the end of every game day.
##
## The amounts are in data/economy.tres (landing_fee, passenger_fee,
## daily_running_cost).

const FlightScript := preload("res://scripts/flights/flight.gd")
const PassengerScript := preload("res://scripts/passengers/passenger.gd")

## A flight's fees were paid: kind is &"landing" or &"passengers".
signal fee_paid(flight: FlightScript, kind: StringName, amount: int)
signal running_cost_paid(amount: int)

## Nodes with the touched_down / took_off and deplaning_finished signals (both optional).
@export var air_traffic: Node
@export var arrivals: Node

## Flight ids whose landing fee and passenger fees have been paid.
var _landed := {}
var _passengers_paid := {}


func _ready() -> void:
	if air_traffic != null:
		air_traffic.touched_down.connect(func(f: FlightScript, _aircraft: Node3D) -> void: pay_landing(f))
		air_traffic.took_off.connect(func(f: FlightScript, _aircraft: Node3D) -> void:
			pay_passengers(f, _count_boarded(f)))
	if arrivals != null:
		arrivals.deplaning_finished.connect(func(f: FlightScript) -> void:
			pay_passengers(f, arrivals.get_deplaning(f).total))
	GameClock.day_passed.connect(_on_day_passed)


## The airline pays the landing fee for an arrival (once per flight).
func pay_landing(flight: FlightScript) -> void:
	if _landed.has(flight.id):
		return
	_landed[flight.id] = true
	var amount: int = Money.settings.landing_fee
	Money.add(amount, &"landing_fees", "Landing fee: %s (%s)" % [flight.flight_number, _airline_name(flight)])
	fee_paid.emit(flight, &"landing", amount)


## The airline pays the passenger fee for count passengers of a flight (once per flight).
func pay_passengers(flight: FlightScript, count: int) -> void:
	if _passengers_paid.has(flight.id):
		return
	_passengers_paid[flight.id] = true
	var amount: int = count * Money.settings.passenger_fee
	Money.add(amount, &"passenger_fees", "Passenger fees: %s, %d %s x %s (%s)" % [flight.flight_number, count,
		"arriving" if flight.is_arrival() else "departing", Money.format(Money.settings.passenger_fee),
		_airline_name(flight)])
	fee_paid.emit(flight, &"passengers", amount)


func _count_boarded(flight: FlightScript) -> int:
	var n := 0
	for p: PassengerScript in flight.passengers:
		if p.state == PassengerScript.State.BOARDED:
			n += 1
	return n


func _airline_name(flight: FlightScript) -> String:
	var airline = AirlineCatalog.get_airline(flight.airline_id)
	return airline.display_name if airline != null else String(flight.airline_id)


func _on_day_passed(_datetime: Dictionary) -> void:
	var amount: int = Money.settings.daily_running_cost
	# Always charged, even into debt.
	Money.add(-amount, &"running_costs", "Daily running cost (day %d)" % (GameClock.get_day_number() - 1))
	running_cost_paid.emit(amount)
	for id: int in _landed.keys():
		if FlightSchedule.get_flight(id) == null:
			_landed.erase(id)
	for id: int in _passengers_paid.keys():
		if FlightSchedule.get_flight(id) == null:
			_passengers_paid.erase(id)

class_name AirlineDef
extends Resource
## Definition of a fictional airline (checklist step 21), stored as a .tres
## file in data/airlines/ and loaded by the AirlineCatalog autoload.

const AircraftLiveryScript := preload("res://scripts/aircraft/aircraft_livery.gd")

## Unique ID used in saves, contracts and schedules. Never change it once saves exist.
@export var id: StringName
@export var display_name := ""
## Two-character code used in flight numbers, for example "BQ" in "BQ 214".
@export var short_code := ""
## Radio callsign, for example "BRIGHTWATER".
@export var callsign := ""
@export_enum("flag", "low_cost", "regional", "long_haul") var airline_type := "flag"
## Colours painted on every aircraft in the fleet.
@export var livery: AircraftLiveryScript
## Aircraft type ID (AircraftTypeDef.id) -> number of aircraft of that type.
@export var fleet: Dictionary[StringName, int] = {}


## Total number of aircraft in the fleet.
func get_fleet_size() -> int:
	var total := 0
	for count: int in fleet.values():
		total += count
	return total


## Every aircraft in the fleet as {type_id, registration}, in a fixed order
## so registrations stay the same between runs.
func get_fleet_aircraft() -> Array[Dictionary]:
	var aircraft: Array[Dictionary] = []
	var type_ids := fleet.keys()
	type_ids.sort()
	for type_id: StringName in type_ids:
		for i in fleet[type_id]:
			aircraft.append({"type_id": type_id, "registration": _registration(aircraft.size())})
	return aircraft


## Registration for the nth aircraft: the short code, then three letters
## counting up from AAA (BQ-AAA, BQ-AAB, ...).
func _registration(n: int) -> String:
	var letters := ""
	for i in 3:
		letters = char(65 + n % 26) + letters
		n /= 26
	return "%s-%s" % [short_code, letters]

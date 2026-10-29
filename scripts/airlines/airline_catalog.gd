extends Node
## AirlineCatalog (autoload, checklist step 21). Loads every airline
## (AirlineDef) from data/airlines/ at startup, checks its fleet against the
## aircraft types, and builds liveried aircraft models for it.

const AirlineDefScript := preload("res://scripts/airlines/airline_def.gd")
const AircraftModelScript := preload("res://scripts/aircraft/aircraft_model.gd")
const AIRLINES_DIR := "res://data/airlines/"

## StringName ID -> AirlineDef
var _airlines := {}
## Airlines ordered by name.
var _ordered: Array = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_airlines.clear()
	_ordered.clear()
	# list_directory also works in exported builds, where files are remapped.
	for file in ResourceLoader.list_directory(AIRLINES_DIR):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var def := load(AIRLINES_DIR + file) as AirlineDefScript
		if def == null:
			push_warning("AirlineCatalog: %s is not an AirlineDef" % file)
			continue
		if def.id == &"":
			def.id = StringName(file.get_basename())
		if def.short_code.length() != 2:
			push_warning("AirlineCatalog: %s short code '%s' should be 2 characters" % [file, def.short_code])
		if def.livery == null:
			push_warning("AirlineCatalog: %s has no livery" % file)
		for type_id: StringName in def.fleet:
			if AircraftCatalog.get_type(type_id) == null:
				push_warning("AirlineCatalog: %s fleet has unknown aircraft type '%s'" % [file, type_id])
		_check_weekly_flights(file, def)
		_airlines[def.id] = def
		_ordered.append(def)
	_ordered.sort_custom(func(a: AirlineDefScript, b: AirlineDefScript) -> bool:
		return a.display_name < b.display_name)
	print("AIRLINES | %d loaded: %s" % [_ordered.size(),
		", ".join(_ordered.map(func(a: AirlineDefScript) -> String:
			var fleet_text := ", ".join(a.fleet.keys().map(func(t: StringName) -> String:
				return "%d x %s" % [a.fleet[t], t]))
			return "%s (%s, %s, fleet %s, %d weekly rotations)" % [a.display_name, a.short_code, a.airline_type, fleet_text, a.weekly_flights.size()]))])


## Warns about weekly rotations with bad times, types outside the fleet or a
## ground time shorter than the type's turnaround.
func _check_weekly_flights(file: String, def: AirlineDefScript) -> void:
	for rotation in def.weekly_flights:
		var label := "%s %d/%d" % [def.short_code, rotation.arrival_number, rotation.departure_number]
		if rotation.get_arrival_minute() < 0 or rotation.get_departure_minute() < 0:
			push_warning("AirlineCatalog: %s %s has a bad time ('%s', '%s')"
				% [file, label, rotation.arrival_time, rotation.departure_time])
			continue
		if not def.fleet.has(rotation.aircraft_type):
			push_warning("AirlineCatalog: %s %s uses %s, which isn't in the fleet" % [file, label, rotation.aircraft_type])
		var type_def: Resource = AircraftCatalog.get_type(rotation.aircraft_type)
		if type_def != null and rotation.get_ground_minutes() < type_def.turnaround_minutes:
			push_warning("AirlineCatalog: %s %s has %d min on the ground, less than the %d min turnaround"
				% [file, label, rotation.get_ground_minutes(), type_def.turnaround_minutes])
		for day in rotation.days:
			if day < 0 or day > 6:
				push_warning("AirlineCatalog: %s %s has day %d (use 0 = Sunday to 6 = Saturday)" % [file, label, day])


## The airline with this ID, or null.
func get_airline(id: StringName) -> AirlineDefScript:
	return _airlines.get(id)


## Every airline, by name.
func get_all_airlines() -> Array:
	return _ordered.duplicate()


## A new model of this aircraft type painted in the airline's livery, or null
## if the type has no model. The caller adds it to the scene.
func make_aircraft_model(airline_id: StringName, type_id: StringName) -> AircraftModelScript:
	var airline := get_airline(airline_id)
	var type_def: Resource = AircraftCatalog.get_type(type_id)
	if airline == null or type_def == null or type_def.model_scene == null:
		return null
	var model := type_def.model_scene.instantiate() as AircraftModelScript
	if model != null:
		model.apply_livery(airline.livery)
	return model

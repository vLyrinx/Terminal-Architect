class_name AircraftTypeDef
extends Resource
## Definition of an aircraft type (checklist step 20), stored as a .tres file
## in data/aircraft/ and loaded by the AircraftCatalog autoload. Dimensions are
## real-world metres (1 tile = 1 m).

## Unique ID used in saves, schedules and fleets. Never change it once saves exist.
@export var id: StringName
## Full name, for example "A320-200".
@export var display_name := ""
@export var manufacturer := ""
## ICAO type designator, for example "A320" or "B738".
@export var icao_code := ""
## Size class ID from data/size_classes/ (SizeClassDef.IDS).
@export_enum("regional_turboprop", "regional_jet", "narrow_body", "wide_body", "very_large") var size_class := "narrow_body"
## Seats in a typical single-class layout.
@export var seats := 180
@export var wingspan := 35.8
@export var length := 37.6
@export var height := 11.8
@export var engine_count := 2
@export_enum("jet", "turboprop") var engine_type := "jet"
## Take-off field length at maximum weight, in metres.
@export var runway_length_needed := 2100
## Time on stand between arrival and pushback, in in-game minutes.
@export var turnaround_minutes := 40
## Low-poly model (checklist step 19). Empty until the model exists.
@export var model_scene: PackedScene

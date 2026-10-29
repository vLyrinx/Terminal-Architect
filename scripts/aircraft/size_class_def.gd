class_name SizeClassDef
extends Resource
## Definition of an aircraft size class (checklist step 20), stored as a .tres
## file in data/size_classes/ and loaded by the AircraftCatalog autoload.
## Stands, runways and contracts read aircraft sizes from these files.
## Sizes are real-world metres (1 tile = 1 m).

## Every size class, smallest first. A stand or runway built for a class also
## takes every class before it in this list.
const IDS := ["regional_turboprop", "regional_jet", "narrow_body", "wide_body", "very_large"]
## Career unlock stages, earliest first (GDD aircraft table).
const UNLOCK_STAGES := ["start", "early", "mid", "late", "endgame"]

## Unique ID, one of IDS. Never change it once saves exist.
@export var id: StringName
@export var display_name := ""
## Stand size this class needs (GDD aircraft table).
@export_enum("small", "medium", "large", "large_extra") var stand_class := "small"
## Stand footprint in tiles: x across the wingspan, y along the fuselage.
## Multiples of 10 so stands line up with the 10 m airside grid.
@export var stand_size_tiles := Vector2i(40, 50)
## Largest wingspan in this class, in metres. A stand for this class is built
## to clear it.
@export var max_wingspan := 30.0
## Shortest runway, in metres, that every type in this class can use.
@export var runway_length_needed := 1200
## Runway size class (RunwayDef.SIZE_CLASSES) that can handle this class.
@export_enum("small", "medium", "large") var runway_class := "small"
## Taxiway size class (TaxiwayDef.SIZE_CLASSES) a stand for this class needs
## in front of it (checklist step 18).
@export_enum("small", "medium", "large") var taxiway_class := "small"
## When the class unlocks in career mode, one of UNLOCK_STAGES.
@export_enum("start", "early", "mid", "late", "endgame") var unlock_stage := "start"
## Example types, shown in tooltips.
@export var example_types := ""


## Position in IDS: 0 for the smallest class.
func get_rank() -> int:
	return IDS.find(String(id))


## True if something built for this class also takes aircraft of other_id.
func takes(other_id: StringName) -> bool:
	var other := IDS.find(String(other_id))
	return other != -1 and other <= get_rank()

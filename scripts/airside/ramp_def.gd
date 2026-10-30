class_name RampDef
extends Resource
## Definition of a runway ramp, stored as a .tres file in data/ramps/ and
## loaded by the RampCatalog autoload. A ramp is a premade piece of taxiway
## that attaches to the side of a runway and carries its own taxi line from
## the runway centreline out to its outer end, where the player's taxiways and
## taxi lines join it. Straight ramps leave the runway at 90 degrees; angled
## ramps (rapid exits) leave at 45 degrees and turn to run straight out at the
## end. Sizes match taxiway sizes. Lengths are real-world metres (1 tile = 1 m).

const SHAPES := ["straight", "angled"]

## Unique ID used in saves and commands. Never change it once ramps exist.
@export var id: StringName
@export var display_name := ""
@export_enum("straight", "angled") var shape := "straight"
## Largest aircraft size class the ramp handles (the same classes as taxiways).
@export_enum("small", "medium", "large") var size_class := "medium"
## Paved width in metres, the same as the matching taxiway size.
@export var width := 24
## How far, at least, the ramp reaches out from the runway's edge, in metres.
## The outer end is rounded out to the 10 m airside grid.
@export var depth := 40
## Construction price.
@export var cost := 6000
## What it is for, shown in the build menu tooltip.
@export_multiline var description := ""
## Build menu category (checklist step 15): an ID from build_categories.gd.
@export var menu_category := "airside"
## Icon shown on the ramp's build menu button.
@export var icon: Texture2D

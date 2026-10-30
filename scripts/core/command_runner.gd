class_name CommandRunner
extends Node
## Runs player action commands (checklist step 11). See game_command.gd.
##
## Tools never change the airport directly: they make a command and call
## submit(). The runner executes it and keeps a history, which undo, saving and
## co-op will build on later. Commands reach the systems they change through
## the exported references here.

## Emitted after a command runs successfully.
signal command_executed(command: RefCounted)
## Emitted when a command is refused; command.error says why.
signal command_failed(command: RefCounted)

const PlaceObjectCommandScript := preload("res://scripts/core/commands/place_object_command.gd")
const RotateObjectCommandScript := preload("res://scripts/core/commands/rotate_object_command.gd")
const DeleteObjectCommandScript := preload("res://scripts/core/commands/delete_object_command.gd")
const SetFloorCommandScript := preload("res://scripts/core/commands/set_floor_command.gd")
const SetWallsCommandScript := preload("res://scripts/core/commands/set_walls_command.gd")
const SetDoorCommandScript := preload("res://scripts/core/commands/set_door_command.gd")
const PlaceRunwayCommandScript := preload("res://scripts/core/commands/place_runway_command.gd")
const DeleteRunwayCommandScript := preload("res://scripts/core/commands/delete_runway_command.gd")
const PlaceTaxiwayCommandScript := preload("res://scripts/core/commands/place_taxiway_command.gd")
const DeleteTaxiwayCommandScript := preload("res://scripts/core/commands/delete_taxiway_command.gd")
const PlaceStandCommandScript := preload("res://scripts/core/commands/place_stand_command.gd")
const DeleteStandCommandScript := preload("res://scripts/core/commands/delete_stand_command.gd")
const PlaceRampCommandScript := preload("res://scripts/core/commands/place_ramp_command.gd")
const DeleteRampCommandScript := preload("res://scripts/core/commands/delete_ramp_command.gd")
const PlaceTaxiLineCommandScript := preload("res://scripts/core/commands/place_taxi_line_command.gd")
const DeleteTaxiLinesCommandScript := preload("res://scripts/core/commands/delete_taxi_lines_command.gd")
## Oldest commands are dropped from the history beyond this.
const MAX_HISTORY := 500

## The PlacedObjects node (placed_objects.gd).
@export var placed_objects: Node3D
## The TerminalFloor node (terminal_floor.gd).
@export var terminal_floor: Node3D
## The TerminalWalls node (terminal_walls.gd).
@export var terminal_walls: Node3D
## The TerminalZones node (terminal_zones.gd), so undoing a floor removal can
## put its zones back. Optional.
@export var terminal_zones: Node3D
## The Runways node (runways.gd).
@export var runways: Node3D
## The Taxiways node (taxiways.gd).
@export var taxiways: Node3D
## The Stands node (stands.gd).
@export var stands: Node3D
## The Ramps node (ramps.gd).
@export var ramps: Node3D
## The TaxiLines node (taxi_lines.gd).
@export var taxi_lines: Node3D

## Commands that ran, oldest first.
var history: Array = []


## Runs a command. Returns false (and changes nothing) if it was refused.
func submit(command: RefCounted) -> bool:
	if not command.execute(self):
		print("CMD | refused %s: %s" % [command.describe(), command.error])
		command_failed.emit(command)
		return false
	history.append(command)
	if history.size() > MAX_HISTORY:
		history.pop_front()
	print("CMD | %s" % command.describe())
	command_executed.emit(command)
	return true


## Undoes the most recent command. Not bound to a key yet.
func undo_last() -> bool:
	if history.is_empty():
		return false
	var command: RefCounted = history.pop_back()
	command.undo(self)
	print("CMD | undo %s" % command.describe())
	return true


## Rebuilds a command from to_dict() data (for saves and co-op). Null if unknown.
static func command_from_dict(data: Dictionary) -> RefCounted:
	var command: RefCounted
	match data.get("type", ""):
		"place_object":
			command = PlaceObjectCommandScript.new()
		"rotate_object":
			command = RotateObjectCommandScript.new()
		"delete_object":
			command = DeleteObjectCommandScript.new()
		"set_floor":
			command = SetFloorCommandScript.new()
		"set_walls":
			command = SetWallsCommandScript.new()
		"set_door":
			command = SetDoorCommandScript.new()
		"place_runway":
			command = PlaceRunwayCommandScript.new()
		"delete_runway":
			command = DeleteRunwayCommandScript.new()
		"place_taxiway":
			command = PlaceTaxiwayCommandScript.new()
		"delete_taxiway":
			command = DeleteTaxiwayCommandScript.new()
		"place_stand":
			command = PlaceStandCommandScript.new()
		"delete_stand":
			command = DeleteStandCommandScript.new()
		"place_ramp":
			command = PlaceRampCommandScript.new()
		"delete_ramp":
			command = DeleteRampCommandScript.new()
		"place_taxi_line":
			command = PlaceTaxiLineCommandScript.new()
		"delete_taxi_lines":
			command = DeleteTaxiLinesCommandScript.new()
		_:
			return null
	command.load_dict(data)
	return command

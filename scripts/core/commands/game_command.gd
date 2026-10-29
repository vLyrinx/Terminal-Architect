extends RefCounted
## Base class for player actions (checklist step 11).
##
## Every change the player makes to the airport is one command object, run by
## the CommandRunner. Because actions are data, they can later be undone,
## saved and replayed, or sent to other players in co-op.
##
## Rules for commands:
##   - execute() checks the action is allowed first and changes nothing if not
##     (it returns false and explains why in `error`).
##   - The same command on the same world state must give the same result.
##     IDs it creates are stored on the command, so replaying or redoing it
##     gives the same IDs.
##   - undo() exactly reverses a successful execute().
##   - to_dict() / load_dict() turn it into plain data and back
##     (CommandRunner.command_from_dict() picks the right command type).

## Why the last execute() failed ("" if it worked).
var error := ""


## Type name used in to_dict() and by CommandRunner.command_from_dict().
func get_type() -> String:
	return "command"


## Applies the command to the world (the CommandRunner, which holds the
## systems commands act on). Returns false if it could not be done.
func execute(_world: Node) -> bool:
	return false


## Reverses a successful execute().
func undo(_world: Node) -> void:
	pass


## Short text for logs, such as "place test_bench #3".
func describe() -> String:
	return get_type()


func to_dict() -> Dictionary:
	return {"type": get_type()}


func load_dict(_data: Dictionary) -> void:
	pass


static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

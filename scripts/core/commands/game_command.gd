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
##   - Money (checklist step 14): execute() calls can_pay() before changing
##     anything, then pay() once the change is made; undo() calls unpay().
##     A command makes at most one transaction.

## Why the last execute() failed ("" if it worked).
var error := ""
## Player who did this action, recorded on its transaction (1 until co-op).
var player_id := 1

# The payment made by the last execute(), for unpay().
var _paid := 0
var _paid_category := &""


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


## True if the player can pay cost; otherwise sets error and returns false.
func can_pay(cost: int) -> bool:
	if Money.can_afford(cost):
		return true
	error = Money.shortfall_message(cost)
	return false


## Records this command's transaction: amount is negative for spending and
## positive for refunds. Call after the change is made.
func pay(amount: int, category: StringName) -> void:
	_paid = amount
	_paid_category = category
	Money.add(amount, category, describe(), player_id)


## Reverses the transaction pay() made (for undo()).
func unpay() -> void:
	if _paid != 0:
		Money.add(-_paid, _paid_category, "Undo " + describe(), player_id)
	_paid = 0


static func vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func array_to_vec3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

extends Node
## Money (autoload, checklist step 14): the airport's balance and a log of every
## transaction, for the finance screen later.
##
## Spending happens inside commands (game_command.gd), never straight from the
## tools: a command checks the player can pay before it changes anything, makes
## the change, then records the payment. Undo records the opposite amount, so
## the log always adds up to the balance. Each transaction keeps the player who
## caused it (always player 1 until co-op).
##
## The starting money and build prices are in data/economy.tres.

## Emitted after the balance changes. change is negative for spending.
signal balance_changed(balance: int, change: int)
## Emitted for each new transaction (see add()).
signal transaction_recorded(transaction: Dictionary)

const EconomySettingsScript := preload("res://scripts/economy/economy_settings.gd")
const SETTINGS_PATH := "res://data/economy.tres"
## Transaction categories, in finance screen order.
const CATEGORIES: Array[StringName] = [&"starting_money", &"construction", &"sale"]
## The player on this computer. Co-op will give other players other numbers.
const LOCAL_PLAYER := 1

var settings: EconomySettingsScript
## Current balance in whole dollars. Change it only through add() or spend().
var balance := 0
## Every transaction, oldest first. Each is a dictionary:
##   id (int), time (GameClock.game_time), day (game day number),
##   amount (int, negative = spent), category (StringName),
##   description (String), player (int)
var transactions: Array[Dictionary] = []

var _next_id := 1


func _ready() -> void:
	settings = load(SETTINGS_PATH) as EconomySettingsScript
	if settings == null:
		push_warning("Money: %s is missing, using default prices" % SETTINGS_PATH)
		settings = EconomySettingsScript.new()
	reset(settings.starting_money)


## Clears the log and starts again with this balance (new game, tests).
func reset(starting_money: int) -> void:
	balance = 0
	transactions.clear()
	_next_id = 1
	add(starting_money, &"starting_money", "Starting money", LOCAL_PLAYER)


func can_afford(amount: int) -> bool:
	return amount <= balance


## Message for a purchase the player can't pay for.
func shortfall_message(amount: int) -> String:
	return "Not enough money: needs %s, you have %s" % [format(amount), format(balance)]


## Pays amount (a positive number) if the balance allows it. Returns false and
## changes nothing if it doesn't.
func spend(amount: int, category: StringName, description: String, player := LOCAL_PLAYER) -> bool:
	if not can_afford(amount):
		return false
	add(-amount, category, description, player)
	return true


## Records a transaction: positive amounts add money, negative ones take it
## away, always (no balance check: use spend() for purchases). Returns the
## transaction, or an empty dictionary for an amount of 0.
func add(amount: int, category: StringName, description: String, player := LOCAL_PLAYER) -> Dictionary:
	if amount == 0:
		return {}
	if not category in CATEGORIES:
		push_warning("Money: unknown category %s" % category)
	var transaction := {
		"id": _next_id,
		"time": GameClock.game_time,
		"day": GameClock.get_day_number(),
		"amount": amount,
		"category": category,
		"description": description,
		"player": player,
	}
	_next_id += 1
	transactions.append(transaction)
	balance += amount
	print("MONEY | %s%s: %s (player %d) | balance %s" % [
		"+" if amount > 0 else "", format(amount), description, player, format(balance)])
	transaction_recorded.emit(transaction)
	balance_changed.emit(balance, amount)
	return transaction


## Total amount per category over the whole log: {category: int}.
func get_totals() -> Dictionary:
	var totals := {}
	for transaction in transactions:
		totals[transaction.category] = totals.get(transaction.category, 0) + transaction.amount
	return totals


## The refund for removing something that cost this much to build.
func refund_for(build_cost: int) -> int:
	return roundi(build_cost * settings.sale_refund)


## "$15,000" or "-$2,500"
func format(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-$" if amount < 0 else "$") + grouped

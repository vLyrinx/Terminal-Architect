extends Label
## Temporary on-screen readout for the game clock (checklist step 3).
## Will be replaced by the top bar in step 15.


func _ready() -> void:
	GameClock.hour_passed.connect(_on_hour_passed)
	GameClock.day_passed.connect(_on_day_passed)
	print("CLOCK START | %s %s" % [GameClock.get_date_string(), GameClock.get_time_string()])


func _process(_delta: float) -> void:
	text = "%s\n%s\nDay %d   Speed %sx\nTicks: %d (%d per second)" % [
		GameClock.get_date_string(),
		GameClock.get_time_string(),
		GameClock.get_day_number(),
		str(GameClock.speed),
		GameClock.tick_count,
		GameClock.ticks_last_second,
	]


func _on_hour_passed(hour: int) -> void:
	print("CLOCK HOUR | %02d:00 | ticks=%d | real_time=%.1fs" % [
		hour, GameClock.tick_count, Time.get_ticks_msec() / 1000.0])


func _on_day_passed(_datetime: Dictionary) -> void:
	print("CLOCK DAY | %s" % GameClock.get_date_string())

extends Node
## Automatic test for the game clock speed controls (checklist step 4).
## Run this scene on its own (F6). It presses the real keys through Godot's
## input system, measures the tick rate at each speed, prints PASS or FAIL
## for each check, then waits for you to close the window.

const MEASURE_SECONDS := 2.0
const TOLERANCE := 0.1  # 10%

var _failures := 0


func _ready() -> void:
	print("TEST START | clock speed controls")
	await get_tree().process_frame

	_press(KEY_1)
	await _check_rate("key 1 sets 1x", 1.0)
	_press(KEY_2)
	await _check_rate("key 2 sets 2x", 2.0)
	_press(KEY_3)
	await _check_rate("key 3 sets 4x", 4.0)

	_press(KEY_SPACE)
	_expect("space pauses", GameClock.paused)
	await _check_rate("no ticks while paused", 0.0)
	_press(KEY_SPACE)
	_expect("space resumes", not GameClock.paused)
	_expect("resume keeps 4x", is_equal_approx(GameClock.speed, 4.0))

	_press(KEY_SPACE)
	_press(KEY_2)
	_expect("speed key while paused unpauses", not GameClock.paused and is_equal_approx(GameClock.speed, 2.0))

	_press(KEY_1)
	var day_seconds := 86400.0 / (GameClock.GAME_SECONDS_PER_REAL_SECOND * GameClock.speed)
	_expect("one day at 1x is about 20 real minutes (%.0f s)" % day_seconds, is_equal_approx(day_seconds, 1200.0))

	print("TEST DONE | %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	# Stays open so the results can be read in the Output panel. Close the window when done.


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = keycode
		e.keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _check_rate(label: String, expected_speed: float) -> void:
	await get_tree().process_frame
	var start_ticks := GameClock.tick_count
	var start_time := GameClock.game_time
	var start_ms := Time.get_ticks_msec()
	await get_tree().create_timer(MEASURE_SECONDS).timeout
	var real := (Time.get_ticks_msec() - start_ms) / 1000.0
	var ticks_per_s := (GameClock.tick_count - start_ticks) / real
	var game_per_real := (GameClock.game_time - start_time) / real
	var expected_ticks := GameClock.GAME_SECONDS_PER_REAL_SECOND * expected_speed / GameClock.TICK_GAME_SECONDS
	var ok: bool
	if expected_speed == 0.0:
		ok = ticks_per_s == 0.0
	else:
		ok = absf(ticks_per_s - expected_ticks) <= expected_ticks * TOLERANCE
	_expect("%s | %.1f ticks/s (expected %.1f), %.0f game s per real s" % [
		label, ticks_per_s, expected_ticks, game_per_real], ok)


func _expect(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s | %s" % ["PASS" if ok else "FAIL", label])

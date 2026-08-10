extends SceneTree
## Headless UI smoke test: instantiate every scene and let one frame of _ready() run.
## godot --headless --script res://tests/ui_smoke_test.gd

var GameState

func _initialize() -> void:
	GameState = root.get_node("GameState")
	print("=== UI smoke test ===")

	GameState.new_game(10, "jaffa")
	_test_scene("res://scenes/MainMenu.tscn")
	await _test_game_overlays()

	GameState.new_game(1, "jaffa")
	GameState.current_day = 2 # force past game_length so EndGame reads a finished run
	_test_scene("res://scenes/EndGame.tscn")

	print("=== ALL UI SMOKE TESTS PASSED ===")
	quit()

func _test_game_overlays() -> void:
	var packed: PackedScene = load("res://scenes/Game.tscn")
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.call("_open_trade_panel")
	instance.call("_close_overlay")
	print("trade panel OK")

	instance.call("_open_bank_panel")
	instance.call("_close_overlay")
	print("bank panel OK")

	instance.call("_open_shipyard_panel")
	instance.call("_close_overlay")
	print("shipyard panel OK")

	instance.call("_open_travel_confirm", "venice")
	instance.call("_close_overlay")
	print("travel confirm panel OK")

	instance.call("_on_pirate_encounter_started", {"pirate_strength": 1.0})
	instance.call("_close_overlay")
	print("pirate encounter panel OK")

	instance.call("_on_menu_pressed")
	instance.call("_close_overlay")
	print("menu panel OK")

	instance.call("_show_message", "test message")
	instance.call("_close_overlay")
	print("message panel OK")

	instance.queue_free()
	print("instantiated OK: res://scenes/Game.tscn (overlays)")

func _test_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	assert(packed != null, "failed to load " + path)
	var instance := packed.instantiate()
	root.add_child(instance)
	print("instantiated OK: %s (children=%d)" % [path, instance.get_child_count()])
	instance.queue_free()

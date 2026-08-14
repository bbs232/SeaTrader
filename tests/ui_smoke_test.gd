extends SceneTree
## Headless UI smoke test: instantiate every scene and let one frame of _ready() run.
## godot --headless --script res://tests/ui_smoke_test.gd

var GameState
var SaveManager

func _initialize() -> void:
	GameState = root.get_node("GameState")
	SaveManager = root.get_node("SaveManager")
	print("=== UI smoke test ===")

	GameState.new_game(10, "jaffa")
	_test_scene("res://scenes/MainMenu.tscn")
	await _test_mainmenu_highscores()
	await _test_game_overlays()

	GameState.new_game(1, "jaffa")
	GameState.current_day = 2 # force past game_length so EndGame reads a finished run
	_test_scene("res://scenes/EndGame.tscn")

	print("=== ALL UI SMOKE TESTS PASSED ===")
	quit()

## Exercises the high-score table with both no entries (empty-state message)
## and at least one entry (the ranked grid, including the rank-1 gold-star
## badge path) so a format-string or column-count mistake in either branch
## would surface here instead of only in a manual playtest.
func _test_mainmenu_highscores() -> void:
	var packed: PackedScene = load("res://scenes/MainMenu.tscn")
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.call("_on_highscores_pressed") # empty-state branch
	instance._highscores_layer.queue_free()
	instance._highscores_layer = null

	SaveManager.add_highscore("UI smoke test", 12345)
	instance.call("_on_highscores_pressed") # ranked grid branch
	instance._highscores_layer.queue_free()

	instance.queue_free()
	print("highscores panel OK")

func _test_game_overlays() -> void:
	var packed: PackedScene = load("res://scenes/Game.tscn")
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame

	instance.call("_open_trade_panel")
	instance.call("_show_confirm", "test confirm", func(): pass)
	print("confirm dialog stacked OK")
	instance.call("_close_overlay")
	print("trade panel OK")

	# Regression test: resolving a pirate encounter can itself push a newer
	# overlay (arrival report / another encounter) before the pirate dialog
	# closes itself. Closing must target that specific dialog, not "whatever
	# is on top", or a nested popup gets destroyed/orphaned. See
	# _close_specific_overlay in Game.gd.
	var panel_a: PanelContainer = instance.call("_open_overlay")
	var panel_b: PanelContainer = instance.call("_open_overlay")
	assert(instance.overlay_stack.size() == 2)
	instance.call("_close_specific_overlay", panel_a)
	assert(instance.overlay_stack.size() == 1)
	assert(instance.overlay_stack[0] == panel_b.get_meta("overlay_layer"))
	instance.call("_close_overlay")
	assert(instance.overlay_stack.size() == 0)
	print("overlay stack targeted-close OK")

	instance.call("_open_bank_panel")
	instance.call("_close_overlay")
	print("bank panel OK")

	instance.call("_open_shipyard_panel")
	instance.call("_close_overlay")
	print("shipyard panel OK")

	instance.call("_open_market_panel")
	instance.call("_close_overlay")
	print("market panel OK")

	instance.call("_open_travel_confirm", "limassol")
	instance.call("_close_overlay")
	print("travel confirm panel OK")

	# Blocked route (jaffa -> venice needs a Limassol/Istanbul/Alexandria stopover):
	# pressing the marker should show an explanatory message instead of a travel confirm.
	assert(GameState.current_port_id == "jaffa")
	assert(instance.overlay_stack.size() == 0)
	instance.call("_on_port_marker_pressed", "venice")
	assert(instance.overlay_stack.size() == 1)
	instance.call("_close_overlay")
	print("blocked route message OK")

	instance.call("_open_rules_panel")
	instance.call("_close_overlay")
	print("rules panel OK")

	instance.call("_on_pirate_encounter_started", {"pirate_strength": 1.0})
	instance.call("_close_overlay")
	print("pirate encounter panel OK")

	# Both cost-path wordings (gold vs. goods) must build without a format-
	# string error (see the %s in capacity_offer_cost_gold).
	instance.call("_on_capacity_offer_available") # no cargo aboard -> gold-cost wording
	instance.call("_close_overlay")
	GameState.gold = 100000
	GameState.buy("silk", 50)
	GameState.gold = 100
	instance.call("_on_capacity_offer_available") # cargo now pricier than gold -> goods-cost wording
	instance.call("_close_overlay")
	print("capacity offer panel OK")

	instance.call("_animate_ship_to", Vector2(100, 100), 1.0)
	assert(instance.is_animating_travel == true)
	print("ship travel animation start OK")

	instance.is_animating_travel = false # the ship animation above never really finishes headlessly (no real time passes)
	var rest_day_before: int = GameState.current_day
	instance.call("_on_rest_pressed")
	assert(instance.is_resting == true)
	assert(GameState.current_day == rest_day_before + 1)
	print("rest animation start OK")

	instance.call("_on_menu_pressed")
	instance.call("_close_overlay")
	print("menu panel OK")

	instance.call("_show_message", "test message")
	instance.call("_close_overlay")
	print("message panel OK")

	# Live gold-formatting on numeric entry fields (quantity/gold-amount
	# dialogs): typing a large number should stay grouped with thousands-
	# separator commas as it's typed, not run together as bare digits.
	# text_changed only fires from real user edits, not a plain .text
	# assignment, so simulate a keystroke by setting text+caret first and
	# then emitting the signal manually, same as the real LineEdit would.
	var edit := LineEdit.new()
	UIUtil.wire_live_gold_formatting(edit)
	edit.text = "1000000000"
	edit.caret_column = 10
	edit.text_changed.emit(edit.text)
	assert(edit.text == "1,000,000,000")
	assert(edit.caret_column == edit.text.length()) # caret was at the end -- should still be
	edit.text = ""
	edit.caret_column = 0
	edit.text_changed.emit(edit.text)
	assert(edit.text == "")
	print("live gold-formatted input OK")

	instance.queue_free()
	print("instantiated OK: res://scenes/Game.tscn (overlays)")

func _test_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	assert(packed != null, "failed to load " + path)
	var instance := packed.instantiate()
	root.add_child(instance)
	print("instantiated OK: %s (children=%d)" % [path, instance.get_child_count()])
	instance.queue_free()

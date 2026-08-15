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

	await _test_multiplayer_screens()

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

## Exercises the multiplayer-only screens added on top of the single-player
## flow: MainMenu's player-count/name-entry setup steps, Game.gd's turn
## banner + pass-device hand-off + standings panel, and EndGame's
## multi-player leaderboard with its "save all scores" button.
func _test_multiplayer_screens() -> void:
	var menu_packed: PackedScene = load("res://scenes/MainMenu.tscn")
	var menu_instance := menu_packed.instantiate()
	root.add_child(menu_instance)
	await process_frame

	var setup_vbox := VBoxContainer.new()
	menu_instance.call("_show_player_setup", setup_vbox, 21)
	assert(setup_vbox.get_child_count() > 0)
	menu_instance.call("_show_player_names", setup_vbox, 21, 3)
	assert(setup_vbox.get_child_count() > 0)
	menu_instance.queue_free()
	print("player setup screens OK")

	GameState.new_multiplayer_game(21, ["Alice", "Bob", "Cleo"], "jaffa")
	var game_packed: PackedScene = load("res://scenes/Game.tscn")
	var game_instance := game_packed.instantiate()
	root.add_child(game_instance)
	await process_frame

	# rest_at_port()/end_turn() advances current_player_index synchronously;
	# the fade animation itself never completes headlessly (no real time
	# passes here), same as the solo "rest animation start" test above.
	game_instance.is_animating_travel = false
	game_instance.call("_on_rest_pressed") # Alice -> Bob
	assert(GameState.current_player_index == 1)
	assert(game_instance.is_resting == true)
	print("turn advance on rest OK")

	game_instance.call("_show_pass_device_screen")
	assert(game_instance.overlay_stack.size() == 1)
	game_instance.call("_close_overlay")
	print("pass-device screen OK")

	game_instance.call("_open_standings_panel")
	assert(game_instance.overlay_stack.size() == 1)
	game_instance.call("_close_overlay")
	print("standings panel OK")

	# The multiplayer "no full-day leg after half a day" rule (see GameState.
	# start_travel's guard) must be visible on the map, not just silently
	# enforced: the destination should be dimmed and tapping it should show
	# an explanatory message instead of silently doing nothing.
	GameState.start_travel("limassol") # half-day hop -- now Bob's turn, half_day_carry becomes 1
	var block_guard := 0
	while not GameState.pending_encounter.is_empty() and block_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		block_guard += 1
	assert(GameState.half_day_carry == 1)
	# game_instance is a live scene wired to GameState's signals, so this trip
	# may have opened a pirate-encounter dialog and always opens an arrival
	# message (see _on_pirate_encounter_started / _on_arrived_at_port) --
	# drain those before checking the blocked-marker behavior below.
	while game_instance.overlay_stack.size() > 0:
		game_instance.call("_close_overlay")
	# Both the arrival's ship-glide tween (_animate_ship_to) and the earlier
	# rest's fade tween never actually finish headlessly (no real time
	# passes), same as the equivalent standalone tests above -- reset both
	# flags so _on_port_marker_pressed below doesn't bail out early on a
	# stuck is_animating_travel/is_resting guard.
	game_instance.is_animating_travel = false
	game_instance.is_resting = false
	assert(game_instance.call("_is_full_day_leg_blocked", "venice") == true)
	assert(game_instance.call("_is_full_day_leg_blocked", "istanbul") == false) # half-day hop, still allowed
	assert(game_instance.overlay_stack.size() == 0)
	game_instance.call("_on_port_marker_pressed", "venice")
	assert(GameState.current_port_id == "limassol") # blocked -- did not silently start sailing
	assert(not GameState.is_traveling)
	assert(game_instance.overlay_stack.size() == 1) # explanatory message shown instead
	game_instance.call("_close_overlay")
	print("full-day leg blocked marker + message OK")

	game_instance.queue_free()

	GameState.new_multiplayer_game(1, ["Alice", "Bob"], "jaffa")
	GameState.current_day = 2 # force past game_length so EndGame reads a finished run
	var endgame_packed: PackedScene = load("res://scenes/EndGame.tscn")
	var endgame_instance := endgame_packed.instantiate()
	root.add_child(endgame_instance)
	await process_frame

	assert(endgame_instance.save_button != null)
	var scores_before: int = SaveManager.get_highscores().size()
	endgame_instance.save_button.pressed.emit()
	assert(endgame_instance.saved)
	# The board persists across runs (real file on disk) and caps at
	# MAX_HIGHSCORES, so repeated local test runs can already be at the cap --
	# assert against that cap rather than assuming unbounded growth by 2.
	assert(SaveManager.get_highscores().size() == mini(scores_before + 2, SaveManager.MAX_HIGHSCORES))
	endgame_instance.queue_free()
	print("multiplayer endgame leaderboard + save-all OK")

func _test_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	assert(packed != null, "failed to load " + path)
	var instance := packed.instantiate()
	root.add_child(instance)
	print("instantiated OK: %s (children=%d)" % [path, instance.get_child_count()])
	instance.queue_free()

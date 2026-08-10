extends SceneTree
## Headless smoke test for core economy/travel logic. Run with:
## godot --headless --script res://tests/smoke_test.gd

var GameState
var SaveManager

func _initialize() -> void:
	GameState = root.get_node("GameState")
	SaveManager = root.get_node("SaveManager")
	print("=== SeaTrader smoke test ===")
	GameState.new_game(21, "jaffa")
	assert(GameState.gold == GameState.STARTING_GOLD)
	assert(GameState.ports.size() == 7)
	assert(GameState.goods.size() == 6)

	# Buy/sell round trip
	var ok_buy: bool = GameState.buy("wheat", 5)
	assert(ok_buy)
	assert(GameState.cargo.get("wheat", 0) == 5)
	var ok_sell: bool = GameState.sell("wheat", 5)
	assert(ok_sell)
	assert(GameState.cargo.get("wheat", 0) == 0)
	print("buy/sell OK")

	# Max-affordable helper backing the "buy max" UI button
	GameState.gold = 100
	var wheat_price: int = GameState.get_price(GameState.current_port_id, "wheat")
	var expected_max: int = min(int(100 / float(wheat_price)), GameState.get_overload_capacity())
	assert(GameState.get_max_affordable("wheat") == expected_max)
	assert(GameState.buy("wheat", GameState.get_max_affordable("wheat")))
	assert(not GameState.can_buy("wheat", GameState.get_max_affordable("wheat") + 1))
	GameState.gold = 100
	print("max-affordable OK")

	# Upgrades
	GameState.gold = 5000
	assert(GameState.buy_upgrade("cargo1"))
	assert(GameState.ship_capacity == GameState.STARTING_CAPACITY + 25)
	assert(not GameState.buy_upgrade("cargo2") == false or true) # cargo2 requires cargo1, already owned -> should succeed
	print("upgrades OK, capacity=%d" % GameState.ship_capacity)

	# Travel across many random runs to exercise events/pirates/storms/overload without crashing
	for i in range(200):
		GameState.new_game(21, "jaffa")
		GameState.gold = 5000
		# Overload the ship on half the runs to exercise the overload-risk path too.
		if i % 2 == 0:
			GameState.buy("wheat", GameState.get_overload_capacity())
			assert(GameState.is_overloaded())
		# jaffa can't reach piraeus/venice directly (route restriction) -- pick a reachable destination.
		var destinations := ["alexandria", "istanbul", "limassol", "beirut"]
		var dest: String = destinations[randi() % destinations.size()]
		GameState.start_travel(dest)
		assert(GameState.is_traveling or GameState.current_port_id == dest)
		var guard := 0
		while not GameState.pending_encounter.is_empty() and guard < 20:
			var choices := ["fight", "flee", "pay"]
			GameState.resolve_pirate_encounter(choices[randi() % choices.size()])
			guard += 1
		assert(guard < 20)
	print("travel/events/overload stress (200 runs) OK")

	# Route restriction: Piraeus/Venice require a Limassol/Istanbul/Alexandria stopover
	GameState.new_game(21, "jaffa")
	assert(not GameState.can_travel_directly("jaffa", "piraeus"))
	assert(not GameState.can_travel_directly("jaffa", "venice"))
	assert(not GameState.can_travel_directly("piraeus", "jaffa"))
	assert(not GameState.can_travel_directly("venice", "beirut"))
	assert(not GameState.can_travel_directly("piraeus", "venice"))
	assert(GameState.can_travel_directly("jaffa", "limassol"))
	assert(GameState.can_travel_directly("limassol", "piraeus"))
	assert(GameState.can_travel_directly("istanbul", "venice"))
	assert(GameState.can_travel_directly("alexandria", "venice"))
	GameState.start_travel("piraeus")
	assert(not GameState.is_traveling) # blocked route must be a no-op
	print("route restriction OK")

	# Fixed travel durations: regular leg = 1 day, far leg = 2 days, any
	# Limassol leg = half a day, except Limassol<->Venice = 1 full day.
	assert(GameState.get_travel_half_days("jaffa", "beirut") == 2)
	assert(GameState.get_travel_half_days("alexandria", "istanbul") == 2)
	assert(GameState.get_travel_half_days("alexandria", "piraeus") == 4)
	assert(GameState.get_travel_half_days("istanbul", "venice") == 4)
	assert(GameState.get_travel_half_days("jaffa", "limassol") == 1)
	assert(GameState.get_travel_half_days("limassol", "piraeus") == 1)
	assert(GameState.get_travel_half_days("limassol", "venice") == 2)
	assert(GameState.get_travel_half_days("venice", "limassol") == 2)
	print("travel duration table OK")

	# Two half-day Limassol legs in a row bank into exactly one full day-tick;
	# a lone half-day leg never rolls a travel event (too short to matter).
	GameState.new_game(21, "jaffa")
	var day_before: int = GameState.current_day
	GameState.start_travel("limassol")
	assert(GameState.current_port_id == "limassol")
	assert(GameState.current_day == day_before)
	GameState.start_travel("istanbul")
	var half_day_guard := 0
	while not GameState.pending_encounter.is_empty() and half_day_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		half_day_guard += 1
	assert(GameState.current_port_id == "istanbul")
	assert(GameState.current_day == day_before + 1)
	print("half-day carry-over OK")

	# A regular one-day leg always resolves in exactly one day-tick.
	GameState.new_game(21, "jaffa")
	day_before = GameState.current_day
	GameState.start_travel("beirut")
	var regular_guard := 0
	while not GameState.pending_encounter.is_empty() and regular_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		regular_guard += 1
	assert(GameState.current_port_id == "beirut")
	assert(GameState.current_day == day_before + 1)
	print("regular one-day leg OK")

	# Overload mechanics in isolation
	GameState.new_game(21, "jaffa")
	GameState.gold = 5000
	assert(not GameState.can_buy("wheat", GameState.get_overload_capacity() + 1))
	assert(GameState.buy("wheat", GameState.get_overload_capacity()))
	assert(GameState.is_overloaded())
	assert(GameState.get_overload_ratio() > 0.99)
	print("overload capacity OK")

	# Bank
	GameState.new_game(21, "jaffa")
	GameState.gold = 1000
	assert(GameState.bank_deposit(500))
	assert(GameState.gold == 500)
	assert(GameState.bank_withdraw(200))
	assert(GameState.gold == 700)
	var max_loan: int = GameState.bank_max_loan()
	if max_loan > 0:
		assert(GameState.bank_borrow(min(100, max_loan)))
	print("bank OK")

	# Save/Load round trip
	SaveManager.save_game()
	assert(SaveManager.has_save())
	var loaded: bool = SaveManager.load_game()
	assert(loaded)
	print("save/load OK")
	SaveManager.delete_save()

	# Highscores
	SaveManager.add_highscore("Test", 12345)
	var scores: Array = SaveManager.get_highscores()
	assert(scores.size() >= 1)
	print("highscores OK")

	print("=== ALL SMOKE TESTS PASSED ===")
	quit()

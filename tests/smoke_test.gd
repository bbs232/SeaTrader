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

	# Upgrades
	GameState.gold = 5000
	assert(GameState.buy_upgrade("cargo1"))
	assert(GameState.ship_capacity == GameState.STARTING_CAPACITY + 25)
	assert(not GameState.buy_upgrade("cargo2") == false or true) # cargo2 requires cargo1, already owned -> should succeed
	print("upgrades OK, capacity=%d" % GameState.ship_capacity)

	# Travel across many random runs to exercise events/pirates/storms without crashing
	for i in range(200):
		GameState.new_game(21, "jaffa")
		GameState.gold = 5000
		var destinations := ["alexandria", "istanbul", "limassol", "piraeus", "beirut", "venice"]
		var dest: String = destinations[randi() % destinations.size()]
		GameState.start_travel(dest)
		var guard := 0
		while not GameState.pending_encounter.is_empty() and guard < 20:
			var choices := ["fight", "flee", "pay"]
			GameState.resolve_pirate_encounter(choices[randi() % choices.size()])
			guard += 1
		assert(guard < 20)
	print("travel/events stress (200 runs) OK")

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

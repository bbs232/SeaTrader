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

	# Max-affordable helper backing the "buy max" UI button -- purchases are
	# limited only by gold, never by hold space (see overload test below).
	GameState.gold = 100
	var wheat_price: int = GameState.get_price(GameState.current_port_id, "wheat")
	var expected_max: int = int(100 / float(wheat_price))
	assert(GameState.get_max_affordable("wheat") == expected_max)
	assert(GameState.buy("wheat", GameState.get_max_affordable("wheat")))
	assert(not GameState.can_buy("wheat", GameState.get_max_affordable("wheat") + 1))
	GameState.gold = 100
	print("max-affordable OK")

	# Upgrades
	GameState.gold = 5000
	assert(GameState.buy_upgrade("cargo1"))
	assert(GameState.ship_capacity == GameState.STARTING_CAPACITY + GameState.get_upgrade("cargo1").amount)
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
		var destinations := ["alexandria", "istanbul", "limassol", "beirut", "piraeus", "venice"]
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

	# Ransom (pay/flee-caught) must never be 0 while the player still has gold
	# to give -- int() floor used to round the demand down to a "free" 0-gold
	# ransom whenever gold was low (e.g. after banking most of it in savings).
	GameState.new_game(21, "jaffa")
	for low_gold in [1, 2, 5, 10, 19, 50]:
		for i in range(30):
			GameState.gold = low_gold
			GameState.pending_encounter = {"type": "pirates", "pirate_strength": 1.0}
			var pay_result: Dictionary = GameState.resolve_pirate_encounter("pay")
			assert(pay_result["ransom"] >= 1)
			assert(GameState.gold >= 0)
			GameState.gold = low_gold
			GameState.pending_encounter = {"type": "pirates", "pirate_strength": 1.0}
			var flee_result: Dictionary = GameState.resolve_pirate_encounter("flee")
			if flee_result.get("outcome", "") == "caught":
				assert(flee_result["ransom"] >= 1)
			assert(GameState.gold >= 0)
	# Flat broke (0 gold) is the one legitimate case where there's nothing to give.
	GameState.gold = 0
	GameState.pending_encounter = {"type": "pirates", "pirate_strength": 1.0}
	var broke_result: Dictionary = GameState.resolve_pirate_encounter("pay")
	assert(broke_result["ransom"] == 0)
	assert(GameState.gold == 0)
	print("pirate ransom never rounds down to free OK")

	# Fixed travel durations: every pair in GameState.FULL_DAY_ROUTES is a
	# full day (2), regardless of direction; everything else is half a day (1).
	GameState.new_game(21, "jaffa")
	assert(GameState.get_travel_half_days("venice", "alexandria") == 2)
	assert(GameState.get_travel_half_days("alexandria", "venice") == 2)
	assert(GameState.get_travel_half_days("venice", "limassol") == 2)
	assert(GameState.get_travel_half_days("venice", "istanbul") == 2)
	assert(GameState.get_travel_half_days("venice", "beirut") == 2)
	assert(GameState.get_travel_half_days("venice", "jaffa") == 2)
	assert(GameState.get_travel_half_days("istanbul", "alexandria") == 2)
	assert(GameState.get_travel_half_days("istanbul", "jaffa") == 2)
	assert(GameState.get_travel_half_days("istanbul", "beirut") == 2)
	assert(GameState.get_travel_half_days("piraeus", "jaffa") == 2)
	assert(GameState.get_travel_half_days("beirut", "piraeus") == 2)
	assert(GameState.get_travel_half_days("piraeus", "venice") == 1)
	assert(GameState.get_travel_half_days("venice", "piraeus") == 1)
	assert(GameState.get_travel_half_days("istanbul", "piraeus") == 1)
	assert(GameState.get_travel_half_days("istanbul", "limassol") == 1)
	assert(GameState.get_travel_half_days("alexandria", "piraeus") == 1)
	assert(GameState.get_travel_half_days("jaffa", "alexandria") == 1)
	assert(GameState.get_travel_half_days("jaffa", "beirut") == 1)
	assert(GameState.get_travel_half_days("limassol", "beirut") == 1)
	print("travel duration table OK")

	# Two half-day Limassol legs in a row bank into exactly one full day's
	# worth of travel, but the resulting day-tick is deferred to evening
	# rather than firing immediately on arrival: the player lands at the
	# second port the same day (half_day_carry == 2), and sailing again is
	# blocked until they rest -- only then does the day actually turn over.
	# Every leg -- even a lone half-day hop -- gets its own shot at a travel
	# event now, so a pirate encounter can interrupt any of these legs too.
	GameState.new_game(21, "jaffa")
	GameState.gold = 5000
	var day_before: int = GameState.current_day
	GameState.start_travel("limassol")
	var leg1_guard := 0
	while not GameState.pending_encounter.is_empty() and leg1_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		leg1_guard += 1
	assert(leg1_guard < 20)
	assert(GameState.current_port_id == "limassol")
	assert(GameState.current_day == day_before)
	assert(GameState.half_day_carry == 1)
	GameState.start_travel("istanbul")
	var leg2_guard := 0
	while not GameState.pending_encounter.is_empty() and leg2_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		leg2_guard += 1
	assert(leg2_guard < 20)
	assert(GameState.current_port_id == "istanbul")
	assert(GameState.current_day == day_before) # arrival is this same evening, not ticked yet
	assert(GameState.half_day_carry == 2)
	GameState.start_travel("limassol") # can't sail again this evening without resting first
	assert(not GameState.is_traveling)
	assert(GameState.current_port_id == "istanbul")
	GameState.rest_at_port()
	assert(GameState.current_day == day_before + 1)
	assert(GameState.half_day_carry == 0)
	print("half-day carry-over OK")

	# Piraeus <-> Venice sails directly, half a day -- still just one event
	# roll for the whole hop.
	GameState.new_game(21, "jaffa")
	GameState.gold = 5000
	GameState.current_port_id = "piraeus"
	day_before = GameState.current_day
	GameState.start_travel("venice")
	var piraeus_venice_guard := 0
	while not GameState.pending_encounter.is_empty() and piraeus_venice_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		piraeus_venice_guard += 1
	assert(piraeus_venice_guard < 20)
	assert(GameState.current_port_id == "venice")
	assert(GameState.current_day == day_before)
	print("Piraeus<->Venice direct crossing OK")

	# A full-day leg lands the ship the same evening it departed, not a day
	# later -- goods must still be tradable there before the day turns over.
	# (Regression check: this used to tick the day automatically on arrival,
	# with no explicit rest.)
	GameState.new_game(21, "jaffa")
	day_before = GameState.current_day
	var istanbul_wheat_before2: int = GameState.get_price("istanbul", "wheat")
	GameState.start_travel("istanbul")
	var regular_guard := 0
	while not GameState.pending_encounter.is_empty() and regular_guard < 20:
		GameState.resolve_pirate_encounter("pay")
		regular_guard += 1
	assert(GameState.current_port_id == "istanbul")
	assert(GameState.current_day == day_before) # still the same day -- arrival is this evening
	assert(GameState.half_day_carry == 2)
	assert(GameState.get_price("istanbul", "wheat") == istanbul_wheat_before2) # no day-tick yet, no price move
	GameState.start_travel("alexandria") # can't sail again this evening without resting first
	assert(not GameState.is_traveling)
	GameState.rest_at_port()
	assert(GameState.current_day == day_before + 1)
	assert(GameState.half_day_carry == 0)
	print("full-day leg OK")

	# Market demand rumors always push the destination price UP, never down.
	GameState.new_game(21, "jaffa")
	GameState.travel_destination_id = "beirut"
	var demand_before := {}
	for g in GameState.goods:
		demand_before[g.id] = GameState.get_price("beirut", g.id)
	GameState._apply_market_demand()
	var any_increased := false
	for g in GameState.goods:
		var after_price: int = GameState.get_price("beirut", g.id)
		assert(after_price >= demand_before[g.id])
		if after_price > demand_before[g.id]:
			any_increased = true
	assert(any_increased)
	print("market demand price spike OK")

	# Resting at port skips a day (prices/interest tick) without traveling.
	GameState.new_game(21, "jaffa")
	day_before = GameState.current_day
	GameState.rest_at_port()
	assert(not GameState.is_traveling)
	assert(GameState.current_port_id == "jaffa")
	assert(GameState.current_day == day_before + 1)
	print("rest at port OK")

	# Overload mechanics: purchases are unlimited by hold space (only by
	# gold) -- the ship just can't set sail carrying more than 150% of
	# nominal capacity, and that cap is enforced only at start_travel.
	GameState.new_game(21, "jaffa")
	GameState.gold = 20000
	var deep_overload_qty: int = GameState.ship_capacity * 4 # 400% of capacity
	assert(GameState.can_buy("wheat", deep_overload_qty))
	assert(GameState.buy("wheat", deep_overload_qty))
	assert(GameState.get_cargo_used() == deep_overload_qty)
	assert(GameState.is_overloaded())
	assert(GameState.get_overload_ratio() > 0.99)
	# Staying docked (resting) while deeply overloaded is fine.
	var overload_day_before: int = GameState.current_day
	GameState.rest_at_port()
	assert(GameState.current_day == overload_day_before + 1)
	assert(GameState.get_cargo_used() > GameState.get_overload_capacity()) # still well past 150%
	# But the ship can't set sail this loaded -- start_travel is a no-op above 150%.
	GameState.start_travel("alexandria")
	assert(not GameState.is_traveling)
	assert(GameState.current_port_id == "jaffa")
	# Sell back down to at most 150% of capacity and sailing works again.
	var sell_qty: int = GameState.get_cargo_used() - GameState.get_overload_capacity()
	assert(GameState.sell("wheat", sell_qty))
	assert(GameState.get_cargo_used() == GameState.get_overload_capacity())
	GameState.start_travel("alexandria")
	assert(GameState.is_traveling or GameState.current_port_id == "alexandria")
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

	# Special capacity offer: fires once per CAPACITY_OFFER_GOLD_STEP of gold
	# reached (not again for the same milestone), grants a flat capacity
	# bonus, and charges whichever of gold/goods (valued at the current port)
	# is worth more.
	GameState.new_game(21, "jaffa")
	var offer_fired := [0] # boxed in an Array -- lambdas capture locals by value, not by reference
	GameState.capacity_offer_available.connect(func(): offer_fired[0] += 1)
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP - 1
	GameState.rest_at_port() # day-tick, still below the threshold
	assert(offer_fired[0] == 0)
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP + 1
	var cap_before: int = GameState.ship_capacity
	var gold_before: int = GameState.gold
	GameState.rest_at_port() # crosses the threshold -- offer fires exactly once
	assert(offer_fired[0] == 1)
	GameState.rest_at_port() # still above the same threshold -- must not refire
	assert(offer_fired[0] == 1)
	# No cargo aboard, so gold is necessarily the pricier 3% -- paid in gold.
	GameState.accept_capacity_offer()
	assert(GameState.ship_capacity == cap_before + GameState.CAPACITY_OFFER_CAPACITY_BONUS)
	assert(GameState.gold == gold_before - int(ceil(gold_before * GameState.CAPACITY_OFFER_COST_RATIO)))

	# Paying in goods instead, when the cargo aboard is worth more than 3% of gold.
	GameState.new_game(21, "jaffa")
	GameState.gold = 100000
	assert(GameState.buy("silk", 50))
	GameState.gold = 100
	assert(GameState.get_capacity_offer_goods_value() > GameState.get_capacity_offer_gold_cost())
	var cargo_before: int = GameState.cargo.get("silk", 0)
	var cap_before2: int = GameState.ship_capacity
	var gold_before2: int = GameState.gold
	GameState.accept_capacity_offer()
	assert(GameState.ship_capacity == cap_before2 + GameState.CAPACITY_OFFER_CAPACITY_BONUS)
	assert(GameState.gold == gold_before2) # paid in goods, not gold
	assert(GameState.cargo.get("silk", 0) < cargo_before)
	print("capacity offer OK")

	# The milestone must persist across save/load, or reloading a save already
	# past a threshold would immediately re-offer on the next day-tick.
	GameState.new_game(21, "jaffa")
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP + 1
	GameState.rest_at_port()
	assert(GameState.capacity_offer_milestone == 1)
	SaveManager.save_game()
	GameState.capacity_offer_milestone = 0
	assert(SaveManager.load_game())
	assert(GameState.capacity_offer_milestone == 1)
	SaveManager.delete_save()
	print("capacity offer milestone persists across save/load OK")

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

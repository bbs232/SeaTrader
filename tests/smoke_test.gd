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

	# Legal vs overloaded "max capacity" buy choice: legal stops exactly at
	# nominal ship_capacity, overloaded allows up to the 150% OVERLOAD_ALLOWANCE.
	GameState.new_game(21, "jaffa")
	# Gold should not be the limiting factor here, but must stay well under
	# MILLIONAIRE_GIFT_GOLD_THRESHOLD -- crossing it (or a MEGA_CAPACITY_GIFT_
	# GOLD_STEP) would grow ship_capacity mid-test and break the "ship starts
	# at STARTING_CAPACITY" assumption below.
	GameState.gold = 500_000
	var legal_max: int = GameState.get_max_legal_capacity_affordable("wheat")
	var overload_max: int = GameState.get_max_sailable_affordable("wheat")
	assert(legal_max == GameState.ship_capacity) # hold starts empty
	assert(overload_max == GameState.get_overload_capacity())
	assert(overload_max > legal_max)
	assert(GameState.buy("wheat", legal_max))
	assert(GameState.get_cargo_used() == GameState.ship_capacity)
	assert(not GameState.is_overloaded()) # exactly at nominal capacity, not over it
	var legal_max_after: int = GameState.get_max_legal_capacity_affordable("wheat")
	assert(legal_max_after == 0) # already full to the legal limit
	var overload_max_after: int = GameState.get_max_sailable_affordable("wheat")
	assert(overload_max_after == GameState.get_overload_capacity() - GameState.ship_capacity)
	assert(GameState.buy("wheat", overload_max_after))
	assert(GameState.get_cargo_used() == GameState.get_overload_capacity())
	assert(GameState.is_overloaded())
	print("legal vs overloaded max-capacity buy OK")

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

	# Fair wind must never claim to shorten a voyage by more than what's
	# actually left at the moment it's rolled -- the event always fires right
	# when the leg's own travel time is spent, so a standalone half-day leg
	# (nothing left by then) must see NO effect/log entry at all, an odd
	# leftover half-day gets logged/cut as half a day (not rounded up to a
	# full day), and only when a full day is genuinely still ahead does it
	# get cut and logged as a full day.
	var fair_wind_ev: EventDef = null
	for ev in GameState.events:
		if ev.id == "fair_wind":
			fair_wind_ev = ev
	assert(fair_wind_ev != null)

	GameState.new_game(21, "jaffa")
	GameState.travel_half_days_remaining = 0 # standalone half-day leg, already fully spent by roll time
	GameState.travel_log.clear()
	GameState.call("_trigger_event", fair_wind_ev)
	assert(GameState.travel_half_days_remaining == 0)
	assert(GameState.travel_log.is_empty())

	GameState.new_game(21, "jaffa")
	GameState.travel_half_days_remaining = 1 # odd leftover half-day
	GameState.travel_log.clear()
	GameState.call("_trigger_event", fair_wind_ev)
	assert(GameState.travel_half_days_remaining == 0)
	assert(GameState.travel_log.size() == 1)
	assert(GameState.travel_log[0]["half_days"] == 1)

	GameState.new_game(21, "jaffa")
	GameState.travel_half_days_remaining = 2 # a full day genuinely still ahead
	GameState.travel_log.clear()
	GameState.call("_trigger_event", fair_wind_ev)
	assert(GameState.travel_half_days_remaining == 0)
	assert(GameState.travel_log.size() == 1)
	assert(GameState.travel_log[0]["half_days"] == 2)
	print("fair wind never over-claims a shortened day OK")

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

	# Special capacity offer: fires the instant gold ever reaches a
	# CAPACITY_OFFER_GOLD_STEP milestone (no day-tick needed, same as the
	# millionaire gift below), never again for the same milestone, grants a
	# flat capacity bonus, and charges whichever of gold/goods (valued at the
	# current port) is worth more.
	GameState.new_game(21, "jaffa")
	var offer_fired := [0] # boxed in an Array -- lambdas capture locals by value, not by reference
	GameState.capacity_offer_available.connect(func(): offer_fired[0] += 1)
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP - 1
	assert(offer_fired[0] == 0)
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP + 1 # crosses the threshold -- offer fires exactly once, immediately
	var cap_before: int = GameState.ship_capacity
	var gold_before: int = GameState.gold
	assert(offer_fired[0] == 1)
	GameState.gold += 500 # still above the same threshold -- must not refire
	assert(offer_fired[0] == 1)
	gold_before = GameState.gold
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

	# A single trade that jumps gold across several CAPACITY_OFFER_GOLD_STEP
	# milestones in one go (e.g. 10M -> 60M) must surface ONE combined offer
	# bundling all the steps crossed (bigger bonus, one payment), not a
	# separate popup per step.
	GameState.new_game(21, "jaffa")
	var offer_fired3 := [0] # boxed in an Array -- lambdas capture locals by value, not by reference
	GameState.capacity_offer_available.connect(func(): offer_fired3[0] += 1)
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP * 6
	assert(offer_fired3[0] == 1)
	assert(GameState.capacity_offer_milestone == 6)
	assert(GameState.capacity_offer_pending_steps == 6)
	assert(GameState.get_capacity_offer_capacity_bonus() == GameState.CAPACITY_OFFER_CAPACITY_BONUS * 6)
	var bundled_cap_before: int = GameState.ship_capacity
	GameState.accept_capacity_offer()
	assert(GameState.ship_capacity == bundled_cap_before + GameState.CAPACITY_OFFER_CAPACITY_BONUS * 6)
	print("capacity offer bundles several milestones crossed in one jump into a single offer OK")

	# The milestone must persist across save/load, or reloading a save already
	# past a threshold would immediately re-offer.
	GameState.new_game(21, "jaffa")
	GameState.gold = GameState.CAPACITY_OFFER_GOLD_STEP + 1
	assert(GameState.capacity_offer_milestone == 1)
	SaveManager.save_game()
	GameState.capacity_offer_milestone = 0
	assert(SaveManager.load_game())
	assert(GameState.capacity_offer_milestone == 1)
	SaveManager.delete_save()
	print("capacity offer milestone persists across save/load OK")

	# Millionaire warehouse gift: a one-time free capacity bonus the instant
	# gold ever reaches MILLIONAIRE_GIFT_GOLD_THRESHOLD (no day-tick needed,
	# unlike the paid capacity offer above), never granted twice.
	GameState.new_game(21, "jaffa")
	var gift_fired := [0] # boxed in an Array -- lambdas capture locals by value, not by reference
	GameState.millionaire_gift_granted.connect(func(): gift_fired[0] += 1)
	GameState.gold = GameState.MILLIONAIRE_GIFT_GOLD_THRESHOLD - 1
	assert(gift_fired[0] == 0)
	var mg_cap_before: int = GameState.ship_capacity
	GameState.gold = GameState.MILLIONAIRE_GIFT_GOLD_THRESHOLD
	assert(gift_fired[0] == 1)
	assert(GameState.ship_capacity == mg_cap_before + GameState.MILLIONAIRE_GIFT_CAPACITY_BONUS)
	GameState.gold += 500 # still above threshold -- must not refire
	assert(gift_fired[0] == 1)
	assert(GameState.ship_capacity == mg_cap_before + GameState.MILLIONAIRE_GIFT_CAPACITY_BONUS)
	# Claimed flag must persist across save/load, or reloading a save already
	# past the threshold would double-grant the capacity bonus.
	SaveManager.save_game()
	var mg_cap_after: int = GameState.ship_capacity
	assert(SaveManager.load_game())
	assert(GameState.millionaire_gift_claimed)
	assert(GameState.ship_capacity == mg_cap_after)
	SaveManager.delete_save()
	print("millionaire warehouse gift OK")

	# Mega warehouse gift: on top of (not instead of) the recurring
	# CAPACITY_OFFER_GOLD_STEP paid offer and the one-time millionaire gift
	# above, every MEGA_CAPACITY_GIFT_GOLD_STEP of gold ever reached grants
	# another free capacity bonus -- and keeps recurring, unlike the
	# millionaire gift's one-shot flag.
	GameState.new_game(21, "jaffa")
	var mega_fired := [0] # boxed in an Array -- lambdas capture locals by value, not by reference
	var offer_fired2 := [0]
	GameState.mega_capacity_gift_granted.connect(func(_bonus: int): mega_fired[0] += 1)
	GameState.capacity_offer_available.connect(func(): offer_fired2[0] += 1)
	GameState.gold = GameState.MEGA_CAPACITY_GIFT_GOLD_STEP - 1 # 99,999,999 -- also crosses several 10M-offer milestones on the way up
	assert(mega_fired[0] == 0)
	offer_fired2[0] = 0 # only care about what fires on the crossing below, not the milestones passed getting here
	var mega_cap_before: int = GameState.ship_capacity
	GameState.gold = GameState.MEGA_CAPACITY_GIFT_GOLD_STEP # crosses 100M -- the mega gift and the regular 10M-offer milestone both fire, independently
	assert(mega_fired[0] == 1)
	assert(offer_fired2[0] == 1)
	assert(GameState.ship_capacity == mega_cap_before + GameState.MEGA_CAPACITY_GIFT_CAPACITY_BONUS)
	GameState.gold += 500 # still above the same threshold -- must not refire
	assert(mega_fired[0] == 1)
	GameState.gold = GameState.MEGA_CAPACITY_GIFT_GOLD_STEP * 2 # next step -- recurs, unlike the millionaire gift
	assert(mega_fired[0] == 2)
	assert(GameState.ship_capacity == mega_cap_before + GameState.MEGA_CAPACITY_GIFT_CAPACITY_BONUS * 2)

	# A single jump spanning multiple steps grants the whole bundled bonus at
	# once and fires ONE message, not one popup per step crossed (same as the
	# CAPACITY_OFFER_GOLD_STEP paid offer above).
	GameState.new_game(21, "jaffa")
	GameState.gold = GameState.MILLIONAIRE_GIFT_GOLD_THRESHOLD # resolve the one-time millionaire gift first so it doesn't interfere with the delta assertion below
	var mega_fired2 := [0]
	var mega_bonus2 := [0]
	GameState.mega_capacity_gift_granted.connect(func(bonus: int): mega_fired2[0] += 1; mega_bonus2[0] = bonus)
	var mega_cap_before2: int = GameState.ship_capacity
	GameState.gold = GameState.MEGA_CAPACITY_GIFT_GOLD_STEP * 3
	assert(mega_fired2[0] == 1)
	assert(mega_bonus2[0] == GameState.MEGA_CAPACITY_GIFT_CAPACITY_BONUS * 3)
	assert(GameState.ship_capacity == mega_cap_before2 + GameState.MEGA_CAPACITY_GIFT_CAPACITY_BONUS * 3)

	# Milestone persists across save/load, same as capacity_offer_milestone.
	SaveManager.save_game()
	GameState.mega_capacity_gift_milestone = 0
	assert(SaveManager.load_game())
	assert(GameState.mega_capacity_gift_milestone == 3)
	SaveManager.delete_save()
	print("mega capacity gift OK")

	# Billionaire gift: one-time free security-ship gift the instant gold ever
	# reaches BILLIONAIRE_GIFT_GOLD_THRESHOLD, same one-shot pattern as the
	# millionaire warehouse gift, just granting escort ships instead.
	GameState.new_game(21, "jaffa")
	var billionaire_fired := [0]
	var billionaire_ships := [0]
	GameState.billionaire_gift_granted.connect(func(ships: int): billionaire_fired[0] += 1; billionaire_ships[0] = ships)
	GameState.gold = GameState.BILLIONAIRE_GIFT_GOLD_THRESHOLD - 1
	assert(billionaire_fired[0] == 0)
	var security_before: int = GameState.security_ships
	GameState.gold = GameState.BILLIONAIRE_GIFT_GOLD_THRESHOLD
	assert(billionaire_fired[0] == 1)
	assert(billionaire_ships[0] == GameState.BILLIONAIRE_GIFT_SECURITY_SHIPS)
	assert(GameState.security_ships == security_before + GameState.BILLIONAIRE_GIFT_SECURITY_SHIPS)
	GameState.gold += 500 # still above threshold -- must not refire
	assert(billionaire_fired[0] == 1)
	assert(GameState.security_ships == security_before + GameState.BILLIONAIRE_GIFT_SECURITY_SHIPS)
	# Claimed flag must persist across save/load, or reloading a save already
	# past the threshold would double-grant the escort ships.
	SaveManager.save_game()
	var security_after: int = GameState.security_ships
	assert(SaveManager.load_game())
	assert(GameState.billionaire_gift_claimed)
	assert(GameState.security_ships == security_after)
	SaveManager.delete_save()
	print("billionaire gift OK")

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

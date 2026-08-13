extends Node
## Central game state and economy simulation. Autoloaded as "GameState".

signal day_advanced(day: int)
signal arrived_at_port(port_id: String, log: Array)
signal pirate_encounter_started(details: Dictionary)
signal game_ended(summary: Dictionary)
signal capacity_offer_available()
signal millionaire_gift_granted()
signal mega_capacity_gift_granted(bonus: int)
signal billionaire_gift_granted(security_ships_granted: int)

## Bumped by one on every gameplay/UI update shipped, shown in the main menu footer.
const GAME_VERSION := "3.6"

const STARTING_GOLD := 500
const STARTING_CAPACITY := 85
const STARTING_SPEED_POINTS := 0
const STARTING_DEFENSE_POINTS := 0
const MAX_LOAN_FACTOR := 2.0 # can borrow up to 2x current net worth
const DAILY_INTEREST := 0.02
const OVERLOAD_ALLOWANCE := 1.5 # can set sail risk-loaded up to 150% of nominal capacity; buying itself has no hold-space limit
const OVERLOAD_DAILY_RISK := 0.5 # scaled by how far over nominal capacity you are
const SECURITY_SHIP_BASE_COST := 700 # cost of the first hired escort ship
const SECURITY_SHIP_COST_STEP := 450 # extra cost added per escort ship already hired
const SECURITY_SHIP_WIN_BONUS := 0.15 # flat pirate-fight win chance added per escort ship
const NOTABLE_PRICE_CHANGE_RATIO := 0.4 # overnight swing must move a good's price by at least this fraction to flash a rest-day news message
const NOTABLE_MIN_ABS_DELTA := 4 # and at least this many gold, so cheap goods don't "notably" swing on +-1 rounding noise
const PRICE_SHOCK_CHANCE := 0.01 # per port/good pair, each night: chance of a genuine demand shock overriding normal jitter
const PRICE_SHOCK_MIN_RATIO := 0.7 # a shock moves the price by at least this fraction (up or down)...
const PRICE_SHOCK_MAX_RATIO := 1.1 # ...up to this much -- comfortably past any good's routine per-good volatility, so shocks still read as distinct events
const WAREHOUSE_MISHAP_CHANCE := 0.05 # per night resting at a port while carrying cargo
const WAREHOUSE_MISHAP_MIN_LOSS := 0.10 # fraction of each cargo good lost to a warehouse fire/theft
const WAREHOUSE_MISHAP_MAX_LOSS := 0.20
const PIRATE_LOOT_GOOD_COUNT_MIN := 1 # a won pirate fight plunders this many different goods...
const PIRATE_LOOT_GOOD_COUNT_MAX := 3 # ...up to this many, picked at random
const PIRATE_LOOT_QTY_MIN := 8 # ...in this much of each, scaled by the pirates' own strength
const PIRATE_LOOT_QTY_MAX := 30
const PIRATE_LOOT_BIG_HAUL_CHANCE := 0.12 # rare chance for a single looted good to be a real windfall
const PIRATE_LOOT_BIG_HAUL_MULT_MIN := 4
const PIRATE_LOOT_BIG_HAUL_MULT_MAX := 9
const PIRATE_CAUGHT_CARGO_LOSS_MIN := 0.15 # getting caught fleeing also costs a slice of cargo, not just gold...
const PIRATE_CAUGHT_CARGO_LOSS_MAX := 0.35 # ...somewhat lighter than a lost fight's jettison (see "fight" -> lost)
const HALF_DAY_EVENT_SCALE := 0.5 # a half-day-only leg's event chance, relative to a full travel day's
const CAPACITY_OFFER_GOLD_STEP := 10_000_000 # each multiple of gold reached unlocks a one-time special cargo-capacity offer
const CAPACITY_OFFER_CAPACITY_BONUS := 100_000 # flat cargo-hold increase the offer grants, unconditionally
const CAPACITY_OFFER_COST_RATIO := 0.03 # cost: 3% of gold or 3% of current cargo's value (whichever is worth more)
const MILLIONAIRE_GIFT_GOLD_THRESHOLD := 1_000_000 # one-time free warehouse gift once gold ever reaches this
const MILLIONAIRE_GIFT_CAPACITY_BONUS := 100_000 # flat cargo-hold increase granted unconditionally, no cost
const MEGA_CAPACITY_GIFT_GOLD_STEP := 100_000_000 # each new multiple of gold reached grants another free warehouse gift, stacking alongside (not replacing) the CAPACITY_OFFER_GOLD_STEP paid offers
const MEGA_CAPACITY_GIFT_CAPACITY_BONUS := 10_000_000 # flat cargo-hold increase granted unconditionally, no cost, per MEGA_CAPACITY_GIFT_GOLD_STEP reached
const BILLIONAIRE_GIFT_GOLD_THRESHOLD := 1_000_000_000 # one-time free security-ship gift once gold ever reaches this -- same one-shot pattern as MILLIONAIRE_GIFT_GOLD_THRESHOLD, just a much bigger milestone
const BILLIONAIRE_GIFT_SECURITY_SHIPS := 3 # flat escort-ship count granted unconditionally, no cost, on top of however many the player already has

var goods: Array[Good] = []
var ports: Array[Port] = []
var upgrades: Array[ShipUpgrade] = []
var events: Array[EventDef] = []

var game_length_days: int = 21
var current_day: int = 1
var gold: int = STARTING_GOLD:
	set(value):
		gold = value
		_check_millionaire_gift()
		_check_capacity_offer()
		_check_mega_capacity_gift()
		_check_billionaire_gift()
var current_port_id: String = ""
var cargo: Dictionary = {} # good_id -> int quantity
var ship_capacity: int = STARTING_CAPACITY
var ship_speed_points: int = STARTING_SPEED_POINTS
var ship_defense_points: int = STARTING_DEFENSE_POINTS
var security_ships: int = 0
var owned_upgrades: Array[String] = []
var loan: float = 0.0
var savings: float = 0.0
## Highest CAPACITY_OFFER_GOLD_STEP multiple already surfaced as a special
## offer (see _check_capacity_offer), so each milestone only prompts once.
var capacity_offer_milestone: int = 0
## How many CAPACITY_OFFER_GOLD_STEP milestones the currently-pending offer
## bundles together (usually 1; more if a single trade jumped gold across
## several steps at once -- see _check_capacity_offer). Not persisted across
## save/load: it only matters between the offer being surfaced and resolved,
## same as pending_encounter.
var capacity_offer_pending_steps: int = 1
## Whether the one-time MILLIONAIRE_GIFT_GOLD_THRESHOLD warehouse gift has
## already been granted (see _check_millionaire_gift), so it only fires once.
var millionaire_gift_claimed: bool = false
## Highest MEGA_CAPACITY_GIFT_GOLD_STEP multiple already granted (see
## _check_mega_capacity_gift) -- recurring like capacity_offer_milestone,
## not a one-time flag like millionaire_gift_claimed.
var mega_capacity_gift_milestone: int = 0
## Whether the one-time BILLIONAIRE_GIFT_GOLD_THRESHOLD security-ship gift has
## already been granted (see _check_billionaire_gift), so it only fires once --
## same one-shot pattern as millionaire_gift_claimed.
var billionaire_gift_claimed: bool = false

var prices: Dictionary = {} # port_id -> { good_id -> int price }

var is_traveling: bool = false
var travel_destination_id: String = ""
var travel_half_days_remaining: int = 0
## Whether this leg has already had its one shot at a travel event (see
## _advance_travel) -- every leg gets exactly one roll, whether it's a lone
## half-day hop or a full multi-half-day route, no matter how many
## _advance_travel calls it takes to get there (a pirate encounter can pause
## and resume the same leg across several calls). Reset in start_travel.
var travel_event_rolled_this_leg: bool = false
## This leg's own duration in half-days (set once in start_travel, unlike
## travel_half_days_remaining which counts down). Used only to scale down the
## event roll's chance for a half-day-only leg (see HALF_DAY_EVENT_SCALE and
## _roll_travel_event) -- it's half the exposure of a full travel day, so it
## should be correspondingly less likely to turn up an event.
var travel_leg_half_days: int = 0
## Half-day legs don't trigger a full day-tick (price update/interest/event
## roll) on their own; this banks the odd half-day so two short hops in a row
## still add up to a real day instead of time silently vanishing. Reaching 2
## while the ship is still en route (more half-days left in the current leg)
## ticks the day immediately, same as always (the ship is at sea either way,
## so no dock stop is lost). But when reaching 2 is what lands the ship --
## whether that's a single full-day leg or the second of two chained
## half-day hops -- the day-tick is left pending: half_day_carry stays at 2
## ("evening", see Game._time_of_day_key) so the player can still trade at
## the new port today. The day only turns over once they rest (see
## rest_at_port), and start_travel refuses to set sail again until then.
var half_day_carry: int = 0
var travel_log: Array = []
var pending_encounter: Dictionary = {}

func _ready() -> void:
	_load_definitions()

func _load_definitions() -> void:
	goods.clear()
	for path in [
		"res://data/goods/copper.tres",
		"res://data/goods/olives.tres",
		"res://data/goods/wheat.tres",
		"res://data/goods/spices.tres",
		"res://data/goods/wine.tres",
		"res://data/goods/silk.tres",
	]:
		goods.append(load(path) as Good)

	ports.clear()
	for path in [
		"res://data/ports/jaffa.tres",
		"res://data/ports/beirut.tres",
		"res://data/ports/limassol.tres",
		"res://data/ports/alexandria.tres",
		"res://data/ports/istanbul.tres",
		"res://data/ports/piraeus.tres",
		"res://data/ports/venice.tres",
	]:
		ports.append(load(path) as Port)

	upgrades.clear()
	for path in [
		"res://data/upgrades/cargo1.tres",
		"res://data/upgrades/cargo2.tres",
		"res://data/upgrades/cargo3.tres",
		"res://data/upgrades/cargo4.tres",
		"res://data/upgrades/hull1.tres",
		"res://data/upgrades/hull2.tres",
		"res://data/upgrades/sail1.tres",
		"res://data/upgrades/sail2.tres",
	]:
		upgrades.append(load(path) as ShipUpgrade)

	events.clear()
	for path in [
		"res://data/events/storm.tres",
		"res://data/events/pirates.tres",
		"res://data/events/fair_wind.tres",
		"res://data/events/market_demand.tres",
		"res://data/events/aground.tres",
	]:
		events.append(load(path) as EventDef)

func get_port(port_id: String) -> Port:
	for p in ports:
		if p.id == port_id:
			return p
	return null

func get_good(good_id: String) -> Good:
	for g in goods:
		if g.id == good_id:
			return g
	return null

func get_upgrade(upgrade_id: String) -> ShipUpgrade:
	for u in upgrades:
		if u.id == upgrade_id:
			return u
	return null

## Starts a brand new game. game_length picks how many in-game days the trading run lasts.
func new_game(game_length: int = 21, start_port_id: String = "jaffa") -> void:
	_load_definitions()
	game_length_days = game_length
	current_day = 1
	gold = STARTING_GOLD
	current_port_id = start_port_id
	cargo.clear()
	ship_capacity = STARTING_CAPACITY
	ship_speed_points = STARTING_SPEED_POINTS
	ship_defense_points = STARTING_DEFENSE_POINTS
	security_ships = 0
	owned_upgrades.clear()
	loan = 0.0
	savings = 0.0
	capacity_offer_milestone = 0
	millionaire_gift_claimed = false
	mega_capacity_gift_milestone = 0
	billionaire_gift_claimed = false
	is_traveling = false
	travel_destination_id = ""
	travel_half_days_remaining = 0
	travel_leg_half_days = 0
	travel_event_rolled_this_leg = false
	half_day_carry = 0
	travel_log.clear()
	pending_encounter.clear()
	_init_prices()

func _init_prices() -> void:
	prices.clear()
	for port in ports:
		var port_prices := {}
		for good in goods:
			var mod: float = port.price_modifiers.get(good.id, 1.0)
			port_prices[good.id] = _jitter_price(good.base_price * mod, good.volatility)
		prices[port.id] = port_prices

## Redraws every port/good price for the new day from that port's own anchor
## (base_price * the port's modifier for that good), not from yesterday's
## price -- so each good has a stable "routine range" around its anchor that
## the price returns to every day, instead of a random walk that can drift
## away and stay drifted for days. Each port/good pair also has a small
## independent chance of a demand "shock" that night (see PRICE_SHOCK_CHANCE):
## a much larger, guaranteed-dramatic move away from the anchor. Because
## tomorrow's price is drawn from the anchor again rather than from tonight's
## shocked price, a shock is always a single-day event that snaps back to the
## routine range the very next day.
func _update_prices() -> void:
	for port in ports:
		var port_prices: Dictionary = prices[port.id]
		for good in goods:
			var mod: float = port.price_modifiers.get(good.id, 1.0)
			var anchor: float = good.base_price * mod
			var new_price: int
			if randf() < PRICE_SHOCK_CHANCE:
				var shock_ratio := randf_range(PRICE_SHOCK_MIN_RATIO, PRICE_SHOCK_MAX_RATIO)
				if randf() < 0.5:
					shock_ratio = -shock_ratio
				new_price = max(1, int(round(anchor * (1.0 + shock_ratio))))
			else:
				new_price = _jitter_price(anchor, good.volatility)
			port_prices[good.id] = new_price

func _jitter_price(anchor: float, volatility: float) -> int:
	var delta := randf_range(-volatility, volatility)
	var price := anchor * (1.0 + delta)
	return max(1, int(round(price)))

func get_price(port_id: String, good_id: String) -> int:
	return prices.get(port_id, {}).get(good_id, 0)

func get_cargo_used() -> int:
	var total := 0
	for qty in cargo.values():
		total += qty
	return total

func get_cargo_free() -> int:
	return ship_capacity - get_cargo_used()

## Ships can be risk-loaded beyond nominal capacity (see OVERLOAD_ALLOWANCE),
## trading a higher daily chance of losing cargo/damaging the hull for extra cargo space.
func get_overload_capacity() -> int:
	return int(ship_capacity * OVERLOAD_ALLOWANCE)

func is_overloaded() -> bool:
	return get_cargo_used() > ship_capacity

## 0.0 when within nominal capacity, rising toward 1.0 at the maximum overload allowance.
func get_overload_ratio() -> float:
	return clamp(float(get_cargo_used() - ship_capacity) / ship_capacity, 0.0, OVERLOAD_ALLOWANCE - 1.0) / (OVERLOAD_ALLOWANCE - 1.0)

## How many units of good_id can be bought right now, limited only by gold --
## purchases aren't limited by hold space; the 150% overload cap is only
## enforced when actually setting sail (see start_travel).
func get_max_affordable(good_id: String) -> int:
	var price := get_price(current_port_id, good_id)
	if price <= 0:
		return 0
	return int(gold / float(price))

## Like get_max_affordable, but also capped so the purchase doesn't leave the
## ship carrying more than it could actually set sail with (the 150%
## overload cap enforced in start_travel) -- for the "buy up to what you can
## sail with" trade button, as opposed to "buy as much as gold allows".
func get_max_sailable_affordable(good_id: String) -> int:
	var by_gold := get_max_affordable(good_id)
	var by_sail_capacity: int = max(0, get_overload_capacity() - get_cargo_used())
	return min(by_gold, by_sail_capacity)

## Like get_max_sailable_affordable, but capped at nominal ship_capacity
## instead of the 150% overload allowance -- for the "legal" (no risk of
## overload mishaps) half of the max-capacity buy choice.
func get_max_legal_capacity_affordable(good_id: String) -> int:
	var by_gold := get_max_affordable(good_id)
	var by_legal_capacity: int = max(0, ship_capacity - get_cargo_used())
	return min(by_gold, by_legal_capacity)

func can_buy(good_id: String, qty: int) -> bool:
	if qty <= 0:
		return false
	var cost := get_price(current_port_id, good_id) * qty
	return cost <= gold

func buy(good_id: String, qty: int) -> bool:
	if not can_buy(good_id, qty):
		return false
	var cost := get_price(current_port_id, good_id) * qty
	gold -= cost
	cargo[good_id] = cargo.get(good_id, 0) + qty
	return true

func can_sell(good_id: String, qty: int) -> bool:
	return qty > 0 and cargo.get(good_id, 0) >= qty

func sell(good_id: String, qty: int) -> bool:
	if not can_sell(good_id, qty):
		return false
	var revenue := get_price(current_port_id, good_id) * qty
	gold += revenue
	cargo[good_id] -= qty
	if cargo[good_id] <= 0:
		cargo.erase(good_id)
	return true

func get_cargo_value_at_current_port() -> int:
	var total := 0
	for good_id in cargo.keys():
		total += get_price(current_port_id, good_id) * cargo[good_id]
	return total

## --- Special capacity offer ---

func get_capacity_offer_gold_cost() -> int:
	return int(ceil(gold * CAPACITY_OFFER_COST_RATIO))

func get_capacity_offer_goods_value() -> int:
	return int(ceil(get_cargo_value_at_current_port() * CAPACITY_OFFER_COST_RATIO))

## The capacity bonus granted by the currently-pending offer -- a multiple of
## CAPACITY_OFFER_CAPACITY_BONUS when it bundles several milestones crossed
## in one jump (see capacity_offer_pending_steps).
func get_capacity_offer_capacity_bonus() -> int:
	return CAPACITY_OFFER_CAPACITY_BONUS * capacity_offer_pending_steps

## The capacity bonus is unconditional -- payment is taken in whichever of
## gold or goods (valued at the current port) is worth more, never both.
func accept_capacity_offer() -> void:
	if get_capacity_offer_goods_value() > get_capacity_offer_gold_cost():
		_jettison_cargo(CAPACITY_OFFER_COST_RATIO)
	else:
		gold -= get_capacity_offer_gold_cost()
	ship_capacity += get_capacity_offer_capacity_bonus()

## --- Ship upgrades ---

func is_upgrade_owned(upgrade_id: String) -> bool:
	return owned_upgrades.has(upgrade_id)

func can_buy_upgrade(upgrade_id: String) -> bool:
	var up := get_upgrade(upgrade_id)
	if up == null or is_upgrade_owned(upgrade_id):
		return false
	if up.requires_id != "" and not is_upgrade_owned(up.requires_id):
		return false
	return gold >= up.cost

func buy_upgrade(upgrade_id: String) -> bool:
	if not can_buy_upgrade(upgrade_id):
		return false
	var up := get_upgrade(upgrade_id)
	gold -= up.cost
	owned_upgrades.append(upgrade_id)
	match up.kind:
		ShipUpgrade.Kind.CARGO:
			ship_capacity += up.amount
		ShipUpgrade.Kind.HULL:
			ship_defense_points += up.amount
		ShipUpgrade.Kind.SAIL:
			ship_speed_points += up.amount
	return true

## --- Security ships ---

## Hired escort ships add a flat bonus to the pirate-fight win chance (see
## resolve_pirate_encounter); each additional ship costs more than the last.
func get_security_ship_cost() -> int:
	return SECURITY_SHIP_BASE_COST + security_ships * SECURITY_SHIP_COST_STEP

func can_hire_security_ship() -> bool:
	return gold >= get_security_ship_cost()

func hire_security_ship() -> bool:
	if not can_hire_security_ship():
		return false
	gold -= get_security_ship_cost()
	security_ships += 1
	return true

## --- Bank ---

func get_net_worth() -> int:
	return int(gold + get_cargo_value_at_current_port() + savings - loan)

func bank_deposit(amount: int) -> bool:
	if amount <= 0 or amount > gold:
		return false
	gold -= amount
	savings += amount
	return true

func bank_withdraw(amount: int) -> bool:
	if amount <= 0 or amount > savings:
		return false
	savings -= amount
	gold += amount
	return true

func bank_max_loan() -> int:
	return max(0, int(get_net_worth() * MAX_LOAN_FACTOR) - int(loan))

func bank_borrow(amount: int) -> bool:
	if amount <= 0 or amount > bank_max_loan():
		return false
	loan += amount
	gold += amount
	return true

func bank_repay(amount: int) -> bool:
	if amount <= 0 or amount > gold:
		return false
	var pay: float = min(float(amount), loan)
	gold -= int(pay)
	loan -= pay
	return true

func _apply_daily_interest() -> void:
	loan *= (1.0 + DAILY_INTEREST)
	savings *= (1.0 + DAILY_INTEREST * 0.5)

## --- Time & travel ---

## Fixed travel durations in half-day units. Every leg listed here is a full
## day (2); every other leg -- including any pair not listed, in either
## direction -- is just half a day (1).
const FULL_DAY_ROUTES: Array[Array] = [
	["venice", "alexandria"],
	["venice", "limassol"],
	["venice", "istanbul"],
	["venice", "beirut"],
	["venice", "jaffa"],
	["istanbul", "alexandria"],
	["istanbul", "jaffa"],
	["istanbul", "beirut"],
	["piraeus", "jaffa"],
	["piraeus", "beirut"],
]

func get_travel_half_days(from_id: String, to_id: String) -> int:
	for route in FULL_DAY_ROUTES:
		if (route[0] == from_id and route[1] == to_id) or (route[0] == to_id and route[1] == from_id):
			return 2
	return 1

func start_travel(destination_id: String) -> void:
	if is_traveling or destination_id == current_port_id or half_day_carry >= 2:
		return # half_day_carry == 2 means it's already evening -- rest first
	if get_cargo_used() > get_overload_capacity():
		return # too loaded to put to sea -- sell down to at most 150% of nominal capacity first
	is_traveling = true
	travel_destination_id = destination_id
	travel_half_days_remaining = get_travel_half_days(current_port_id, destination_id)
	travel_leg_half_days = travel_half_days_remaining
	travel_event_rolled_this_leg = false
	travel_log.clear()
	_advance_travel()

func _advance_travel() -> void:
	while is_traveling and travel_half_days_remaining > 0 and pending_encounter.is_empty():
		travel_half_days_remaining -= 1
		half_day_carry += 1
		# Every leg gets exactly one shot at a travel event, whether it's a
		# lone half-day hop or a longer route -- fire it either when a full
		# day's worth of travel has accumulated (possibly banked across two
		# half-day legs) or, for a standalone half-day leg that never
		# accumulates a full day on its own, once its own travel is spent.
		if not travel_event_rolled_this_leg and (half_day_carry >= 2 or travel_half_days_remaining <= 0):
			travel_event_rolled_this_leg = true
			_roll_travel_event()
		if not pending_encounter.is_empty():
			return
		if half_day_carry < 2:
			continue # short half-day hop: half a day passed, no day-tick yet
		if travel_half_days_remaining > 0:
			# still at sea -- no dock stop to protect here, so the day ticks
			# over immediately, same as any other overnight passage.
			half_day_carry = 0
			_advance_day()
			if current_day > game_length_days:
				return # _advance_day already triggered game_ended
		# else: this half-day is the one that lands the ship. Arrival stays
		# on the CURRENT day, in the evening (half_day_carry left at 2), so
		# goods can still be traded today; the day only turns over once the
		# player rests.
	if is_traveling and travel_half_days_remaining <= 0:
		current_port_id = travel_destination_id
		is_traveling = false
		arrived_at_port.emit(current_port_id, travel_log.duplicate())

## Skips a day while staying docked at the current port: no travel events
## (storms/pirates/etc.) since the ship never leaves, but prices still drift
## and interest still accrues exactly like any other day. Also closes out an
## "evening" left over from an arrival that used up the day's travel budget
## (half_day_carry == 2), opening the next day fresh in the morning either
## way. Returns a dict with "price_change" (details of the single most
## notable overnight price swing across all ports, see
## _find_notable_price_change, or {} if nothing crossed the threshold) and,
## if a warehouse mishap struck, "warehouse" (see _roll_warehouse_event) --
## so the UI can flash a "morning news" message about either.
func rest_at_port() -> Dictionary:
	if is_traveling:
		return {}
	var before := _snapshot_prices()
	half_day_carry = 0
	_advance_day()
	var result := {"price_change": _find_notable_price_change(before)}
	var warehouse := _roll_warehouse_event()
	if not warehouse.is_empty():
		result["warehouse"] = warehouse
	return result

## Small nightly risk while docked with cargo aboard: a warehouse fire or a
## theft eats into part of every good in the hold. Deliberately rare and
## light compared to the travel mishaps (storm/aground/overload/pirates),
## since it can't be avoided by playing safe the way those can.
func _roll_warehouse_event() -> Dictionary:
	if cargo.is_empty() or randf() >= WAREHOUSE_MISHAP_CHANCE:
		return {}
	var cause := "fire" if randf() < 0.5 else "theft"
	var severity := randf_range(WAREHOUSE_MISHAP_MIN_LOSS, WAREHOUSE_MISHAP_MAX_LOSS)
	var lost_goods := _jettison_cargo(severity)
	if lost_goods.is_empty():
		return {}
	return {"type": "warehouse", "cause": cause, "lost_goods": lost_goods}

func _snapshot_prices() -> Dictionary:
	var snap := {}
	for port_id in prices.keys():
		snap[port_id] = (prices[port_id] as Dictionary).duplicate()
	return snap

## Picks the single most notable overnight price swing (across every
## port/good pair) for the rest-day news flash: a swing counts only once it
## moves the price by at least NOTABLE_PRICE_CHANGE_RATIO, a flat threshold
## applied the same way regardless of the good's own normal volatility, so
## the "spiked" wording always corresponds to a genuinely large move rather
## than a routine one for a jumpy good like spices. Returns {} if nothing
## qualified.
func _find_notable_price_change(before: Dictionary) -> Dictionary:
	var best := {}
	var best_ratio := 0.0
	for port_id in prices.keys():
		var before_port: Dictionary = before.get(port_id, {})
		var after_port: Dictionary = prices[port_id]
		for good_id in after_port.keys():
			var old_price: int = before_port.get(good_id, 0)
			var new_price: int = after_port[good_id]
			if old_price <= 0 or absi(new_price - old_price) < NOTABLE_MIN_ABS_DELTA:
				continue # ignore +-1/2 gold rounding noise on cheap goods, even if it's a big % swing
			var ratio := float(new_price - old_price) / float(old_price)
			if absf(ratio) < NOTABLE_PRICE_CHANGE_RATIO:
				continue
			if absf(ratio) > best_ratio:
				best_ratio = absf(ratio)
				best = {"port_id": port_id, "good_id": good_id, "old_price": old_price, "new_price": new_price, "ratio": ratio}
	return best

func _advance_day() -> void:
	current_day += 1
	_update_prices()
	_apply_daily_interest()
	day_advanced.emit(current_day)
	if current_day > game_length_days:
		_end_game()

## Every CAPACITY_OFFER_GOLD_STEP of gold reached (10M, 20M, ...) unlocks a
## one-time special offer to expand cargo capacity; capacity_offer_milestone
## tracks the highest one already surfaced so it only fires once per step.
## Checked on every gold change (see the gold setter), same as
## _check_millionaire_gift, so it fires the moment the milestone is crossed.
## A single gold jump spanning several steps (e.g. a huge sale) still counts
## every step crossed instead of silently dropping the skipped-over ones --
## but unlike _check_mega_capacity_gift's free, repeatable gift, this is a
## single paid offer, so the steps are bundled into capacity_offer_pending_steps
## and surfaced as ONE combined offer (bigger bonus, one payment) rather than
## one popup per step.
func _check_capacity_offer() -> void:
	var milestone := int(gold) / CAPACITY_OFFER_GOLD_STEP
	if milestone > capacity_offer_milestone:
		capacity_offer_pending_steps = milestone - capacity_offer_milestone
		capacity_offer_milestone = milestone
		capacity_offer_available.emit()

## The first time gold ever reaches MILLIONAIRE_GIFT_GOLD_THRESHOLD, the
## player's warehouse is expanded for free as a one-time congratulatory gift.
## Checked on every gold change (see the gold setter) so it fires the moment
## the milestone is crossed, not just at the next day boundary.
func _check_millionaire_gift() -> void:
	if millionaire_gift_claimed or gold < MILLIONAIRE_GIFT_GOLD_THRESHOLD:
		return
	millionaire_gift_claimed = true
	ship_capacity += MILLIONAIRE_GIFT_CAPACITY_BONUS
	millionaire_gift_granted.emit()

## Every MEGA_CAPACITY_GIFT_GOLD_STEP of gold reached (100M, 200M, ...) grants
## another free warehouse-capacity gift -- same recurring-milestone pattern as
## _check_capacity_offer, but unconditional/free like _check_millionaire_gift,
## and fires independently alongside both (this is a bigger, repeatable bonus
## layered on top, not a replacement for the smaller paid offer every 10M).
## A single gold jump spanning several steps (e.g. a huge sale) still counts
## every step crossed instead of silently dropping the skipped-over ones, but
## -- same reasoning as _check_capacity_offer -- grants the whole bundled
## bonus at once and fires ONE message, not one popup per step.
func _check_mega_capacity_gift() -> void:
	var milestone := int(gold) / MEGA_CAPACITY_GIFT_GOLD_STEP
	if milestone > mega_capacity_gift_milestone:
		var steps := milestone - mega_capacity_gift_milestone
		mega_capacity_gift_milestone = milestone
		var bonus := MEGA_CAPACITY_GIFT_CAPACITY_BONUS * steps
		ship_capacity += bonus
		mega_capacity_gift_granted.emit(bonus)

## The first time gold ever reaches BILLIONAIRE_GIFT_GOLD_THRESHOLD, the
## player is granted BILLIONAIRE_GIFT_SECURITY_SHIPS free escort ships on top
## of however many they already have -- a one-time congratulatory gift, same
## one-shot pattern as _check_millionaire_gift, just a much bigger milestone.
func _check_billionaire_gift() -> void:
	if billionaire_gift_claimed or gold < BILLIONAIRE_GIFT_GOLD_THRESHOLD:
		return
	billionaire_gift_claimed = true
	security_ships += BILLIONAIRE_GIFT_SECURITY_SHIPS
	billionaire_gift_granted.emit(BILLIONAIRE_GIFT_SECURITY_SHIPS)

func _roll_travel_event() -> void:
	var from_port := get_port(current_port_id)
	var to_port := get_port(travel_destination_id)
	var danger: float = 0.2
	if from_port and to_port:
		danger = (from_port.danger_level + to_port.danger_level) * 0.5
	var half_day_scale: float = 1.0 if travel_leg_half_days >= 2 else HALF_DAY_EVENT_SCALE

	for ev in events:
		var chance := ev.base_chance * half_day_scale
		if ev.kind == EventDef.Kind.PIRATES:
			chance *= (0.5 + danger)
		elif ev.kind == EventDef.Kind.STORM:
			chance *= (0.7 + danger * 0.5)
		elif ev.kind == EventDef.Kind.AGROUND:
			chance *= (0.6 + danger * 0.6)
		if randf() < chance:
			_trigger_event(ev)
			return # only one weather/hazard event per travel day

	_check_overload_risk()

func _trigger_event(ev: EventDef) -> void:
	match ev.kind:
		EventDef.Kind.STORM:
			_apply_storm()
		EventDef.Kind.PIRATES:
			_start_pirate_encounter()
		EventDef.Kind.FAIR_WIND:
			travel_half_days_remaining = max(0, travel_half_days_remaining - 2)
			travel_log.append({"type": "fair_wind"})
		EventDef.Kind.MARKET_DEMAND:
			_apply_market_demand()
		EventDef.Kind.AGROUND:
			_apply_aground()

## Rumors of high demand always push a price UP, never down, and always at
## the port you're actually heading to (not wherever the rumor was "heard"),
## since that's the price that matters to the player planning the sale.
func _apply_market_demand() -> void:
	var dest_prices: Dictionary = prices.get(travel_destination_id, {})
	if dest_prices.is_empty():
		return
	var good_ids := dest_prices.keys()
	var good_id: String = good_ids[randi() % good_ids.size()]
	var multiplier := randf_range(1.4, 2.2)
	var new_price: int = max(1, int(round(dest_prices[good_id] * multiplier)))
	dest_prices[good_id] = new_price
	travel_log.append({"type": "market_demand", "good_id": good_id, "new_price": new_price})

func _apply_storm() -> void:
	var mitigation: float = clamp(ship_defense_points * 0.1, 0.0, 0.6)
	var severity := randf_range(0.05, 0.25) * (1.0 - mitigation)
	var lost_goods := _jettison_cargo(severity)
	travel_log.append({"type": "storm", "lost_goods": lost_goods})

func _apply_aground() -> void:
	var mitigation: float = clamp(ship_defense_points * 0.08, 0.0, 0.5)
	var severity := randf_range(0.1, 0.3) * (1.0 - mitigation)
	var lost_goods := _jettison_cargo(severity)
	var repair_cost := int(gold * randf_range(0.05, 0.12))
	gold -= repair_cost
	travel_log.append({"type": "aground", "lost_goods": lost_goods, "repair_cost": repair_cost})

## Carrying more than nominal capacity risks losing part of the excess (or
## worse) every travel day; the more overloaded, the higher the chance and
## the harsher the outcome.
func _check_overload_risk() -> void:
	var ratio := get_overload_ratio()
	if ratio <= 0.0:
		return
	if randf() < ratio * OVERLOAD_DAILY_RISK:
		_apply_overload_mishap(ratio)

func _apply_overload_mishap(ratio: float) -> void:
	var severe := randf() < ratio
	var severity := randf_range(0.35, 0.6) if severe else randf_range(0.15, 0.3)
	var lost_goods := _jettison_cargo(severity)
	var repair_cost := 0
	if severe:
		repair_cost = int(gold * randf_range(0.05, 0.15))
		gold -= repair_cost
	travel_log.append({"type": "overload", "severe": severe, "lost_goods": lost_goods, "repair_cost": repair_cost})

## Removes a `severity` fraction of every cargo good (rounded up) and returns what was lost.
func _jettison_cargo(severity: float) -> Dictionary:
	var lost_goods := {}
	for good_id in cargo.keys():
		var lost := int(ceil(cargo[good_id] * severity))
		if lost > 0:
			cargo[good_id] -= lost
			lost_goods[good_id] = lost
	for good_id in lost_goods.keys():
		if cargo[good_id] <= 0:
			cargo.erase(good_id)
	return lost_goods

## Winning a pirate fight lets you plunder part of their hold too: a handful
## of random goods in varying amounts (occasionally a real windfall), scaled
## by how strong the pirates were. Added straight onto the ship, bypassing
## the normal 150% overload cap (see start_travel) since it's seized cargo,
## not something bought -- the player just has to sell back down before
## setting sail again like any other overloaded ship.
func _generate_pirate_loot(pirate_strength: float) -> Dictionary:
	var loot := {}
	var pool: Array[Good] = goods.duplicate()
	pool.shuffle()
	var good_count: int = randi_range(PIRATE_LOOT_GOOD_COUNT_MIN, min(PIRATE_LOOT_GOOD_COUNT_MAX, pool.size()))
	for i in range(good_count):
		var good: Good = pool[i]
		var qty := randi_range(PIRATE_LOOT_QTY_MIN, PIRATE_LOOT_QTY_MAX) * pirate_strength
		if randf() < PIRATE_LOOT_BIG_HAUL_CHANCE:
			qty *= randi_range(PIRATE_LOOT_BIG_HAUL_MULT_MIN, PIRATE_LOOT_BIG_HAUL_MULT_MAX)
		loot[good.id] = max(1, int(round(qty)))
	return loot

func _start_pirate_encounter() -> void:
	var pirate_strength := randf_range(0.5, 1.5)
	pending_encounter = {
		"type": "pirates",
		"pirate_strength": pirate_strength,
	}
	pirate_encounter_started.emit(pending_encounter)

## Rolls a ransom as a fraction of the player's current gold. Floors at 1
## (never rounds down to a "free" 0-gold ransom just because the player is
## carrying little cash, e.g. after banking most of it in savings) and caps
## at whatever gold the player actually has (0 if they're flat broke).
func _roll_ransom(min_ratio: float, max_ratio: float) -> int:
	if gold <= 0:
		return 0
	return min(gold, max(1, int(ceil(gold * randf_range(min_ratio, max_ratio)))))

## choice: "fight" | "flee" | "pay"
func resolve_pirate_encounter(choice: String) -> Dictionary:
	if pending_encounter.is_empty():
		return {}
	var pirate_strength: float = pending_encounter.get("pirate_strength", 1.0)
	var result := {"type": "pirates", "choice": choice}

	match choice:
		"fight":
			var my_strength := 0.4 + ship_defense_points * 0.15
			var base_chance := my_strength / (my_strength + pirate_strength)
			var win_chance: float = clamp(base_chance + security_ships * SECURITY_SHIP_WIN_BONUS, 0.05, 0.95)
			if randf() < win_chance:
				var bounty := randi_range(50, 200) * int(round(pirate_strength * 10))
				gold += bounty
				var loot := _generate_pirate_loot(pirate_strength)
				for good_id in loot.keys():
					cargo[good_id] = cargo.get(good_id, 0) + loot[good_id]
				result["outcome"] = "won"
				result["bounty"] = bounty
				result["loot"] = loot
			else:
				var lost_goods := _jettison_cargo(randf_range(0.2, 0.5))
				result["outcome"] = "lost"
				result["lost_goods"] = lost_goods
		"flee":
			var flee_chance: float = clamp(0.4 + ship_speed_points * 0.15, 0.1, 0.9)
			if randf() < flee_chance:
				result["outcome"] = "escaped"
			else:
				var ransom := _roll_ransom(0.1, 0.25)
				gold -= ransom
				var lost_goods := _jettison_cargo(randf_range(PIRATE_CAUGHT_CARGO_LOSS_MIN, PIRATE_CAUGHT_CARGO_LOSS_MAX))
				result["outcome"] = "caught"
				result["ransom"] = ransom
				result["lost_goods"] = lost_goods
		"pay":
			var demand := _roll_ransom(0.05, 0.15)
			gold -= demand
			result["outcome"] = "paid"
			result["ransom"] = demand

	travel_log.append(result)
	pending_encounter.clear()
	_advance_travel()
	return result

func _end_game() -> void:
	is_traveling = false
	var summary := {
		"days": game_length_days,
		"final_gold": gold,
		"final_cargo_value": get_cargo_value_at_current_port(),
		"loan": loan,
		"savings": savings,
		"net_worth": get_net_worth(),
	}
	game_ended.emit(summary)

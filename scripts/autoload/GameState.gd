extends Node
## Central game state and economy simulation. Autoloaded as "GameState".

signal day_advanced(day: int)
signal arrived_at_port(port_id: String, log: Array)
signal pirate_encounter_started(details: Dictionary)
signal game_ended(summary: Dictionary)

const STARTING_GOLD := 500
const STARTING_CAPACITY := 50
const STARTING_SPEED_POINTS := 0
const STARTING_DEFENSE_POINTS := 0
const MAX_LOAN_FACTOR := 2.0 # can borrow up to 2x current net worth
const DAILY_INTEREST := 0.02
const OVERLOAD_ALLOWANCE := 1.5 # can risk-load up to 150% of nominal capacity
const OVERLOAD_DAILY_RISK := 0.5 # scaled by how far over nominal capacity you are

## Piraeus and Venice sit at the far corners of the trade map; direct voyages
## to/from them are blocked unless one of these hub ports is the other end
## of the leg (i.e. they must be used as a stopover first).
const HUB_PORTS: Array[String] = ["limassol", "istanbul", "alexandria"]
const FAR_PORTS: Array[String] = ["piraeus", "venice"]

var goods: Array[Good] = []
var ports: Array[Port] = []
var upgrades: Array[ShipUpgrade] = []
var events: Array[EventDef] = []

var game_length_days: int = 21
var current_day: int = 1
var gold: int = STARTING_GOLD
var current_port_id: String = ""
var cargo: Dictionary = {} # good_id -> int quantity
var ship_capacity: int = STARTING_CAPACITY
var ship_speed_points: int = STARTING_SPEED_POINTS
var ship_defense_points: int = STARTING_DEFENSE_POINTS
var owned_upgrades: Array[String] = []
var loan: float = 0.0
var savings: float = 0.0

var prices: Dictionary = {} # port_id -> { good_id -> int price }

var is_traveling: bool = false
var travel_destination_id: String = ""
var travel_half_days_remaining: int = 0
## Half-a-day legs (any Limassol connection except Limassol<->Venice) don't
## trigger a full day-tick (price update/interest/event roll) on their own;
## this banks the odd half-day so two short hops in a row still add up to a
## real day instead of time silently vanishing.
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
		"res://data/ports/alexandria.tres",
		"res://data/ports/istanbul.tres",
		"res://data/ports/limassol.tres",
		"res://data/ports/piraeus.tres",
		"res://data/ports/beirut.tres",
		"res://data/ports/venice.tres",
	]:
		ports.append(load(path) as Port)

	upgrades.clear()
	for path in [
		"res://data/upgrades/cargo1.tres",
		"res://data/upgrades/cargo2.tres",
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
	owned_upgrades.clear()
	loan = 0.0
	savings = 0.0
	is_traveling = false
	travel_destination_id = ""
	travel_half_days_remaining = 0
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

## Applies a random day-to-day walk to every port/good price, biased back toward the base price.
func _update_prices() -> void:
	for port in ports:
		var port_prices: Dictionary = prices[port.id]
		for good in goods:
			var mod: float = port.price_modifiers.get(good.id, 1.0)
			var anchor: float = good.base_price * mod
			var current: float = port_prices[good.id]
			var pulled: float = lerp(current, anchor, 0.15)
			port_prices[good.id] = _jitter_price(pulled, good.volatility)

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

## How many units of good_id can be bought right now, limited by both gold and remaining hold space.
func get_max_affordable(good_id: String) -> int:
	var price := get_price(current_port_id, good_id)
	if price <= 0:
		return 0
	var by_gold := int(gold / float(price))
	var by_space := get_overload_capacity() - get_cargo_used()
	return max(0, min(by_gold, by_space))

func can_buy(good_id: String, qty: int) -> bool:
	if qty <= 0:
		return false
	if get_cargo_used() + qty > get_overload_capacity():
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

## Fixed travel durations in half-day units (so Limassol's short in-between
## hops can be modeled precisely): a "regular" direct leg is a full day (2),
## a "far" leg to/from Piraeus/Venice is two days (4), and any leg touching
## Limassol is just half a day (1) -- except Limassol<->Venice, which is a
## full day (2) like a regular leg despite Venice being a far port.
func get_travel_half_days(from_id: String, to_id: String) -> int:
	if from_id == "limassol" or to_id == "limassol":
		var other := to_id if from_id == "limassol" else from_id
		return 2 if other == "venice" else 1
	if FAR_PORTS.has(from_id) or FAR_PORTS.has(to_id):
		return 4
	return 2

## Direct travel is disallowed between a far port (Piraeus/Venice) and
## anything other than a hub port (Limassol/Istanbul/Alexandria) — including
## between the two far ports themselves. A hub port on either end always
## satisfies the required stopover.
func can_travel_directly(from_id: String, to_id: String) -> bool:
	if FAR_PORTS.has(from_id) and not HUB_PORTS.has(to_id):
		return false
	if FAR_PORTS.has(to_id) and not HUB_PORTS.has(from_id):
		return false
	return true

func start_travel(destination_id: String) -> void:
	if is_traveling or destination_id == current_port_id:
		return
	if not can_travel_directly(current_port_id, destination_id):
		return
	is_traveling = true
	travel_destination_id = destination_id
	travel_half_days_remaining = get_travel_half_days(current_port_id, destination_id)
	travel_log.clear()
	_advance_travel()

func _advance_travel() -> void:
	while is_traveling and travel_half_days_remaining > 0 and pending_encounter.is_empty():
		travel_half_days_remaining -= 1
		half_day_carry += 1
		if half_day_carry < 2:
			continue # short Limassol hop: half a day passed, no day-tick yet
		half_day_carry = 0
		_advance_day()
		if current_day > game_length_days:
			return # _advance_day already triggered game_ended
		_roll_travel_event()
		if not pending_encounter.is_empty():
			return
	if is_traveling and travel_half_days_remaining <= 0:
		current_port_id = travel_destination_id
		is_traveling = false
		arrived_at_port.emit(current_port_id, travel_log.duplicate())

func _advance_day() -> void:
	current_day += 1
	_update_prices()
	_apply_daily_interest()
	day_advanced.emit(current_day)
	if current_day > game_length_days:
		_end_game()

func _roll_travel_event() -> void:
	var from_port := get_port(current_port_id)
	var to_port := get_port(travel_destination_id)
	var danger: float = 0.2
	if from_port and to_port:
		danger = (from_port.danger_level + to_port.danger_level) * 0.5

	for ev in events:
		var chance := ev.base_chance
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
			travel_log.append({"type": "market_demand"})
		EventDef.Kind.AGROUND:
			_apply_aground()

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

func _start_pirate_encounter() -> void:
	var pirate_strength := randf_range(0.5, 1.5)
	pending_encounter = {
		"type": "pirates",
		"pirate_strength": pirate_strength,
	}
	pirate_encounter_started.emit(pending_encounter)

## choice: "fight" | "flee" | "pay"
func resolve_pirate_encounter(choice: String) -> Dictionary:
	if pending_encounter.is_empty():
		return {}
	var pirate_strength: float = pending_encounter.get("pirate_strength", 1.0)
	var result := {"type": "pirates", "choice": choice}

	match choice:
		"fight":
			var my_strength := 0.4 + ship_defense_points * 0.15
			if randf() < clamp(my_strength / (my_strength + pirate_strength), 0.05, 0.95):
				var bounty := randi_range(50, 200) * int(round(pirate_strength * 10))
				gold += bounty
				result["outcome"] = "won"
				result["bounty"] = bounty
			else:
				var lost_goods := _jettison_cargo(randf_range(0.2, 0.5))
				result["outcome"] = "lost"
				result["lost_goods"] = lost_goods
		"flee":
			var flee_chance: float = clamp(0.4 + ship_speed_points * 0.15, 0.1, 0.9)
			if randf() < flee_chance:
				result["outcome"] = "escaped"
			else:
				var ransom := int(gold * randf_range(0.1, 0.25))
				gold -= ransom
				result["outcome"] = "caught"
				result["ransom"] = ransom
		"pay":
			var demand := int(gold * randf_range(0.05, 0.15))
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

extends RefCounted
class_name PlayerState
## Per-player runtime state (ship, wallet, position, travel). GameState holds
## an Array[PlayerState] and exposes the "active" one (players[current_player_index])
## through proxy properties, so most existing code that reads e.g. GameState.gold
## keeps working unchanged -- see GameState.gd's proxy property block.

var player_name: String = ""

var gold: int = 0
var current_port_id: String = ""
var cargo: Dictionary = {} # good_id -> int quantity
var ship_capacity: int = 0
var ship_speed_points: int = 0
var ship_defense_points: int = 0
var security_ships: int = 0
var owned_upgrades: Array[String] = []
var loan: float = 0.0
var savings: float = 0.0

var capacity_offer_milestone: int = 0
var capacity_offer_pending_steps: int = 1
var millionaire_gift_claimed: bool = false
var mega_capacity_gift_milestone: int = 0
var billionaire_gift_claimed: bool = false

var is_traveling: bool = false
var travel_destination_id: String = ""
var travel_half_days_remaining: int = 0
var travel_event_rolled_this_leg: bool = false
var travel_leg_half_days: int = 0
var half_day_carry: int = 0
var travel_log: Array = []
var pending_encounter: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"player_name": player_name,
		"gold": gold,
		"current_port_id": current_port_id,
		"cargo": cargo,
		"ship_capacity": ship_capacity,
		"ship_speed_points": ship_speed_points,
		"ship_defense_points": ship_defense_points,
		"security_ships": security_ships,
		"owned_upgrades": owned_upgrades,
		"loan": loan,
		"savings": savings,
		"capacity_offer_milestone": capacity_offer_milestone,
		"millionaire_gift_claimed": millionaire_gift_claimed,
		"mega_capacity_gift_milestone": mega_capacity_gift_milestone,
		"billionaire_gift_claimed": billionaire_gift_claimed,
	}

static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.player_name = String(d.get("player_name", ""))
	p.gold = d.get("gold", 0)
	p.current_port_id = d.get("current_port_id", "jaffa")
	p.cargo = d.get("cargo", {})
	p.ship_capacity = d.get("ship_capacity", 0)
	p.ship_speed_points = d.get("ship_speed_points", 0)
	p.ship_defense_points = d.get("ship_defense_points", 0)
	p.security_ships = d.get("security_ships", 0)
	var owned: Array[String] = []
	for u in d.get("owned_upgrades", []):
		owned.append(String(u))
	p.owned_upgrades = owned
	p.loan = d.get("loan", 0.0)
	p.savings = d.get("savings", 0.0)
	p.capacity_offer_milestone = d.get("capacity_offer_milestone", 0)
	p.millionaire_gift_claimed = d.get("millionaire_gift_claimed", false)
	p.mega_capacity_gift_milestone = d.get("mega_capacity_gift_milestone", 0)
	p.billionaire_gift_claimed = d.get("billionaire_gift_claimed", false)
	# Travel state is never persisted mid-flight (same as today's pending_encounter
	# handling) -- a loaded game always resumes docked.
	p.is_traveling = false
	return p

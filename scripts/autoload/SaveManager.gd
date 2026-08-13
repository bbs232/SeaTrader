extends Node
## Local save game + high score persistence. Autoloaded as "SaveManager".

const SAVE_PATH := "user://savegame.json"
const HIGHSCORES_PATH := "user://highscores.json"
const MAX_HIGHSCORES := 10

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var data := {
		"game_length_days": GameState.game_length_days,
		"current_day": GameState.current_day,
		"gold": GameState.gold,
		"current_port_id": GameState.current_port_id,
		"cargo": GameState.cargo,
		"ship_capacity": GameState.ship_capacity,
		"ship_speed_points": GameState.ship_speed_points,
		"ship_defense_points": GameState.ship_defense_points,
		"security_ships": GameState.security_ships,
		"owned_upgrades": GameState.owned_upgrades,
		"loan": GameState.loan,
		"savings": GameState.savings,
		"prices": GameState.prices,
		"capacity_offer_milestone": GameState.capacity_offer_milestone,
		"millionaire_gift_claimed": GameState.millionaire_gift_claimed,
		"mega_capacity_gift_milestone": GameState.mega_capacity_gift_milestone,
		"billionaire_gift_claimed": GameState.billionaire_gift_claimed,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	GameState._load_definitions()
	GameState.game_length_days = parsed.get("game_length_days", 21)
	GameState.current_day = parsed.get("current_day", 1)
	GameState.millionaire_gift_claimed = parsed.get("millionaire_gift_claimed", false)
	GameState.billionaire_gift_claimed = parsed.get("billionaire_gift_claimed", false)
	GameState.gold = parsed.get("gold", GameState.STARTING_GOLD)
	GameState.current_port_id = parsed.get("current_port_id", "jaffa")
	GameState.cargo = parsed.get("cargo", {})
	GameState.ship_capacity = parsed.get("ship_capacity", GameState.STARTING_CAPACITY)
	GameState.ship_speed_points = parsed.get("ship_speed_points", 0)
	GameState.ship_defense_points = parsed.get("ship_defense_points", 0)
	GameState.security_ships = parsed.get("security_ships", 0)
	var owned: Array[String] = []
	for u in parsed.get("owned_upgrades", []):
		owned.append(String(u))
	GameState.owned_upgrades = owned
	GameState.loan = parsed.get("loan", 0.0)
	GameState.savings = parsed.get("savings", 0.0)
	GameState.prices = parsed.get("prices", {})
	GameState.capacity_offer_milestone = parsed.get("capacity_offer_milestone", 0)
	GameState.mega_capacity_gift_milestone = parsed.get("mega_capacity_gift_milestone", 0)
	GameState.is_traveling = false
	GameState.pending_encounter.clear()
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func get_highscores() -> Array:
	if not FileAccess.file_exists(HIGHSCORES_PATH):
		return []
	var file := FileAccess.open(HIGHSCORES_PATH, FileAccess.READ)
	if not file:
		return []
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed

## Saves the score and returns its 1-based rank in the (post-save) top-10
## list, or -1 if it didn't place high enough to make the cut.
func add_highscore(player_name: String, net_worth: int) -> int:
	var scores := get_highscores()
	var entry := {
		"name": player_name,
		"net_worth": net_worth,
		"days": GameState.game_length_days,
		"date": Time.get_date_string_from_system() + " " + Time.get_time_string_from_system().substr(0, 5),
	}
	scores.append(entry)
	scores.sort_custom(func(a, b): return a["net_worth"] > b["net_worth"])
	var rank := scores.find(entry) + 1
	if scores.size() > MAX_HIGHSCORES:
		scores.resize(MAX_HIGHSCORES)
	var file := FileAccess.open(HIGHSCORES_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scores))
		file.close()
	return rank if rank <= MAX_HIGHSCORES else -1

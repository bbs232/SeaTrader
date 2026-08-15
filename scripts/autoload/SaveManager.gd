extends Node
## Local save game + high score persistence. Autoloaded as "SaveManager".

const SAVE_PATH := "user://savegame.json"
const HIGHSCORES_PATH := "user://highscores.json"
const MAX_HIGHSCORES := 10

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var player_dicts := []
	for p in GameState.players:
		player_dicts.append(p.to_dict())
	var data := {
		"game_length_days": GameState.game_length_days,
		"current_day": GameState.current_day,
		"prices": GameState.prices,
		"player_count": GameState.player_count,
		"current_player_index": GameState.current_player_index,
		"players": player_dicts,
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
	GameState.prices = parsed.get("prices", {})

	if parsed.has("players"):
		# Current (multiplayer-capable) save format.
		var players: Array[PlayerState] = []
		for pd in parsed.get("players", []):
			players.append(PlayerState.from_dict(pd))
		GameState.players = players
		GameState.player_count = parsed.get("player_count", players.size())
		GameState.current_player_index = parsed.get("current_player_index", 0)
	else:
		# Legacy single-player save (flat fields) -- migrate into a single
		# PlayerState so old saves keep loading correctly.
		var legacy := {
			"gold": parsed.get("gold", GameState.STARTING_GOLD),
			"current_port_id": parsed.get("current_port_id", "jaffa"),
			"cargo": parsed.get("cargo", {}),
			"ship_capacity": parsed.get("ship_capacity", GameState.STARTING_CAPACITY),
			"ship_speed_points": parsed.get("ship_speed_points", 0),
			"ship_defense_points": parsed.get("ship_defense_points", 0),
			"security_ships": parsed.get("security_ships", 0),
			"owned_upgrades": parsed.get("owned_upgrades", []),
			"loan": parsed.get("loan", 0.0),
			"savings": parsed.get("savings", 0.0),
			"capacity_offer_milestone": parsed.get("capacity_offer_milestone", 0),
			"millionaire_gift_claimed": parsed.get("millionaire_gift_claimed", false),
			"mega_capacity_gift_milestone": parsed.get("mega_capacity_gift_milestone", 0),
			"billionaire_gift_claimed": parsed.get("billionaire_gift_claimed", false),
		}
		GameState.players = [PlayerState.from_dict(legacy)]
		GameState.player_count = 1
		GameState.current_player_index = 0

	for p in GameState.players:
		p.is_traveling = false
		p.pending_encounter = {}
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

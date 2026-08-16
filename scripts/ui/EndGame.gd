extends Control

var name_edit: LineEdit
var saved := false
var save_button: Button

func _ready() -> void:
	UIUtil.apply_rtl(self)
	theme = UIUtil.build_theme()
	SaveManager.delete_save()
	_build_ui()

func _build_ui() -> void:
	add_child(UIUtil.make_bg("res://assets/art/sea_bg.svg"))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UIUtil.make_panel()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	if GameState.net_worth_victory:
		_build_wealth_victory_banner(vbox)

	if GameState.is_multiplayer():
		_build_multiplayer_results(vbox)
	else:
		_build_solo_results(vbox)

	var btn_menu := UIUtil.make_button(tr("endgame_to_menu"))
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(btn_menu)

## Shown above the normal results when the game ended early because someone's
## net worth crossed NET_WORTH_VICTORY_CAP (a joke instant-win), rather than
## by running out of days. Widens the label past the panel's normal 420px
## (same AUTOWRAP_WORD trick as _show_message's long gift-milestone text) so
## the humorous paragraph wraps readably instead of running off-screen.
func _build_wealth_victory_banner(vbox: VBoxContainer) -> void:
	vbox.add_child(UIUtil.make_title(tr("endgame_wealth_victory_title"), 28))
	var message_key := "endgame_wealth_victory_message_solo" if not GameState.is_multiplayer() else "endgame_wealth_victory_message_multi"
	var label := UIUtil.make_label(tr(message_key), 17)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(560, 0)
	vbox.add_child(label)

func _build_solo_results(vbox: VBoxContainer) -> void:
	vbox.add_child(UIUtil.make_title(tr("endgame_title"), 32))

	var net_worth := GameState.get_net_worth()
	var summary := "%s: %s\n%s: %s\n%s: %s\n%s: %s\n%s: %d\n\n%s: %s" % [
		tr("hud_gold"), UIUtil.format_gold(GameState.gold),
		tr("endgame_cargo_value"), UIUtil.format_gold(GameState.get_cargo_value_at_current_port()),
		tr("bank_savings"), UIUtil.format_gold(int(GameState.savings)),
		tr("bank_loan"), UIUtil.format_gold(int(GameState.loan)),
		tr("endgame_days"), GameState.game_length_days,
		tr("endgame_networth"), UIUtil.format_gold(net_worth),
	]
	vbox.add_child(UIUtil.make_label(summary, 18))

	vbox.add_child(UIUtil.make_label(tr("endgame_enter_name"), 16))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = tr("endgame_name_placeholder")
	name_edit.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(name_edit)

	save_button = UIUtil.make_button(tr("endgame_save_score"))
	save_button.pressed.connect(func():
		var player_name := name_edit.text.strip_edges()
		if player_name == "":
			player_name = "?"
		var rank := SaveManager.add_highscore(player_name, net_worth)
		saved = true
		save_button.disabled = true
		save_button.text = (tr("endgame_rank_top10") % rank) if rank >= 1 else tr("endgame_score_saved")
	)
	vbox.add_child(save_button)

## Names were already collected at game setup (see MainMenu._show_player_names),
## so unlike solo play there's nothing left to type here -- just the final
## leaderboard, ranked by net worth, and one button to submit every player's
## result to the shared local high-score board at once.
func _build_multiplayer_results(vbox: VBoxContainer) -> void:
	vbox.add_child(UIUtil.make_title(tr("endgame_title"), 32))

	var standings: Array = GameState.get_standings()
	if not standings.is_empty():
		var winner_name := _player_label(standings[0])
		vbox.add_child(UIUtil.make_label(tr("endgame_winner") % winner_name, 22, Color("#D9A441")))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(UIUtil.make_label("", 14))
	grid.add_child(UIUtil.make_label(tr("highscores_col_name"), 14, Color("#9FB6BE")))
	var header_networth := UIUtil.make_label(tr("hud_networth"), 14, Color("#9FB6BE"))
	header_networth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(header_networth)

	var rank := 1
	for entry in standings:
		var rank_label := UIUtil.make_label("★" if rank <= 3 else "%d." % rank, 18)
		rank_label.custom_minimum_size = Vector2(28, 0)
		grid.add_child(rank_label)
		grid.add_child(UIUtil.make_label(_player_label(entry), 17))
		var worth_label := UIUtil.make_label(UIUtil.format_gold(entry["net_worth"]), 17, Color("#D9A441"))
		worth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(worth_label)
		rank += 1

	save_button = UIUtil.make_button(tr("endgame_save_all_scores"))
	save_button.pressed.connect(func():
		for entry in standings:
			SaveManager.add_highscore(_player_label(entry), entry["net_worth"])
		saved = true
		save_button.disabled = true
		save_button.text = tr("endgame_all_scores_saved")
	)
	vbox.add_child(save_button)

func _player_label(standings_entry: Dictionary) -> String:
	var raw_name := String(standings_entry.get("player_name", "")).strip_edges()
	if raw_name != "":
		return raw_name
	return tr("player_name_default") % (int(standings_entry.get("index", 0)) + 1)

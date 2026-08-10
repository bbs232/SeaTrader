extends Control

var name_edit: LineEdit
var saved := false
var save_button: Button

func _ready() -> void:
	UIUtil.apply_rtl(self)
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

	vbox.add_child(UIUtil.make_title(tr("endgame_title"), 32))

	var net_worth := GameState.get_net_worth()
	var summary := "%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n\n%s: %d" % [
		tr("hud_gold"), GameState.gold,
		tr("endgame_cargo_value"), GameState.get_cargo_value_at_current_port(),
		tr("bank_savings"), int(GameState.savings),
		tr("bank_loan"), int(GameState.loan),
		tr("endgame_days"), GameState.game_length_days,
		tr("endgame_networth"), net_worth,
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
		SaveManager.add_highscore(player_name, net_worth)
		saved = true
		save_button.disabled = true
		save_button.text = tr("endgame_score_saved")
	)
	vbox.add_child(save_button)

	var btn_menu := UIUtil.make_button(tr("endgame_to_menu"))
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(btn_menu)

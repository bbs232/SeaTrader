extends Control

var _length_dialog_layer: CanvasLayer
var _highscores_layer: CanvasLayer

func _ready() -> void:
	UIUtil.apply_rtl(self)
	_build_ui()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	add_child(UIUtil.make_bg("res://assets/art/sea_bg.svg"))

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.custom_minimum_size = Vector2(420, 0)
	center.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("app_title"), 44))
	vbox.add_child(UIUtil.make_label(tr("app_subtitle"), 18, Color("#CFE8F2")))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	var btn_new := UIUtil.make_button(tr("menu_new_game"))
	btn_new.pressed.connect(_on_new_game_pressed)
	vbox.add_child(btn_new)

	if SaveManager.has_save():
		var btn_continue := UIUtil.make_button(tr("menu_continue"))
		btn_continue.pressed.connect(_on_continue_pressed)
		vbox.add_child(btn_continue)

	var btn_scores := UIUtil.make_button(tr("menu_highscores"))
	btn_scores.pressed.connect(_on_highscores_pressed)
	vbox.add_child(btn_scores)

	var btn_lang := UIUtil.make_button(tr("menu_language"))
	btn_lang.pressed.connect(_on_language_pressed)
	vbox.add_child(btn_lang)

	if not OS.has_feature("web"):
		var btn_quit := UIUtil.make_button(tr("menu_quit"))
		btn_quit.pressed.connect(func(): get_tree().quit())
		vbox.add_child(btn_quit)

func _on_new_game_pressed() -> void:
	_length_dialog_layer = CanvasLayer.new()
	add_child(_length_dialog_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_length_dialog_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := UIUtil.make_panel()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(380, 0)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("new_game_pick_length"), 26))

	var lengths := [[tr("length_short"), 10], [tr("length_medium"), 21], [tr("length_long"), 35]]
	for entry in lengths:
		var b := UIUtil.make_button(entry[0])
		var days: int = entry[1]
		b.pressed.connect(func(): _start_new_game(days))
		vbox.add_child(b)

	var btn_cancel := UIUtil.make_button(tr("cancel"))
	btn_cancel.pressed.connect(func(): _length_dialog_layer.queue_free())
	vbox.add_child(btn_cancel)

func _start_new_game(days: int) -> void:
	GameState.new_game(days, "jaffa")
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_continue_pressed() -> void:
	if SaveManager.load_game():
		get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_highscores_pressed() -> void:
	_highscores_layer = CanvasLayer.new()
	add_child(_highscores_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highscores_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := UIUtil.make_panel()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("highscores_title"), 26))

	var scores := SaveManager.get_highscores()
	if scores.is_empty():
		vbox.add_child(UIUtil.make_label(tr("highscores_empty"), 18))
	else:
		var i := 1
		for entry in scores:
			var line := "%d. %s — %s (%s)" % [i, entry.get("name", "?"), entry.get("net_worth", 0), entry.get("date", "")]
			vbox.add_child(UIUtil.make_label(line, 18))
			i += 1

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(func(): _highscores_layer.queue_free())
	vbox.add_child(btn_close)

func _on_language_pressed() -> void:
	var current := TranslationServer.get_locale()
	TranslationServer.set_locale("en" if current.begins_with("he") else "he")
	_build_ui()

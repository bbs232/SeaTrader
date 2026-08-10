extends Control

var map_layer: Control
var hud_layer: Control
## A real stack, not a single slot: GameState can resolve a whole voyage
## synchronously and fire more than one signal in a row (e.g. a pirate
## encounter that immediately resolves into arrival, or a second encounter),
## each opening its own popup before the player has closed the previous one.
var overlay_stack: Array[CanvasLayer] = []

var port_buttons: Dictionary = {} # port_id -> TextureButton
var ship_icon: TextureRect
var hud_label: Label
var dock_panel: PanelContainer

var ship_tween: Tween
var is_animating_travel: bool = false

func _ready() -> void:
	UIUtil.apply_rtl(self)
	GameState.arrived_at_port.connect(_on_arrived_at_port)
	GameState.pirate_encounter_started.connect(_on_pirate_encounter_started)
	GameState.game_ended.connect(_on_game_ended)
	_build_ui()

func _build_ui() -> void:
	add_child(UIUtil.make_bg("res://assets/art/map_bg.svg"))

	map_layer = Control.new()
	map_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The map uses absolute canvas coordinates for ports/ship; it must not be
	# mirrored by RTL locales the way text/containers are.
	map_layer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	add_child(map_layer)
	_build_map()

	hud_layer = Control.new()
	hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_layer)
	_build_hud()

	_build_dock()
	_refresh_all()

func _build_map() -> void:
	# NOTE: position/size must be assigned AFTER add_child(). Godot resolves
	# RTL anchor-mirroring against the parent's width at the moment position/
	# size are set; before the node is in the tree that width is unknown
	# (treated as 0), which sends manually-positioned controls flying off to
	# huge negative/positive coordinates under the Hebrew (RTL) locale.
	for port in GameState.ports:
		var btn := TextureButton.new()
		btn.layout_direction = Control.LAYOUT_DIRECTION_LTR
		btn.texture_normal = load("res://assets/art/port_marker.svg")
		btn.pressed.connect(_on_port_marker_pressed.bind(port.id))
		map_layer.add_child(btn)
		btn.size = Vector2(40, 40)
		btn.position = port.map_position - Vector2(20, 20)

		var label := UIUtil.make_label(tr(port.name_key), 16)
		label.layout_direction = Control.LAYOUT_DIRECTION_LTR
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_layer.add_child(label)
		label.position = port.map_position + Vector2(-40, 20)
		label.size = Vector2(100, 24)

		port_buttons[port.id] = btn

	ship_icon = TextureRect.new()
	ship_icon.texture = load("res://assets/art/ship.svg")
	ship_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(ship_icon)
	ship_icon.size = Vector2(36, 36)

func _build_hud() -> void:
	var bg := UIUtil.make_panel()
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bg)
	# Reserve room on the physical right edge (where the LTR-pinned menu
	# button sits) so the HUD text never runs underneath it.
	(bg.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 170

	hud_label = UIUtil.make_label("", 20)
	bg.add_child(hud_label)

	var menu_btn := UIUtil.make_button(tr("menu_button"), 44, 18)
	menu_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_btn.layout_direction = Control.LAYOUT_DIRECTION_LTR
	menu_btn.pressed.connect(_on_menu_pressed)
	hud_layer.add_child(menu_btn)
	menu_btn.size = Vector2(140, 40)
	menu_btn.position = Vector2(1130, 8)

func _build_dock() -> void:
	dock_panel = UIUtil.make_panel()
	dock_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock_panel.position.y -= 90
	add_child(dock_panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	dock_panel.add_child(hbox)

	var btn_trade := UIUtil.make_button(tr("action_trade"))
	btn_trade.pressed.connect(_open_trade_panel)
	hbox.add_child(btn_trade)

	var btn_bank := UIUtil.make_button(tr("action_bank"))
	btn_bank.pressed.connect(_open_bank_panel)
	hbox.add_child(btn_bank)

	var btn_shipyard := UIUtil.make_button(tr("action_shipyard"))
	btn_shipyard.pressed.connect(_open_shipyard_panel)
	hbox.add_child(btn_shipyard)

	var btn_prices := UIUtil.make_button(tr("action_prices"))
	btn_prices.pressed.connect(_open_market_panel)
	hbox.add_child(btn_prices)

func _refresh_all() -> void:
	var port := GameState.get_port(GameState.current_port_id)
	var port_name := tr(port.name_key) if port else "?"
	hud_label.text = "%s %d/%d   |   %s: %d   |   %s: %d/%d   |   %s: %d   |   %s" % [
		tr("hud_day"), GameState.current_day, GameState.game_length_days,
		tr("hud_gold"), GameState.gold,
		tr("hud_cargo"), GameState.get_cargo_used(), GameState.ship_capacity,
		tr("hud_networth"), GameState.get_net_worth(),
		port_name,
	]
	if port and not is_animating_travel:
		ship_icon.position = port.map_position - Vector2(18, 18)
	dock_panel.visible = not GameState.is_traveling and not is_animating_travel

func _on_port_marker_pressed(port_id: String) -> void:
	if GameState.is_traveling or is_animating_travel:
		return
	if port_id == GameState.current_port_id:
		return
	_open_travel_confirm(port_id)

## --- Ship travel animation ---
##
## GameState resolves an entire voyage synchronously (advancing days,
## rolling events) and only returns control to us when it either finishes
## or hits a pirate encounter that needs the player's input. So rather than
## pacing the animation to real time, each signal we get is treated as one
## "leg": a pirate encounter glides the ship halfway from its current visual
## spot toward the destination (still "at sea" when the dialog appears),
## and the final arrival always glides the rest of the way there exactly,
## no matter how many encounters happened along the route.

func _animate_ship_to(map_pos: Vector2, fraction: float = 1.0) -> void:
	var target := map_pos - Vector2(18, 18)
	var start: Vector2 = ship_icon.position
	var leg_target: Vector2 = start.lerp(target, fraction)
	var duration: float = clamp(start.distance_to(leg_target) / 220.0, 0.4, 2.2)

	is_animating_travel = true
	dock_panel.visible = false
	if ship_tween:
		ship_tween.kill()
	ship_tween = create_tween()
	ship_tween.tween_property(ship_icon, "position", leg_target, duration)
	if fraction >= 1.0:
		ship_tween.finished.connect(func():
			is_animating_travel = false
			_refresh_all()
		)

## --- Overlay helpers ---

func _open_overlay() -> PanelContainer:
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay_stack.append(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(scroll)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var panel := UIUtil.make_panel()
	center.add_child(panel)
	panel.set_meta("overlay_layer", layer)
	return panel

## Closes only the top-most overlay, revealing whatever was open beneath it
## (there may be nothing, or there may be an earlier popup still waiting).
func _close_overlay() -> void:
	if not overlay_stack.is_empty():
		var layer: CanvasLayer = overlay_stack.pop_back()
		layer.queue_free()
	_refresh_all()

## Closes exactly the overlay owned by `panel`, wherever it sits in the
## stack. Needed when a GameState call can itself push a newer overlay on
## top before the code that opened `panel` gets a chance to close it (e.g.
## resolving a pirate encounter can immediately trigger arrival's own
## popup) — closing "whatever is on top" at that point would be wrong.
func _close_specific_overlay(panel: PanelContainer) -> void:
	if panel and panel.has_meta("overlay_layer"):
		var layer: CanvasLayer = panel.get_meta("overlay_layer")
		overlay_stack.erase(layer)
		layer.queue_free()
	_refresh_all()

## Stacks a small yes/no confirmation on top of whatever panel is currently
## open (e.g. the trade panel), without closing it. on_confirm only runs if
## the player accepts; cancelling or dismissing just removes the popup.
func _show_confirm(text: String, on_confirm: Callable) -> void:
	if overlay_stack.is_empty():
		return
	var layer: CanvasLayer = overlay_stack.back()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := UIUtil.make_panel()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_label(text, 18))

	var btn_confirm := UIUtil.make_button(tr("confirm"))
	btn_confirm.pressed.connect(func():
		dim.queue_free()
		on_confirm.call()
	)
	vbox.add_child(btn_confirm)

	var btn_cancel := UIUtil.make_button(tr("cancel"))
	btn_cancel.pressed.connect(func(): dim.queue_free())
	vbox.add_child(btn_cancel)

## Confirms a purchase before it happens, surfacing the overload warning
## up front (in the confirmation itself) whenever this purchase would push
## the ship past its nominal capacity, rather than only after the fact.
func _confirm_and_buy(good: Good, qty: int, on_bought: Callable) -> void:
	if qty <= 0:
		return
	var cost := GameState.get_price(GameState.current_port_id, good.id) * qty
	var msg := tr("confirm_buy_max") % [qty, tr(good.name_key), cost]
	if GameState.get_cargo_used() + qty > GameState.ship_capacity:
		msg += "\n" + tr("confirm_overload_warning")
	_show_confirm(msg, func():
		if GameState.buy(good.id, qty):
			on_bought.call()
	)

## --- Travel confirm ---

func _open_travel_confirm(port_id: String) -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var dest := GameState.get_port(port_id)
	var days := GameState.get_travel_days(GameState.current_port_id, port_id)

	vbox.add_child(UIUtil.make_title(tr(dest.name_key), 26))
	vbox.add_child(UIUtil.make_label(tr("travel_estimate") % days, 18))

	var btn_go := UIUtil.make_button(tr("travel_confirm"))
	btn_go.pressed.connect(func():
		_close_overlay()
		GameState.start_travel(port_id)
	)
	vbox.add_child(btn_go)

	var btn_cancel := UIUtil.make_button(tr("cancel"))
	btn_cancel.pressed.connect(_close_overlay)
	vbox.add_child(btn_cancel)

## --- Trade panel ---

func _open_trade_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(760, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var port := GameState.get_port(GameState.current_port_id)
	vbox.add_child(UIUtil.make_title(tr("trade_title") % tr(port.name_key), 26))
	var status_label := UIUtil.make_label("", 16)
	vbox.add_child(status_label)
	var overload_label := UIUtil.make_label("", 15, Color("#E0674A"))
	vbox.add_child(overload_label)

	var refresh_status := func():
		status_label.text = "%s: %d   |   %s: %d/%d" % [
			tr("hud_gold"), GameState.gold, tr("hud_cargo"), GameState.get_cargo_used(), GameState.ship_capacity]
		overload_label.text = tr("trade_overload_warning") if GameState.is_overloaded() else ""

	refresh_status.call()

	for good in GameState.goods:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var name_label := UIUtil.make_label(tr(good.name_key), 18)
		name_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(name_label)

		var price_label := UIUtil.make_label("", 16)
		price_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(price_label)

		var owned_label := UIUtil.make_label("", 16)
		owned_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(owned_label)

		var amount := SpinBox.new()
		amount.min_value = 1
		amount.max_value = 9999
		amount.value = 1
		amount.custom_minimum_size = Vector2(80, 0)
		row.add_child(amount)

		var btn_buy := UIUtil.make_button(tr("trade_buy"), 44, 16)
		btn_buy.custom_minimum_size = Vector2(70, 44)
		row.add_child(btn_buy)

		var btn_buy_max := UIUtil.make_button(tr("trade_max"), 44, 16)
		btn_buy_max.custom_minimum_size = Vector2(60, 44)
		row.add_child(btn_buy_max)

		var btn_sell := UIUtil.make_button(tr("trade_sell"), 44, 16)
		btn_sell.custom_minimum_size = Vector2(70, 44)
		row.add_child(btn_sell)

		var btn_sell_all := UIUtil.make_button(tr("trade_all"), 44, 16)
		btn_sell_all.custom_minimum_size = Vector2(60, 44)
		row.add_child(btn_sell_all)

		var refresh_row := func():
			var price := GameState.get_price(GameState.current_port_id, good.id)
			price_label.text = "%s: %d" % [tr("trade_price"), price]
			var owned: int = GameState.cargo.get(good.id, 0)
			owned_label.text = "%s: %d" % [tr("trade_owned"), owned]
			var max_buy := GameState.get_max_affordable(good.id)
			btn_buy.disabled = max_buy <= 0
			btn_buy_max.disabled = max_buy <= 0
			btn_sell.disabled = owned <= 0
			btn_sell_all.disabled = owned <= 0

		refresh_row.call()

		btn_buy.pressed.connect(func():
			_confirm_and_buy(good, int(amount.value), func():
				refresh_row.call()
				refresh_status.call()
			)
		)
		btn_buy_max.pressed.connect(func():
			var max_buy := GameState.get_max_affordable(good.id)
			_confirm_and_buy(good, max_buy, func():
				amount.value = max_buy
				refresh_row.call()
				refresh_status.call()
			)
		)
		btn_sell.pressed.connect(func():
			if GameState.sell(good.id, int(amount.value)):
				refresh_row.call()
				refresh_status.call()
		)
		btn_sell_all.pressed.connect(func():
			var owned: int = GameState.cargo.get(good.id, 0)
			if owned <= 0:
				return
			var revenue := GameState.get_price(GameState.current_port_id, good.id) * owned
			_show_confirm(tr("confirm_sell_all") % [owned, tr(good.name_key), revenue], func():
				if GameState.sell(good.id, owned):
					amount.value = 1
					refresh_row.call()
					refresh_status.call()
			)
		)

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

## --- Bank panel ---

func _open_bank_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("bank_title"), 26))
	var info_label := UIUtil.make_label("", 18)
	vbox.add_child(info_label)

	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 999999
	amount.value = 100
	amount.step = 1
	vbox.add_child(amount)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	var btn_deposit := UIUtil.make_button(tr("bank_deposit"))
	grid.add_child(btn_deposit)
	var btn_deposit_max := UIUtil.make_button(tr("bank_deposit_all"))
	grid.add_child(btn_deposit_max)

	var btn_withdraw := UIUtil.make_button(tr("bank_withdraw"))
	grid.add_child(btn_withdraw)
	var btn_withdraw_max := UIUtil.make_button(tr("bank_withdraw_all"))
	grid.add_child(btn_withdraw_max)

	var btn_borrow := UIUtil.make_button(tr("bank_borrow"))
	grid.add_child(btn_borrow)
	var btn_borrow_max := UIUtil.make_button(tr("bank_borrow_max"))
	grid.add_child(btn_borrow_max)

	var btn_repay := UIUtil.make_button(tr("bank_repay"))
	grid.add_child(btn_repay)
	var btn_repay_max := UIUtil.make_button(tr("bank_repay_all"))
	grid.add_child(btn_repay_max)

	var refresh_info := func():
		info_label.text = "%s: %d\n%s: %d\n%s: %d\n%s: %d" % [
			tr("hud_gold"), GameState.gold,
			tr("bank_savings"), int(GameState.savings),
			tr("bank_loan"), int(GameState.loan),
			tr("bank_max_loan"), GameState.bank_max_loan(),
		]
		btn_deposit.disabled = GameState.gold <= 0
		btn_deposit_max.disabled = GameState.gold <= 0
		btn_withdraw.disabled = GameState.savings <= 0
		btn_withdraw_max.disabled = GameState.savings <= 0
		btn_borrow.disabled = GameState.bank_max_loan() <= 0
		btn_borrow_max.disabled = GameState.bank_max_loan() <= 0
		var can_repay := GameState.loan > 0 and GameState.gold > 0
		btn_repay.disabled = not can_repay
		btn_repay_max.disabled = not can_repay

	refresh_info.call()

	btn_deposit.pressed.connect(func():
		GameState.bank_deposit(int(amount.value))
		refresh_info.call()
	)
	btn_deposit_max.pressed.connect(func():
		GameState.bank_deposit(GameState.gold)
		refresh_info.call()
	)
	btn_withdraw.pressed.connect(func():
		GameState.bank_withdraw(int(amount.value))
		refresh_info.call()
	)
	btn_withdraw_max.pressed.connect(func():
		GameState.bank_withdraw(int(GameState.savings))
		refresh_info.call()
	)
	btn_borrow.pressed.connect(func():
		GameState.bank_borrow(int(amount.value))
		refresh_info.call()
	)
	btn_borrow_max.pressed.connect(func():
		GameState.bank_borrow(GameState.bank_max_loan())
		refresh_info.call()
	)
	btn_repay.pressed.connect(func():
		GameState.bank_repay(int(amount.value))
		refresh_info.call()
	)
	btn_repay_max.pressed.connect(func():
		GameState.bank_repay(min(GameState.gold, int(ceil(GameState.loan))))
		refresh_info.call()
	)

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

## --- Shipyard panel ---

func _open_shipyard_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("shipyard_title"), 26))

	for up in GameState.upgrades:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var label := UIUtil.make_label(tr(up.name_key), 18)
		label.custom_minimum_size = Vector2(220, 0)
		row.add_child(label)

		var status_label := UIUtil.make_label("", 16)
		status_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(status_label)

		var btn_buy := UIUtil.make_button(tr("shipyard_buy") % up.cost, 44, 16)
		row.add_child(btn_buy)

		var refresh_row := func():
			if GameState.is_upgrade_owned(up.id):
				status_label.text = tr("shipyard_owned")
				btn_buy.disabled = true
			elif up.requires_id != "" and not GameState.is_upgrade_owned(up.requires_id):
				status_label.text = tr("shipyard_locked")
				btn_buy.disabled = true
			else:
				status_label.text = ""
				btn_buy.disabled = not GameState.can_buy_upgrade(up.id)

		refresh_row.call()
		btn_buy.pressed.connect(func():
			if GameState.buy_upgrade(up.id):
				refresh_row.call()
		)

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

## --- Market prices (all ports) ---

func _open_market_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("market_title"), 26))
	vbox.add_child(UIUtil.make_label(tr("market_hint"), 14, Color("#CFE8F2")))

	var grid := GridContainer.new()
	grid.columns = GameState.ports.size() + 1
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	grid.add_child(UIUtil.make_label("", 15))
	for port in GameState.ports:
		var is_here := port.id == GameState.current_port_id
		var header := UIUtil.make_label(tr(port.name_key), 15, Color("#D9A441") if is_here else Color("#FFF6E3"))
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.custom_minimum_size = Vector2(90, 0)
		grid.add_child(header)

	for good in GameState.goods:
		var name_label := UIUtil.make_label(tr(good.name_key), 15)
		grid.add_child(name_label)
		for port in GameState.ports:
			var is_here := port.id == GameState.current_port_id
			var price_label := UIUtil.make_label(str(GameState.get_price(port.id, good.id)), 15,
				Color("#D9A441") if is_here else Color("#FFF6E3"))
			price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(price_label)

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

## --- Menu (save & exit) ---

func _on_menu_pressed() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var btn_resume := UIUtil.make_button(tr("menu_resume"))
	btn_resume.pressed.connect(_close_overlay)
	vbox.add_child(btn_resume)

	var btn_save_exit := UIUtil.make_button(tr("menu_save_exit"))
	btn_save_exit.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	vbox.add_child(btn_save_exit)

## --- Pirate encounter ---

func _on_pirate_encounter_started(_details: Dictionary) -> void:
	var dest := GameState.get_port(GameState.travel_destination_id)
	if dest:
		_animate_ship_to(dest.map_position, 0.5)

	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var icon := TextureRect.new()
	icon.texture = load("res://assets/art/pirate.svg")
	icon.custom_minimum_size = Vector2(80, 80)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_center := CenterContainer.new()
	icon_center.add_child(icon)
	vbox.add_child(icon_center)

	vbox.add_child(UIUtil.make_title(tr("pirates_title"), 24))
	vbox.add_child(UIUtil.make_label(tr("pirates_desc"), 16))

	var btn_fight := UIUtil.make_button(tr("pirates_fight"))
	btn_fight.pressed.connect(func(): _resolve_pirates("fight", panel))
	vbox.add_child(btn_fight)

	var btn_flee := UIUtil.make_button(tr("pirates_flee"))
	btn_flee.pressed.connect(func(): _resolve_pirates("flee", panel))
	vbox.add_child(btn_flee)

	var btn_pay := UIUtil.make_button(tr("pirates_pay"))
	btn_pay.pressed.connect(func(): _resolve_pirates("pay", panel))
	vbox.add_child(btn_pay)

## `panel` (not just "the top overlay") is closed explicitly here because
## resolve_pirate_encounter() can synchronously resolve the rest of the
## voyage and push a newer popup (arrival, or another encounter) on top of
## this dialog before we get back here to close it.
func _resolve_pirates(choice: String, panel: PanelContainer) -> void:
	var result := GameState.resolve_pirate_encounter(choice)
	_close_specific_overlay(panel)
	_show_message(_format_pirate_result(result))

func _format_pirate_result(result: Dictionary) -> String:
	match result.get("outcome", ""):
		"won":
			return tr("log_pirates_won") % result.get("bounty", 0)
		"lost":
			return tr("log_pirates_lost")
		"escaped":
			return tr("log_pirates_escaped")
		"caught":
			return tr("log_pirates_caught") % result.get("ransom", 0)
		"paid":
			return tr("log_pirates_paid") % result.get("ransom", 0)
		_:
			return ""

## --- Arrival / travel report ---

func _on_arrived_at_port(port_id: String, log: Array) -> void:
	var dest := GameState.get_port(port_id)
	if dest:
		_animate_ship_to(dest.map_position, 1.0)

	if GameState.current_day > GameState.game_length_days:
		return # game_ended will handle the transition
	var lines: Array = []
	for entry in log:
		var line := _format_log_entry(entry)
		if line != "":
			lines.append(line)
	if lines.is_empty():
		lines.append(tr("travel_uneventful"))
	_show_message("\n".join(lines))

func _format_log_entry(entry: Dictionary) -> String:
	match entry.get("type", ""):
		"storm":
			var lost: Dictionary = entry.get("lost_goods", {})
			if lost.is_empty():
				return tr("log_storm_none")
			return tr("log_storm_loss") % _format_goods_list(lost)
		"aground":
			var lost: Dictionary = entry.get("lost_goods", {})
			var repair_cost: int = entry.get("repair_cost", 0)
			if lost.is_empty():
				return tr("log_aground_none") % repair_cost
			return tr("log_aground_loss") % [_format_goods_list(lost), repair_cost]
		"overload":
			var lost: Dictionary = entry.get("lost_goods", {})
			var repair_cost: int = entry.get("repair_cost", 0)
			if entry.get("severe", false):
				return tr("log_overload_severe") % [_format_goods_list(lost), repair_cost]
			return tr("log_overload_minor") % _format_goods_list(lost)
		"fair_wind":
			return tr("log_fair_wind")
		"market_demand":
			return tr("log_market_demand")
		"pirates":
			return _format_pirate_result(entry)
		_:
			return ""

func _format_goods_list(lost: Dictionary) -> String:
	var parts: Array = []
	for good_id in lost.keys():
		var good := GameState.get_good(good_id)
		parts.append("%d %s" % [lost[good_id], tr(good.name_key) if good else good_id])
	return ", ".join(parts)

func _show_message(text: String) -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	vbox.add_child(UIUtil.make_label(text, 18))
	var btn_ok := UIUtil.make_button(tr("ok"))
	btn_ok.pressed.connect(_close_overlay)
	vbox.add_child(btn_ok)

## --- Game end ---

func _on_game_ended(_summary: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/EndGame.tscn")

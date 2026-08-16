extends Control

const SHIP_ICON_SIZE := Vector2(90, 90)
## Ships dock a bit to the left (out to sea) of the port marker's anchor icon
## instead of centered on it, so the ship never covers the marker itself or
## the port name label (which sits below the marker). An offset straight up
## is ambiguous when two ports are stacked close together on the coastline
## (can't tell which one the ship is docked at); offsetting sideways keeps it
## unambiguously level with its port.
const SHIP_PORT_OFFSET := Vector2(-70, 0)

## Port/ship map coordinates (Port.map_position, and everything derived from
## it below) are authored as absolute pixels against this canvas size, which
## matches project.godot's window/size/viewport_width|height. Under
## window/stretch/aspect="expand" the *logical* canvas can actually be bigger
## than this on non-16:9 screens (that's how it fills the screen instead of
## letterboxing) -- see _map_scale(), which rescales the authored coordinates
## to whatever the canvas actually is so markers/ship stay aligned with the
## map background (which stretches to fill the same way).
const MAP_DESIGN_SIZE := Vector2(1280, 720)

var map_layer: Control
var hud_layer: Control
## A real stack, not a single slot: GameState can resolve a whole voyage
## synchronously and fire more than one signal in a row (e.g. a pirate
## encounter that immediately resolves into arrival, or a second encounter),
## each opening its own popup before the player has closed the previous one.
var overlay_stack: Array[CanvasLayer] = []

var port_buttons: Dictionary = {} # port_id -> TextureButton
var port_labels: Dictionary = {} # port_id -> Label
var ship_icon: TextureRect
var hud_label: Label
var menu_btn: Button
var dock_panel: PanelContainer
var map_bg: TextureRect

var ship_tween: Tween
var is_animating_travel: bool = false
var is_resting: bool = false

func _ready() -> void:
	UIUtil.apply_rtl(self)
	theme = UIUtil.build_theme()
	GameState.arrived_at_port.connect(_on_arrived_at_port)
	GameState.pirate_encounter_started.connect(_on_pirate_encounter_started)
	GameState.game_ended.connect(_on_game_ended)
	GameState.capacity_offer_available.connect(_on_capacity_offer_available)
	GameState.millionaire_gift_granted.connect(_on_millionaire_gift_granted)
	GameState.mega_capacity_gift_granted.connect(_on_mega_capacity_gift_granted)
	GameState.billionaire_gift_granted.connect(_on_billionaire_gift_granted)
	_build_ui()

func _build_ui() -> void:
	map_bg = UIUtil.make_bg("res://assets/art/map_bg.svg")
	add_child(map_bg)

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

## Ratio between the actual current canvas size and MAP_DESIGN_SIZE -- 1:1
## on a 16:9 screen, >1 on one axis wherever "expand" widened/heightened the
## canvas past the design size to fill a different-aspect screen.
func _map_scale() -> Vector2:
	return size / MAP_DESIGN_SIZE

## Rescales a Port.map_position (or any other MAP_DESIGN_SIZE-authored point,
## e.g. the ship's target while gliding between ports) to the actual canvas.
func _map_marker_position(design_pos: Vector2) -> Vector2:
	return design_pos * _map_scale()

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

		var label := UIUtil.make_label(tr(port.name_key), 16)
		label.layout_direction = Control.LAYOUT_DIRECTION_LTR
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_layer.add_child(label)
		label.size = Vector2(100, 24)

		port_buttons[port.id] = btn
		port_labels[port.id] = label

	ship_icon = TextureRect.new()
	ship_icon.texture = load("res://assets/art/ship.svg")
	ship_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(ship_icon)
	ship_icon.size = SHIP_ICON_SIZE

	_reposition_map()
	# The logical canvas can change size after this (browser window resize,
	# device rotation) since "expand" ties it to the actual screen aspect --
	# reposition markers/ship to match instead of leaving them at their
	# build-time spot.
	resized.connect(_reposition_map)

## Re-applies _map_scale() to every port marker/label and the ship, so they
## stay aligned with the (equally rescaled) map background. Called once at
## build time and again on every resize.
func _reposition_map() -> void:
	for port in GameState.ports:
		var btn: TextureButton = port_buttons[port.id]
		btn.position = _map_marker_position(port.map_position) - Vector2(20, 20)
		var label: Label = port_labels[port.id]
		label.position = _map_marker_position(port.map_position) + Vector2(-40, 20)
	var current_port := GameState.get_port(GameState.current_port_id)
	if current_port and not is_animating_travel:
		ship_icon.position = _map_marker_position(current_port.map_position) + SHIP_PORT_OFFSET - SHIP_ICON_SIZE / 2

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

	menu_btn = UIUtil.make_button(tr("menu_button"), 44, 18)
	menu_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_btn.layout_direction = Control.LAYOUT_DIRECTION_LTR
	menu_btn.pressed.connect(_on_menu_pressed)
	hud_layer.add_child(menu_btn)
	menu_btn.size = Vector2(140, 40)
	# Positioned from the actual current canvas width (not an anchor preset --
	# Control.set_anchors_preset() mirrors TOP_RIGHT/TOP_LEFT for RTL locales
	# even when this node's own layout_direction is forced LTR, which sent it
	# flying to the physical left instead) so it stays pinned to the true
	# right edge regardless of width -- under window/stretch/aspect="expand"
	# that width can exceed MAP_DESIGN_SIZE.x on non-16:9 screens. Reapplied
	# on resize below, same reasoning as _reposition_map().
	_reposition_hud()
	resized.connect(_reposition_hud)

## Keeps the menu button pinned to the true physical top-right corner as the
## canvas size changes (see the comment in _build_hud()).
func _reposition_hud() -> void:
	menu_btn.position = Vector2(size.x - 150, 8)

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

	var btn_rest := UIUtil.make_button(tr("action_rest"))
	btn_rest.pressed.connect(_on_rest_pressed)
	hbox.add_child(btn_rest)

func _refresh_all() -> void:
	var port := GameState.get_port(GameState.current_port_id)
	var port_name := tr(port.name_key) if port else "?"
	var turn_prefix := ""
	if GameState.is_multiplayer():
		turn_prefix = (tr("turn_banner") % _active_player_label()) + "   |   "
	hud_label.text = "%s%s %d/%d (%s)   |   %s: %s   |   %s: %s/%s   |   %s: %s   |   %s" % [
		turn_prefix,
		tr("hud_day"), GameState.current_day, GameState.game_length_days, tr(_time_of_day_key()),
		tr("hud_gold"), UIUtil.format_gold(GameState.gold),
		tr("hud_cargo"), UIUtil.format_gold(GameState.get_cargo_used()), UIUtil.format_gold(GameState.ship_capacity),
		tr("hud_networth"), UIUtil.format_gold(GameState.get_net_worth()),
		port_name,
	]
	map_bg.modulate = _time_of_day_tint()
	if port and not is_animating_travel:
		ship_icon.position = _map_marker_position(port.map_position) + SHIP_PORT_OFFSET - SHIP_ICON_SIZE / 2
	dock_panel.visible = not GameState.is_traveling and not is_animating_travel and not is_resting
	_update_port_marker_states()

## Derives a lightweight sense of time of day from state that already exists,
## rather than tracking a separate persisted clock:
## - "Evening" covers the moments time is visibly passing (ship gliding at
##   sea, or the rest fade-to-dark) so the transition itself reads as dusk --
##   and also a settled arrival that used up today's whole travel budget
##   (half_day_carry == 2): the player can still trade, but can't sail again
##   until they rest.
## - Once settled at a port, half_day_carry otherwise tells us whether a
##   half-day-length hop already happened today without ticking the day over
##   (1, Noon) or the day just started fresh (0, Morning).
## Falls back to a generic "Player N" label when the player left the name
## field blank at setup time (see MainMenu._show_player_names).
func _active_player_label(index: int = -1) -> String:
	var i: int = GameState.current_player_index if index < 0 else index
	var p: PlayerState = GameState.players[i]
	if p.player_name.strip_edges() != "":
		return p.player_name
	return tr("player_name_default") % (i + 1)

func _time_of_day_key() -> String:
	if is_animating_travel or is_resting or GameState.half_day_carry >= 2:
		return "hud_time_evening"
	if GameState.half_day_carry == 0:
		return "hud_time_morning"
	return "hud_time_noon"

func _time_of_day_tint() -> Color:
	match _time_of_day_key():
		"hud_time_evening":
			return Color(0.95, 0.75, 0.65)
		"hud_time_noon":
			return Color(1.0, 1.0, 1.0)
		_:
			return Color(1.0, 0.97, 0.9)

## Multiplayer-only: a full-day leg can't be launched once half a day has
## already been spent this turn (see GameState.start_travel's own guard,
## which silently no-ops on a blocked port -- this is what makes that same
## rule visible on the map, both as a dim marker and as a tap explanation).
func _is_full_day_leg_blocked(port_id: String) -> bool:
	return GameState.is_multiplayer() and GameState.half_day_carry != 0 \
		and GameState.get_travel_half_days(GameState.current_port_id, port_id) == 2

## Dims every other port once the day's travel budget is spent
## (half_day_carry == 2) -- sailing again has to wait for Rest -- and, in
## multiplayer, also dims any full-day-leg destination once half the day is
## already spent (half_day_carry == 1), since launching one now would be
## blocked (see _is_full_day_leg_blocked).
func _update_port_marker_states() -> void:
	for port_id in port_buttons.keys():
		var btn: TextureButton = port_buttons[port_id]
		if port_id == GameState.current_port_id:
			btn.modulate = Color(1, 1, 1, 1)
		elif GameState.half_day_carry >= 2 or _is_full_day_leg_blocked(port_id):
			btn.modulate = Color(1, 1, 1, 0.4)
		else:
			btn.modulate = Color(1, 1, 1, 1)

func _on_port_marker_pressed(port_id: String) -> void:
	if GameState.is_traveling or is_animating_travel or is_resting:
		return
	if port_id == GameState.current_port_id:
		return
	if GameState.half_day_carry >= 2:
		_show_message(tr("must_rest_evening"))
		return
	if _is_full_day_leg_blocked(port_id):
		_show_message(tr("must_wait_full_day_leg"))
		return
	if GameState.get_cargo_used() > GameState.get_overload_capacity():
		_show_message(tr("must_sell_overload"))
		return
	_open_travel_confirm(port_id)

## --- Resting (skip a day at the current port) ---

func _on_rest_pressed() -> void:
	if GameState.is_traveling or is_animating_travel or is_resting:
		return
	is_resting = true
	_refresh_all()
	var rest_result := GameState.rest_at_port()
	if GameState.current_day > GameState.game_length_days:
		return # the game just ended; game_ended already handles the scene change
	_play_rest_animation(rest_result)

## No ship movement to animate here (the player stays put), so a day passing
## is shown as a brief fade-to-dark-and-back with a "resting" caption; the
## HUD (new day, updated prices) only becomes visible once it fades back in.
## If resting turned up a notable overnight price swing and/or a warehouse
## mishap, a combined "morning news" message follows right after the fade,
## once the HUD is visible again.
func _play_rest_animation(rest_result: Dictionary = {}) -> void:
	dock_panel.visible = false

	var overlay := ColorRect.new()
	overlay.color = Color(0.04, 0.08, 0.14, 0.0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var label := UIUtil.make_title(tr("resting_label"), 30)
	label.modulate.a = 0.0
	center.add_child(label)

	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.85, 0.35)
	tween.parallel().tween_property(label, "modulate:a", 1.0, 0.35)
	tween.tween_interval(0.5)
	tween.tween_property(overlay, "color:a", 0.0, 0.4)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.4)
	tween.finished.connect(func():
		overlay.queue_free()
		is_resting = false
		_refresh_all()
		var lines: Array = []
		var price_change: Dictionary = rest_result.get("price_change", {})
		if not price_change.is_empty():
			lines.append(_format_notable_price_change(price_change))
		var warehouse: Dictionary = rest_result.get("warehouse", {})
		if not warehouse.is_empty():
			lines.append(_format_log_entry(warehouse))
		if not lines.is_empty():
			_show_message("\n".join(lines))
		if GameState.is_multiplayer() and GameState.current_day <= GameState.game_length_days:
			_show_pass_device_screen()
	)

## --- Hotseat turn hand-off ---

## end_turn() (called via rest_at_port above) already moved
## current_player_index on to whoever plays next -- this just blocks the
## screen behind a "pass the device" prompt naming them before their own
## trade/travel options become visible, so the outgoing player's info isn't
## left on screen for the incoming one to see by accident.
func _show_pass_device_screen() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_label(tr("turn_pass_device"), 18))
	vbox.add_child(UIUtil.make_title(_active_player_label(), 30))

	var btn_start := UIUtil.make_button(tr("turn_start_turn"))
	btn_start.pressed.connect(_close_overlay)
	vbox.add_child(btn_start)

## Formats the "morning news" line for a notable overnight price swing found
## by GameState.rest_at_port (see _find_notable_price_change).
func _format_notable_price_change(details: Dictionary) -> String:
	var good := GameState.get_good(details.get("good_id", ""))
	var port := GameState.get_port(details.get("port_id", ""))
	if good == null or port == null:
		return ""
	var key := "rest_notable_price_drop" if details.get("ratio", 0.0) < 0.0 else "rest_notable_price_rise"
	return tr(key) % [tr(good.name_key), tr(port.name_key)]

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
	var target := _map_marker_position(map_pos) + SHIP_PORT_OFFSET - SHIP_ICON_SIZE / 2
	var start: Vector2 = ship_icon.position
	var leg_target: Vector2 = start.lerp(target, fraction)
	var duration: float = clamp(start.distance_to(leg_target) / 220.0, 0.4, 2.2)

	is_animating_travel = true
	dock_panel.visible = false
	_refresh_all()
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

## Stacks a choice between the two "max capacity" purchase sizes on top of
## the trade panel: strictly within nominal ship_capacity (no overload risk)
## or up to the 150% overload allowance (see OVERLOAD_ALLOWANCE). Reports the
## chosen quantity via on_choice, which the caller then runs through the
## normal _confirm_and_buy flow (cost + overload warning) same as any other
## buy button -- this dialog only decides how much, not whether.
func _open_capacity_choice(good: Good, on_choice: Callable) -> void:
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

	vbox.add_child(UIUtil.make_title(tr("capacity_choice_title"), 20))

	var legal_max := GameState.get_max_legal_capacity_affordable(good.id)
	var btn_legal := UIUtil.make_button(tr("capacity_choice_legal") % UIUtil.format_gold(legal_max))
	btn_legal.disabled = legal_max <= 0
	btn_legal.pressed.connect(func():
		dim.queue_free()
		on_choice.call(legal_max)
	)
	vbox.add_child(btn_legal)

	var overload_max := GameState.get_max_sailable_affordable(good.id)
	var btn_overload := UIUtil.make_button(tr("capacity_choice_overload") % UIUtil.format_gold(overload_max))
	btn_overload.disabled = overload_max <= 0
	btn_overload.pressed.connect(func():
		dim.queue_free()
		on_choice.call(overload_max)
	)
	vbox.add_child(btn_overload)

	var btn_cancel_choice := UIUtil.make_button(tr("cancel"))
	btn_cancel_choice.pressed.connect(func(): dim.queue_free())
	vbox.add_child(btn_cancel_choice)

## Stacks a small numeric-entry dialog on top of the current overlay, used by
## the trade panel's quantity/gold-amount buttons instead of a raw SpinBox --
## a SpinBox's internal LineEdit only commits typed text on blur/Enter, which
## a fast tap straight to Buy/Sell can race and silently ignore. This dialog
## only ever reports a value back via on_set when the player explicitly
## confirms, so there's no ambiguous partially-typed state to race against.
func _open_quantity_dialog(current: int, on_set: Callable, title_key: String = "quantity_dialog_title", min_value: int = 1) -> void:
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
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr(title_key), 20))

	var edit := LineEdit.new()
	edit.text = UIUtil.format_gold(current)
	edit.custom_minimum_size = Vector2(0, 48)
	edit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.select_all_on_focus = true
	# Requests the OS's numeric keypad instead of a full letter keyboard on
	# mobile/tablet -- this field only ever holds digits.
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	UIUtil.wire_live_gold_formatting(edit)
	vbox.add_child(edit)

	var apply := func():
		# Strips thousands-separator commas (the field is pre-filled with them
		# via UIUtil.format_gold) before parsing -- int() would otherwise stop
		# at the first comma and silently truncate the value.
		var qty := int(edit.text.strip_edges().replace(",", ""))
		if qty < min_value:
			qty = min_value
		dim.queue_free()
		on_set.call(qty)

	edit.text_submitted.connect(func(_new_text: String): apply.call())

	var btn_ok := UIUtil.make_button(tr("confirm"))
	btn_ok.pressed.connect(apply)
	vbox.add_child(btn_ok)

	var btn_cancel2 := UIUtil.make_button(tr("cancel"))
	btn_cancel2.pressed.connect(func(): dim.queue_free())
	vbox.add_child(btn_cancel2)

	# Auto-focusing here is only safe on desktop: browsers only pop the OS
	# on-screen keyboard for a text field when it's focused synchronously
	# within the user's own tap. A deferred grab_focus() lands a frame after
	# the tap that opened this dialog, so on touchscreens it silently focuses
	# the field with no keyboard behind it -- the player sees a caret but has
	# nothing to type with, and the pre-filled number never changes. On
	# touchscreens, leave it unfocused; tapping the field directly (like the
	# player-name fields elsewhere) is what triggers the real keyboard.
	if not DisplayServer.is_touchscreen_available():
		edit.call_deferred("grab_focus")

## Confirms a purchase before it happens, surfacing the overload warning
## up front (in the confirmation itself) whenever this purchase would push
## the ship past its nominal capacity, rather than only after the fact.
func _confirm_and_buy(good: Good, qty: int, on_bought: Callable) -> void:
	if qty <= 0:
		return
	var cost := GameState.get_price(GameState.current_port_id, good.id) * qty
	var msg := tr("confirm_buy_max") % [UIUtil.format_gold(qty), tr(good.name_key), UIUtil.format_gold(cost)]
	_show_buy_confirm(good, qty, msg, on_bought)

## Like _confirm_and_buy, but for the "buy by gold amount" flow: qty was
## derived by rounding a player-entered gold budget down to a whole number
## of units, so the confirmation spells out both the resulting quantity/cost
## and the original amount it was rounded from.
func _confirm_and_buy_by_gold(good: Good, qty: int, entered_gold: int, on_bought: Callable) -> void:
	if qty <= 0:
		return
	var cost := GameState.get_price(GameState.current_port_id, good.id) * qty
	var msg := tr("confirm_buy_by_gold") % [UIUtil.format_gold(qty), tr(good.name_key), UIUtil.format_gold(cost), UIUtil.format_gold(entered_gold)]
	_show_buy_confirm(good, qty, msg, on_bought)

func _show_buy_confirm(good: Good, qty: int, msg: String, on_bought: Callable) -> void:
	var full_msg := msg
	if GameState.get_cargo_used() + qty > GameState.ship_capacity:
		full_msg += "\n" + tr("confirm_overload_warning")
	_show_confirm(full_msg, func():
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
	var half_days := GameState.get_travel_half_days(GameState.current_port_id, port_id)
	var days_label := tr("travel_half_day")
	if half_days == 2:
		days_label = tr("travel_one_day")

	vbox.add_child(UIUtil.make_title(tr(dest.name_key), 26))
	vbox.add_child(UIUtil.make_label(tr("travel_estimate") % days_label, 18))

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
	vbox.custom_minimum_size = Vector2(910, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var port := GameState.get_port(GameState.current_port_id)
	vbox.add_child(UIUtil.make_title(tr("trade_title") % tr(port.name_key), 26))
	var status_label := UIUtil.make_label("", 16)
	vbox.add_child(status_label)
	var overload_label := UIUtil.make_label("", 15, Color("#E0674A"))
	vbox.add_child(overload_label)

	var refresh_status := func():
		status_label.text = "%s: %s   |   %s: %s/%s" % [
			tr("hud_gold"), UIUtil.format_gold(GameState.gold), tr("hud_cargo"), UIUtil.format_gold(GameState.get_cargo_used()), UIUtil.format_gold(GameState.ship_capacity)]
		overload_label.text = tr("trade_overload_warning") if GameState.is_overloaded() else ""

	refresh_status.call()

	# Every good's Buy/Max button depends on current gold, and every good's
	# cargo-overload check depends on total cargo used -- both change on any
	# trade, not just the row that was clicked. So a trade in one row has to
	# refresh every row's buttons, not just its own, or another row's now-
	# affordable "Buy" can stay stuck disabled until the panel is reopened.
	var row_refreshers: Array[Callable] = []
	var refresh_all_rows := func():
		for refresher in row_refreshers:
			refresher.call()

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

		# A box, not a plain int, so the nested lambdas below (buy/sell/max/
		# quantity dialog) all mutate the same live quantity regardless of
		# GDScript lambda capture semantics -- an Array is captured by
		# reference, a plain local int would not reliably be.
		var qty_box: Array = [1]
		var btn_amount := UIUtil.make_button(UIUtil.format_gold(qty_box[0]), 44, 16)
		btn_amount.custom_minimum_size = Vector2(80, 44)
		row.add_child(btn_amount)

		var btn_buy := UIUtil.make_button(tr("trade_buy"), 44, 16)
		btn_buy.custom_minimum_size = Vector2(70, 44)
		row.add_child(btn_buy)

		var btn_buy_max := UIUtil.make_button(tr("trade_max"), 44, 16)
		btn_buy_max.custom_minimum_size = Vector2(60, 44)
		row.add_child(btn_buy_max)

		var btn_buy_max_capacity := UIUtil.make_button(tr("trade_max_capacity"), 44, 16)
		btn_buy_max_capacity.custom_minimum_size = Vector2(60, 44)
		row.add_child(btn_buy_max_capacity)

		var btn_buy_by_gold := UIUtil.make_button(tr("trade_buy_by_gold"), 44, 16)
		btn_buy_by_gold.custom_minimum_size = Vector2(70, 44)
		row.add_child(btn_buy_by_gold)

		var btn_sell := UIUtil.make_button(tr("trade_sell"), 44, 16)
		btn_sell.custom_minimum_size = Vector2(70, 44)
		row.add_child(btn_sell)

		var btn_sell_all := UIUtil.make_button(tr("trade_all"), 44, 16)
		btn_sell_all.custom_minimum_size = Vector2(60, 44)
		row.add_child(btn_sell_all)

		var refresh_row := func():
			var price := GameState.get_price(GameState.current_port_id, good.id)
			price_label.text = "%s: %s" % [tr("trade_price"), UIUtil.format_gold(price)]
			var owned: int = GameState.cargo.get(good.id, 0)
			owned_label.text = "%s: %s" % [tr("trade_owned"), UIUtil.format_gold(owned)]
			var max_buy := GameState.get_max_affordable(good.id)
			btn_buy.disabled = max_buy <= 0
			btn_buy_max.disabled = max_buy <= 0
			btn_buy_max_capacity.disabled = GameState.get_max_sailable_affordable(good.id) <= 0
			btn_buy_by_gold.disabled = max_buy <= 0
			btn_sell.disabled = owned <= 0
			btn_sell_all.disabled = owned <= 0

		refresh_row.call()
		row_refreshers.append(refresh_row)

		btn_amount.pressed.connect(func():
			_open_quantity_dialog(qty_box[0], func(new_qty: int):
				qty_box[0] = new_qty
				btn_amount.text = UIUtil.format_gold(new_qty)
			)
		)
		btn_buy.pressed.connect(func():
			_confirm_and_buy(good, qty_box[0], func():
				refresh_all_rows.call()
				refresh_status.call()
			)
		)
		btn_buy_max.pressed.connect(func():
			var max_buy := GameState.get_max_affordable(good.id)
			_confirm_and_buy(good, max_buy, func():
				qty_box[0] = max_buy
				btn_amount.text = UIUtil.format_gold(max_buy)
				refresh_all_rows.call()
				refresh_status.call()
			)
		)
		btn_buy_max_capacity.pressed.connect(func():
			_open_capacity_choice(good, func(max_buy: int):
				_confirm_and_buy(good, max_buy, func():
					qty_box[0] = max_buy
					btn_amount.text = UIUtil.format_gold(max_buy)
					refresh_all_rows.call()
					refresh_status.call()
				)
			)
		)
		btn_buy_by_gold.pressed.connect(func():
			var price := GameState.get_price(GameState.current_port_id, good.id)
			if price <= 0:
				return
			_open_quantity_dialog(price, func(entered_gold: int):
				# Rounds down to a whole number of units, and clamps the
				# spend to the gold actually on hand -- an entered amount
				# above current gold would otherwise produce a qty the
				# player can't actually afford.
				var spendable: int = min(entered_gold, GameState.gold)
				var qty := int(spendable / float(price))
				if qty <= 0:
					_show_message(tr("trade_gold_too_low"))
					return
				_confirm_and_buy_by_gold(good, qty, entered_gold, func():
					qty_box[0] = qty
					btn_amount.text = UIUtil.format_gold(qty)
					refresh_all_rows.call()
					refresh_status.call()
				)
			, "gold_dialog_title", 1)
		)
		btn_sell.pressed.connect(func():
			if GameState.sell(good.id, qty_box[0]):
				refresh_all_rows.call()
				refresh_status.call()
		)
		btn_sell_all.pressed.connect(func():
			var owned: int = GameState.cargo.get(good.id, 0)
			if owned <= 0:
				return
			var revenue := GameState.get_price(GameState.current_port_id, good.id) * owned
			_show_confirm(tr("confirm_sell_all") % [UIUtil.format_gold(owned), tr(good.name_key), UIUtil.format_gold(revenue)], func():
				if GameState.sell(good.id, owned):
					qty_box[0] = 1
					btn_amount.text = "1"
					refresh_all_rows.call()
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

	# A box, not a plain int, so the nested button callbacks below all read
	# the same live amount regardless of GDScript lambda capture semantics.
	var amount_box: Array = [100]
	var btn_amount := UIUtil.make_button(UIUtil.format_gold(amount_box[0]))
	btn_amount.pressed.connect(func():
		_open_quantity_dialog(amount_box[0], func(new_amount: int):
			amount_box[0] = new_amount
			btn_amount.text = UIUtil.format_gold(new_amount)
		)
	)
	vbox.add_child(btn_amount)

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
		info_label.text = "%s: %s\n%s: %s\n%s: %s\n%s: %s" % [
			tr("hud_gold"), UIUtil.format_gold(GameState.gold),
			tr("bank_savings"), UIUtil.format_gold(int(GameState.savings)),
			tr("bank_loan"), UIUtil.format_gold(int(GameState.loan)),
			tr("bank_max_loan"), UIUtil.format_gold(GameState.bank_max_loan()),
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
		GameState.bank_deposit(amount_box[0])
		refresh_info.call()
	)
	btn_deposit_max.pressed.connect(func():
		GameState.bank_deposit(GameState.gold)
		refresh_info.call()
	)
	btn_withdraw.pressed.connect(func():
		GameState.bank_withdraw(amount_box[0])
		refresh_info.call()
	)
	btn_withdraw_max.pressed.connect(func():
		GameState.bank_withdraw(int(GameState.savings))
		refresh_info.call()
	)
	btn_borrow.pressed.connect(func():
		GameState.bank_borrow(amount_box[0])
		refresh_info.call()
	)
	btn_borrow_max.pressed.connect(func():
		GameState.bank_borrow(GameState.bank_max_loan())
		refresh_info.call()
	)
	btn_repay.pressed.connect(func():
		GameState.bank_repay(amount_box[0])
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

	# Buying one upgrade changes gold (affects every other row's afford
	# check) and, for cargo tiers, ship_capacity (affects the "resulting
	# total" preview shown on every other cargo row) -- so a purchase has to
	# refresh every row, not just its own.
	var row_refreshers: Array[Callable] = []
	var refresh_all_rows := func():
		for refresher in row_refreshers:
			refresher.call()

	for up in GameState.upgrades:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var label := UIUtil.make_label(tr(up.name_key), 18)
		label.custom_minimum_size = Vector2(190, 0)
		row.add_child(label)

		var amount_label := UIUtil.make_label("", 14, Color("#CFE8F2"))
		amount_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(amount_label)

		var status_label := UIUtil.make_label("", 16)
		status_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(status_label)

		var btn_buy := UIUtil.make_button(tr("shipyard_buy") % UIUtil.format_gold(up.cost), 44, 16)
		row.add_child(btn_buy)

		var refresh_row := func():
			if GameState.is_upgrade_owned(up.id):
				status_label.text = tr("shipyard_owned")
				amount_label.text = tr("shipyard_amount_plain") % UIUtil.format_gold(up.amount)
				btn_buy.disabled = true
			elif up.requires_id != "" and not GameState.is_upgrade_owned(up.requires_id):
				status_label.text = tr("shipyard_locked")
				amount_label.text = tr("shipyard_amount_plain") % UIUtil.format_gold(up.amount)
				btn_buy.disabled = true
			else:
				status_label.text = ""
				if up.kind == ShipUpgrade.Kind.CARGO:
					amount_label.text = tr("shipyard_amount_cargo") % [UIUtil.format_gold(up.amount), UIUtil.format_gold(GameState.ship_capacity + up.amount)]
				else:
					amount_label.text = tr("shipyard_amount_plain") % UIUtil.format_gold(up.amount)
				btn_buy.disabled = not GameState.can_buy_upgrade(up.id)

		refresh_row.call()
		row_refreshers.append(refresh_row)
		btn_buy.pressed.connect(func():
			if GameState.buy_upgrade(up.id):
				refresh_all_rows.call()
		)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var sec_row := HBoxContainer.new()
	sec_row.add_theme_constant_override("separation", 10)
	vbox.add_child(sec_row)

	var sec_label := UIUtil.make_label(tr("shipyard_security_ships"), 18)
	sec_label.custom_minimum_size = Vector2(220, 0)
	sec_row.add_child(sec_label)

	var sec_status := UIUtil.make_label("", 16)
	sec_status.custom_minimum_size = Vector2(90, 0)
	sec_row.add_child(sec_status)

	var btn_hire := UIUtil.make_button("", 44, 16)
	sec_row.add_child(btn_hire)

	var refresh_sec := func():
		sec_status.text = tr("shipyard_security_owned") % GameState.security_ships
		btn_hire.text = tr("shipyard_hire") % UIUtil.format_gold(GameState.get_security_ship_cost())
		btn_hire.disabled = not GameState.can_hire_security_ship()

	refresh_sec.call()
	row_refreshers.append(refresh_sec) # hiring a ship spends gold too, same as buying an upgrade
	btn_hire.pressed.connect(func():
		if GameState.hire_security_ship():
			refresh_all_rows.call()
	)

	var sec_hint := UIUtil.make_label(tr("shipyard_security_hint"), 13, Color("#CFE8F2"))
	sec_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(sec_hint)

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
			var price_label := UIUtil.make_label(UIUtil.format_gold(GameState.get_price(port.id, good.id)), 15,
				Color("#D9A441") if is_here else Color("#FFF6E3"))
			price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(price_label)

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

## --- Rules ---

func _open_rules_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(600, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("rules_title"), 26))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	vbox.add_child(scroll)

	var label := UIUtil.make_label(UIUtil.load_rules_text(), 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(580, 0)
	scroll.add_child(label)

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

	if GameState.is_multiplayer():
		var btn_standings := UIUtil.make_button(tr("standings_button"))
		btn_standings.pressed.connect(_open_standings_panel)
		vbox.add_child(btn_standings)

	var btn_rules := UIUtil.make_button(tr("menu_rules"))
	btn_rules.pressed.connect(_open_rules_panel)
	vbox.add_child(btn_rules)

	var btn_save_exit := UIUtil.make_button(tr("menu_save_exit"))
	btn_save_exit.pressed.connect(func():
		SaveManager.save_game()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	vbox.add_child(btn_save_exit)

	var btn_restart := UIUtil.make_button(tr("menu_restart"))
	btn_restart.pressed.connect(func():
		_show_confirm(tr("confirm_restart"), func():
			var names: Array = []
			for p in GameState.players:
				names.append(p.player_name)
			GameState.new_multiplayer_game(GameState.game_length_days, names, "jaffa")
			get_tree().reload_current_scene()
		)
	)
	vbox.add_child(btn_restart)

## --- Standings (multiplayer only) ---

func _open_standings_panel() -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("standings_title"), 26))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(UIUtil.make_label("", 14))
	var header_name := UIUtil.make_label(tr("highscores_col_name"), 14, Color("#9FB6BE"))
	grid.add_child(header_name)
	var header_networth := UIUtil.make_label(tr("hud_networth"), 14, Color("#9FB6BE"))
	header_networth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(header_networth)

	var standings: Array = GameState.get_standings()
	var rank := 1
	for entry in standings:
		var rank_label := UIUtil.make_label("%d." % rank, 18)
		rank_label.custom_minimum_size = Vector2(28, 0)
		grid.add_child(rank_label)

		var idx: int = entry["index"]
		var is_active := idx == GameState.current_player_index
		var name_color := Color("#D9A441") if is_active else Color("#FFF6E3")
		grid.add_child(UIUtil.make_label(_active_player_label(idx), 17, name_color))

		var worth_label := UIUtil.make_label(UIUtil.format_gold(entry["net_worth"]), 17, name_color)
		worth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(worth_label)

		rank += 1

	var btn_close := UIUtil.make_button(tr("close"))
	btn_close.pressed.connect(_close_overlay)
	vbox.add_child(btn_close)

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
			var text := tr("log_pirates_won") % UIUtil.format_gold(result.get("bounty", 0))
			var loot: Dictionary = result.get("loot", {})
			if not loot.is_empty():
				text += "\n" + tr("log_pirates_won_goods") % _format_goods_list(loot)
			return text
		"lost":
			return tr("log_pirates_lost")
		"escaped":
			return tr("log_pirates_escaped")
		"caught":
			var text := tr("log_pirates_caught") % UIUtil.format_gold(result.get("ransom", 0))
			var lost_goods: Dictionary = result.get("lost_goods", {})
			if not lost_goods.is_empty():
				text += "\n" + tr("log_pirates_caught_goods") % _format_goods_list(lost_goods)
			return text
		"paid":
			return tr("log_pirates_paid") % UIUtil.format_gold(result.get("ransom", 0))
		_:
			return ""

## --- Special capacity offer ---

func _on_capacity_offer_available() -> void:
	var gold_cost := GameState.get_capacity_offer_gold_cost()
	var goods_value := GameState.get_capacity_offer_goods_value()
	var pay_with_goods := goods_value > gold_cost

	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(UIUtil.make_title(tr("capacity_offer_title"), 22))
	vbox.add_child(UIUtil.make_label(tr("capacity_offer_desc") % UIUtil.format_gold(GameState.get_capacity_offer_capacity_bonus()), 16))
	var cost_text: String
	if pay_with_goods:
		cost_text = tr("capacity_offer_cost_goods")
	else:
		cost_text = tr("capacity_offer_cost_gold") % UIUtil.format_gold(gold_cost)
	vbox.add_child(UIUtil.make_label(cost_text, 16))

	var btn_accept := UIUtil.make_button(tr("capacity_offer_accept"))
	btn_accept.pressed.connect(func():
		GameState.accept_capacity_offer()
		_close_specific_overlay(panel)
	)
	vbox.add_child(btn_accept)

	var btn_decline := UIUtil.make_button(tr("capacity_offer_decline"))
	btn_decline.pressed.connect(func(): _close_specific_overlay(panel))
	vbox.add_child(btn_decline)

## --- Millionaire warehouse gift ---

func _on_millionaire_gift_granted() -> void:
	_show_message(tr("millionaire_gift_message") % UIUtil.format_gold(GameState.MILLIONAIRE_GIFT_CAPACITY_BONUS))

func _on_mega_capacity_gift_granted(bonus: int) -> void:
	_show_message(tr("mega_capacity_gift_message") % UIUtil.format_gold(bonus))

## --- Billionaire gift ---

func _on_billionaire_gift_granted(security_ships_granted: int) -> void:
	_show_message(tr("billionaire_gift_message") % security_ships_granted)

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
				return tr("log_aground_none") % UIUtil.format_gold(repair_cost)
			return tr("log_aground_loss") % [_format_goods_list(lost), UIUtil.format_gold(repair_cost)]
		"overload":
			var lost: Dictionary = entry.get("lost_goods", {})
			var repair_cost: int = entry.get("repair_cost", 0)
			if entry.get("severe", false):
				return tr("log_overload_severe") % [_format_goods_list(lost), UIUtil.format_gold(repair_cost)]
			return tr("log_overload_minor") % _format_goods_list(lost)
		"fair_wind":
			if entry.get("half_days", 2) == 1:
				return tr("log_fair_wind_half_day")
			return tr("log_fair_wind")
		"market_demand":
			var good := GameState.get_good(entry.get("good_id", ""))
			var good_name := tr(good.name_key) if good else "?"
			return tr("log_market_demand") % [good_name, UIUtil.format_gold(entry.get("new_price", 0))]
		"pirates":
			return _format_pirate_result(entry)
		"warehouse":
			var lost: Dictionary = entry.get("lost_goods", {})
			if lost.is_empty():
				return ""
			var key := "log_warehouse_fire" if entry.get("cause", "fire") == "fire" else "log_warehouse_theft"
			return tr(key) % _format_goods_list(lost)
		_:
			return ""

func _format_goods_list(lost: Dictionary) -> String:
	var parts: Array = []
	for good_id in lost.keys():
		var good := GameState.get_good(good_id)
		parts.append("%s %s" % [UIUtil.format_gold(lost[good_id]), tr(good.name_key) if good else good_id])
	return ", ".join(parts)

func _show_message(text: String) -> void:
	var panel := _open_overlay()
	var vbox := VBoxContainer.new()
	# Wide enough for the longer congratulatory messages (millionaire/mega/
	# billionaire gifts) to wrap into a readable paragraph instead of running
	# off-screen as one unwrapped line -- same width as the rules panel,
	# which has the same "arbitrarily long body text" shape. _open_overlay()
	# already wraps every dialog in a full-screen ScrollContainer, so a
	# message tall enough to exceed the screen scrolls the same way rules do.
	vbox.custom_minimum_size = Vector2(600, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var label := UIUtil.make_label(text, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(580, 0)
	vbox.add_child(label)
	var btn_ok := UIUtil.make_button(tr("ok"))
	btn_ok.pressed.connect(_close_overlay)
	vbox.add_child(btn_ok)

## --- Game end ---

func _on_game_ended(_summary: Dictionary) -> void:
	get_tree().change_scene_to_file("res://scenes/EndGame.tscn")

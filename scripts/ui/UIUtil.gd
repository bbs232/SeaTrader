class_name UIUtil
extends RefCounted
## Small shared helpers for building touch-friendly UI purely from code.

## Formats an integer with thousands separators, e.g. 1324324 -> "1,324,324".
static func format_gold(amount: int) -> String:
	var sign := "-" if amount < 0 else ""
	var digits := str(absi(amount))
	var groups: Array[String] = []
	var i := digits.length()
	while i > 3:
		groups.push_front(digits.substr(i - 3, 3))
		i -= 3
	groups.push_front(digits.substr(0, i))
	return sign + ",".join(groups)

## Wires a numeric-entry LineEdit to keep itself live-formatted with
## thousands-separator commas (via format_gold) as the player types, so a
## typed-in amount stays readable digit-group by digit-group (hundreds of
## thousands, millions, hundreds of millions...) instead of running together
## as one undifferentiated string of digits. Re-derives the caret position
## from how many actual digits (not commas) sat before it, so typing/deleting
## mid-string doesn't jump the caret to an unrelated spot once commas shift.
static func wire_live_gold_formatting(edit: LineEdit) -> void:
	var reentrant := [false] # boxed -- lambdas capture locals by value, not by reference
	edit.text_changed.connect(func(new_text: String):
		if reentrant[0]:
			return
		reentrant[0] = true
		var caret: int = edit.caret_column
		var digits_before_caret := 0
		for i in range(mini(caret, new_text.length())):
			if new_text[i] != ",":
				digits_before_caret += 1
		var digits := ""
		for c in new_text:
			if c >= "0" and c <= "9":
				digits += c
		var formatted := format_gold(int(digits)) if digits != "" else ""
		edit.text = formatted
		var new_caret := formatted.length()
		var seen := 0
		for i in range(formatted.length()):
			if seen >= digits_before_caret:
				new_caret = i
				break
			if formatted[i] != ",":
				seen += 1
		edit.caret_column = new_caret
		reentrant[0] = false
	)

static func make_button(text: String, min_h: int = 56, font_size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func make_label(text: String, font_size: int = 22, color: Color = Color("#FFF6E3")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_title(text: String, font_size: int = 40) -> Label:
	var l := make_label(text, font_size, Color("#D9A441"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.16, 0.22, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color("#D9A441")
	p.add_theme_stylebox_override("panel", style)
	return p

static func make_bg(texture_path: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load(texture_path)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

static func apply_rtl(control: Control) -> void:
	control.layout_direction = Control.LAYOUT_DIRECTION_LOCALE

## Builds the shared look for every raw Control (Button/LineEdit/SpinBox/...)
## so screens get consistent, polished styling even where they use engine
## controls directly instead of going through the make_* helpers above.
## Applied once per top-level scene via `self.theme = UIUtil.build_theme()`.
static func build_theme() -> Theme:
	var theme := Theme.new()
	var gold := Color("#D9A441")
	var cream := Color("#FFF6E3")

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.11, 0.24, 0.31, 0.95)
	btn_normal.set_corner_radius_all(10)
	btn_normal.set_content_margin_all(10)
	btn_normal.set_border_width_all(2)
	btn_normal.border_color = gold.lerp(Color.BLACK, 0.35)

	var btn_hover: StyleBoxFlat = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.16, 0.32, 0.41, 0.98)
	btn_hover.border_color = gold

	var btn_pressed: StyleBoxFlat = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.06, 0.13, 0.17, 0.98)
	btn_pressed.border_color = gold

	var btn_disabled: StyleBoxFlat = btn_normal.duplicate()
	btn_disabled.bg_color = Color(0.14, 0.14, 0.15, 0.6)
	btn_disabled.border_color = Color(0.4, 0.4, 0.4, 0.6)

	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("focus", "Button", btn_hover)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_color("font_color", "Button", cream)
	theme.set_color("font_hover_color", "Button", Color("#FFE9B8"))
	theme.set_color("font_pressed_color", "Button", Color("#FFE9B8"))
	theme.set_color("font_focus_color", "Button", Color("#FFE9B8"))
	theme.set_color("font_disabled_color", "Button", Color(0.62, 0.62, 0.62))

	var line_normal := StyleBoxFlat.new()
	line_normal.bg_color = Color(0.06, 0.12, 0.16, 0.9)
	line_normal.set_corner_radius_all(8)
	line_normal.set_content_margin_all(8)
	line_normal.set_border_width_all(1)
	line_normal.border_color = gold.lerp(Color.BLACK, 0.4)

	var line_focus: StyleBoxFlat = line_normal.duplicate()
	line_focus.border_color = gold

	theme.set_stylebox("normal", "LineEdit", line_normal)
	theme.set_stylebox("focus", "LineEdit", line_focus)
	theme.set_color("font_color", "LineEdit", cream)
	theme.set_color("font_placeholder_color", "LineEdit", Color(0.75, 0.8, 0.82, 0.6))
	theme.set_color("caret_color", "LineEdit", gold)

	theme.set_stylebox("up_background", "SpinBox", btn_normal)
	theme.set_stylebox("down_background", "SpinBox", btn_normal)
	theme.set_stylebox("up_background_hovered", "SpinBox", btn_hover)
	theme.set_stylebox("down_background_hovered", "SpinBox", btn_hover)
	theme.set_stylebox("up_background_pressed", "SpinBox", btn_pressed)
	theme.set_stylebox("down_background_pressed", "SpinBox", btn_pressed)

	return theme

## Rules text is embedded here (not in the CSV translation table, which isn't
## meant to carry long-form prose with commas/newlines) and not loaded from a
## plain .txt asset either -- Godot's "all_resources" export filter silently
## drops raw, unimported file types like .txt from the exported PCK, so a
## GDScript constant is the only reliable way to ship it.
static func load_rules_text() -> String:
	if TranslationServer.get_locale().begins_with("he"):
		return _RULES_HE
	return _RULES_EN

const _RULES_HE := """מטרת המשחק
לצבור את ההון הנקי הגבוה ביותר (זהב + שווי מטען + חיסכון − הלוואה) עד תום הימים שנבחרו למשחק.

נמלים ומחירים
יש 7 נמלים ו-6 סוגי סחורות. מסך "מחירי שוק" מציג את המחירים הנוכחיים בכל הנמלים בו-זמנית, אך המחירים ממשיכים להשתנות בכל יום — כולל בזמן הפלגה — כך שהמחיר ביעד עשוי להיות שונה עד ההגעה בפועל.

מסחר
"קנה"/"מכור" פועלים על הכמות שנבחרה. "מקס׳" קונה את המקסימום האפשרי לפי הזהב הפנוי ומקום בספינה. "הכל" מוכר את כל הכמות המוחזקת. קנייה מרבית או מכירה מלאה תמיד מציגות חלון אישור מראש, ואם הקנייה תגרום לעומס יתר — האזהרה על כך מופיעה בתוך אותו חלון אישור, לפני ביצוע הרכישה.

נסיעה וזמן
אפשר להפליג ישירות בין כל שני נמלים. ברירת המחדל היא הפלגה של חצי יום, חוץ מהקווים הבאים שאורכים יום שלם: מונציה — לאלכסנדריה, ללימסול, לאיסטנבול, לביירות וליפו; מאיסטנבול — לאלכסנדריה, ליפו ולביירות; מפיראוס — ליפו ולביירות. כל שאר הקווים, כולל פיראוס-ונציה, אורכים חצי יום. בהפלגות של יום שלם חולף יום אמיתי: המחירים מתעדכנים, וריבית נצברת על הלוואות/חיסכון — בהפלגות חצי-יום כמעט שום דבר מזה לא מספיק להשתנות.

מנוחה בנמל
כפתור "מנוחה" מדלג יום קדימה בלי להפליג: המחירים והריבית מתעדכנים בדיוק כמו ביום הפלגה רגיל, אבל בלי שום סיכון לאירועי דרך כי הספינה נשארת בנמל.

פיראטים
עלולה להופיע ספינת פיראטים. ניתן להילחם (תלוי בחיזוק הספינה), לברוח (תלוי במפרשים), או לשלם כופר ולהיפטר מהעימות מיד.

אירועים בדרך
סערה ושרטון עלולים לגרום לאובדן מטען ולעלות תיקון בזהב (שרטון תמיד גובה עלות תיקון). רוח גבית מקצרת את ההפלגה ביום, או בחצי יום אם זה כל מה שנותר. שמועות ביקוש מעלות דרמטית (אף פעם לא מורידות) מחיר של סחורה אקראית בנמל היעד שאליו אתם מפליגים. שדרוגי חיזוק מקטינים סיכוני נזק.

עומס יתר
ניתן לטעון עד פי 1.5 מהקיבולת הנקובה של הספינה, אך כל יום הפלגה בעומס יתר יש סיכון הולך וגדל לאובדן מטען עודף, ובמקרים חמורים גם נזק לספינה שדורש תיקון בזהב.

שדרוגי ספינה
הרחבת מחסן מגדילה את קיבולת המטען, וניתן לשדרג אותה עד ארבע רמות. חיזוק גוף משפר קרבות פיראטים ומקטין נזקים. שדרוג מפרשים משפר סיכויי בריחה מפיראטים. לחיזוק גוף ולמפרשים שתי רמות, ולהרחבת מחסן ארבע רמות; כל רמה דורשת בעלות על הרמה שלפניה.

ספינות אבטחה
במספנה ניתן לגייס ספינות אבטחה נוספות, ללא הגבלת מספר. כל ספינה עולה יותר מקודמתה, אך מוסיפה 15% לסיכוי הניצחון בקרב מול פיראטים.

בנק
ניתן להפקיד/למשוך זהב מחיסכון (עם ריבית), וללוות/להחזיר הלוואה עד למסגרת אשראי שתלויה בהון הנקי.

שמירה ושיאים
ניתן לשמור משחק פעיל ולחזור אליו, ולשמור את ההון הנקי הסופי בלוח השיאים בסיום המשחק."""

const _RULES_EN := """Goal
Reach the highest net worth (gold + cargo value + savings - loan) by the end of the chosen game length.

Ports and prices
There are 7 ports and 6 goods. The "Market Prices" screen shows current prices at every port at once, but prices keep drifting every day - including while you're sailing - so the price at your destination may differ by the time you actually arrive.

Trading
"Buy"/"Sell" act on the chosen quantity. "Max" buys the largest amount you can afford that still fits the ship. "All" sells your entire held quantity of a good. Buying the max or selling all always shows a confirmation dialog first, and if the purchase would overload the ship, that warning appears inside the same confirmation dialog, before the purchase happens.

Travel and time
You can sail directly between any two ports. Most legs take half a day, except these, which take a full day: from Venice -- to Alexandria, Limassol, Istanbul, Beirut, or Jaffa; from Istanbul -- to Alexandria, Jaffa, or Beirut; from Piraeus -- to Jaffa or Beirut. Every other leg, including Piraeus-Venice, is half a day. On full-day voyages, a real day passes: prices update, and interest accrues on loans/savings -- on half-day legs, barely any of that has time to happen.

Resting at port
The "Rest" button skips a day forward without sailing anywhere: prices and interest update exactly like on a normal travel day, but with no risk of any travel event since the ship never leaves port.

Pirates
A pirate ship may appear during a voyage. You can fight (depends on hull upgrades), flee (depends on sail upgrades), or pay a ransom to end the encounter immediately.

Events at sea
Storms and running aground can cause cargo loss and a gold repair cost (running aground always costs a repair fee). A fair wind shortens the voyage by a day, or by half a day if that's all that's left. Rumors of high demand cause the price of a random good to spike dramatically (never drop) at the port you're actually sailing to. Hull upgrades reduce damage risk.

Overload
You can load up to 1.5x the ship's nominal capacity, but every day sailing overloaded carries a growing risk of losing excess cargo, and in severe cases hull damage requiring a gold repair.

Ship upgrades
Cargo Hold increases capacity and can be upgraded through four tiers. Hull Plating improves pirate fights and reduces damage. Sail Upgrade improves your odds of fleeing pirates. Hull Plating and Sail Upgrade each have two tiers, Cargo Hold has four; every tier requires owning the one before it.

Security ships
The Shipyard also lets you hire additional security ships, with no limit on how many. Each one costs more than the last, but adds 15% to your win chance when fighting pirates.

Bank
Deposit/withdraw gold to/from savings (which earns interest), and borrow/repay a loan up to a credit limit based on your net worth.

Saving and high scores
You can save an active game and resume it later, and save your final net worth to the local high score board when a game ends."""

class_name UIUtil
extends RefCounted
## Small shared helpers for building touch-friendly UI purely from code.

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
הפלגה רגילה בין שני נמלים (שאינם לימסול) אורכת יום אחד, והפלגה ל/מפיראוס או ונציה אורכת יומיים. כל הפלגה שנוגעת בלימסול אורכת חצי יום בלבד — חוץ מהקטע לימסול-ונציה, שאורך יום שלם. בהפלגות של יום ומעלה חולפים ימים אמיתיים, המחירים מתעדכנים, וריבית נצברת על הלוואות/חיסכון.

מגבלת מסלולים לפיראוס ולונציה
אי אפשר להפליג ישירות לפיראוס או לונציה, וגם לא לחזור מהם ישירות, לכל נמל אחר. חובה לעצור קודם באחד משלושת נמלי הציר: לימסול, איסטנבול או אלכסנדריה. גם הפלגה ישירה בין פיראוס לונציה עצמן אסורה. נמלים חסומים למסלול ישיר מסומנים במפה במעומעם.

פיראטים
עלולה להופיע ספינת פיראטים. ניתן להילחם (תלוי בחיזוק הספינה), לברוח (תלוי במפרשים), או לשלם כופר ולהיפטר מהעימות מיד.

אירועים בדרך
סערה ושרטון עלולים לגרום לאובדן מטען ולעלות תיקון בזהב (שרטון תמיד גובה עלות תיקון). רוח גבית מקצרת את ההפלגה ביום. שדרוגי חיזוק מקטינים סיכוני נזק.

עומס יתר
ניתן לטעון עד פי 1.5 מהקיבולת הנקובה של הספינה, אך כל יום הפלגה בעומס יתר יש סיכון הולך וגדל לאובדן מטען עודף, ובמקרים חמורים גם נזק לספינה שדורש תיקון בזהב.

שדרוגי ספינה
הרחבת מחסן מגדילה את קיבולת המטען. חיזוק גוף משפר קרבות פיראטים ומקטין נזקים. שדרוג מפרשים משפר סיכויי בריחה מפיראטים. לכל שדרוג שתי רמות, השנייה דורשת בעלות על הראשונה.

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
A regular voyage between two ports (neither of them Limassol) takes one day, and a voyage to/from Piraeus or Venice takes two days. Any leg touching Limassol takes only half a day -- except the Limassol-Venice leg, which takes a full day. On voyages of a day or more, real days pass: prices update, and interest accrues on loans/savings.

Route restriction for Piraeus and Venice
You cannot sail directly to Piraeus or Venice, or directly back from them, to/from any other port. You must first stop at one of the three hub ports: Limassol, Istanbul, or Alexandria. Direct travel between Piraeus and Venice themselves is also blocked. Ports you can't reach directly are shown dimmed on the map.

Pirates
A pirate ship may appear during a voyage. You can fight (depends on hull upgrades), flee (depends on sail upgrades), or pay a ransom to end the encounter immediately.

Events at sea
Storms and running aground can cause cargo loss and a gold repair cost (running aground always costs a repair fee). A fair wind shortens the voyage by a day. Hull upgrades reduce damage risk.

Overload
You can load up to 1.5x the ship's nominal capacity, but every day sailing overloaded carries a growing risk of losing excess cargo, and in severe cases hull damage requiring a gold repair.

Ship upgrades
Cargo Hold increases capacity. Hull Plating improves pirate fights and reduces damage. Sail Upgrade improves your odds of fleeing pirates. Each has two tiers; the second requires owning the first.

Bank
Deposit/withdraw gold to/from savings (which earns interest), and borrow/repay a loan up to a credit limit based on your net worth.

Saving and high scores
You can save an active game and resume it later, and save your final net worth to the local high score board when a game ends."""

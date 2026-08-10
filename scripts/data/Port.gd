extends Resource
class_name Port

@export var id: String = ""
@export var name_key: String = ""
## Position on the stylized world map (viewport pixel coords)
@export var map_position: Vector2 = Vector2.ZERO
## good_id -> price multiplier. Below 1.0 = this port produces it cheaply, above 1.0 = scarce/expensive.
@export var price_modifiers: Dictionary = {}
## How dangerous the waters around this port are (0.0 - 1.0), affects pirate chance when leaving/arriving.
@export var danger_level: float = 0.2
@export var icon: Texture2D

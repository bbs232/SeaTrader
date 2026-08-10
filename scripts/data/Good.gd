extends Resource
class_name Good

@export var id: String = ""
@export var name_key: String = ""
@export var base_price: int = 10
## How much prices swing day to day (0.0 - 1.0)
@export var volatility: float = 0.2
@export var icon: Texture2D

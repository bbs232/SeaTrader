extends Resource
class_name EventDef

enum Kind { STORM, PIRATES, FAIR_WIND, MARKET_DEMAND, AGROUND }

@export var id: String = ""
@export var kind: Kind = Kind.STORM
## Base chance per travel day before danger_level/modifiers are applied (0.0 - 1.0)
@export var base_chance: float = 0.1

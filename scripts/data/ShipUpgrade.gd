extends Resource
class_name ShipUpgrade

enum Kind { CARGO, HULL, SAIL }

@export var id: String = ""
@export var name_key: String = ""
@export var kind: Kind = Kind.CARGO
@export var cost: int = 500
## Amount added to the relevant ship stat when purchased.
@export var amount: int = 20
## Prerequisite upgrade id required before this one can be bought (tiering). Empty = no prerequisite.
@export var requires_id: String = ""

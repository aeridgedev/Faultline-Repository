## Faultline — manual loot pickup. Automatic collection is disabled; the player
## presses Q ("pickup") while within pickup range of a LootDrop to collect it.
## When several drops are in range, the closest is collected first (one item per
## press). If the closest item cannot be accepted, a brief "Inventory full" HUD
## message is shown.
class_name AutoCollect
extends Node

@onready var _inventory: InventoryManager = $"../InventoryManager"
@onready var _controller: PlayerController = get_parent() as PlayerController

var _pickup_radius: float = 0.0   # TBD: loaded from data["pickup_radius"]


func _ready() -> void:
	var r = GameManager.data.get("pickup_radius", null)
	_pickup_radius = float(r) if r != null else 32.0  # 32px fallback (2 tiles)


func _physics_process(_delta: float) -> void:
	if _controller == null or _controller.stats.is_dead:
		return
	if Input.is_action_just_pressed("pickup"):
		_try_pickup()


## Collect the closest in-range LootDrop. One item per Q press. Shows
## "Inventory full" when the closest in-range drop cannot be accepted.
func _try_pickup() -> void:
	var my_pos: Vector2 = _controller.global_position
	var closest: LootDrop = null
	var closest_dist: float = _pickup_radius   # only drops within radius qualify
	# Group lookup — LootDrop.add_to_group("loot_drops") in _ready(); freed drops
	# leave the group automatically. O(active drops only).
	for node: Node in get_tree().get_nodes_in_group("loot_drops"):
		var drop := node as LootDrop
		if drop == null or drop.pickup_delay > 0.0:
			continue
		var dist: float = my_pos.distance_to(drop.global_position)
		if dist > closest_dist:
			continue
		closest = drop
		closest_dist = dist

	if closest == null:
		return  # nothing pickable in range

	if not _inventory.can_add(closest.item_data):
		_controller._show_notify("Inventory full", 1.5)
		return

	if _inventory.add_item(closest.item_data) >= 0:
		closest.consume()

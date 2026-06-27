## Faultline — scans nearby LootDrop nodes each frame and collects them
## when the player is within pickup radius and LootRestriction allows it.
class_name AutoCollect
extends Node

@onready var _inventory: InventoryManager = $"../InventoryManager"
@onready var _controller: PlayerController = get_parent() as PlayerController

var _pickup_radius: float = 0.0   # TBD: loaded from data["pickup_radius"]

const _SCAN_INTERVAL := 0.1   # seconds between world scans (not every physics frame)
var _scan_timer: float = 0.0


func _ready() -> void:
	var r = GameManager.data.get("pickup_radius", null)
	_pickup_radius = float(r) if r != null else 32.0  # 32px fallback (2 tiles)


func _physics_process(delta: float) -> void:
	if _controller == null or _controller.stats.is_dead:
		return
	_scan_timer += delta
	if _scan_timer < _SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	_scan_for_drops()


func _scan_for_drops() -> void:
	# Skip scan only when every slot is full — armor slot counts separately.
	if not _inventory.has_space() and _inventory.get_armor() != null:
		return
	if not LootRestriction.can_loot(_controller.is_drilling(), _controller.is_attacking()):
		return

	var my_pos: Vector2 = _controller.global_position
	# Walk the scene tree from root to find all LootDrop nodes.
	# This is deliberately simple for offline play; server step will use interest management.
	var root := get_tree().get_root()
	_collect_nearby(root, my_pos)


func _collect_nearby(node: Node, my_pos: Vector2) -> void:
	if node is LootDrop:
		var drop := node as LootDrop
		if my_pos.distance_to(drop.global_position) <= _pickup_radius:
			if _inventory.can_add(drop.item_data):
				var accepted := _inventory.add_item(drop.item_data)
				if accepted >= 0:
					drop.consume()
					return
	for child in node.get_children():
		if not _inventory.has_space() and _inventory.get_armor() != null:
			return
		_collect_nearby(child, my_pos)

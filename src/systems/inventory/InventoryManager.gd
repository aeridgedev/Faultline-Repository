## Faultline — manages all 8 carry slots for one player.
## Layout: slots 0–4 = hotbar (drill + weapon live here too),
##         slot  5   = armor sidebar (armor items only),
##         slots 6–7 = backpack.
## Each item is a Dictionary {type, item_class, tier} from LootTable.
## Full Resource-based items arrive in Step 5 (weapons) and are slotted the same way.
class_name InventoryManager
extends Node

signal slot_changed(slot_idx: int, item)   # item = Dictionary or null

const HOTBAR_START  := 0
const HOTBAR_END    := Constants.HOTBAR_SLOTS - 1          # 4
const ARMOR_SLOT    := Constants.HOTBAR_SLOTS              # 5
const BACKPACK_START := Constants.HOTBAR_SLOTS + 1         # 6
const BACKPACK_END  := Constants.TOTAL_CARRY_SLOTS - 1     # 7

var _slots: Array = []   # size 8; each entry = Dictionary or null


func _ready() -> void:
	_slots.resize(Constants.TOTAL_CARRY_SLOTS)
	for i in _slots.size():
		_slots[i] = null


## Attempt to add item_data (Dictionary from LootTable) to the first available slot.
## Returns the slot index used, or -1 if no space.
func add_item(item_data: Dictionary) -> int:
	if item_data.get("type", "") == "armor":
		if _slots[ARMOR_SLOT] == null:
			_set_slot(ARMOR_SLOT, item_data)
			return ARMOR_SLOT
	for i in range(HOTBAR_START, HOTBAR_END + 1):
		if _slots[i] == null:
			_set_slot(i, item_data)
			return i
	for i in range(BACKPACK_START, BACKPACK_END + 1):
		if _slots[i] == null:
			_set_slot(i, item_data)
			return i
	return -1  # inventory full


func remove_item(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _slots.size():
		return
	_set_slot(slot_idx, null)


func get_item(slot_idx: int):
	if slot_idx < 0 or slot_idx >= _slots.size():
		return null
	return _slots[slot_idx]


func swap_slots(a: int, b: int) -> void:
	if a < 0 or a >= _slots.size() or b < 0 or b >= _slots.size():
		return
	var tmp = _slots[a]
	_set_slot(a, _slots[b])
	_set_slot(b, tmp)


func has_space() -> bool:
	for i in range(HOTBAR_START, HOTBAR_END + 1):
		if _slots[i] == null:
			return true
	for i in range(BACKPACK_START, BACKPACK_END + 1):
		if _slots[i] == null:
			return true
	return false


func get_armor():
	return _slots[ARMOR_SLOT]


## Returns all non-null items as an Array of {slot, item} Dictionaries.
func all_items() -> Array:
	var result := []
	for i in _slots.size():
		if _slots[i] != null:
			result.append({"slot": i, "item": _slots[i]})
	return result


func _set_slot(idx: int, value) -> void:
	_slots[idx] = value
	slot_changed.emit(idx, value)

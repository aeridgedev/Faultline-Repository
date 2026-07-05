## Faultline — tracks the active hotbar slot and handles slot-switch input.
## Slot indices 0–4 match InventoryManager's hotbar range.
class_name Hotbar
extends Node

signal active_slot_changed(slot_idx: int)

@onready var _inventory: InventoryManager = $"../InventoryManager"

var _active_slot: int = 0


func _ready() -> void:
	active_slot_changed.emit(_active_slot)


func _input(event: InputEvent) -> void:
	if _inventory != null and _inventory.is_open:
		return
	if event is InputEventKey:
		# NOTE: InputEvent has is_action_pressed(), NOT is_action_just_pressed()
		# (that one only exists on the Input singleton). Inside _input(), a pressed
		# key event firing the action already means "just pressed".
		for i in range(Constants.HOTBAR_SLOTS):
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				select_slot(i)
				return
		if event.is_action_pressed("cycle_throwable"):
			_cycle_throwable()
			return
		if event.is_action_pressed("cycle_consumable"):
			_cycle_consumable()
			return
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				select_slot((_active_slot + 1) % Constants.HOTBAR_SLOTS)
			MOUSE_BUTTON_WHEEL_UP:
				select_slot((_active_slot - 1 + Constants.HOTBAR_SLOTS) % Constants.HOTBAR_SLOTS)


# R key: select the next throwable-type item among the free hotbar slots (3-5,
# indices 2-4). Starts searching just after the current active slot and wraps
# around, so repeated presses step through every throwable in the hotbar. Reserved
# drill/weapon slots (0-1) are never candidates. No-op if no throwable is carried.
func _cycle_throwable() -> void:
	_cycle_type("throwable")


# C key: same as _cycle_throwable() but for consumable-type items. Lets a player
# step through every consumable they carry (Bloodstim / Medkit / Thermal Capsule /
# Fault Beacon / Lytes) in the free hotbar slots. No-op if no consumable is carried.
func _cycle_consumable() -> void:
	_cycle_type("consumable")


# Selects the next free-hotbar-slot (3-5, indices 2-4) item whose "type" matches,
# starting just after the current active slot and wrapping, so repeated presses
# step through every match. Reserved drill/weapon slots (0-1) are never candidates.
func _cycle_type(item_type: String) -> void:
	if _inventory == null:
		return
	var start := InventoryManager.FREE_HOTBAR_START
	var count := InventoryManager.HOTBAR_END - InventoryManager.FREE_HOTBAR_START + 1
	for step in range(1, count + 1):
		var idx := start + posmod(_active_slot - start + step, count)
		var item = _inventory.get_item(idx)
		if item != null and item.get("type") == item_type:
			select_slot(idx)
			return


func select_slot(idx: int) -> void:
	idx = clampi(idx, 0, Constants.HOTBAR_SLOTS - 1)
	if idx == _active_slot:
		return
	_active_slot = idx
	active_slot_changed.emit(_active_slot)


func get_active_slot() -> int:
	return _active_slot


func get_active_item():
	if _inventory == null:
		return null
	return _inventory.get_item(_active_slot)

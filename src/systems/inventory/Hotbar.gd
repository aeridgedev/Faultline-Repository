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
	if event is InputEventKey:
		for i in range(Constants.HOTBAR_SLOTS):
			if event.is_action_just_pressed("hotbar_%d" % (i + 1)):
				select_slot(i)
				return
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				select_slot((_active_slot + 1) % Constants.HOTBAR_SLOTS)
			MOUSE_BUTTON_WHEEL_UP:
				select_slot((_active_slot - 1 + Constants.HOTBAR_SLOTS) % Constants.HOTBAR_SLOTS)


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

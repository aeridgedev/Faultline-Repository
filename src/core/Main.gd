extends Node2D
## Faultline — temporary boot/entry scene.
##
## Phase 0 placeholder. This will become the bootstrap that loads the world,
## spawns the local player, and (later) hands off to the network client.
## For now it just confirms the project boots and data loads correctly.

func _ready() -> void:
	print("=== Faultline boot ===")
	print("Tiers: ", Constants.TIER_NAMES.values())
	print("Layers: ", Constants.LAYER_NAMES.values())
	print("Chest spawn — Crust: %.3f  Mantle: %.3f  Outer: %.3f  Inner: %.3f" % [
		Constants.chest_spawn_chance(0.0),
		Constants.chest_spawn_chance(0.2),
		Constants.chest_spawn_chance(0.4),
		Constants.chest_spawn_chance(0.6),
	])
	print("Carry slots — hotbar %d + armor %d + backpack %d = %d" % [
		Constants.HOTBAR_SLOTS, Constants.ARMOR_SLOTS,
		Constants.BACKPACK_SLOTS, Constants.TOTAL_CARRY_SLOTS,
	])
	print("======================")

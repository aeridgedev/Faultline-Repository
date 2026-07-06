## Faultline — UpgradeTemplate in-world item. Applies a tier upgrade to a held drill or weapon.
## Weight in the relevant rarity pool = 10% (LOCKED, CLAUDE.md). Application logic is in
## DrillUpgrade.apply() / WeaponUpgrade.apply(); this is the pickup-side item data wrapper.
class_name UpgradeTemplate
extends Resource

# Which rarity pool this template belongs to (matches the target item's current tier).
# Stored as int to avoid @export type resolution issues with autoload enums.
@export var target_tier: int = 0


## Try to upgrade the best candidate in the given inventory.
## Priority: active hotbar drill → active hotbar weapon → first drill → first weapon.
func apply_to_inventory(inventory: InventoryManager, hotbar: Hotbar) -> bool:
	var active: Variant = inventory.get_item(hotbar.get_active_slot())
	if _try_upgrade_item_data(active, inventory, hotbar.get_active_slot()):
		return true
	for entry in inventory.all_items():
		if _try_upgrade_item_data(entry["item"], inventory, entry["slot"]):
			return true
	return false


func _try_upgrade_item_data(item_data, inventory: InventoryManager, slot: int) -> bool:
	if item_data == null:
		return false
	# Items in the inventory are Dictionaries {type, item_class, tier} (Step 4 design).
	# When Step 5 Resource items are equipped, the drill/weapon live on PlayerController,
	# not in InventoryManager — handle those via the caller providing the equipped item directly.
	var item_tier = item_data.get("tier", null)
	if item_tier == null or item_tier != target_tier:
		return false
	if item_tier >= Constants.TIER_CEILING:
		return false  # already legendary
	# Raise tier in the dictionary — actual Resource upgrade happens on equipped items.
	item_data["tier"] = item_tier + 1
	return true

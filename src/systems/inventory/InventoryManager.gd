## Faultline — manages all 8 carry slots for one player.
## Layout: slot  0   = reserved DRILL slot  (hotbar slot 1, drills only),
##         slot  1   = reserved WEAPON slot (hotbar slot 2, melee weapons only),
##         slots 2–4 = free hotbar          (hotbar slots 3–5: consumables/throwables/…),
##         slot  5   = armor sidebar (armor items only),
##         slots 6–7 = backpack (overflow for the free-hotbar item types).
## The drill/weapon slots are FIXED: a picked-up drill always replaces slot 0 and a
## picked-up melee weapon always replaces slot 1, dropping the old one to the world.
## Each item is a Dictionary {type, item_class, tier} from LootTable.
class_name InventoryManager
extends Node

signal slot_changed(slot_idx: int, item)   # item = Dictionary or null
signal inventory_opened
signal inventory_closed

const HOTBAR_START   := 0
const HOTBAR_END     := 4   # HOTBAR_SLOTS - 1
const DRILL_SLOT     := 0   # reserved: drills only (hotbar slot 1, 1-based)
const WEAPON_SLOT    := 1   # reserved: melee weapons only (hotbar slot 2, 1-based)
const FREE_HOTBAR_START := 2   # slots 3–5 (1-based): free for other item types
const ARMOR_SLOT     := 5   # HOTBAR_SLOTS
const BACKPACK_START := 6   # HOTBAR_SLOTS + 1
const BACKPACK_END   := 7   # TOTAL_CARRY_SLOTS - 1

var _slots: Array = []   # size 8; each entry = Dictionary or null
var is_open: bool = false

var _panel_layer: CanvasLayer = null
var _slot_rows: Array = []   # [{lbl: Label, btn: Button, idx: int}, ...]


func _ready() -> void:
	_slots.resize(Constants.TOTAL_CARRY_SLOTS)
	for i in _slots.size():
		_slots[i] = null
	_build_panel()
	# Auto-refresh the open panel whenever any slot changes.
	slot_changed.connect(func(_idx: int, _item: Variant) -> void:
		if is_open:
			_refresh_panel())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F:
		if is_open:
			close_panel()
		else:
			open_panel()
		get_viewport().set_input_as_handled()


# --- Panel open / close ---

func open_panel() -> void:
	if is_open:
		return
	is_open = true
	_refresh_panel()
	_panel_layer.visible = true
	inventory_opened.emit()


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_panel_layer.visible = false
	inventory_closed.emit()


# --- Panel construction (built once in _ready, shown/hidden on demand) ---

func _build_panel() -> void:
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 20
	_panel_layer.visible = false
	add_child(_panel_layer)

	# Dim backdrop — blocks mouse input to the world while panel is open.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_layer.add_child(backdrop)

	# Centered panel — 220×270.
	var panel := Panel.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -110.0
	panel.offset_right  =  110.0
	panel.offset_top    = -135.0
	panel.offset_bottom =  135.0

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.35, 0.40, 0.50)
	ps.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", ps)
	_panel_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "INVENTORY   [F to close]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 8)
	title.add_theme_color_override("font_color", Color(0.90, 0.72, 0.30))
	vbox.add_child(title)

	_add_section(vbox, "HOTBAR", [0, 1, 2, 3, 4])
	_add_section(vbox, "ARMOR", [ARMOR_SLOT])
	_add_section(vbox, "BACKPACK", [BACKPACK_START, BACKPACK_END])


func _add_section(vbox: VBoxContainer, header: String, indices: Array) -> void:
	var sep := HSeparator.new()
	vbox.add_child(sep)

	var hdr := Label.new()
	hdr.text = header
	hdr.add_theme_font_size_override("font_size", 6)
	hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	vbox.add_child(hdr)

	for idx in indices:
		vbox.add_child(_build_slot_row(idx))


func _build_slot_row(slot_idx: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Fixed-width slot identifier.
	var lbl_key := Label.new()
	lbl_key.text = _slot_key_name(slot_idx)
	lbl_key.custom_minimum_size = Vector2(22, 0)
	lbl_key.add_theme_font_size_override("font_size", 7)
	lbl_key.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	row.add_child(lbl_key)

	# Expanding item name — colored by tier when occupied.
	var lbl_item := Label.new()
	lbl_item.text = "—"
	lbl_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_item.add_theme_font_size_override("font_size", 8)
	lbl_item.add_theme_color_override("font_color", Color(0.30, 0.32, 0.38))
	row.add_child(lbl_item)

	var btn := Button.new()
	btn.text = "Drop"
	btn.custom_minimum_size = Vector2(38, 16)
	btn.add_theme_font_size_override("font_size", 7)
	btn.disabled = true
	btn.pressed.connect(_on_discard_pressed.bind(slot_idx))
	row.add_child(btn)

	_slot_rows.append({"lbl": lbl_item, "btn": btn, "idx": slot_idx})
	return row


func _refresh_panel() -> void:
	for entry in _slot_rows:
		var idx: int    = entry.idx
		var item        = _slots[idx]
		var lbl: Label  = entry.lbl
		var btn: Button = entry.btn
		if item == null:
			lbl.text = "—"
			lbl.add_theme_color_override("font_color", Color(0.30, 0.32, 0.38))
			btn.disabled = true
		else:
			var tier: int          = item.get("tier", Constants.Tier.COMMON)
			var tier_col: Color    = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))
			var tier_name: String  = Constants.TIER_NAMES.get(tier, "Common")
			var type_str: String   = item.get("type", "")
			var cls_id: int        = item.get("item_class", -1)
			lbl.text = "%s %s" % [tier_name, _item_display_name(type_str, cls_id)]
			lbl.add_theme_color_override("font_color", tier_col)
			# Reserved drill/weapon slots keep the Drop button disabled — the loadout
			# is fixed; you replace them by picking up a new drill/weapon.
			btn.disabled = (idx == DRILL_SLOT or idx == WEAPON_SLOT)


func _slot_key_name(slot_idx: int) -> String:
	match slot_idx:
		0: return "H1"
		1: return "H2"
		2: return "H3"
		3: return "H4"
		4: return "H5"
		ARMOR_SLOT:     return "ARM"
		BACKPACK_START: return "BP1"
		BACKPACK_END:   return "BP2"
	return "?"


func _item_display_name(type_str: String, cls_id: int) -> String:
	match type_str:
		"drill":      return Constants.DRILL_CLASS_NAMES.get(cls_id, "?")
		"weapon":     return Constants.WEAPON_CLASS_NAMES.get(cls_id, "?")
		"armor":      return Constants.ARMOR_CLASS_NAMES.get(cls_id, "?")
		"relic":      return Constants.RELIC_NAMES.get(cls_id, "?")
		"throwable":  return Constants.THROWABLE_NAMES.get(cls_id, "?")
		"consumable": return "Consumable"
	return type_str.capitalize()


func _on_discard_pressed(slot_idx: int) -> void:
	# Reserved drill/weapon slots are fixed — they can't be emptied by hand; swap
	# them by picking up a replacement instead.
	if slot_idx == DRILL_SLOT or slot_idx == WEAPON_SLOT:
		return
	var item = _slots[slot_idx]
	if item == null:
		return
	_spawn_loot_drop(item)
	remove_item(slot_idx)   # emits slot_changed → _refresh_panel() via connected lambda


func _spawn_loot_drop(item_data_dict: Dictionary) -> void:
	var player := get_parent() as Node2D
	if player == null:
		return
	var world := player.get_parent()
	if world == null:
		return
	var drop := LootDrop.new()
	drop.item_data = item_data_dict
	drop.pickup_delay = 0.8   # prevents AutoCollect from instantly re-collecting at player position
	world.add_child(drop)
	drop.global_position = player.global_position


# --- Slot operations ---

## Add item_data (Dictionary from LootTable) to the correct slot; returns the slot
## index used, or -1 if it can't be placed. Slot rules:
##   drill  → always the reserved DRILL_SLOT  (replaces + drops any existing drill)
##   weapon → always the reserved WEAPON_SLOT (replaces + drops any existing weapon)
##   armor  → the armor sidebar slot (only if empty)
##   else   → first free hotbar slot 3–5, then a backpack slot
func add_item(item_data: Dictionary) -> int:
	match item_data.get("type", ""):
		"drill":
			return _place_reserved(DRILL_SLOT, item_data)
		"weapon":
			return _place_reserved(WEAPON_SLOT, item_data)
		"armor":
			if _slots[ARMOR_SLOT] == null:
				_set_slot(ARMOR_SLOT, item_data)
				return ARMOR_SLOT
			return -1
	for i in range(FREE_HOTBAR_START, HOTBAR_END + 1):
		if _slots[i] == null:
			_set_slot(i, item_data)
			return i
	for i in range(BACKPACK_START, BACKPACK_END + 1):
		if _slots[i] == null:
			_set_slot(i, item_data)
			return i
	return -1  # free hotbar + backpack full


## Places a drill/weapon into its reserved slot, replacing whatever is there. The
## replaced item (if any) is dropped as a LootDrop at the player's position. The
## in-hand Resource is re-equipped BEFORE slot_changed fires, so every listener
## (HUD durability bar, player active tool) sees the new drill/weapon consistently.
func _place_reserved(slot_idx: int, item_data: Dictionary) -> int:
	var old = _slots[slot_idx]
	if old != null:
		# Preserve the outgoing drill/weapon's live current durability on the dropped
		# item, so re-picking it up restores its wear instead of a full-durability copy.
		# Read now — _reequip_player below replaces the equipped Resource.
		_spawn_loot_drop(_with_current_durability(slot_idx, old))
	_reequip_player(slot_idx, item_data)
	_set_slot(slot_idx, item_data)
	return slot_idx


## Returns a copy of a reserved slot's item dict annotated with the currently
## equipped drill/weapon's live current_durability (so a dropped drill/weapon keeps
## its wear). No annotation if there's no equipped Resource or its durability is TBD.
func _with_current_durability(slot_idx: int, item_dict: Dictionary) -> Dictionary:
	var out := item_dict.duplicate()
	var player := get_parent()
	if player == null:
		return out
	if slot_idx == DRILL_SLOT and player.has_method("get_equipped_drill"):
		var d = player.get_equipped_drill()
		if d != null and d.max_durability != null:
			out["durability"] = d.current_durability
	elif slot_idx == WEAPON_SLOT and player.has_method("get_equipped_weapon"):
		var w = player.get_equipped_weapon()
		if w != null and w.max_durability != null:
			out["durability"] = w.current_durability
	return out


## Rebuilds the player's in-hand drill/weapon Resource to match a reserved slot.
func _reequip_player(slot_idx: int, item_data: Dictionary) -> void:
	var player := get_parent()
	if player == null:
		return
	if slot_idx == DRILL_SLOT and player.has_method("equip_drill_from_item"):
		player.equip_drill_from_item(item_data)
	elif slot_idx == WEAPON_SLOT and player.has_method("equip_weapon_from_item"):
		player.equip_weapon_from_item(item_data)


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


## Room for a generic (non-drill/weapon/armor) item: a free hotbar slot 3–5 or a
## backpack slot. The reserved drill/weapon slots (0–1) never count as free.
func has_space() -> bool:
	for i in range(FREE_HOTBAR_START, HOTBAR_END + 1):
		if _slots[i] == null:
			return true
	for i in range(BACKPACK_START, BACKPACK_END + 1):
		if _slots[i] == null:
			return true
	return false


## True if item_data can be accepted. Drills and weapons always fit (they replace
## their reserved slot). Armor needs its dedicated slot free. Everything else needs
## a free hotbar (3–5) or backpack slot.
func can_add(item_data: Dictionary) -> bool:
	match item_data.get("type", ""):
		"drill", "weapon":
			return true
		"armor":
			return _slots[ARMOR_SLOT] == null
	return has_space()


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

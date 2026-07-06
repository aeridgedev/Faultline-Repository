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
var _slot_rows: Array = []   # [{lbl: Label, btn: Button, ctrl: _InvSlotControl, idx: int}, ...]
var _row_by_idx: Dictionary = {}   # slot_idx -> _slot_rows entry (fast lookup during drag)

# --- Drag-and-drop state (inventory panel only; see _build_slot_row / _begin_drag) ---
var _drag_source_idx: int = -1     # slot the current drag started from, or -1
var _style_base: StyleBoxEmpty     # normal (no-highlight) slot background
var _style_valid: StyleBoxFlat     # green tint shown on a valid drop target under the cursor
var _style_invalid: StyleBoxFlat   # red tint shown on a wrong-type drop target under the cursor
var _msg_label: Label = null       # transient "Wrong slot type" message on the panel
var _msg_token: int = 0            # guards overlapping _flash_message timers


## Draggable + droppable slot control for the inventory panel. Godot's built-in
## drag-and-drop virtual callbacks are overridden here and forwarded to the owning
## InventoryManager, which holds all slot state + rules. Kept as an inner class
## (rather than a new file) so every inventory-panel concern stays in this script,
## per the task's file-scope constraint.
class _InvSlotControl extends PanelContainer:
	var manager: InventoryManager
	var slot_idx: int

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var data: Variant = manager._begin_drag(slot_idx)
		if data == null:
			return null   # empty slot → no drag begins
		# The floating preview is created by the manager and attached to THIS source
		# control; set_drag_preview renders it above every CanvasLayer automatically.
		set_drag_preview(manager._make_drag_preview_for(slot_idx))
		return data

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return manager._hover_drop(slot_idx, data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		manager._perform_drop(slot_idx, data)

	# NOTIFICATION_DRAG_END is broadcast to every Control when any drag ends
	# (dropped OR cancelled), so this is the reliable place to clear the drag's
	# visual state. Guarded in the manager so it runs its cleanup only once.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			manager._on_drag_end()


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
	_build_drag_styles()

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

	# Transient drag-error message ("Wrong slot type"), hidden until flashed. Overlaid
	# on the panel (bottom-anchored, so showing it doesn't reflow the slot list) and on
	# the panel's own CanvasLayer (layer 20): the HUD sits on a lower layer and would be
	# occluded by this panel, so a HUD-hosted message wouldn't be visible here. Added
	# last so it draws above the slot rows.
	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.anchor_left = 0.0
	_msg_label.anchor_right = 1.0
	_msg_label.anchor_top = 1.0
	_msg_label.anchor_bottom = 1.0
	_msg_label.offset_top = -18.0
	_msg_label.offset_bottom = -4.0
	_msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_label.add_theme_font_size_override("font_size", 8)
	_msg_label.add_theme_color_override("font_color", Color(0.96, 0.40, 0.38))
	_msg_label.visible = false
	panel.add_child(_msg_label)


# Shared styleboxes for slot drop-target feedback: transparent normally, a subtle
# green tint over a valid target, a red tint over a wrong-type target.
func _build_drag_styles() -> void:
	_style_base = StyleBoxEmpty.new()
	_style_base.set_content_margin_all(2.0)

	_style_valid = StyleBoxFlat.new()
	_style_valid.bg_color = Color(0.20, 0.85, 0.35, 0.18)
	_style_valid.border_color = Color(0.32, 0.92, 0.48, 0.95)
	_style_valid.set_border_width_all(1)
	_style_valid.set_corner_radius_all(3)
	_style_valid.set_content_margin_all(2.0)

	_style_invalid = StyleBoxFlat.new()
	_style_invalid.bg_color = Color(0.90, 0.25, 0.25, 0.22)
	_style_invalid.border_color = Color(0.96, 0.38, 0.36, 0.98)
	_style_invalid.set_border_width_all(1)
	_style_invalid.set_corner_radius_all(3)
	_style_invalid.set_content_margin_all(2.0)


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


# Each slot row is wrapped in an _InvSlotControl (PanelContainer) that is both a drag
# source and a drop target. The key/item labels use MOUSE_FILTER_IGNORE so presses
# fall through to the control (starting a drag); the Drop button keeps STOP so it stays
# clickable and grabbing it never starts a drag.
func _build_slot_row(slot_idx: int) -> _InvSlotControl:
	var ctrl := _InvSlotControl.new()
	ctrl.manager = self
	ctrl.slot_idx = slot_idx
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.add_theme_stylebox_override("panel", _style_base)
	ctrl.mouse_exited.connect(_on_slot_mouse_exited.bind(slot_idx))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	ctrl.add_child(row)

	# Fixed-width slot identifier.
	var lbl_key := Label.new()
	lbl_key.text = _slot_key_name(slot_idx)
	lbl_key.custom_minimum_size = Vector2(22, 0)
	lbl_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_key.add_theme_font_size_override("font_size", 7)
	lbl_key.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	row.add_child(lbl_key)

	# Expanding item name — colored by tier when occupied.
	var lbl_item := Label.new()
	lbl_item.text = "—"
	lbl_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_item.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var entry := {"lbl": lbl_item, "btn": btn, "ctrl": ctrl, "idx": slot_idx}
	_slot_rows.append(entry)
	_row_by_idx[slot_idx] = entry
	return ctrl


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
		"consumable": return Constants.CONSUMABLE_NAMES.get(cls_id, "Consumable")
		"scanner":    return Constants.SCANNER_NAMES.get(cls_id, "Scanner")
	return type_str.capitalize()


func _on_discard_pressed(slot_idx: int) -> void:
	# Reserved drill/weapon slots are fixed — they can't be emptied by hand; swap
	# them by picking up a replacement instead.
	if slot_idx == DRILL_SLOT or slot_idx == WEAPON_SLOT:
		return
	var item = _slots[slot_idx]
	if item == null:
		return
	# Armor keeps its wear on the dropped LootDrop (read while still equipped, before
	# remove_item unequips it). Other item types have no live durability to stamp.
	if slot_idx == ARMOR_SLOT:
		item = _with_current_durability(ARMOR_SLOT, item)
	_spawn_loot_drop(item)
	remove_item(slot_idx)   # emits slot_changed → _refresh_panel() via connected lambda


# --- Drag and drop (inventory panel only) --------------------------------------
# Godot's built-in Control drag-and-drop drives this: _InvSlotControl forwards
# _get_drag_data / _can_drop_data / _drop_data here. The engine handles the floating
# preview following the cursor (above all CanvasLayers) and snap-back when a drop
# lands on no valid target; this script only decides validity and mutates slot state.

## Begins a drag from slot_idx. Returns the drag payload (a Dictionary) or null when
## the slot is empty (no drag starts). Dims the source row for the drag's duration.
func _begin_drag(slot_idx: int) -> Variant:
	if _slots[slot_idx] == null:
		return null
	_drag_source_idx = slot_idx
	_set_row_dim(slot_idx, true)
	return {"inv_drag": true, "src": slot_idx}


## Floating visual that follows the cursor: a tier-colored name chip mirroring how the
## slot renders the item (this game has no item icons — the text IS the item's visual).
func _make_drag_preview_for(slot_idx: int) -> Control:
	var item = _slots[slot_idx]
	var tier: int = item.get("tier", Constants.Tier.COMMON) if item != null else Constants.Tier.COMMON
	var tier_col: Color = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))
	var tier_name: String = Constants.TIER_NAMES.get(tier, "Common")
	var name_str: String = _item_display_name(item.get("type", ""), item.get("item_class", -1)) if item != null else "?"

	# Wrapper offsets the chip up-left of the pointer so it doesn't sit under the cursor.
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := PanelContainer.new()
	chip.position = Vector2(-8, -20)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.12, 0.16, 0.96)
	st.border_color = tier_col
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(4.0)
	chip.add_theme_stylebox_override("panel", st)

	var lbl := Label.new()
	lbl.text = "%s %s" % [tier_name, name_str]
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", tier_col)
	chip.add_child(lbl)
	wrapper.add_child(chip)
	return wrapper


## Called every frame the dragged item hovers a slot. Highlights the target green
## (valid) or red (wrong type) and returns true so a wrong-type drop still fires
## _drop_data (letting us snap back AND show the "Wrong slot type" message). Returns
## false only for a non-inventory drag or a drop onto the same slot (a no-op).
func _hover_drop(target_idx: int, data: Variant) -> bool:
	if not _is_inv_drag(data):
		return false
	_clear_all_highlights()
	var src_idx: int = data["src"]
	if target_idx == src_idx:
		return false
	_set_row_style(target_idx, _style_valid if _is_move_valid(src_idx, target_idx) else _style_invalid)
	return true


## Called when the item is released over target_idx. Moves/swaps if valid; on a
## wrong-type drop shows the message and leaves state unchanged (engine snaps back).
func _perform_drop(target_idx: int, data: Variant) -> void:
	if not _is_inv_drag(data):
		return
	var src_idx: int = data["src"]
	if target_idx == src_idx:
		return
	if not _is_move_valid(src_idx, target_idx):
		_flash_message("Wrong slot type")
		return
	_move_or_swap(src_idx, target_idx)


## Broadcast to all controls when any drag ends (dropped or cancelled). Restores the
## dimmed source row and clears every hover highlight. Guarded so it runs once.
func _on_drag_end() -> void:
	if _drag_source_idx == -1:
		return
	_drag_source_idx = -1
	_clear_all_highlights()
	_reset_all_dim()
	if is_open:
		_refresh_panel()


func _is_inv_drag(data: Variant) -> bool:
	return data is Dictionary and data.get("inv_drag", false) == true and data.has("src")


# --- Move validity + execution ---

func _is_reserved(idx: int) -> bool:
	return idx == DRILL_SLOT or idx == WEAPON_SLOT or idx == ARMOR_SLOT


## The item type a reserved slot demands, or "" for a free slot.
## NOTE (deliberate extension beyond the brief): the task specifies type enforcement
## only for slot 1 (drill) and slot 2 (weapon). We enforce the armor sidebar slot the
## same way — placing a non-armor item there would make PlayerController build an
## ArmorBase from a non-armor class and desync PlayerStats' equipped armor, a real bug.
## Free hotbar/backpack slots accept any type.
func _required_type(idx: int) -> String:
	match idx:
		DRILL_SLOT:  return "drill"
		WEAPON_SLOT: return "weapon"
		ARMOR_SLOT:  return "armor"
	return ""


func _type_ok(idx: int, item) -> bool:
	var req := _required_type(idx)
	if req == "":
		return true
	return item != null and item.get("type", "") == req


## Both directions of a potential swap must satisfy slot type rules: the dragged item
## must fit the target, and (on a swap) the target's item must fit the source slot.
## Moving a reserved slot's item onto an empty free slot is allowed (it unequips).
func _is_move_valid(src_idx: int, target_idx: int) -> bool:
	var src_item = _slots[src_idx]
	var tgt_item = _slots[target_idx]
	if not _type_ok(target_idx, src_item):
		return false
	if tgt_item != null and not _type_ok(src_idx, tgt_item):
		return false
	return true


## Executes the move/swap. Handles reserved slots (drill/weapon/armor): live durability
## is stamped onto their outgoing item BEFORE any re-equip rebuilds the equipped
## Resource, and _reequip_player runs BEFORE slot_changed fires so the HUD durability
## bar / active tool read the new equipped state (mirrors _place_reserved's ordering).
func _move_or_swap(from_idx: int, to_idx: int) -> void:
	# Snapshot both items up front — stamp reserved-slot items while their equipped
	# Resources still exist. from/to reserved slots are always distinct Resource types
	# (drill vs weapon vs armor), so stamping both before any re-equip is safe.
	var from_item = _stamped_item(from_idx)
	var to_item   = _stamped_item(to_idx)
	# Swap: to_idx receives from_item; from_idx receives to_item (null on a move-to-empty).
	_assign_slot(from_idx, to_item)
	_assign_slot(to_idx, from_item)


## A reserved, occupied slot's item annotated with its live durability (so wear
## survives the move); otherwise the slot's item unchanged.
func _stamped_item(idx: int):
	var item = _slots[idx]
	if item != null and _is_reserved(idx):
		return _with_current_durability(idx, item)
	return item


## Writes new_item into a slot. For reserved slots, re-equips (or unequips on null)
## the player's in-hand Resource BEFORE emitting slot_changed, keeping equip state in
## lockstep with slot contents. slot_changed then refreshes both HUD and panel.
func _assign_slot(idx: int, new_item) -> void:
	if _is_reserved(idx):
		_reequip_player(idx, new_item)
	_set_slot(idx, new_item)


# --- Slot visual helpers (drag feedback) ---

func _set_row_style(slot_idx: int, style: StyleBox) -> void:
	var entry = _row_by_idx.get(slot_idx, null)
	if entry != null:
		entry.ctrl.add_theme_stylebox_override("panel", style)


func _clear_all_highlights() -> void:
	for entry in _slot_rows:
		entry.ctrl.add_theme_stylebox_override("panel", _style_base)


func _on_slot_mouse_exited(slot_idx: int) -> void:
	# Clears a lingering highlight when the cursor leaves a slot for empty panel space
	# mid-drag (where no other slot's _can_drop_data fires to overwrite it).
	if _drag_source_idx != -1:
		_set_row_style(slot_idx, _style_base)


func _set_row_dim(slot_idx: int, dim: bool) -> void:
	var entry = _row_by_idx.get(slot_idx, null)
	if entry != null:
		entry.ctrl.modulate = Color(1, 1, 1, 0.35) if dim else Color(1, 1, 1, 1)


func _reset_all_dim() -> void:
	for entry in _slot_rows:
		entry.ctrl.modulate = Color(1, 1, 1, 1)


func _flash_message(text: String) -> void:
	if _msg_label == null:
		return
	_msg_label.text = text
	_msg_label.visible = true
	_msg_token += 1
	var my_token := _msg_token
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func() -> void:
		if my_token == _msg_token and _msg_label != null:
			_msg_label.visible = false)


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
			# Same replace-and-drop rule as drill/weapon: picking up armor always
			# equips it, dropping whatever the sidebar slot held as a LootDrop.
			return _place_reserved(ARMOR_SLOT, item_data)
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
	elif slot_idx == ARMOR_SLOT and player.has_method("get_equipped_armor"):
		var a = player.get_equipped_armor()
		if a != null and a.max_durability != null:
			out["durability"] = a.current_durability
	return out


## Rebuilds the player's in-hand drill/weapon/armor Resource to match a reserved slot.
## item_data is Variant (not Dictionary) because remove_item() must be able to pass
## null here to unequip the armor slot — Dictionary is a non-nullable value type in
## GDScript 4's static typing, so a `Dictionary` parameter cannot accept null and
## passing one is a compile-time error. The player's equip_*_from_item() methods
## already handle null (unequip), so this only widens the parameter type to match.
func _reequip_player(slot_idx: int, item_data: Variant) -> void:
	var player := get_parent()
	if player == null:
		return
	if slot_idx == DRILL_SLOT and player.has_method("equip_drill_from_item"):
		player.equip_drill_from_item(item_data)
	elif slot_idx == WEAPON_SLOT and player.has_method("equip_weapon_from_item"):
		player.equip_weapon_from_item(item_data)
	elif slot_idx == ARMOR_SLOT and player.has_method("equip_armor_from_item"):
		player.equip_armor_from_item(item_data)


func remove_item(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= _slots.size():
		return
	# Emptying the armor slot must also unequip it from PlayerStats — otherwise the
	# damage reduction would linger with no armor shown. (Drill/weapon can't be emptied.)
	if slot_idx == ARMOR_SLOT:
		_reequip_player(ARMOR_SLOT, null)
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


## True if item_data can be accepted. Drills, weapons, and armor always fit — each
## replaces its reserved / sidebar slot (dropping the old piece). Everything else
## needs a free hotbar (3–5) or backpack slot.
func can_add(item_data: Dictionary) -> bool:
	match item_data.get("type", ""):
		"drill", "weapon", "armor":
			return true
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

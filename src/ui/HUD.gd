## Faultline — main heads-up display.
## Shows health bar, 5-slot hotbar (with per-slot durability bars), armor slot,
## 2 backpack slots, and storm timer.
## Call init(player, storm) from Main after player and StormSystem are ready.
class_name HUD
extends CanvasLayer

@onready var _fps_label: Label = $Control/FPSLabel
@onready var _health_bar: ProgressBar = $Control/BottomHUD/HealthSection/HealthBar
@onready var _armor_label: Label = $Control/BottomHUD/HealthSection/ArmorLabel
@onready var _hp_label: Label = $Control/BottomHUD/HealthSection/HPLabel
@onready var _hotbar_row: HBoxContainer = $Control/BottomHUD/HotbarSection
@onready var _bottom_hud: HBoxContainer = $Control/BottomHUD
@onready var _storm_timer: StormTimer = $Control/StormPanel/StormTimer
@onready var _layer_indicator: LayerIndicator = $Control/LayerPanel/LayerIndicator
@onready var _death_screen: DeathScreen = $Control/DeathScreen
@onready var _spectator_view: SpectatorView = $Control/SpectatorView
@onready var _kill_counter: KillCounter = $Control/KillCounter
@onready var _kill_progress_panel: PanelContainer = $Control/KillProgressPanel
@onready var _kill_progress_label: Label = $Control/KillProgressPanel/VBoxContainer/KillLabel
@onready var _kill_progress_bar: ProgressBar = $Control/KillProgressPanel/VBoxContainer/KillBar
@onready var _effects_panel: PanelContainer = $Control/EffectsPanel
@onready var _effects_vbox: VBoxContainer = $Control/EffectsPanel/VBoxContainer

var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_dur_bars: Array[ProgressBar] = []
var _slot_dur_fills: Array[StyleBoxFlat] = []
var _slot_dur_resources: Array = []   # DrillBase|WeaponBase|null per hotbar slot
var _slot_cooldown_overlays: Array[ColorRect] = []   # weapon swing-cooldown dim, per slot
var _inventory: InventoryManager = null
var _player: PlayerController = null

# Armor slot panel — built in code, appended to _bottom_hud after the hotbar.
var _armor_panel: PanelContainer = null
var _armor_cls_label: Label = null
var _armor_panel_style: StyleBoxFlat = null

# Backpack slot panels — built in code, appended after the armor slot.
var _bp_panels: Array[PanelContainer] = []
var _bp_labels: Array[Label] = []

const _COLOR_SLOT_NORMAL := Color(0.10, 0.12, 0.17, 0.92)
const _COLOR_SLOT_ACTIVE := Color(0.08, 0.88, 0.96, 0.95)
const _COLOR_SLOT_BORDER_NORMAL := Color(0.55, 0.58, 0.65, 0.90)
const _COLOR_SLOT_BORDER_ACTIVE := Color(0.08, 0.88, 0.96, 1.00)


func init(player: PlayerController, storm: StormSystem, layer_manager: LayerManager) -> void:
	_player = player
	var stats: PlayerStats = player.get_node("PlayerStats")
	var hotbar: Hotbar = player.get_node("Hotbar")
	_inventory = player.get_node("InventoryManager")

	_build_hotbar_slots()
	_build_armor_slot()
	_build_backpack_slots()
	_style_health_bar()
	_style_panels()
	_hp_label.add_theme_font_size_override("font_size", 8)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.85))
	_fps_label.add_theme_font_size_override("font_size", 9)
	_fps_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70, 0.65))

	stats.health_changed.connect(_on_health_changed)
	stats.player_died.connect(_on_player_died)
	stats.active_effects_changed.connect(_on_effects_changed)
	hotbar.active_slot_changed.connect(_on_slot_changed)
	_inventory.slot_changed.connect(_on_inventory_slot_changed)
	_death_screen.spectate_requested.connect(_on_spectate_requested)

	var max_hp := stats.max_health if stats.max_health > 0.0 else 1.0
	_health_bar.max_value = max_hp
	_health_bar.value = stats.current_health
	_hp_label.text = "%d / %d" % [int(stats.current_health), int(max_hp)]

	_refresh_armor(_inventory.get_armor())
	_on_slot_changed(hotbar.get_active_slot())
	for i in 2:
		_refresh_bp_slot(i, _inventory.get_item(InventoryManager.BACKPACK_START + i))

	_layer_indicator.init(stats)
	_storm_timer.init(storm)
	_kill_counter.init(stats)

	# Prominent descent-gate display: large gold text + thick gold bar + gold-bordered
	# panel so the kill requirement for the next layer stands out from the cyan HUD.
	_kill_progress_label.add_theme_font_size_override("font_size", 14)
	_kill_progress_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28))
	_kill_progress_label.add_theme_color_override("font_outline_color", Color(0.10, 0.06, 0.0, 0.9))
	_kill_progress_label.add_theme_constant_override("outline_size", 3)
	_kill_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kp_fill := StyleBoxFlat.new()
	kp_fill.bg_color = Color(1.0, 0.74, 0.16)
	kp_fill.set_corner_radius_all(2)
	_kill_progress_bar.add_theme_stylebox_override("fill", kp_fill)
	var kp_bg := StyleBoxFlat.new()
	kp_bg.bg_color = Color(0.10, 0.08, 0.04, 0.92)
	kp_bg.set_corner_radius_all(2)
	kp_bg.set_border_width_all(1)
	kp_bg.border_color = Color(0.45, 0.34, 0.12, 0.9)
	_kill_progress_bar.add_theme_stylebox_override("background", kp_bg)
	var kp_panel := StyleBoxFlat.new()
	kp_panel.bg_color = Color(0.13, 0.10, 0.04, 0.94)
	kp_panel.set_corner_radius_all(5)
	kp_panel.set_border_width_all(2)
	kp_panel.border_color = Color(1.0, 0.78, 0.22, 0.95)
	kp_panel.set_content_margin_all(6)
	_kill_progress_panel.add_theme_stylebox_override("panel", kp_panel)
	var descent_tracker: DescentTracker = player.get_node("DescentTracker")
	descent_tracker.kill_progress_changed.connect(_on_kill_progress_changed)


func _process(_delta: float) -> void:
	_fps_label.text = str(Engine.get_frames_per_second()) + " fps"
	_update_weapon_cooldown_overlay()


# Dims the hotbar slot holding the weapon while its swing is on cooldown.
func _update_weapon_cooldown_overlay() -> void:
	if _player == null or _slot_cooldown_overlays.is_empty():
		return
	var ratio := _player.get_attack_cooldown_ratio()
	# The weapon occupies whichever hotbar slot holds a WeaponBase resource.
	var weapon_slot := -1
	for i in _slot_dur_resources.size():
		if _slot_dur_resources[i] is WeaponBase:
			weapon_slot = i
			break
	for i in _slot_cooldown_overlays.size():
		var a := (ratio * 0.65) if (i == weapon_slot and ratio > 0.0) else 0.0
		_slot_cooldown_overlays[i].color = Color(0.02, 0.03, 0.05, a)


func _style_health_bar() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.22, 0.82, 0.32)
	fill.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.06, 0.90)
	bg.set_corner_radius_all(2)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.20, 0.20, 0.22, 0.60)
	_health_bar.add_theme_stylebox_override("background", bg)

	_health_bar.add_theme_color_override("font_color", Color(0, 0, 0, 0))  # hide pct text


func _style_panels() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, 0.88)
	s.set_corner_radius_all(4)
	s.set_border_width_all(1)
	s.border_color = Color(0.55, 0.58, 0.65, 0.80)
	var ctrl := get_node_or_null("Control")
	if ctrl == null:
		return
	for panel_name in ["LayerPanel", "StormPanel", "KillCounter", "EffectsPanel"]:
		var panel := ctrl.get_node_or_null(panel_name)
		if panel != null:
			panel.add_theme_stylebox_override("panel", s.duplicate())


# --- Hotbar construction ---

func _build_hotbar_slots() -> void:
	_slot_dur_resources.resize(Constants.HOTBAR_SLOTS)
	for i in Constants.HOTBAR_SLOTS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(40, 40)

		# Outer column: inner content expands to fill, bar sits at the very bottom.
		var col := VBoxContainer.new()

		# Inner section: slot number + item name, vertically centered.
		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var num := Label.new()
		num.text = str(i + 1)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 7)
		num.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))

		var label := Label.new()
		label.text = ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(36, 0)

		inner.add_child(num)
		inner.add_child(label)

		# Durability bar: 3px strip pinned to the slot bottom; hidden until a
		# drill or weapon occupies the slot.
		var dur_bar := ProgressBar.new()
		dur_bar.custom_minimum_size = Vector2(0, 2)
		dur_bar.max_value = 1.0
		dur_bar.value = 1.0
		dur_bar.show_percentage = false
		dur_bar.visible = false

		var dur_fill := StyleBoxFlat.new()
		dur_fill.bg_color = Color(0.22, 0.82, 0.32)   # starts green; updated per ratio
		dur_bar.add_theme_stylebox_override("fill", dur_fill)

		var dur_bg := StyleBoxFlat.new()
		dur_bg.bg_color = Color(0.06, 0.05, 0.05, 0.85)
		dur_bar.add_theme_stylebox_override("background", dur_bg)

		col.add_child(inner)
		col.add_child(dur_bar)
		panel.add_child(col)

		# Swing-cooldown overlay: a full-slot dim that fades from dark (just swung)
		# to clear (ready). PanelContainer stretches it across the slot; added last
		# so it draws on top of the slot contents. Ignores mouse so it never blocks.
		var cd := ColorRect.new()
		cd.color = Color(0.02, 0.03, 0.05, 0.0)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cd)

		_hotbar_row.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)
		_slot_dur_bars.append(dur_bar)
		_slot_dur_fills.append(dur_fill)
		_slot_cooldown_overlays.append(cd)

	_highlight_slot(0)


# --- Armor slot panel ---

func _build_armor_slot() -> void:
	_armor_label.visible = false   # hide the tscn label; panel replaces it

	_armor_panel = PanelContainer.new()
	_armor_panel.custom_minimum_size = Vector2(48, 40)

	var col := VBoxContainer.new()

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hdr := Label.new()
	hdr.text = "ARM"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 7)
	hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))

	_armor_cls_label = Label.new()
	_armor_cls_label.text = "—"
	_armor_cls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armor_cls_label.add_theme_font_size_override("font_size", 8)
	_armor_cls_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	_armor_cls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_armor_cls_label.custom_minimum_size = Vector2(44, 0)

	inner.add_child(hdr)
	inner.add_child(_armor_cls_label)
	col.add_child(inner)
	_armor_panel.add_child(col)
	_bottom_hud.add_child(_armor_panel)

	_armor_panel_style = StyleBoxFlat.new()
	_armor_panel_style.bg_color = _COLOR_SLOT_NORMAL
	_armor_panel_style.set_corner_radius_all(4)
	_armor_panel_style.set_border_width_all(2)
	_armor_panel_style.border_color = _COLOR_SLOT_BORDER_NORMAL
	_armor_panel.add_theme_stylebox_override("panel", _armor_panel_style)


func _build_backpack_slots() -> void:
	# Thin divider between armor and backpack.
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(3, 0)
	sep.color = Color(0.20, 0.22, 0.28, 0.70)
	_bottom_hud.add_child(sep)

	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)

	var hdr := Label.new()
	hdr.text = "PACK"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 6)
	hdr.add_theme_color_override("font_color", Color(0.40, 0.44, 0.52))
	section.add_child(hdr)

	for i in 2:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(46, 16)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)

		var key_lbl := Label.new()
		key_lbl.text = "BP%d" % (i + 1)
		key_lbl.add_theme_font_size_override("font_size", 6)
		key_lbl.add_theme_color_override("font_color", Color(0.40, 0.44, 0.52))
		row.add_child(key_lbl)

		var item_lbl := Label.new()
		item_lbl.text = "—"
		item_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_lbl.add_theme_font_size_override("font_size", 7)
		item_lbl.add_theme_color_override("font_color", Color(0.40, 0.44, 0.52))
		item_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_lbl.custom_minimum_size = Vector2(30, 0)
		row.add_child(item_lbl)

		panel.add_child(row)
		section.add_child(panel)
		_bp_panels.append(panel)
		_bp_labels.append(item_lbl)

		var style := StyleBoxFlat.new()
		style.bg_color = _COLOR_SLOT_NORMAL
		style.set_corner_radius_all(3)
		style.set_border_width_all(1)
		style.border_color = _COLOR_SLOT_BORDER_NORMAL
		panel.add_theme_stylebox_override("panel", style)

	_bottom_hud.add_child(section)


func _set_armor_slot_style(equipped: bool, tier: int) -> void:
	if _armor_panel_style == null or _armor_panel == null:
		return
	if equipped:
		var tc: Color = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))
		_armor_panel_style.bg_color = tc.darkened(0.82)
		_armor_panel_style.border_color = tc
	else:
		_armor_panel_style.bg_color = _COLOR_SLOT_NORMAL
		_armor_panel_style.border_color = _COLOR_SLOT_BORDER_NORMAL
	_armor_panel.add_theme_stylebox_override("panel", _armor_panel_style)


# --- Signal handlers ---

func _on_player_died() -> void:
	_death_screen.show_death()


func _on_spectate_requested() -> void:
	_death_screen.visible = false
	_bottom_hud.visible = false
	_spectator_view.show_spectating()


func _on_health_changed(new_hp: float, max_hp: float) -> void:
	_health_bar.max_value = max_hp if max_hp > 0.0 else 1.0
	_health_bar.value = new_hp
	_hp_label.text = "%d / %d" % [int(new_hp), int(max_hp)]
	var ratio := new_hp / max_hp if max_hp > 0.0 else 1.0
	var fill_color: Color
	if ratio > 0.55:
		fill_color = Color(0.22, 0.82, 0.32)
	elif ratio > 0.28:
		fill_color = Color(0.92, 0.68, 0.10)
	else:
		fill_color = Color(0.88, 0.18, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", fill)


func _on_slot_changed(slot_idx: int) -> void:
	_highlight_slot(slot_idx)


func _on_inventory_slot_changed(slot_idx: int, item) -> void:
	if slot_idx == InventoryManager.ARMOR_SLOT:
		_refresh_armor(item)
		return
	if slot_idx < 0:
		return
	if slot_idx < Constants.HOTBAR_SLOTS:
		_slot_labels[slot_idx].text = _item_short_name(item, slot_idx)
		_refresh_dur_bar(slot_idx, item)
		return
	var bp_idx := slot_idx - InventoryManager.BACKPACK_START
	if bp_idx >= 0 and bp_idx < _bp_labels.size():
		_refresh_bp_slot(bp_idx, item)


# --- Helpers ---

func _highlight_slot(active: int) -> void:
	for i in _slot_panels.size():
		var is_active := (i == active)
		var style := StyleBoxFlat.new()
		style.bg_color = _COLOR_SLOT_ACTIVE.darkened(0.72) if is_active else _COLOR_SLOT_NORMAL
		style.set_corner_radius_all(4)
		style.set_border_width_all(2 if not is_active else 3)
		style.border_color = _COLOR_SLOT_BORDER_ACTIVE if is_active else _COLOR_SLOT_BORDER_NORMAL
		_slot_panels[i].add_theme_stylebox_override("panel", style)
		if i < _slot_labels.size():
			var fc := Color(0.08, 0.90, 0.96) if is_active else Color(0.82, 0.86, 0.92)
			_slot_labels[i].add_theme_color_override("font_color", fc)


func _refresh_armor(item) -> void:
	if _armor_cls_label == null:
		return
	if item == null:
		_armor_cls_label.text = "—"
		_armor_cls_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
		_set_armor_slot_style(false, Constants.Tier.COMMON)
		return
	var cls_name: String = Constants.ARMOR_CLASS_NAMES.get(item.get("item_class", -1), "?")
	var tier: int = item.get("tier", Constants.Tier.COMMON)
	var tier_col: Color = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))
	_armor_cls_label.text = cls_name
	_armor_cls_label.add_theme_color_override("font_color", tier_col)
	_set_armor_slot_style(true, tier)


## Shows or hides the durability bar for a hotbar slot.
## Only drills and weapons have durability; everything else hides the bar.
## Uses a named Callable so duplicate connections are detected and skipped.
func _refresh_dur_bar(slot_idx: int, item) -> void:
	var bar: ProgressBar = _slot_dur_bars[slot_idx]

	# Disconnect from the previous resource occupying this slot.
	if slot_idx < _slot_dur_resources.size():
		var prev = _slot_dur_resources[slot_idx]
		var cb := Callable(self, "_on_dur_changed").bind(slot_idx)
		if prev is DrillBase:
			if (prev as DrillBase).durability_changed.is_connected(cb):
				(prev as DrillBase).durability_changed.disconnect(cb)
		elif prev is WeaponBase:
			if (prev as WeaponBase).durability_changed.is_connected(cb):
				(prev as WeaponBase).durability_changed.disconnect(cb)
		_slot_dur_resources[slot_idx] = null

	if item == null or _player == null:
		bar.visible = false
		return

	var item_type: String = item.get("type", "")
	var cb := Callable(self, "_on_dur_changed").bind(slot_idx)

	match item_type:
		"drill":
			var drill: DrillBase = _player.get_equipped_drill()
			if drill == null or drill.max_durability == null:
				bar.visible = false
				return
			if not drill.durability_changed.is_connected(cb):
				drill.durability_changed.connect(cb)
			_slot_dur_resources[slot_idx] = drill
			_update_dur_bar(slot_idx, drill.current_durability, float(drill.max_durability))
		"weapon":
			var weapon: WeaponBase = _player.get_equipped_weapon()
			if weapon == null or weapon.max_durability == null:
				bar.visible = false
				return
			if not weapon.durability_changed.is_connected(cb):
				weapon.durability_changed.connect(cb)
			_slot_dur_resources[slot_idx] = weapon
			_update_dur_bar(slot_idx, weapon.current_durability, float(weapon.max_durability))
		_:
			bar.visible = false


func _on_dur_changed(current: float, maximum: float, slot_idx: int) -> void:
	_update_dur_bar(slot_idx, current, maximum)


func _refresh_bp_slot(bp_idx: int, item) -> void:
	if bp_idx < 0 or bp_idx >= _bp_labels.size():
		return
	var lbl: Label = _bp_labels[bp_idx]
	var panel: PanelContainer = _bp_panels[bp_idx]
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(1)
	if item == null:
		lbl.text = "—"
		lbl.add_theme_color_override("font_color", Color(0.40, 0.44, 0.52))
		style.bg_color = _COLOR_SLOT_NORMAL
		style.border_color = _COLOR_SLOT_BORDER_NORMAL
	else:
		var tier: int = item.get("tier", Constants.Tier.COMMON)
		var tier_col: Color = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))
		lbl.text = _item_short_name(item, InventoryManager.BACKPACK_START + bp_idx)
		lbl.add_theme_color_override("font_color", tier_col)
		style.bg_color = tier_col.darkened(0.84)
		style.border_color = tier_col.darkened(0.25)
	panel.add_theme_stylebox_override("panel", style)


func _update_dur_bar(slot_idx: int, current: float, maximum: float) -> void:
	if slot_idx < 0 or slot_idx >= _slot_dur_bars.size():
		return
	var bar: ProgressBar = _slot_dur_bars[slot_idx]
	if maximum <= 0.0:
		bar.visible = false
		return
	bar.visible = true
	bar.max_value = maximum
	bar.value = current
	var ratio := current / maximum
	if ratio > 0.5:
		_slot_dur_fills[slot_idx].bg_color = Color(0.22, 0.82, 0.32)   # green
	elif ratio > 0.25:
		_slot_dur_fills[slot_idx].bg_color = Color(0.92, 0.68, 0.10)   # amber
	else:
		_slot_dur_fills[slot_idx].bg_color = Color(0.88, 0.18, 0.14)   # red


func _item_short_name(item, slot_idx: int) -> String:
	if item == null:
		return str(slot_idx + 1)
	var item_class = item.get("item_class", -1)
	match item.get("type", ""):
		"drill":      return Constants.DRILL_CLASS_NAMES.get(item_class, "?").left(6)
		"weapon":     return Constants.WEAPON_CLASS_NAMES.get(item_class, "?").left(6)
		"armor":      return Constants.ARMOR_CLASS_NAMES.get(item_class, "?").left(6)
		"throwable":  return Constants.THROWABLE_NAMES.get(item_class, "?").left(6)
		"relic":      return Constants.RELIC_NAMES.get(item_class, "?").left(6)
		"consumable": return "Medkit"
	return "?"


func _on_kill_progress_changed(current_kills: int, required_kills: int, next_layer_name: String) -> void:
	if required_kills == 0 or next_layer_name.is_empty():
		_kill_progress_panel.visible = false
		return
	_kill_progress_panel.visible = true
	var display_kills := mini(current_kills, required_kills)
	_kill_progress_label.text = "%s: %d/%d kills" % [next_layer_name, display_kills, required_kills]
	_kill_progress_bar.value = minf(float(current_kills) / float(required_kills), 1.0)


func _on_effects_changed(effects: Array) -> void:
	for child in _effects_vbox.get_children():
		_effects_vbox.remove_child(child)
		child.queue_free()
	if effects.is_empty():
		_effects_panel.visible = false
		return
	_effects_panel.visible = true
	for effect: Dictionary in effects:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var name_lbl := Label.new()
		name_lbl.text = effect["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 8)
		var col: Color = Color(0.38, 0.90, 0.45) if effect["is_buff"] else Color(0.92, 0.30, 0.30)
		name_lbl.add_theme_color_override("font_color", col)
		var dur_lbl := Label.new()
		dur_lbl.text = "%ds" % ceili(effect["remaining"])
		dur_lbl.add_theme_font_size_override("font_size", 8)
		dur_lbl.add_theme_color_override("font_color", Color(0.70, 0.74, 0.82))
		row.add_child(name_lbl)
		row.add_child(dur_lbl)
		_effects_vbox.add_child(row)
	# 14px per row + 6px panel padding, grows downward from offset_top.
	_effects_panel.offset_bottom = _effects_panel.offset_top + 6 + effects.size() * 14

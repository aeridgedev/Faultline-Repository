## Faultline — main heads-up display.
## Shows health bar, 5-slot hotbar (with per-slot durability bars), armor slot, and storm timer.
## Call init(player, storm) from Main after player and StormSystem are ready.
class_name HUD
extends CanvasLayer

@onready var _health_bar: ProgressBar = $Control/BottomHUD/HealthSection/HealthBar
@onready var _armor_label: Label = $Control/BottomHUD/HealthSection/ArmorLabel
@onready var _hotbar_row: HBoxContainer = $Control/BottomHUD/HotbarSection
@onready var _bottom_hud: HBoxContainer = $Control/BottomHUD
@onready var _storm_timer: StormTimer = $Control/StormPanel/StormTimer
@onready var _layer_indicator: LayerIndicator = $Control/LayerPanel/LayerIndicator
@onready var _death_screen: DeathScreen = $Control/DeathScreen
@onready var _spectator_view: SpectatorView = $Control/SpectatorView
@onready var _kill_counter: KillCounter = $Control/KillCounter

var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_dur_bars: Array[ProgressBar] = []
var _slot_dur_fills: Array[StyleBoxFlat] = []   # stored so color can be updated in place
var _inventory: InventoryManager = null
var _player: PlayerController = null

# Armor slot panel — built in code, appended to _bottom_hud after the hotbar.
var _armor_panel: PanelContainer = null
var _armor_cls_label: Label = null
var _armor_panel_style: StyleBoxFlat = null

const _COLOR_SLOT_NORMAL := Color(0.10, 0.12, 0.17, 0.92)
const _COLOR_SLOT_ACTIVE := Color(0.08, 0.88, 0.96, 0.95)
const _COLOR_SLOT_BORDER_NORMAL := Color(0.55, 0.58, 0.65, 0.90)
const _COLOR_SLOT_BORDER_ACTIVE := Color(0.08, 0.88, 0.96, 1.00)


func init(player: PlayerController, storm: StormSystem) -> void:
	print("[HUD] init started")
	_player = player
	var stats: PlayerStats = player.get_node("PlayerStats")
	var hotbar: Hotbar = player.get_node("Hotbar")
	_inventory = player.get_node("InventoryManager")

	_build_hotbar_slots()
	_build_armor_slot()
	_style_health_bar()
	_style_panels()

	stats.health_changed.connect(_on_health_changed)
	stats.player_died.connect(_on_player_died)
	hotbar.active_slot_changed.connect(_on_slot_changed)
	_inventory.slot_changed.connect(_on_inventory_slot_changed)
	_death_screen.spectate_requested.connect(_on_spectate_requested)

	var max_hp := stats.max_health if stats.max_health > 0.0 else 1.0
	_health_bar.max_value = max_hp
	_health_bar.value = stats.current_health

	_refresh_armor(_inventory.get_armor())
	_on_slot_changed(hotbar.get_active_slot())

	_layer_indicator.init(stats)
	_storm_timer.init(storm)
	_kill_counter.init(stats)


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
	for panel_name in ["LayerPanel", "StormPanel", "KillCounter"]:
		var panel := ctrl.get_node_or_null(panel_name)
		if panel != null:
			panel.add_theme_stylebox_override("panel", s.duplicate())


# --- Hotbar construction ---

func _build_hotbar_slots() -> void:
	for i in Constants.HOTBAR_SLOTS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(60, 60)

		# Outer column: inner content expands to fill, bar sits at the very bottom.
		var col := VBoxContainer.new()

		# Inner section: slot number + item name, vertically centered.
		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.size_flags_vertical = Control.SIZE_EXPAND_FILL

		var num := Label.new()
		num.text = str(i + 1)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 9)
		num.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))

		var label := Label.new()
		label.text = ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(54, 0)

		inner.add_child(num)
		inner.add_child(label)

		# Durability bar: 3px strip pinned to the slot bottom; hidden until a
		# drill or weapon occupies the slot.
		var dur_bar := ProgressBar.new()
		dur_bar.custom_minimum_size = Vector2(0, 3)
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
		_hotbar_row.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)
		_slot_dur_bars.append(dur_bar)
		_slot_dur_fills.append(dur_fill)

	_highlight_slot(0)


# --- Armor slot panel ---

func _build_armor_slot() -> void:
	_armor_label.visible = false   # hide the tscn label; panel replaces it

	_armor_panel = PanelContainer.new()
	_armor_panel.custom_minimum_size = Vector2(72, 60)

	var col := VBoxContainer.new()

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var hdr := Label.new()
	hdr.text = "ARM"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 9)
	hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))

	_armor_cls_label = Label.new()
	_armor_cls_label.text = "—"
	_armor_cls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armor_cls_label.add_theme_font_size_override("font_size", 10)
	_armor_cls_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	_armor_cls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_armor_cls_label.custom_minimum_size = Vector2(66, 0)

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
	if slot_idx < 0 or slot_idx >= Constants.HOTBAR_SLOTS:
		return
	_slot_labels[slot_idx].text = _item_short_name(item, slot_idx)
	_refresh_dur_bar(slot_idx, item)


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


## Shows or hides the durability bar for a hotbar slot and connects the signal.
## Only drills and weapons have durability; everything else hides the bar.
func _refresh_dur_bar(slot_idx: int, item) -> void:
	var bar: ProgressBar = _slot_dur_bars[slot_idx]
	if item == null:
		bar.visible = false
		return

	var item_type: String = item.get("type", "")
	if item_type not in ["drill", "weapon"]:
		bar.visible = false
		return

	if _player == null:
		bar.visible = false
		return

	var resource: Resource = null
	match item_type:
		"drill":  resource = _player.get_equipped_drill()
		"weapon": resource = _player.get_equipped_weapon()

	if resource == null:
		bar.visible = false
		return

	var max_val: Variant = resource.max_durability
	if max_val == null:
		# TBD balance values not set yet; hide bar rather than show 0/0.
		bar.visible = false
		return

	# Connect so the bar updates automatically whenever durability changes.
	resource.durability_changed.connect(func(cur: float, mx: float) -> void:
		_update_dur_bar(slot_idx, cur, mx))

	_update_dur_bar(slot_idx, resource.current_durability, float(max_val))


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

## Faultline — main heads-up display.
## Shows health bar, 5-slot hotbar, armor slot, and the storm timer.
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

var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _inventory: InventoryManager = null

const _COLOR_SLOT_NORMAL := Color(0.08, 0.09, 0.12, 0.88)
const _COLOR_SLOT_ACTIVE := Color(0.08, 0.88, 0.96, 0.95)   # teal active frame
const _COLOR_SLOT_BORDER_NORMAL := Color(0.22, 0.24, 0.30, 0.60)
const _COLOR_SLOT_BORDER_ACTIVE := Color(0.08, 0.88, 0.96, 1.00)


func init(player: PlayerController, storm: StormSystem) -> void:
	var stats: PlayerStats = player.get_node("PlayerStats")
	var hotbar: Hotbar = player.get_node("Hotbar")
	_inventory = player.get_node("InventoryManager")

	_build_hotbar_slots()
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
	s.bg_color = Color(0.06, 0.07, 0.10, 0.82)
	s.set_corner_radius_all(4)
	s.set_border_width_all(1)
	s.border_color = Color(0.22, 0.24, 0.32, 0.55)
	# Apply to named containers found via the Control root
	var ctrl := get_node_or_null("Control")
	if ctrl == null:
		return
	for name in ["LayerPanel", "StormPanel"]:
		var panel := ctrl.get_node_or_null(name)
		if panel != null:
			panel.add_theme_stylebox_override("panel", s.duplicate())


# --- Hotbar construction ---

func _build_hotbar_slots() -> void:
	for i in Constants.HOTBAR_SLOTS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(60, 60)

		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER

		# Slot number — small, dimmed
		var num := Label.new()
		num.text = str(i + 1)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 9)
		num.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))

		# Item name — main slot text
		var label := Label.new()
		label.text = ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(54, 0)

		inner.add_child(num)
		inner.add_child(label)
		panel.add_child(inner)
		_hotbar_row.add_child(panel)
		_slot_panels.append(panel)
		_slot_labels.append(label)

	_highlight_slot(0)


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
	# Health bar color shifts green → amber → red as HP drops
	var ratio := new_hp / max_hp if max_hp > 0.0 else 1.0
	var fill_color: Color
	if ratio > 0.55:
		fill_color = Color(0.22, 0.82, 0.32)           # healthy green
	elif ratio > 0.28:
		fill_color = Color(0.92, 0.68, 0.10)           # warning amber
	else:
		fill_color = Color(0.88, 0.18, 0.14)           # critical red
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


# --- Helpers ---

func _highlight_slot(active: int) -> void:
	for i in _slot_panels.size():
		var is_active := (i == active)
		var style := StyleBoxFlat.new()
		style.bg_color = _COLOR_SLOT_ACTIVE.darkened(0.72) if is_active else _COLOR_SLOT_NORMAL
		style.set_corner_radius_all(4)
		style.set_border_width_all(1 if not is_active else 2)
		style.border_color = _COLOR_SLOT_BORDER_ACTIVE if is_active else _COLOR_SLOT_BORDER_NORMAL
		_slot_panels[i].add_theme_stylebox_override("panel", style)
		# Label color: bright teal on active slot, muted on inactive
		if i < _slot_labels.size():
			var fc := Color(0.08, 0.90, 0.96) if is_active else Color(0.82, 0.86, 0.92)
			_slot_labels[i].add_theme_color_override("font_color", fc)


func _refresh_armor(item) -> void:
	if item == null:
		_armor_label.text = "ARMOR: —"
		return
	var cls_name: String = Constants.ARMOR_CLASS_NAMES.get(item.get("item_class", -1), "?")
	var tier_name: String = Constants.TIER_NAMES.get(item.get("tier", -1), "?")
	_armor_label.text = "ARMOR: %s %s" % [tier_name, cls_name]


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

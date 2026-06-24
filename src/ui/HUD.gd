## Faultline — main heads-up display.
## Shows health bar, 5-slot hotbar, armor slot, and the storm timer.
## Call init(player, storm) from Main after player and StormSystem are ready.
class_name HUD
extends CanvasLayer

@onready var _health_bar: ProgressBar = $Control/BottomHUD/HealthSection/HealthBar
@onready var _armor_label: Label = $Control/BottomHUD/HealthSection/ArmorLabel
@onready var _hotbar_row: HBoxContainer = $Control/BottomHUD/HotbarSection
@onready var _storm_timer: StormTimer = $Control/StormPanel/StormTimer
@onready var _layer_indicator: LayerIndicator = $Control/LayerPanel/LayerIndicator
@onready var _death_screen: DeathScreen = $Control/DeathScreen
@onready var _spectator_view: SpectatorView = $Control/SpectatorView

var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _inventory: InventoryManager = null

const _COLOR_SLOT_NORMAL := Color(0.12, 0.12, 0.12, 0.85)
const _COLOR_SLOT_ACTIVE := Color(0.88, 0.72, 0.18, 0.95)


func init(player: PlayerController, storm: StormSystem) -> void:
	var stats: PlayerStats = player.get_node("PlayerStats")
	var hotbar: Hotbar = player.get_node("Hotbar")
	_inventory = player.get_node("InventoryManager")

	_build_hotbar_slots()

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


# --- Hotbar construction ---

func _build_hotbar_slots() -> void:
	for i in Constants.HOTBAR_SLOTS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(56, 56)

		var inner := VBoxContainer.new()
		inner.alignment = BoxContainer.ALIGNMENT_CENTER

		var label := Label.new()
		label.text = str(i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)

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
	$Control/BottomHUD.visible = false
	_spectator_view.show_spectating()


func _on_health_changed(new_hp: float, max_hp: float) -> void:
	_health_bar.max_value = max_hp if max_hp > 0.0 else 1.0
	_health_bar.value = new_hp


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
		var style := StyleBoxFlat.new()
		style.bg_color = _COLOR_SLOT_ACTIVE if i == active else _COLOR_SLOT_NORMAL
		style.set_corner_radius_all(3)
		style.set_border_width_all(1)
		style.border_color = Color(1.0, 1.0, 1.0, 0.15)
		_slot_panels[i].add_theme_stylebox_override("panel", style)


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

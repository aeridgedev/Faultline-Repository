## Faultline — physical chest placed by ChestSpawner.
## Player walks into range and presses E to open. Spawns a LootDrop in the world
## and shows a popup with the item name, then switches to an open visual. One-time open.
class_name Chest
extends Node2D

const LootDropScene := preload("res://src/systems/loot/LootDrop.tscn")

signal chest_opened(chest: Chest)

## Set by ChestSpawner before add_child so _ready() can read tier color.
var item_data: Dictionary = {}
var source_layer: Constants.Layer = Constants.Layer.CRUST

var _opened: bool = false
var _player_nearby: bool = false
var _popup_visible: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _prompt: Label    = $Prompt
@onready var _area: Area2D     = $Area2D

var _popup_layer: CanvasLayer = null
var _popup_panel: Panel = null
var _popup_type: Label = null
var _popup_body: Label = null


func _ready() -> void:
	_build_chest_sprite(false)
	_prompt.text = "Press E"
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 7)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	_build_popup()


# Draws the 16×12 chest pixel art.  opened=false → closed lid with tier latch;
# opened=true → dark interior void where the lid was, muted body.
func _build_chest_sprite(opened: bool) -> void:
	const W := 16; const H := 12
	var tier: int = item_data.get("tier", Constants.Tier.COMMON)
	var latch_col: Color = Constants.TIER_COLORS.get(tier, Color(0.6, 0.6, 0.6))

	var K   := Color(0.06, 0.04, 0.02)
	var WD  := Color(0.28, 0.14, 0.04)
	var WB  := Color(0.42, 0.23, 0.08)
	var WLT := Color(0.56, 0.34, 0.12)
	var BN  := Color(0.28, 0.24, 0.20)
	var BH  := Color(0.44, 0.38, 0.30)

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	if opened:
		var OP := Color(0.10, 0.05, 0.02)   # dark interior void
		var WM := Color(0.32, 0.17, 0.06)   # muted body wood
		for y in H:
			for x in W:
				if x == 0 or y == 0 or x == W - 1 or y == H - 1:
					img.set_pixel(x, y, K)
				elif y <= 3:
					img.set_pixel(x, y, OP)   # open lid = interior void
				elif y == 4:
					img.set_pixel(x, y, BN)
				elif (x == 7 or x == 8) and y > 4:
					img.set_pixel(x, y, BN)
				else:
					img.set_pixel(x, y, WM if (x + y) % 3 != 0 else WD)
	else:
		var LA  := latch_col
		var LH  := latch_col.lightened(0.25)
		for y in H:
			for x in W:
				if x == 0 or y == 0 or x == W - 1 or y == H - 1:
					img.set_pixel(x, y, K)
					continue
				var is_lid   := y <= 3
				var on_hband := (y == 3 or y == 4)
				var on_vband := (x == 7 or x == 8)
				if on_hband:
					img.set_pixel(x, y, BH if y == 3 else BN)
					continue
				if on_vband and not is_lid:
					img.set_pixel(x, y, BH if x == 7 else BN)
					continue
				if (x == 7 or x == 8) and (y == 3 or y == 4):
					img.set_pixel(x, y, LH if x == 7 else LA)
					continue
				if is_lid:
					img.set_pixel(x, y, WLT if (x <= 3 or y <= 1) else WB)
				else:
					img.set_pixel(x, y, WB if (x + y) % 3 != 0 else WD)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true


func _build_popup() -> void:
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 10
	_popup_layer.visible = false
	add_child(_popup_layer)

	# Add Panel to the layer FIRST so anchors resolve against the viewport.
	_popup_panel = Panel.new()
	_popup_layer.add_child(_popup_panel)

	# 220×88 panel, centered on screen via 0.5 anchors + pixel offsets.
	_popup_panel.anchor_left   = 0.5
	_popup_panel.anchor_right  = 0.5
	_popup_panel.anchor_top    = 0.5
	_popup_panel.anchor_bottom = 0.5
	_popup_panel.offset_left   = -110.0
	_popup_panel.offset_right  =  110.0
	_popup_panel.offset_top    = -44.0
	_popup_panel.offset_bottom =  44.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.03, 0.94)
	style.set_border_width_all(1)
	style.border_color = Color(0.56, 0.34, 0.12)
	style.set_corner_radius_all(3)
	_popup_panel.add_theme_stylebox_override("panel", style)

	# Add MarginContainer to Panel FIRST, then set FULL_RECT preset.
	var margin := MarginContainer.new()
	_popup_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Chest Contents"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.90, 0.72, 0.30))
	vbox.add_child(title)

	_popup_type = Label.new()
	_popup_type.text = ""
	_popup_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_type.add_theme_font_size_override("font_size", 7)
	_popup_type.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	vbox.add_child(_popup_type)

	_popup_body = Label.new()
	_popup_body.text = ""
	_popup_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_body.add_theme_font_size_override("font_size", 10)
	_popup_body.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(_popup_body)

	var hint := Label.new()
	hint.text = "Press E to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.40, 0.40, 0.40))
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo
			and event.physical_keycode == KEY_E):
		return
	if _popup_visible:
		_close_popup()
		get_viewport().set_input_as_handled()
	elif not _opened and _player_nearby:
		_open()
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = true
		if not _opened:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = false
		_prompt.visible = false
		if _popup_visible:
			_close_popup()


func _open() -> void:
	if _opened:
		return
	_opened = true
	_prompt.visible = false
	_build_chest_sprite(true)
	_spawn_loot_drop()
	_show_popup()
	chest_opened.emit(self)


func _spawn_loot_drop() -> void:
	if item_data.is_empty():
		item_data = LootTable.roll(source_layer)

	var drop := LootDropScene.instantiate() as LootDrop
	if drop == null:
		push_error("[Chest] LootDrop.tscn failed to instantiate")
		return
	drop.item_data = item_data
	drop.source_layer = source_layer
	# Place the drop one tile above the chest so it lands on the surface.
	get_parent().add_child(drop)
	drop.global_position = global_position + Vector2(0.0, -float(Constants.TILE_SIZE))

	if _popup_body != null:
		var tier_name: String = Constants.TIER_NAMES.get(item_data.get("tier", Constants.Tier.COMMON), "Common")
		var type_str: String = item_data.get("type", "item")
		var cls_id: int = item_data.get("item_class", -1)
		var tier_col: Color = Constants.TIER_COLORS.get(item_data.get("tier", Constants.Tier.COMMON), Color(0.82, 0.86, 0.92))
		if _popup_type != null:
			_popup_type.text = _category_label(type_str)
		_popup_body.text = "%s %s" % [tier_name, _item_name(type_str, cls_id)]
		_popup_body.add_theme_color_override("font_color", tier_col)


# Short category tag shown above the item name, e.g. "— DRILL —"
func _category_label(type_str: String) -> String:
	match type_str:
		"drill":      return "— DRILL —"
		"weapon":     return "— WEAPON —"
		"armor":      return "— ARMOR —"
		"relic":      return "— RELIC —"
		"throwable":  return "— THROWABLE —"
		"consumable": return "— CONSUMABLE —"
	return ("— %s —" % type_str.to_upper())


# Human-readable item name, e.g. "Common Precision" for a drill, "Common Swords" for a weapon.
func _item_name(type_str: String, cls_id: int) -> String:
	match type_str:
		"drill":      return Constants.DRILL_CLASS_NAMES.get(cls_id, "?")
		"weapon":     return Constants.WEAPON_CLASS_NAMES.get(cls_id, "?")
		"armor":      return Constants.ARMOR_CLASS_NAMES.get(cls_id, "?")
		"relic":      return Constants.RELIC_NAMES.get(cls_id, "?")
		"throwable":  return Constants.THROWABLE_NAMES.get(cls_id, "?")
		"consumable": return "Consumable"
	return type_str.capitalize()


func _show_popup() -> void:
	_popup_visible = true
	_popup_layer.visible = true


func _close_popup() -> void:
	_popup_visible = false
	_popup_layer.visible = false

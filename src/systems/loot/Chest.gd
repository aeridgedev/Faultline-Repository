## Faultline — physical chest placed by ChestSpawner.
## Player walks into range and presses E to open an interactive popup.
## The item inside is shown as a clickable button that transfers it directly
## to the player's inventory. Popup closes on E or click outside.
class_name Chest
extends Node2D

signal chest_opened(chest: Chest)

## Set by ChestSpawner before add_child so _ready() can read tier color.
var item_data: Dictionary = {}
var source_layer: Constants.Layer = Constants.Layer.CRUST

var _opened: bool = false
var _item_taken: bool = false
var _player_nearby: bool = false
var _popup_visible: bool = false
var _inventory: InventoryManager = null

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _prompt: Label    = $Prompt
@onready var _area: Area2D     = $Area2D

var _popup_layer: CanvasLayer = null
var _popup_panel: Panel = null
var _category_lbl: Label = null
var _item_btn: Button = null
var _status_label: Label = null


func _ready() -> void:
	_build_chest_sprite(false)
	_prompt.text = "Press E"
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 7)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	# Popup UI is built lazily on first open — see _ensure_popup_built(). Building
	# it here for every chest spawned hundreds of CanvasLayers + full-rect Controls
	# up front, bloating the scene tree for UI that most chests never show.


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
		var OP := Color(0.10, 0.05, 0.02)
		var WM := Color(0.32, 0.17, 0.06)
		for y in H:
			for x in W:
				if x == 0 or y == 0 or x == W - 1 or y == H - 1:
					img.set_pixel(x, y, K)
				elif y <= 3:
					img.set_pixel(x, y, OP)
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


# Builds the popup UI on demand (first open). No-op once built.
func _ensure_popup_built() -> void:
	if _popup_layer == null:
		_build_popup()


func _build_popup() -> void:
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 10
	_popup_layer.visible = false
	add_child(_popup_layer)

	# Dim backdrop — clicking it closes the popup. Added first so the panel renders on top.
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.42)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_popup())
	_popup_layer.add_child(backdrop)

	# Centered panel — 260×180.
	_popup_panel = Panel.new()
	_popup_panel.anchor_left   = 0.5
	_popup_panel.anchor_right  = 0.5
	_popup_panel.anchor_top    = 0.5
	_popup_panel.anchor_bottom = 0.5
	_popup_panel.offset_left   = -130.0
	_popup_panel.offset_right  =  130.0
	_popup_panel.offset_top    = -90.0
	_popup_panel.offset_bottom =  90.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.05, 0.03, 0.96)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(0.56, 0.34, 0.12)
	panel_style.set_corner_radius_all(3)
	_popup_panel.add_theme_stylebox_override("panel", panel_style)
	_popup_layer.add_child(_popup_panel)

	var margin := MarginContainer.new()
	_popup_panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",   14)
	margin.add_theme_constant_override("margin_right",  14)
	margin.add_theme_constant_override("margin_top",    12)
	margin.add_theme_constant_override("margin_bottom", 12)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Chest Contents"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.90, 0.72, 0.30))
	vbox.add_child(title)

	_category_lbl = Label.new()
	_category_lbl.text = ""
	_category_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_lbl.add_theme_font_size_override("font_size", 8)
	_category_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	vbox.add_child(_category_lbl)

	_item_btn = Button.new()
	_item_btn.custom_minimum_size = Vector2(0, 38)
	_item_btn.add_theme_font_size_override("font_size", 11)
	_item_btn.pressed.connect(_on_item_pressed)
	vbox.add_child(_item_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Press E or click outside to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 7)
	hint.add_theme_color_override("font_color", Color(0.32, 0.32, 0.38))
	vbox.add_child(hint)


func _setup_item_button() -> void:
	if _item_btn == null:
		return
	if item_data.is_empty():
		item_data = LootTable.roll(source_layer)

	var type_str: String = item_data.get("type", "item")
	var cls_id: int      = item_data.get("item_class", -1)
	var tier: int        = item_data.get("tier", Constants.Tier.COMMON)
	var tier_name: String = Constants.TIER_NAMES.get(tier, "Common")
	var tier_col: Color   = Constants.TIER_COLORS.get(tier, Color(0.82, 0.86, 0.92))

	if _category_lbl != null:
		_category_lbl.text = _category_label(type_str)

	_item_btn.text = "%s %s" % [tier_name, _item_name(type_str, cls_id)]
	_style_item_button(tier_col)
	_refresh_button_state()


func _style_item_button(tier_col: Color) -> void:
	var mk_box := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_border_width_all(bw)
		s.border_color = border
		s.set_corner_radius_all(3)
		return s

	_item_btn.add_theme_stylebox_override("normal",
		mk_box.call(tier_col.darkened(0.78), tier_col, 1))
	_item_btn.add_theme_stylebox_override("hover",
		mk_box.call(tier_col.darkened(0.58), tier_col.lightened(0.18), 2))
	_item_btn.add_theme_stylebox_override("pressed",
		mk_box.call(tier_col.darkened(0.48), tier_col, 2))
	_item_btn.add_theme_stylebox_override("disabled",
		mk_box.call(Color(0.10, 0.10, 0.12, 0.70), Color(0.30, 0.30, 0.34, 0.55), 1))

	_item_btn.add_theme_color_override("font_color", tier_col.lightened(0.20))
	_item_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.92))
	_item_btn.add_theme_color_override("font_pressed_color", tier_col.lightened(0.30))
	_item_btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.38, 0.40))


func _refresh_button_state() -> void:
	if _item_btn == null:
		return
	if _item_taken:
		_item_btn.disabled = true
		_item_btn.tooltip_text = ""
		_status_label.text = "Item taken"
		_status_label.add_theme_color_override("font_color", Color(0.28, 0.72, 0.32))
		return
	if _inventory == null or not _inventory.can_add(item_data):
		_item_btn.disabled = true
		_item_btn.tooltip_text = "Inventory Full"
		_status_label.text = "Inventory Full"
		_status_label.add_theme_color_override("font_color", Color(0.82, 0.28, 0.22))
	else:
		_item_btn.disabled = false
		_item_btn.tooltip_text = ""
		_status_label.text = "Click to take"
		_status_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))


func _on_item_pressed() -> void:
	if _item_taken or _inventory == null:
		return
	var result: int = _inventory.add_item(item_data)
	if result >= 0:
		_item_taken = true
	# Always refresh — if add_item returned -1, inventory filled between state check and click.
	_refresh_button_state()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo
			and event.physical_keycode == KEY_E):
		return
	if _popup_visible:
		_close_popup()
		get_viewport().set_input_as_handled()
	elif _player_nearby:
		if not _opened:
			_open()
		else:
			_show_popup()   # re-open popup for an already-opened chest
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = true
		_inventory = body.get_node_or_null("InventoryManager") as InventoryManager
		if not _popup_visible:
			_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = false
		_inventory = null
		_prompt.visible = false
		if _popup_visible:
			_close_popup()


func _open() -> void:
	if _opened:
		return
	_opened = true
	_ensure_popup_built()
	_build_chest_sprite(true)
	_setup_item_button()
	_show_popup()
	chest_opened.emit(self)


func _show_popup() -> void:
	_ensure_popup_built()
	_refresh_button_state()
	_popup_visible = true
	_popup_layer.visible = true
	_prompt.visible = false


func _close_popup() -> void:
	_popup_visible = false
	_popup_layer.visible = false
	if _player_nearby:
		_prompt.visible = true


# Short category tag shown above the button, e.g. "— DRILL —"
func _category_label(type_str: String) -> String:
	match type_str:
		"drill":      return "— DRILL —"
		"weapon":     return "— WEAPON —"
		"armor":      return "— ARMOR —"
		"relic":      return "— RELIC —"
		"throwable":  return "— THROWABLE —"
		"consumable": return "— CONSUMABLE —"
	return "— %s —" % type_str.to_upper()


func _item_name(type_str: String, cls_id: int) -> String:
	match type_str:
		"drill":      return Constants.DRILL_CLASS_NAMES.get(cls_id, "?")
		"weapon":     return Constants.WEAPON_CLASS_NAMES.get(cls_id, "?")
		"armor":      return Constants.ARMOR_CLASS_NAMES.get(cls_id, "?")
		"relic":      return Constants.RELIC_NAMES.get(cls_id, "?")
		"throwable":  return Constants.THROWABLE_NAMES.get(cls_id, "?")
		"consumable": return "Consumable"
	return type_str.capitalize()

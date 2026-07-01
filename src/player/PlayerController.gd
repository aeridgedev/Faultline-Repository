## Faultline — player input and physics controller.
class_name PlayerController
extends CharacterBody2D

const ThrowableScene := preload("res://src/systems/throwables/ThrowableBase.tscn")

@export var player_id: int = 0

@onready var stats: PlayerStats = $PlayerStats
@onready var stamina: Stamina = $Stamina

var _move_speed: float = 0.0    # TBD: loaded from GameManager.data["player_move_speed"]
var _gravity: float = 0.0       # TBD: loaded from GameManager.data["player_gravity"]
var _gravity_default: float = 0.0
var _sprint_mult: float = 1.0   # TBD: loaded from GameManager.data["sprint_speed_mult"]
var _sprint_cost: float = 0.0   # TBD: stamina/sec while sprinting

var _terrain_manager: TerrainManager = null
var _storm: StormSystem = null
var _world_width_px: float = 0.0
var _equipped_drill: DrillBase = null
var _equipped_weapon: WeaponBase = null

var _dig_target: Vector2i = Vector2i(-1, -1)
var _dig_timer: float = 0.0
var _dig_duration: float = 0.0  # total time for the current dig (for progress display)
var _attack_timer: float = 0.0  # counts down while the swing is on cooldown
var _attack_duration: float = 0.0  # full cooldown of the current swing (HUD ratio)

# Melee hitbox: a persistent Area2D child enabled briefly at the start of each
# swing. Bodies overlapping while it is live take the weapon's damage (once each).
var _attack_hitbox: Area2D = null
var _attack_collision: CollisionShape2D = null
var _attack_shape: RectangleShape2D = null
var _hitbox_active_timer: float = 0.0   # how long the hitbox stays live this swing
var _swing_hit_bodies: Array = []       # bodies already damaged this swing
var _swing_consumed: bool = false       # durability spent once per connecting swing

var _dig_highlight: Node2D = null   # world-space drill target indicator
var _dig_fill: Sprite2D = null      # fills up as the tile is mined

var _resonance_overlay: ResonanceOverlay = null

var _held_pivot: Node2D = null      # rotates the held tool toward the aim point
var _held_sprite: Sprite2D = null   # the in-hand drill / sword visual
var _drill_tex: Texture2D = null
var _sword_tex: Texture2D = null

# Active in-hand tool: right-click toggles drill <-> sword and it PERSISTS;
# left-click uses whichever is equipped. The held visual always shows this tool.
const TOOL_DRILL := 0
const TOOL_SWORD := 1
var _active_tool: int = TOOL_DRILL

var _active_slot: int = 0
var _consumable_cache: Dictionary = {}  # slot_index -> ConsumableBase instance
var _hotbar: Hotbar = null
var _relic_manager: RelicManager = null
var _inv_open: bool = false          # true while InventoryManager panel is visible

# Floating status label — shows transient messages (drill broken, etc.) above the player.
var _notify_label: Label = null
var _notify_timer: float = 0.0


func _ready() -> void:
	var d: Dictionary = GameManager.data
	_move_speed = float(d.get("player_move_speed", 0.0))
	_gravity = float(d.get("player_gravity", 0.0))
	_gravity_default = _gravity
	_sprint_mult = float(d.get("sprint_speed_mult", 1.0))
	_sprint_cost = float(d.get("stamina_sprint_cost_per_sec", 0.0))
	var wtiles: int = d.get("world_width_tiles", 0)
	_world_width_px = float(wtiles) * float(Constants.TILE_SIZE)
	_build_dev_sprite()
	_build_dig_highlight()
	_build_held_visual()
	_build_notify_label()
	_build_resonance_overlay()
	_build_attack_hitbox()
	var dt := get_node_or_null("DescentTracker") as DescentTracker
	if dt != null:
		dt.descent_blocked.connect(_on_descent_blocked)


func _build_dev_sprite() -> void:
	const W := 14; const H := 28
	var K  := Color(0.04, 0.05, 0.08)   # outline
	var HM := Color(0.28, 0.34, 0.46)   # helmet base
	var HL := Color(0.40, 0.48, 0.62)   # helmet lit (dome top)
	var VB := Color(0.08, 0.90, 0.97)   # visor bright
	var VD := Color(0.04, 0.52, 0.68)   # visor dim
	var SA := Color(0.16, 0.28, 0.48)   # suit armor
	var SL := Color(0.24, 0.40, 0.63)   # suit light (chest plate)
	var SD := Color(0.10, 0.18, 0.34)   # suit dark (arms / legs)
	var BT := Color(0.15, 0.16, 0.22)   # boot dark
	var BH := Color(0.22, 0.24, 0.30)   # boot highlight
	var AC := Color(0.95, 0.62, 0.14)   # amber core-device
	var NK := Color(0.12, 0.14, 0.18)   # neck

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Helmet dome (y 0-8): narrowed at top, widens by y=3
	for y in range(9):
		var mx := 3 if y < 2 else (2 if y == 2 else 1)
		for x in range(mx, W - mx):
			if x == mx or x == W - 1 - mx or y == 0 or y == 8:
				img.set_pixel(x, y, K)
			elif y <= 2:
				img.set_pixel(x, y, HL)
			else:
				img.set_pixel(x, y, HM)

	# Visor strip (y 4-5) — overrides helmet interior
	for y in range(4, 6):
		for x in range(2, W - 2):
			if x == 2 or x == W - 3:
				img.set_pixel(x, y, K)
			elif y == 4:
				img.set_pixel(x, y, VB)
			else:
				img.set_pixel(x, y, VD)

	# Neck (y 9)
	for x in range(5, 9):
		img.set_pixel(x, 9, K if (x == 5 or x == 8) else NK)

	# Torso (y 10-19)
	for y in range(10, 20):
		for x in range(W):
			if x == 0 or x == W - 1 or y == 10 or y == 19:
				img.set_pixel(x, y, K)
			elif x <= 2 or x >= W - 3:
				img.set_pixel(x, y, SD)
			elif y == 15:
				img.set_pixel(x, y, K)    # chest plate divider
			elif y <= 14:
				img.set_pixel(x, y, SL)
			else:
				img.set_pixel(x, y, SA)

	# Amber core device (2×2, upper chest)
	img.set_pixel(6, 12, AC); img.set_pixel(7, 12, AC)
	img.set_pixel(6, 13, AC); img.set_pixel(7, 13, AC)

	# Legs (y 20-27): left leg x=1-5, right leg x=8-12, gap x=6-7
	for pair in [[1, 5], [8, 12]]:
		var lx: int = pair[0]; var rx: int = pair[1]
		for y in range(20, 28):
			for x in range(lx, rx + 1):
				if x == lx or x == rx or y == 20 or y == 27:
					img.set_pixel(x, y, K)
				elif y >= 24:
					img.set_pixel(x, y, BH if x == lx + 1 else BT)
				elif x == lx + 1 and y < 23:
					img.set_pixel(x, y, SL)
				else:
					img.set_pixel(x, y, SD)

	$Sprite2D.texture = ImageTexture.create_from_image(img)


# A world-space drill indicator: a fixed outline box on the targeted tile plus an
# inner square that grows as the tile is mined, so drilling is visibly happening.
func _build_dig_highlight() -> void:
	var size := Constants.TILE_SIZE
	_dig_highlight = Node2D.new()
	_dig_highlight.top_level = true
	_dig_highlight.z_index = 50
	_dig_highlight.visible = false
	add_child(_dig_highlight)

	# Outer border: 2px teal frame with corner accents
	var border := Sprite2D.new()
	border.texture = ImageTexture.create_from_image(_make_drill_indicator_border(size))
	_dig_highlight.add_child(border)

	# Inner fill: teal overlay that grows with dig progress
	_dig_fill = Sprite2D.new()
	_dig_fill.texture = ImageTexture.create_from_image(_make_solid_image(size - 4, Color(0.08, 0.88, 0.95, 0.28)))
	_dig_highlight.add_child(_dig_fill)


func _make_drill_indicator_border(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rim  := Color(0.10, 0.90, 0.96, 0.90)
	var dim  := Color(0.06, 0.60, 0.72, 0.70)
	var corn := Color(0.80, 0.98, 1.00, 1.00)
	for i in range(size):
		var on_edge := (i == 0 or i == size - 1)
		# Top / bottom rows
		img.set_pixel(i, 0,      corn if on_edge else rim)
		img.set_pixel(i, 1,      dim  if (not on_edge) else Color(0,0,0,0))
		img.set_pixel(i, size-1, corn if on_edge else rim)
		img.set_pixel(i, size-2, dim  if (not on_edge) else Color(0,0,0,0))
		# Left / right columns
		img.set_pixel(0,      i, corn if on_edge else rim)
		img.set_pixel(1,      i, dim  if (not on_edge) else Color(0,0,0,0))
		img.set_pixel(size-1, i, corn if on_edge else rim)
		img.set_pixel(size-2, i, dim  if (not on_edge) else Color(0,0,0,0))
	return img


func _make_solid_image(size: int, color: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return img


# In-hand tool: a pivot at the hand that rotates the held sprite toward the aim
# point. Shows the drill normally and the sword during a swing. Placeholder art.
func _build_held_visual() -> void:
	_drill_tex = _make_drill_tex()
	_sword_tex = _make_sword_tex()

	_held_pivot = Node2D.new()
	_held_pivot.position = Vector2(0, -1)  # roughly hand/chest height
	_held_pivot.z_index = 1                # draw in front of the body
	add_child(_held_pivot)

	_held_sprite = Sprite2D.new()
	_held_sprite.centered = true
	_held_sprite.texture = _drill_tex
	_held_sprite.position = Vector2(9, 0)  # offset out from the hand
	_held_pivot.add_child(_held_sprite)


func _update_held_visual() -> void:
	if _held_sprite == null:
		return
	var aim := get_global_mouse_position() - _held_pivot.global_position
	_held_pivot.rotation = aim.angle()
	# Flip vertically when aiming left so the tool reads right-side up, not mirrored.
	_held_sprite.scale.y = -1.0 if aim.x < 0.0 else 1.0
	# Show whichever tool is equipped; it stays until the player toggles (right-click).
	_held_sprite.visible = true
	if _active_tool == TOOL_SWORD:
		_held_sprite.texture = _sword_tex
		_held_sprite.position.x = 11.0
	else:
		_held_sprite.texture = _drill_tex
		_held_sprite.position.x = 9.0


func _make_drill_tex() -> Texture2D:
	# 14×8: ribbed rubber grip | cyan power ring | steel body | tapered hot bit
	const W := 14; const H := 8
	var K  := Color(0.04, 0.05, 0.08)   # outline
	var G1 := Color(0.28, 0.18, 0.10)   # grip dark
	var G2 := Color(0.42, 0.28, 0.16)   # grip ribbed highlight
	var PR := Color(0.08, 0.88, 0.96)   # power ring (cyan)
	var S1 := Color(0.52, 0.54, 0.58)   # steel base
	var S2 := Color(0.70, 0.72, 0.76)   # steel top highlight
	var S3 := Color(0.36, 0.37, 0.40)   # steel bottom shadow
	var B1 := Color(0.92, 0.54, 0.10)   # bit base
	var B2 := Color(1.00, 0.80, 0.28)   # bit hot tip
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(W):
		var taper := clampi(x - 9, 0, int(H / 2) - 1)
		var y_min := taper; var y_max := H - 1 - taper
		if y_max < y_min:
			continue
		for y in range(y_min, y_max + 1):
			var on_edge := (x == 0 or y == y_min or y == y_max)
			if on_edge:
				img.set_pixel(x, y, K)
			elif x < 4:
				img.set_pixel(x, y, G1 if x % 2 == 0 else G2)
			elif x == 4:
				img.set_pixel(x, y, PR)
			elif x < 10:
				if y <= y_min + 1:
					img.set_pixel(x, y, S2)
				elif y >= y_max - 1:
					img.set_pixel(x, y, S3)
				else:
					img.set_pixel(x, y, S1)
			else:
				var heat := float(x - 10) / float(W - 10)
				img.set_pixel(x, y, B1.lerp(B2, heat))
	return ImageTexture.create_from_image(img)


func _make_sword_tex() -> Texture2D:
	# 18×6: wrapped hilt | brass cross-guard | tapered blade with fuller + edge
	const W := 18; const H := 6
	var K  := Color(0.04, 0.05, 0.08)
	var H1 := Color(0.30, 0.19, 0.09)   # hilt dark
	var H2 := Color(0.44, 0.30, 0.15)   # hilt wrap highlight
	var G1 := Color(0.44, 0.35, 0.13)   # guard
	var G2 := Color(0.62, 0.52, 0.22)   # guard lit
	var BE := Color(0.86, 0.90, 0.96)   # blade edge (bright)
	var BM := Color(0.68, 0.72, 0.78)   # blade mid
	var BF := Color(0.58, 0.65, 0.82)   # fuller (blue sheen)
	var BS := Color(0.48, 0.50, 0.55)   # blade shadow side
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(W):
		var taper := clampi(x - (W - 5), 0, int(H / 2) - 1)
		var y_min := taper; var y_max := H - 1 - taper
		if y_max < y_min:
			continue
		for y in range(y_min, y_max + 1):
			var on_edge := (x == 0 or y == y_min or y == y_max)
			if on_edge:
				img.set_pixel(x, y, K)
			elif x < 3:
				img.set_pixel(x, y, H2 if (x + y) % 2 == 0 else H1)
			elif x < 5:
				img.set_pixel(x, y, G2 if y <= int(H / 2) - 1 else G1)
			else:
				if y == y_min + 1:
					img.set_pixel(x, y, BE)                   # bright edge
				elif y == (y_min + y_max) >> 1:
					img.set_pixel(x, y, BF)                   # fuller groove
				elif y == y_max - 1:
					img.set_pixel(x, y, BS)                   # shadow edge
				else:
					img.set_pixel(x, y, BM)
	return ImageTexture.create_from_image(img)


func _build_notify_label() -> void:
	_notify_label = Label.new()
	_notify_label.z_index = 10
	_notify_label.add_theme_font_size_override("font_size", 7)
	_notify_label.add_theme_color_override("font_color", Color(1.0, 0.40, 0.15))
	_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notify_label.visible = false
	add_child(_notify_label)


func _build_resonance_overlay() -> void:
	_resonance_overlay = ResonanceOverlay.new()
	_resonance_overlay.top_level = true
	_resonance_overlay.visible = false
	add_child(_resonance_overlay)


func _update_resonance_visibility() -> void:
	if _resonance_overlay == null:
		return
	var should_show := (_equipped_drill != null
			and not _equipped_drill.is_broken
			and DrillClassData.reveals_weak_terrain(_equipped_drill.drill_class))
	_resonance_overlay.visible = should_show


func _show_notify(text: String, duration: float = 3.5) -> void:
	_notify_label.text = text
	# Centre horizontally above the sprite (sprite top is at y≈-14).
	_notify_label.position = Vector2(-40.0, -34.0)
	_notify_label.custom_minimum_size = Vector2(80, 0)
	_notify_label.visible = true
	_notify_timer = duration


func _on_descent_blocked(required: int) -> void:
	_show_notify("Need %d kills\nto descend" % required, 2.0)


func init_world(tm: TerrainManager) -> void:
	_terrain_manager = tm
	if _resonance_overlay != null:
		_resonance_overlay.setup(self, _terrain_manager)
		_update_resonance_visibility()


func init_storm(storm: StormSystem) -> void:
	_storm = storm
	stats.init_storm(storm)


func equip_starter_drill() -> void:
	_equipped_drill = DrillBase.new()
	_equipped_drill.drill_class = Constants.DrillClass.PRECISION
	_equipped_drill.tier = Constants.Tier.COMMON
	_equipped_drill.init_from_data()
	_equipped_drill.drill_broken.connect(_on_drill_broken)
	_equipped_drill.equip()
	_update_resonance_visibility()


func _on_drill_broken() -> void:
	_show_notify("DRILL BROKEN\nNeeds Upgrade Template")
	print("[Drill] Broken — all %d blocks used." % int(_equipped_drill.max_durability if _equipped_drill.max_durability != null else 0))
	_update_resonance_visibility()


# Called by the inventory system when the player picks up or swaps drills.
# Unequips the current drill (hides Resonance overlay etc.) then wires the new one.
func equip_drill(drill: DrillBase) -> void:
	if _equipped_drill != null:
		_equipped_drill.unequip()
	_equipped_drill = drill
	_equipped_drill.drill_broken.connect(_on_drill_broken)
	_equipped_drill.equip()
	_update_resonance_visibility()


func equip_starter_weapon() -> void:
	_equipped_weapon = WeaponBase.new()
	_equipped_weapon.weapon_class = Constants.WeaponClass.SWORDS
	_equipped_weapon.tier = Constants.Tier.COMMON
	_equipped_weapon.init_from_data()


# Wires the 5 hotbar slots to actual usable items and follows slot selection.
# Call AFTER the starter drill/weapon are equipped and AFTER the HUD is init'd
# (so the HUD receives the inventory slot_changed signals for its labels).
# The throwable/consumable/relic entries are DEV test items so every item-use
# path is reachable offline; real loadouts will come from the loot system.
func setup_hotbar() -> void:
	_relic_manager = get_node_or_null("RelicManager")
	_hotbar = get_node_or_null("Hotbar") as Hotbar
	var inv := get_node_or_null("InventoryManager") as InventoryManager

	if inv != null:
		inv.add_item({"type": "drill",      "item_class": Constants.DrillClass.PRECISION, "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "weapon",     "item_class": Constants.WeaponClass.SWORDS,   "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "throwable",  "item_class": Constants.Throwable.SMOKE_BOMB, "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "consumable", "item_class": 1,                              "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "relic",      "item_class": Constants.Relic.SPEED,          "tier": Constants.Tier.COMMON})
		inv.slot_changed.connect(func(slot: int, _item: Variant) -> void:
			_consumable_cache.erase(slot))
		inv.inventory_opened.connect(func() -> void:
			_inv_open = true
			_reset_dig())
		inv.inventory_closed.connect(func() -> void:
			_inv_open = false)

	if _hotbar != null:
		_hotbar.active_slot_changed.connect(func(idx: int) -> void: _active_slot = idx)
		_active_slot = _hotbar.get_active_slot()


func _active_item() -> Variant:
	if _hotbar == null:
		return null
	return _hotbar.get_active_item()


# G key (use_item action) uses whatever non-weapon item is in the active hotbar slot.
func _handle_item_use(delta: float) -> void:
	var use_just     := Input.is_action_just_pressed("use_item")
	var use_held     := Input.is_action_pressed("use_item")
	var use_released := Input.is_action_just_released("use_item")

	if not use_just and not use_held and not use_released:
		return
	var item: Variant = _active_item()
	if item == null:
		return
	match item.get("type"):
		"throwable":
			if use_just:
				_throw_active(item)
		"consumable":
			var c: ConsumableBase = _get_or_create_consumable(_active_slot, item.get("item_class", 0))
			if c != null:
				if use_just:
					print("[Item] Using consumable — hold F to channel.")
				if use_held:
					c.tick_use(delta, stats)
				elif use_released:
					c.interrupt_use()
		"relic":
			if use_just:
				_use_relic(item)
		_:
			# drill / weapon slots are mouse-controlled; G has nothing to use here.
			if use_just:
				print("[Item] Used: %s" % _debug_item_name(item))


func _throw_active(item: Dictionary) -> void:
	var t := ThrowableScene.instantiate() as ThrowableBase
	get_parent().add_child(t)
	t.add_collision_exception_with(self)  # don't detonate on the thrower
	t.setup(item.get("item_class"), player_id)
	var dir := (get_global_mouse_position() - global_position).normalized()
	t.throw(global_position + dir * 18.0, dir, 320.0)


func _use_relic(item: Dictionary) -> void:
	if _relic_manager == null:
		return
	_relic_manager.activate_relic(item.get("item_class"))
	print("[Item] Activated relic: ", Constants.RELIC_NAMES.get(item.get("item_class"), "?"))


func _get_or_create_consumable(slot: int, item_class: int) -> ConsumableBase:
	if not _consumable_cache.has(slot):
		var c := _make_consumable(item_class)
		if c == null:
			return null
		_consumable_cache[slot] = c
	return _consumable_cache[slot]


func _debug_item_name(item: Dictionary) -> String:
	var type_str: String = item.get("type", "")
	var cls_id: int = item.get("item_class", -1)
	var tier: int = item.get("tier", Constants.Tier.COMMON)
	var tier_name: String = Constants.TIER_NAMES.get(tier, "Common")
	var item_name: String
	match type_str:
		"drill":      item_name = Constants.DRILL_CLASS_NAMES.get(cls_id, "?")
		"weapon":     item_name = Constants.WEAPON_CLASS_NAMES.get(cls_id, "?")
		"armor":      item_name = Constants.ARMOR_CLASS_NAMES.get(cls_id, "?")
		"relic":      item_name = Constants.RELIC_NAMES.get(cls_id, "?")
		"throwable":  item_name = Constants.THROWABLE_NAMES.get(cls_id, "?")
		"consumable": item_name = "Consumable"
		_:            item_name = type_str.capitalize()
	return "%s %s" % [tier_name, item_name]


func _make_consumable(item_class: int) -> ConsumableBase:
	match item_class:
		0: return Lytes.new()
		1: return Medkit.new()
		_: return null  # TBD: ThermalCapsule / Bloodstim / FaultBeacon (step 6)


func _physics_process(delta: float) -> void:
	if stats.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Tick the floating notification label.
	if _notify_timer > 0.0:
		_notify_timer -= delta
		if _notify_timer <= 0.0:
			_notify_label.visible = false

	# Advance swing cooldown / hitbox here so they keep ticking regardless of which
	# tool is in hand or whether the inventory panel is open.
	_tick_attack_hitbox(delta)

	_apply_gravity(delta)

	if _inv_open:
		velocity.x = 0.0
		move_and_slide()
		return

	_handle_movement(delta)
	_handle_tool_toggle()
	_handle_tool_use(delta)
	_handle_item_use(delta)
	_update_held_visual()
	move_and_slide()
	_try_step_up()
	_wrap_horizontal()
	_stream_terrain()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta


# Single-block step-up: when the player walks horizontally into a ledge exactly
# one tile high, lift the body onto it instead of being stopped flat. This is a
# standard platformer step (no jump, no extra height) and only runs while grounded.
#
# It is purely LOCAL navigation over dug terrain: it only ever nudges the player
# UP by a single tile and never touches the descend-only layer gate. DescentTracker
# runs after this (child processes after parent) and still clamps any attempt to
# cross a layer boundary, so re-entering upper layers remains fully blocked.
func _try_step_up() -> void:
	# Only step while standing on the ground and actually pressed against a wall.
	if not is_on_floor() or not is_on_wall():
		return
	var direction := Input.get_axis("move_left", "move_right")
	if direction == 0.0:
		return

	var step := float(Constants.TILE_SIZE)
	var forward := Vector2(signf(direction) * step, 0.0)
	var up := Vector2(0.0, -step)
	var from := global_transform

	# Must be genuinely blocked moving forward at foot level (a real ledge ahead).
	if not test_move(from, forward):
		return
	# Need a full tile of headroom to rise; abort if a ceiling is in the way.
	if test_move(from, up):
		return
	# After rising one tile the path forward must be clear. If it is still blocked
	# the obstacle is taller than one tile, so this is NOT a single-block step —
	# leave the player blocked rather than climbing it.
	if test_move(from.translated(up), forward):
		return

	# Clear single-tile ledge: lift exactly one tile onto it. Existing horizontal
	# velocity carries the body across and floor snapping settles it on the surface.
	global_position.y -= step


func _handle_movement(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	var speed := _move_speed
	# Sprint: hold sprint while moving to go faster, draining stamina. Blocked while
	# depleted so the player must let it recover (recovery threshold in Stamina).
	if direction != 0.0 and Input.is_action_pressed("sprint") and not stamina.is_depleted:
		if stamina.drain(_sprint_cost * delta):
			speed *= _sprint_mult
	# Active Speed relic multiplies movement (1.0 when no relic / not active).
	if _relic_manager != null:
		speed *= _relic_manager.move_speed_mult()
	velocity.x = direction * speed


func _handle_drill(delta: float) -> void:
	if not Input.is_action_pressed("drill"):
		_reset_dig()
		return
	if _equipped_drill == null or _terrain_manager == null:
		return
	if _equipped_drill.is_broken:
		_reset_dig()  # ensure indicator is always hidden while broken
		# Re-show the "broken" message each time the player clicks so they know why.
		if Input.is_action_just_pressed("drill"):
			_show_notify("DRILL BROKEN\nNeeds Upgrade Template")
		return

	var target := _get_dig_target()
	if not _terrain_manager.has_tile(target):
		_reset_dig()
		return

	if target != _dig_target:
		_dig_target = target
		_dig_duration = _calc_dig_duration(target)
		_dig_timer = _dig_duration

	_dig_timer -= delta
	_update_dig_highlight()
	if _dig_timer <= 0.0:
		_complete_dig()
		_reset_dig()


func _complete_dig() -> void:
	if not _terrain_manager.destroy_tile(_dig_target):
		return
	_equipped_drill.consume_durability(1.0)
	# Burst: also destroys the next tile in the dig direction (one tile beyond the primary).
	if DrillClassData.burst_tile_count(_equipped_drill.drill_class) > 1:
		var secondary := _calc_burst_secondary()
		if _terrain_manager.destroy_tile(secondary):
			_equipped_drill.consume_durability(1.0)


# Returns the cell one step beyond the primary dig target in the dominant dig direction.
# Used by Burst drills to destroy a second tile per completed dig.
func _calc_burst_secondary() -> Vector2i:
	var player_cell := _terrain_manager.world_to_cell(global_position)
	var diff        := _dig_target - player_cell
	var step: Vector2i
	if abs(diff.x) >= abs(diff.y):
		step = Vector2i(signi(diff.x), 0)
	else:
		step = Vector2i(0, signi(diff.y))
	return _dig_target + step


func _update_dig_highlight() -> void:
	if _dig_highlight == null:
		return
	_dig_highlight.visible = true
	# Position over the targeted tile (cell_to_world returns the cell's top-left corner).
	var half := Constants.TILE_SIZE / 2.0
	_dig_highlight.global_position = _terrain_manager.cell_to_world(_dig_target) + Vector2(half, half)
	# Inner square grows from nothing to full as the dig completes.
	var progress := 1.0 - clampf(_dig_timer / _dig_duration, 0.0, 1.0) if _dig_duration > 0.0 else 1.0
	_dig_fill.scale = Vector2(progress, progress)


func _reset_dig() -> void:
	_dig_target = Vector2i(-1, -1)
	_dig_timer = 0.0
	_dig_duration = 0.0
	if _dig_highlight != null:
		_dig_highlight.visible = false


func _get_dig_target() -> Vector2i:
	var dir := (get_global_mouse_position() - global_position).normalized()
	return _terrain_manager.world_to_cell(global_position + dir * float(Constants.TILE_SIZE))


func _calc_dig_duration(cell: Vector2i) -> float:
	var terrain_type: Variant = _terrain_manager.get_tile_type(cell)
	if terrain_type == null:
		return 0.0
	var base: Variant = TerrainTypes.base_dig_time(terrain_type)
	# Thermal ignores class_effectiveness — uniform dig speed on all terrain.
	var class_mult: Variant = null
	if not DrillClassData.ignores_terrain_effectiveness(_equipped_drill.drill_class):
		class_mult = TerrainTypes.class_effectiveness(terrain_type, _equipped_drill.drill_class)
	var tier_mult: Variant = DrillTier.dig_time_mult(_equipped_drill.drill_class, _equipped_drill.tier)
	var duration := float(base) if base != null else 1.0
	if class_mult != null:
		duration *= float(class_mult)
	if tier_mult != null:
		duration *= float(tier_mult)
	# Storm reduces drill efficiency — lower mult means longer dig time.
	if _storm != null:
		var storm_eff := _storm.get_drill_efficiency_mult()
		if storm_eff > 0.0:
			duration /= storm_eff
	return duration


# Right-click toggles which tool is in hand. It stays toggled until pressed again,
# so the sword no longer snaps back to the drill on its own.
func _handle_tool_toggle() -> void:
	if Input.is_action_just_pressed("attack"):
		_active_tool = TOOL_SWORD if _active_tool == TOOL_DRILL else TOOL_DRILL
		_reset_dig()  # drop any in-progress dig when switching tools


# Left-click uses the equipped tool: the drill mines, the sword swings.
func _handle_tool_use(delta: float) -> void:
	if _active_tool == TOOL_SWORD:
		_reset_dig()
		_handle_sword(delta)
	else:
		_handle_drill(delta)


func _handle_sword(_delta: float) -> void:
	# The cooldown is advanced centrally in _tick_attack_hitbox so it keeps
	# counting even if the player switches tools mid-swing. Here we only gate
	# new swings: blocked while still on cooldown.
	if _attack_timer > 0.0:
		return
	if Input.is_action_just_pressed("drill"):  # left-click swings the equipped weapon
		_try_attack()


func _try_attack() -> void:
	if _equipped_weapon == null or _equipped_weapon.is_broken:
		return
	# Swing cooldown = 1 / swing_speed; falls back to 0.5s while swing_speed is TBD.
	var swing_spd: Variant = _equipped_weapon.swing_speed
	_attack_timer = (1.0 / float(swing_spd)) if swing_spd != null else 0.5
	# Haste relic reduces the cooldown between swings (mult > 1 = faster).
	if _relic_manager != null:
		_attack_timer /= _relic_manager.attack_speed_mult()
	_attack_duration = _attack_timer
	_activate_attack_hitbox()


# Persistent melee hitbox: an Area2D child positioned in front of the player and
# enabled only at the start of a swing. collision_mask bit 1 covers player bodies
# and the test dummy (terrain is filtered out by the PlayerStats lookup).
func _build_attack_hitbox() -> void:
	_attack_hitbox = Area2D.new()
	_attack_hitbox.collision_layer = 0   # the hitbox itself is not detectable
	_attack_hitbox.collision_mask = 1    # detect bodies on layer bit 1 (players + dummy)
	_attack_hitbox.monitoring = false
	_attack_hitbox.monitorable = false
	add_child(_attack_hitbox)

	_attack_shape = RectangleShape2D.new()
	_attack_shape.size = Vector2(float(Constants.TILE_SIZE) * 3.0, float(Constants.TILE_SIZE) * 2.0)
	_attack_collision = CollisionShape2D.new()
	_attack_collision.shape = _attack_shape
	_attack_collision.disabled = true
	_attack_hitbox.add_child(_attack_collision)


# Places and enables the hitbox for a short active window aimed at the cursor.
# The rectangle spans from the player outward to the weapon's reach.
func _activate_attack_hitbox() -> void:
	if _attack_hitbox == null:
		return
	var aim := get_global_mouse_position() - global_position
	if aim.length_squared() < 0.0001:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	var reach: Variant = _equipped_weapon.attack_range
	var reach_px := float(reach) if reach != null else float(Constants.TILE_SIZE * 3)

	_attack_shape.size = Vector2(reach_px, float(Constants.TILE_SIZE) * 2.0)
	_attack_hitbox.position = aim * (reach_px * 0.5)
	_attack_hitbox.rotation = aim.angle()
	_attack_collision.disabled = false
	_attack_hitbox.monitoring = true
	# Live for a brief slice of the swing (capped by the cooldown for very fast weapons).
	_hitbox_active_timer = minf(0.12, _attack_duration)
	_swing_hit_bodies.clear()
	_swing_consumed = false


# Ticks the swing cooldown and, while the hitbox is live, damages overlapping
# targets. Polling get_overlapping_bodies() across the active window absorbs the
# one-physics-frame delay before Area2D overlaps register.
func _tick_attack_hitbox(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer = maxf(0.0, _attack_timer - delta)
	if _hitbox_active_timer > 0.0:
		_process_hitbox_overlaps()
		_hitbox_active_timer -= delta
		if _hitbox_active_timer <= 0.0:
			_deactivate_attack_hitbox()


func _deactivate_attack_hitbox() -> void:
	_hitbox_active_timer = 0.0
	if _attack_hitbox != null:
		_attack_hitbox.monitoring = false
	if _attack_collision != null:
		_attack_collision.disabled = true


func _process_hitbox_overlaps() -> void:
	if _attack_hitbox == null or not _attack_hitbox.monitoring:
		return
	var dmg: Variant = _equipped_weapon.damage if _equipped_weapon != null else null
	for body in _attack_hitbox.get_overlapping_bodies():
		if body == self or _swing_hit_bodies.has(body):
			continue
		var target_stats := body.get_node_or_null("PlayerStats") as PlayerStats
		if target_stats == null or target_stats == stats or target_stats.is_dead:
			continue
		_swing_hit_bodies.append(body)
		if dmg == null:
			continue  # TBD: no base damage value yet
		var total_dmg := float(dmg)
		# Strength relic multiplies outgoing damage.
		if _relic_manager != null:
			total_dmg *= _relic_manager.damage_mult()
		target_stats.take_damage(total_dmg)
		if target_stats.is_dead:
			stats.add_kill()
		# Durability is spent once per swing that actually connects.
		if not _swing_consumed:
			_swing_consumed = true
			_equipped_weapon.consume_durability(1.0)


# 0.0 = ready, >0.0 = fraction of the swing cooldown still remaining (for the HUD).
func get_attack_cooldown_ratio() -> float:
	if _attack_duration <= 0.0:
		return 0.0
	return clampf(_attack_timer / _attack_duration, 0.0, 1.0)


func _wrap_horizontal() -> void:
	if _world_width_px <= 0.0:
		return
	var x := global_position.x
	if x < 0.0:
		global_position.x += _world_width_px
		_snap_camera()
	elif x >= _world_width_px:
		global_position.x -= _world_width_px
		_snap_camera()


func _snap_camera() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()


func _stream_terrain() -> void:
	if _terrain_manager == null:
		return
	var col := int(global_position.x / float(Constants.TILE_SIZE))
	_terrain_manager.stream_columns(col, 48)


func get_equipped_drill() -> DrillBase:
	return _equipped_drill


func get_equipped_weapon() -> WeaponBase:
	return _equipped_weapon


func set_zero_gravity(enabled: bool) -> void:
	_gravity = 0.0 if enabled else _gravity_default
	if enabled:
		velocity.y = 0.0


func is_drilling() -> bool:
	return _dig_target != Vector2i(-1, -1)


func is_attacking() -> bool:
	return _attack_timer > 0.0

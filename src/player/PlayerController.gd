## Faultline — player input and physics controller.
class_name PlayerController
extends CharacterBody2D

const ThrowableScene := preload("res://src/systems/throwables/ThrowableBase.tscn")

@export var player_id: int = 0

@onready var stats: PlayerStats = $PlayerStats
@onready var stamina: Stamina = $Stamina

var _move_speed: float = 0.0    # TBD: loaded from GameManager.data["player_move_speed"]
var _gravity: float = 0.0       # TBD: loaded from GameManager.data["player_gravity"]
var _sprint_mult: float = 1.0   # TBD: loaded from GameManager.data["sprint_speed_mult"]
var _sprint_cost: float = 0.0   # TBD: stamina/sec while sprinting

var _terrain_manager: TerrainManager = null
var _equipped_drill: DrillBase = null
var _equipped_weapon: WeaponBase = null

var _dig_target: Vector2i = Vector2i(-1, -1)
var _dig_timer: float = 0.0
var _dig_duration: float = 0.0  # total time for the current dig (for progress display)
var _attack_timer: float = 0.0  # counts down while swing is active

var _dig_highlight: Node2D = null   # world-space drill target indicator
var _dig_fill: Sprite2D = null      # fills up as the tile is mined

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
var _use_was_pressed: bool = false   # F-key edge detection (no input-map entry needed)


func _ready() -> void:
	var d: Dictionary = GameManager.data
	_move_speed = float(d.get("player_move_speed", 0.0))       # TBD: balance pass
	_gravity = float(d.get("player_gravity", 0.0))             # TBD: balance pass
	_sprint_mult = float(d.get("sprint_speed_mult", 1.0))      # TBD: balance pass
	_sprint_cost = float(d.get("stamina_sprint_cost_per_sec", 0.0))  # TBD: balance pass
	_build_dev_sprite()
	_build_dig_highlight()
	_build_held_visual()


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
		var taper := clampi(x - 9, 0, H / 2 - 1)
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
		var taper := clampi(x - (W - 5), 0, H / 2 - 1)
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
				img.set_pixel(x, y, G2 if y <= H / 2 - 1 else G1)
			else:
				if y == y_min + 1:
					img.set_pixel(x, y, BE)                   # bright edge
				elif y == (y_min + y_max) / 2:
					img.set_pixel(x, y, BF)                   # fuller groove
				elif y == y_max - 1:
					img.set_pixel(x, y, BS)                   # shadow edge
				else:
					img.set_pixel(x, y, BM)
	return ImageTexture.create_from_image(img)


func init_world(tm: TerrainManager) -> void:
	_terrain_manager = tm


func equip_starter_drill() -> void:
	_equipped_drill = DrillBase.new()
	_equipped_drill.drill_class = Constants.DrillClass.PRECISION
	_equipped_drill.tier = Constants.Tier.COMMON
	_equipped_drill.init_from_data()


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

	if _hotbar != null:
		_hotbar.active_slot_changed.connect(func(idx: int) -> void: _active_slot = idx)
		_active_slot = _hotbar.get_active_slot()


func _active_item() -> Variant:
	if _hotbar == null:
		return null
	return _hotbar.get_active_item()


# Drill (left-click) and sword (right-click) are always available on the mouse.
# The F key uses whatever non-weapon item is selected in the hotbar. We poll the
# physical key directly (with manual edge detection) so no input-map entry is
# required — Godot tends to overwrite manual project.godot edits while it's open.
func _handle_item_use(delta: float) -> void:
	var use_held := Input.is_physical_key_pressed(KEY_F)
	var use_just := use_held and not _use_was_pressed
	var use_released := (not use_held) and _use_was_pressed
	_use_was_pressed = use_held

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
			# drill / weapon slots are mouse-controlled; F has nothing to use here.
			if use_just:
				print("[Item] Slot %d is the %s (mouse-controlled). Select slot 3, 4 or 5 (throwable / medkit / relic), then press F." % [_active_slot + 1, str(item.get("type", "?"))])


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

	_apply_gravity(delta)
	_handle_movement(delta)
	_handle_tool_toggle()       # right-click toggles drill <-> sword (persists)
	_handle_tool_use(delta)     # left-click uses the equipped tool
	_handle_item_use(delta)     # F-key uses the active throwable / consumable / relic
	_update_held_visual()
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta


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
	if _equipped_drill == null or _equipped_drill.is_broken or _terrain_manager == null:
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
		if _terrain_manager.destroy_tile(_dig_target):
			_equipped_drill.consume_durability(1.0)
		_reset_dig()


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
	var class_mult: Variant = TerrainTypes.class_effectiveness(terrain_type, _equipped_drill.drill_class)
	var tier_mult: Variant = DrillTier.dig_time_mult(_equipped_drill.drill_class, _equipped_drill.tier)
	# TBD: all values null until balance pass; 1.0 keeps the dig system functional in the meantime
	var duration := float(base) if base != null else 1.0
	if class_mult != null:
		duration *= float(class_mult)
	if tier_mult != null:
		duration *= float(tier_mult)
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


func _handle_sword(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
		return
	if Input.is_action_just_pressed("drill"):  # left-click swings the equipped sword
		_try_attack()


func _try_attack() -> void:
	if _equipped_weapon == null or _equipped_weapon.is_broken:
		return
	# Swing duration = 1 / swing_speed; falls back to 0.5s while TBD.
	var swing_spd: Variant = _equipped_weapon.swing_speed
	_attack_timer = (1.0 / float(swing_spd)) if swing_spd != null else 0.5
	# Haste relic reduces the cooldown between swings (mult > 1 = faster).
	if _relic_manager != null:
		_attack_timer /= _relic_manager.attack_speed_mult()

	# Raycast toward mouse to find the nearest hittable PlayerStats in range.
	var attack_dir := (get_global_mouse_position() - global_position).normalized()
	var reach: Variant = _equipped_weapon.attack_range
	var reach_px := float(reach) if reach != null else float(Constants.TILE_SIZE * 3)

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + attack_dir * reach_px,
			0xFFFFFFFF,
			[get_rid()]
	)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return
	var target_body = result.get("collider")
	if target_body == null:
		return
	var target_stats: PlayerStats = target_body.get_node_or_null("PlayerStats")
	if target_stats == null or target_stats == stats:
		return

	var dmg: Variant = _equipped_weapon.damage
	if dmg == null:
		return  # TBD: no base damage value yet
	var total_dmg := float(dmg)
	# Strength relic multiplies outgoing damage.
	if _relic_manager != null:
		total_dmg *= _relic_manager.damage_mult()
	target_stats.take_damage(total_dmg)
	_equipped_weapon.consume_durability(1.0)


func is_drilling() -> bool:
	return _dig_target != Vector2i(-1, -1)


func is_attacking() -> bool:
	return _attack_timer > 0.0

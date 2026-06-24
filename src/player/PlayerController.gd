## Faultline — player input and physics controller.
class_name PlayerController
extends CharacterBody2D

@export var player_id: int = 0

@onready var stats: PlayerStats = $PlayerStats
@onready var stamina: Stamina = $Stamina

var _move_speed: float = 0.0    # TBD: loaded from GameManager.data["player_move_speed"]
var _gravity: float = 0.0       # TBD: loaded from GameManager.data["player_gravity"]
var _jump_velocity: float = 0.0 # TBD: loaded from GameManager.data["player_jump_velocity"]
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

# Hotbar: which of the 5 slots is active and what each holds. Each entry is a
# Dictionary like {"kind": "drill"} / {"kind": "throwable", "type": ...}.
var _active_slot: int = 0
var _hotbar_items: Array = []
var _relic_manager: RelicManager = null


func _ready() -> void:
	var d: Dictionary = GameManager.data
	_move_speed = float(d.get("player_move_speed", 0.0))       # TBD: balance pass
	_gravity = float(d.get("player_gravity", 0.0))             # TBD: balance pass
	_jump_velocity = float(d.get("player_jump_velocity", 0.0)) # TBD: balance pass
	_sprint_mult = float(d.get("sprint_speed_mult", 1.0))      # TBD: balance pass
	_sprint_cost = float(d.get("stamina_sprint_cost_per_sec", 0.0))  # TBD: balance pass
	_build_dev_sprite()
	_build_dig_highlight()
	_build_held_visual()


func _build_dev_sprite() -> void:
	# Dev placeholder "driller": helmet + visor over a suit, with a dark outline so
	# the figure reads clearly against terrain. Replaced by real art later.
	var w := 14
	var h := 28
	var outline := Color(0.04, 0.05, 0.08)
	var suit := Color(0.18, 0.45, 0.85)
	var suit_dark := Color(0.12, 0.32, 0.62)
	var helmet := Color(0.75, 0.80, 0.88)
	var visor := Color(0.35, 0.85, 0.95)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c: Color
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				c = outline
			elif y < 10:
				c = helmet            # head/helmet
			elif y < 20:
				c = suit              # torso
			else:
				c = suit_dark         # legs
			img.set_pixel(x, y, c)
	# Visor band across the helmet.
	for x in range(3, w - 3):
		img.set_pixel(x, 5, visor)
		img.set_pixel(x, 6, visor)
	$Sprite2D.texture = ImageTexture.create_from_image(img)


# A world-space drill indicator: a fixed outline box on the targeted tile plus an
# inner square that grows as the tile is mined, so drilling is visibly happening.
func _build_dig_highlight() -> void:
	var size := Constants.TILE_SIZE
	_dig_highlight = Node2D.new()
	_dig_highlight.top_level = true   # ignore the player's transform; positioned in world space
	_dig_highlight.z_index = 50
	_dig_highlight.visible = false
	add_child(_dig_highlight)

	var border := Sprite2D.new()
	border.texture = ImageTexture.create_from_image(_make_outline_image(size, Color(1.0, 0.85, 0.3)))
	_dig_highlight.add_child(border)

	_dig_fill = Sprite2D.new()
	_dig_fill.texture = ImageTexture.create_from_image(_make_solid_image(size, Color(1.0, 0.85, 0.3, 0.45)))
	_dig_highlight.add_child(_dig_fill)


func _make_outline_image(size: int, color: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(size):
		img.set_pixel(i, 0, color)
		img.set_pixel(i, size - 1, color)
		img.set_pixel(0, i, color)
		img.set_pixel(size - 1, i, color)
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
	# Show the held tool that matches the active hotbar item (sword while swinging).
	var item: Variant = _active_item()
	var kind: String = String(item.get("kind", "")) if item != null else ""
	if is_attacking() or kind == "weapon":
		_held_sprite.visible = true
		_held_sprite.texture = _sword_tex
		_held_sprite.position.x = 11.0
	elif kind == "drill":
		_held_sprite.visible = true
		_held_sprite.texture = _drill_tex
		_held_sprite.position.x = 9.0
	else:
		_held_sprite.visible = false  # throwable / consumable / relic: no tool in hand


func _make_drill_tex() -> Texture2D:
	# 14×8: brown handle, steel body, tapered orange bit at the tip.
	var w := 14
	var h := 8
	var outline := Color(0.04, 0.05, 0.08)
	var handle := Color(0.35, 0.22, 0.12)
	var steel := Color(0.60, 0.62, 0.66)
	var bit := Color(0.95, 0.60, 0.15)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(w):
		var col := handle if x < 4 else (steel if x < 9 else bit)
		var taper := (x - 9) if x >= 9 else 0   # shrink toward the bit tip
		for y in range(h):
			if y < taper or y > h - 1 - taper:
				continue
			var edge: bool = y == taper or y == h - 1 - taper or x == 0
			img.set_pixel(x, y, outline if edge else col)
	return ImageTexture.create_from_image(img)


func _make_sword_tex() -> Texture2D:
	# 18×6: brown hilt, brass guard, tapered steel blade.
	var w := 18
	var h := 6
	var outline := Color(0.04, 0.05, 0.08)
	var hilt := Color(0.35, 0.22, 0.12)
	var guard := Color(0.55, 0.42, 0.18)
	var blade := Color(0.82, 0.85, 0.90)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(w):
		var col := hilt if x < 3 else (guard if x < 5 else blade)
		var taper := (x - (w - 4) + 1) if x >= w - 4 else 0   # point at the tip
		for y in range(h):
			if y < taper or y > h - 1 - taper:
				continue
			var edge: bool = y == taper or y == h - 1 - taper or x == 0
			img.set_pixel(x, y, outline if edge else col)
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
	var hotbar := get_node_or_null("Hotbar") as Hotbar
	var inv := get_node_or_null("InventoryManager") as InventoryManager

	_hotbar_items = [
		{"kind": "drill"},
		{"kind": "weapon"},
		{"kind": "throwable", "type": Constants.Throwable.SMOKE_BOMB},
		{"kind": "consumable", "obj": Medkit.new()},
		{"kind": "relic", "type": Constants.Relic.SPEED},
	]

	if inv != null:
		inv.add_item({"type": "drill",      "item_class": Constants.DrillClass.PRECISION, "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "weapon",     "item_class": Constants.WeaponClass.SWORDS,   "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "throwable",  "item_class": Constants.Throwable.SMOKE_BOMB, "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "consumable", "item_class": 0,                              "tier": Constants.Tier.COMMON})
		inv.add_item({"type": "relic",      "item_class": Constants.Relic.SPEED,          "tier": Constants.Tier.COMMON})

	if hotbar != null:
		hotbar.active_slot_changed.connect(func(idx: int) -> void: _active_slot = idx)
		_active_slot = hotbar.get_active_slot()


func _active_item() -> Variant:
	if _active_slot < 0 or _active_slot >= _hotbar_items.size():
		return null
	return _hotbar_items[_active_slot]


# Left-click ("drill" action) uses the active hotbar item, context-sensitive by
# kind. Right-click stays a quick weapon swing (see _handle_attack_input).
func _handle_active_use(delta: float) -> void:
	var item: Variant = _active_item()
	# Drill is a continuous hold action with its own per-frame logic + highlight.
	if item != null and item.get("kind") == "drill":
		_handle_drill(delta)
	else:
		_reset_dig()  # keep the dig highlight hidden when the drill isn't active

	if item == null:
		return
	match item.get("kind"):
		"weapon":
			if Input.is_action_just_pressed("drill") and _attack_timer <= 0.0:
				_try_attack()
		"throwable":
			if Input.is_action_just_pressed("drill"):
				_throw_active(item)
		"consumable":
			_handle_consume(delta, item)
		"relic":
			if Input.is_action_just_pressed("drill"):
				_use_relic(item)


func _throw_active(item: Dictionary) -> void:
	var t := ThrowableBase.new()
	# RigidBody2D only emits body_entered when contact monitoring is on, otherwise
	# the throwable would never detonate on impact.
	t.contact_monitor = true
	t.max_contacts_reported = 4

	var spr := Sprite2D.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.85, 0.40))
	spr.texture = ImageTexture.create_from_image(img)
	t.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	t.add_child(col)

	get_parent().add_child(t)
	t.add_collision_exception_with(self)  # don't detonate on the thrower
	t.setup(item.get("type"), player_id)
	var dir := (get_global_mouse_position() - global_position).normalized()
	t.throw(global_position + dir * 18.0, dir, 320.0)


func _handle_consume(delta: float, item: Dictionary) -> void:
	var c: ConsumableBase = item.get("obj")
	if c == null:
		return
	if Input.is_action_pressed("drill"):
		c.tick_use(delta, stats)
	elif Input.is_action_just_released("drill"):
		c.interrupt_use()


func _use_relic(item: Dictionary) -> void:
	if _relic_manager == null:
		return
	_relic_manager.activate_relic(item.get("type"))


func _physics_process(delta: float) -> void:
	if stats.is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_apply_gravity(delta)
	_handle_jump()
	_handle_movement(delta)
	_handle_active_use(delta)
	_handle_attack_input(delta)
	_update_held_visual()
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta


func _handle_jump() -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = _jump_velocity


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


func _handle_attack_input(delta: float) -> void:
	if _attack_timer > 0.0:
		_attack_timer -= delta
		return
	if Input.is_action_just_pressed("attack"):
		_try_attack()


func _try_attack() -> void:
	if _equipped_weapon == null or _equipped_weapon.is_broken:
		return
	# Swing duration = 1 / swing_speed; falls back to 0.5s while TBD.
	var swing_spd: Variant = _equipped_weapon.swing_speed
	_attack_timer = (1.0 / float(swing_spd)) if swing_spd != null else 0.5

	# Raycast toward mouse to find the nearest hittable PlayerStats in range.
	var attack_dir := (get_global_mouse_position() - global_position).normalized()
	var reach: Variant = _equipped_weapon.attack_range
	var reach_px := float(reach) if reach != null else float(Constants.TILE_SIZE * 3)

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + attack_dir * reach_px,
			0xFFFFFFFF,
			[self]
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
	target_stats.take_damage(float(dmg))
	_equipped_weapon.consume_durability(1.0)


func is_drilling() -> bool:
	return _dig_target != Vector2i(-1, -1)


func is_attacking() -> bool:
	return _attack_timer > 0.0

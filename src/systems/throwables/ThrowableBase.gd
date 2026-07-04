## Faultline — base for all 7 throwables. Each throwable is a subclass overriding
## _on_impact() (Smoke.gd, ParalysisBomb.gd, …). PlayerController._make_throwable()
## instantiates the right subclass; no scene is required — collision shape and dev
## sprite are built in code if absent.
## Physics: RigidBody2D so gravity handles the arc automatically. throw_at() solves
## the launch velocity ballistically so the projectile lands at the aimed point.
## Effect strengths, durations, and radii are TBD in data/world_config.json
## "throwables" (read via _data()).
class_name ThrowableBase
extends RigidBody2D

var throwable_type: Constants.Throwable = Constants.Throwable.SMOKE_BOMB
var _owner_id: int = -1   # player_id that threw this; FFA: the thrower is never affected
var _terrain_manager: TerrainManager = null   # for Seismic Charge tile destruction
var _impacted: bool = false


func setup(type: Constants.Throwable, owner_id: int, terrain_manager: TerrainManager = null) -> void:
	throwable_type = type
	_owner_id = owner_id
	_terrain_manager = terrain_manager


## Launch in an arc that lands at `target` (the aimed cursor position). Flight time
## scales with distance (clamped) and the vertical velocity compensates for gravity,
## so short throws are flat and long throws loft.
func throw_at(origin: Vector2, target: Vector2) -> void:
	global_position = origin
	var to := target - origin
	var flight_time := clampf(to.length() / 260.0, 0.30, 0.90)
	var v := to / flight_time
	var g := _gravity_magnitude()
	v.y -= 0.5 * g * flight_time
	linear_velocity = v


func _gravity_magnitude() -> float:
	return float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)) * gravity_scale


func _ready() -> void:
	collision_layer = 0   # nothing detects the projectile itself (keeps chests etc. quiet)
	collision_mask = 1    # collide with terrain + player bodies (layer bit 1)
	contact_monitor = true
	max_contacts_reported = 4
	_ensure_children()
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(10.0).timeout.connect(func(): if is_instance_valid(self): queue_free())
	_build_dev_sprite()


# Collision shape + sprite are created here when the node is built via .new()
# (the legacy ThrowableBase.tscn provides them already; both paths work).
func _ensure_children() -> void:
	if get_node_or_null("CollisionShape2D") == null:
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var shape := CircleShape2D.new()
		shape.radius = 4.0
		col.shape = shape
		add_child(col)
	if get_node_or_null("Sprite2D") == null:
		var spr := Sprite2D.new()
		spr.name = "Sprite2D"
		add_child(spr)


func _build_dev_sprite() -> void:
	var spr := get_node_or_null("Sprite2D") as Sprite2D
	if spr == null:
		return
	# 8×8 grenade silhouette: dark oval body, bright band, pin pixel
	const S := 8
	var K  := Color(0.06, 0.06, 0.07)   # body
	var B  := Color(0.22, 0.22, 0.24)   # body lit
	var BD := Color(0.12, 0.12, 0.14)   # body shadow
	var BN := Color(0.72, 0.68, 0.22)   # safety band
	var PN := Color(0.60, 0.62, 0.65)   # pin metal
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Oval body: fill pixels where (dx/3)^2 + (dy/3)^2 < 1 roughly
	for y in S:
		for x in S:
			var cx := float(x) - 3.5; var cy := float(y) - 4.0
			if (cx * cx / 9.0 + cy * cy / 12.0) < 1.0:
				if y == 2:
					img.set_pixel(x, y, BN)   # safety band
				elif x <= 2 and y <= 3:
					img.set_pixel(x, y, B)    # lit upper-left
				elif x >= 5 or y >= 6:
					img.set_pixel(x, y, BD)   # shadow
				else:
					img.set_pixel(x, y, K)
	# Pin — single pixel above body
	img.set_pixel(4, 0, PN)
	img.set_pixel(5, 0, PN)
	spr.texture = ImageTexture.create_from_image(img)
	spr.modulate = _dev_tint()


## Subclasses override to tint the shared grenade sprite (quick visual telling-apart).
func _dev_tint() -> Color:
	return Color.WHITE


func _on_body_entered(body: Node) -> void:
	if _impacted:
		return
	_impacted = true
	# Deferred: body_entered fires while the physics space is locked, so subclass
	# effects (shape queries, tile destruction) would error if run synchronously.
	_do_impact.call_deferred(global_position, body)


func _do_impact(impact_point: Vector2, hit_body: Node) -> void:
	_on_impact(impact_point, hit_body)
	queue_free()


## Override in each throwable subclass: apply the area effect at the impact point.
## hit_body is whatever the projectile struck first (terrain TileMap or a body).
func _on_impact(_impact_point: Vector2, _hit_body: Node) -> void:
	push_warning("ThrowableBase._on_impact not overridden for type %d" % throwable_type)


# --- Shared helpers for subclasses ---

## Tunable value from data/world_config.json "throwables" (all TBD placeholders).
func _data(key: String, fallback: Variant) -> Variant:
	var v: Variant = (GameManager.data.get("throwables", {}) as Dictionary).get(key, null)
	return v if v != null else fallback


## All damageable bodies within `radius` of the impact point, as an Array of
## { "body": Node2D, "stats": PlayerStats }. Excludes the thrower (no self-damage)
## and dead targets. FFA: everyone else is a valid target — no friendly fire exists.
func targets_in_radius(radius: float) -> Array:
	var result: Array = []
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 1   # player bodies + test dummies (terrain filtered below)
	params.collide_with_bodies = true
	var seen: Dictionary = {}
	for hit: Dictionary in space.intersect_shape(params, 32):
		var body := hit.get("collider") as Node
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if body is PlayerController and (body as PlayerController).player_id == _owner_id:
			continue   # never affect the thrower
		var stats := body.get_node_or_null("PlayerStats") as PlayerStats
		if stats == null or stats.is_dead:
			continue   # terrain TileMap and non-damageable bodies land here
		result.append({"body": body, "stats": stats})
	return result


## The world node throwable effects (clouds, markers) should be parented to —
## the same parent this projectile was spawned into.
func effect_parent() -> Node:
	return get_parent()

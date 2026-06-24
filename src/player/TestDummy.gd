## Faultline — DEV-ONLY combat target. Not part of the real game.
## A stationary, damageable body with a "PlayerStats" child so the player's melee
## raycast can hit it (it looks for a node named PlayerStats and calls take_damage).
## Shows its health above its head and respawns on death so you can keep testing.
## Remove once real networked players exist.
class_name TestDummy
extends CharacterBody2D

var _stats: PlayerStats = null
var _label: Label = null
var _gravity: float = 0.0


func _ready() -> void:
	_gravity = float(GameManager.data.get("player_gravity", 0.0)) if GameManager.data else 0.0
	collision_layer = 1
	collision_mask = 1

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 28)
	col.shape = shape
	add_child(col)

	var spr := Sprite2D.new()
	var img := Image.create(16, 28, false, Image.FORMAT_RGBA8)
	for y in range(28):
		for x in range(16):
			var edge: bool = x == 0 or y == 0 or x == 15 or y == 27
			img.set_pixel(x, y, Color(0.04, 0.05, 0.08) if edge else Color(0.80, 0.27, 0.27))
	spr.texture = ImageTexture.create_from_image(img)
	add_child(spr)

	# Named "PlayerStats" so PlayerController._try_attack's get_node_or_null finds it.
	_stats = PlayerStats.new()
	_stats.name = "PlayerStats"
	add_child(_stats)
	_stats.health_changed.connect(_on_health_changed)
	_stats.player_died.connect(_on_died)

	_label = Label.new()
	_label.position = Vector2(-18, -42)
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)
	_refresh_label()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	_refresh_label()


func _refresh_label() -> void:
	_label.text = "DUMMY %d/%d" % [int(_stats.current_health), int(_stats.max_health)]


func _on_died() -> void:
	# Dev convenience: respawn at full health so combat can be tested repeatedly.
	_stats.is_dead = false
	_stats.current_health = _stats.max_health
	_stats.health_changed.emit(_stats.current_health, _stats.max_health)
	_refresh_label()

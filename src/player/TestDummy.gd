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
	# Straw-filled target dummy: burlap body with a red X on the chest
	const W := 16; const H := 28
	var K  := Color(0.06, 0.04, 0.02)   # outline
	var BU := Color(0.58, 0.46, 0.26)   # burlap base
	var BL := Color(0.70, 0.56, 0.32)   # burlap lit
	var BD := Color(0.42, 0.32, 0.16)   # burlap shadow
	var RX := Color(0.84, 0.18, 0.18)   # red X mark
	var ST := Color(0.74, 0.64, 0.32)   # straw wisps
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in H:
		for x in W:
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				img.set_pixel(x, y, K)
			elif x <= 2 or x >= W - 3:
				img.set_pixel(x, y, BD)
			elif y <= 3:
				img.set_pixel(x, y, BL)
			else:
				img.set_pixel(x, y, BU if (x + y) % 4 != 0 else BD)
	# Red X on chest (y=8..18, x=4..11)
	for i in range(8):
		var cx := 4 + i; var cy1 := 8 + i; var cy2 := 16 - i
		if cx < W - 1 and cy1 < H - 1 and cy1 > 0:
			img.set_pixel(cx, cy1, RX)
		if cx < W - 1 and cy2 < H - 1 and cy2 > 0:
			img.set_pixel(cx, cy2, RX)
	# Straw wisps poking out of head
	for i in [3, 7, 10, 13]:
		if i < W - 1:
			img.set_pixel(i, 1, ST)
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
	queue_free()

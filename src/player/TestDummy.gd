## Faultline — DEV-ONLY combat target. Not part of the real game.
## A stationary, damageable body with a "PlayerStats" child so the player's melee
## raycast can hit it (it looks for a node named PlayerStats and calls take_damage).
## Shows its health above its head. Remove once real networked players exist.
##
## Step 8 scope decision: dummies also register as GameManager roster entries
## (see setup()) so the leaderboard/win-condition flow has real multi-participant
## data to exercise before step 9 (networking) exists. This is a deliberate
## deviation from "DEV-ONLY combat target, not a player" — flagged in GAME_STATE.md.
class_name TestDummy
extends CharacterBody2D

var _stats: PlayerStats = null
var _label: Label = null
var _sprite: Sprite2D = null
var _gravity: float = 0.0
var player_id: int = -1

# Real art first: assets/sprites/dummy.png (frame 0 = idle, frame 1 = alert).
# The engine still tints _sprite.modulate for the attack flash; the alert frame
# just gives that flash a warmer base to read against. Falls back to code art.
const DUMMY_SHEET := "res://assets/sprites/dummy.png"
const DUMMY_FRAME := 32
var _dummy_sheet: Texture2D = null
var _sprite_frame: int = -1

# DEV-ONLY attack behaviour so dummies act as live threats during testing.
# All three numbers are TBD placeholders — dummies are a dev aid, not a balanced
# enemy, so these are deliberately gentle and not sourced from data/*.json.
const DETECT_RADIUS: float = 56.0     # ~3.5 tiles; player must be this close to be attacked (TBD)
const ATTACK_DAMAGE: float = 5.0      # per hit (TBD placeholder)
const ATTACK_COOLDOWN: float = 1.5    # seconds between hits (TBD)
const FLASH_TIME: float = 0.18        # how long the red attack flash lasts

var _detect_area: Area2D = null
var _targets_in_range: Array = []     # PlayerController bodies currently within DETECT_RADIUS
var _attack_cooldown: float = 0.0     # counts down; a hit fires when it reaches 0
var _flash_timer: float = 0.0         # >0 while showing the red attack flash


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
	var sheet := _load_dummy_sheet()
	if sheet != null:
		_dummy_sheet = sheet
		spr.texture = sheet
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, DUMMY_FRAME, DUMMY_FRAME)
		_sprite_frame = 0
	else:
		spr.texture = ImageTexture.create_from_image(_make_dummy_codegen())
	add_child(spr)
	_sprite = spr

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

	# Detection radius: an Area2D on collision_mask bit 1 (the same bit the player
	# body lives on and that the player's melee hitbox already scans), so the player
	# reliably registers. body_entered/exited keep _targets_in_range current.
	_detect_area = Area2D.new()
	_detect_area.collision_layer = 0   # the sensor itself is not detectable
	_detect_area.collision_mask = 1    # detect bodies on bit 1 (players + dummies)
	var det_col := CollisionShape2D.new()
	var det_shape := CircleShape2D.new()
	det_shape.radius = DETECT_RADIUS
	det_col.shape = det_shape
	_detect_area.add_child(det_col)
	add_child(_detect_area)
	_detect_area.body_entered.connect(_on_body_entered)
	_detect_area.body_exited.connect(_on_body_exited)


# Loads assets/sprites/dummy.png, or null if absent / unimported / wrong-size.
func _load_dummy_sheet() -> Texture2D:
	if not ResourceLoader.exists(DUMMY_SHEET):
		return null
	var tex := load(DUMMY_SHEET) as Texture2D
	if tex == null:
		return null
	if tex.get_height() != DUMMY_FRAME or tex.get_width() % DUMMY_FRAME != 0:
		push_warning("[TestDummy] %s is %d×%d, expected %d-tall multiple of %d — using code art." % [
			DUMMY_SHEET, tex.get_width(), tex.get_height(), DUMMY_FRAME, DUMMY_FRAME])
		return null
	return tex


# Straw-filled target dummy fallback: burlap body with a red X on the chest.
func _make_dummy_codegen() -> Image:
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
	return img


# Switches the sheet region between idle (0) and alert (1). No-op on code art.
func _set_frame(frame: int) -> void:
	if _dummy_sheet == null or frame == _sprite_frame or _sprite == null:
		return
	_sprite_frame = frame
	_sprite.region_rect = Rect2(frame * DUMMY_FRAME, 0, DUMMY_FRAME, DUMMY_FRAME)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_process_attack(delta)


## DEV-ONLY: face the nearest in-range player and deal damage on a cooldown.
## Damage is attributed to this dummy (source_id = player_id) so PlayerStats sets
## the correct killer for the DeathScreen / spectator target if the player dies.
func _process_attack(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_update_flash()

	var target := _nearest_target()
	if target == null:
		_attack_cooldown = 0.0   # reset so a fresh approach can hit promptly
		_update_flash()
		return

	# Face the target (attack-mode indicator #1: the dummy turns toward the player).
	if _sprite:
		_sprite.flip_h = target.global_position.x < global_position.x

	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		var target_stats := target.get_node_or_null("PlayerStats") as PlayerStats
		if target_stats != null and not target_stats.is_dead:
			target_stats.take_damage(ATTACK_DAMAGE, _display_name(), player_id)
			_flash_timer = FLASH_TIME   # attack-mode indicator #2: red flash on each hit
			_update_flash()


## Nearest living PlayerController within range, or null. Other TestDummies share
## collision bit 1 and get filtered out here so dummies never fight each other.
func _nearest_target() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for body in _targets_in_range:
		if not is_instance_valid(body) or not (body is PlayerController):
			continue
		var d := global_position.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best


func _on_body_entered(body: Node) -> void:
	if body is PlayerController and not _targets_in_range.has(body):
		_targets_in_range.append(body)


func _on_body_exited(body: Node) -> void:
	_targets_in_range.erase(body)


func _display_name() -> String:
	if player_id != -1:
		return str(GameManager.get_player(player_id).get("name", "Dummy"))
	return "Dummy"


## Red while flashing a hit, a subtle aggressive tint while a target is in range,
## normal otherwise — so it's visible at a glance when a dummy is targeting you.
func _update_flash() -> void:
	if _sprite == null:
		return
	var aggressive := _nearest_target() != null
	if _flash_timer > 0.0:
		_sprite.modulate = Color(1.6, 0.5, 0.5)
	elif aggressive:
		_sprite.modulate = Color(1.25, 0.85, 0.85)
	else:
		_sprite.modulate = Color(1, 1, 1)
	# Show the warmer "alert" frame while targeting/attacking, idle otherwise.
	_set_frame(1 if (aggressive or _flash_timer > 0.0) else 0)


func _on_health_changed(_hp: float, _max_hp: float) -> void:
	_refresh_label()


func _refresh_label() -> void:
	_label.text = "DUMMY %d/%d" % [int(_stats.current_health), int(_stats.max_health)]


func _on_died() -> void:
	if player_id != -1:
		GameManager.mark_player_dead(player_id)
	queue_free()


## Called by Main.gd right after spawn + positioning. `index` gives each dummy
## a stable display name; `layer` is the Constants.Layer it spawned in (dummies
## don't move, so spawn layer IS their deepest layer reached).
func setup(index: int, layer: int) -> void:
	player_id = GameManager.register_player("Dummy %d" % index, self, true)
	GameManager.record_layer_reached(player_id, layer)


## Matches PlayerController.get_stats() — lets SpectatorView reach either
## roster participant type through one shared method instead of a hardcoded
## "PlayerStats" child-name lookup.
func get_stats() -> PlayerStats:
	return _stats

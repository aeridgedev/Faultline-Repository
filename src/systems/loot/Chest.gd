## Faultline — physical chest placed by ChestSpawner.
## Holds one loot roll (item_data dict). Player presses E to open it.
## Spawns a LootDrop at its position, then removes itself.
class_name Chest
extends Node2D

signal chest_opened(chest: Chest)

const LootDropScene := preload("res://src/systems/loot/LootDrop.tscn")

## Set by ChestSpawner before add_child so _ready() can read these.
var item_data: Dictionary = {}
var source_layer: Constants.Layer = Constants.Layer.CRUST

var _opened: bool = false
var _player_nearby: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _prompt: Label  = $Prompt
@onready var _area: Area2D   = $Area2D


func _ready() -> void:
	_build_chest_sprite()
	_prompt.visible = false
	_prompt.add_theme_font_size_override("font_size", 7)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


# 16×12 pixel chest: brown wood lid + body, iron band, tier-coloured latch.
func _build_chest_sprite() -> void:
	const W := 16; const H := 12
	var tier: int = item_data.get("tier", Constants.Tier.COMMON)
	var latch_col: Color = Constants.TIER_COLORS.get(tier, Color(0.6, 0.6, 0.6))

	var K   := Color(0.06, 0.04, 0.02)       # dark outline
	var WD  := Color(0.28, 0.14, 0.04)       # wood dark
	var WB  := Color(0.42, 0.23, 0.08)       # wood base
	var WLT := Color(0.56, 0.34, 0.12)       # wood lit (lid top/left)
	var BN  := Color(0.28, 0.24, 0.20)       # iron band dark
	var BH  := Color(0.44, 0.38, 0.30)       # iron band highlight
	var LA  := latch_col                      # latch base
	var LH  := latch_col.lightened(0.25)     # latch highlight

	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for y in H:
		for x in W:
			var border := (x == 0 or y == 0 or x == W - 1 or y == H - 1)
			if border:
				img.set_pixel(x, y, K)
				continue
			# Lid occupies rows 1–3; body rows 4–10.
			var is_lid  := y <= 3
			# Horizontal iron band at the seam (y=3,4) and narrow vertical band.
			var on_hband := (y == 3 or y == 4)
			var on_vband := (x == 7 or x == 8)
			if on_hband:
				img.set_pixel(x, y, BH if y == 3 else BN)
				continue
			if on_vband and not is_lid:
				img.set_pixel(x, y, BH if x == 7 else BN)
				continue
			# Tier-coloured latch centred on hband (x 7-8, y 3-4) — already handled
			# via on_hband above; draw latch block over it.
			if (x == 7 or x == 8) and (y == 3 or y == 4):
				img.set_pixel(x, y, LH if x == 7 else LA)
				continue
			if is_lid:
				var lit := (x <= 3 or y <= 1)
				img.set_pixel(x, y, WLT if lit else WB)
			else:
				img.set_pixel(x, y, WB if (x + y) % 3 != 0 else WD)

	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.centered = true


func _unhandled_input(event: InputEvent) -> void:
	if _opened or not _player_nearby:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_E:
		_open()
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = true
		_prompt.visible = true


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = false
		_prompt.visible = false


func _open() -> void:
	if _opened:
		return
	_opened = true
	_prompt.visible = false

	if not item_data.is_empty():
		var drop := LootDropScene.instantiate() as LootDrop
		drop.item_data = item_data
		drop.source_layer = source_layer
		get_parent().add_child(drop)
		# Place the drop one tile above the chest center so it clears the floor.
		drop.global_position = global_position + Vector2(0.0, -float(Constants.TILE_SIZE))

	chest_opened.emit(self)
	queue_free()

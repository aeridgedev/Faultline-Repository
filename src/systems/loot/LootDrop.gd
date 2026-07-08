## Faultline — a loot item lying on the ground after spawning from a chest.
## Holds the roll result from LootTable and emits pickup_requested when
## a player enters range. AutoCollect is the consumer.
class_name LootDrop
extends Node2D

signal pickup_requested(drop: LootDrop)

## The roll data produced by LootTable.roll(): {type, item_class, tier}
var item_data: Dictionary = {}

## Set by ChestSpawner after instantiation.
var source_layer: Constants.Layer = Constants.Layer.CRUST

## Seconds remaining before AutoCollect may pick this drop up.
## Set to > 0 when spawning a discarded item so it is not immediately re-collected.
var pickup_delay: float = 0.0

# World-drop icon sheet (assets/sprites/loot.png): one 16px glyph per item
# category, tinted to the item's tier at runtime. Falls back to the gem below.
const LOOT_SHEET := "res://assets/sprites/loot.png"
const LOOT_ICON := 16


func _process(delta: float) -> void:
	if pickup_delay > 0.0:
		pickup_delay = maxf(pickup_delay - delta, 0.0)


func _ready() -> void:
	add_to_group("loot_drops")
	# TBD(art): replace with a real tier-colored chest/icon once assets exist.
	# Dev placeholder: a tier-colored gem with a dark outline so loot is visible
	# on the terrain and you can watch AutoCollect pick it up.
	_build_dev_marker()


func _build_dev_marker() -> void:
	var tier: int = item_data.get("tier", Constants.Tier.COMMON)
	var base: Color = Constants.TIER_COLORS.get(tier, Color(0.7, 0.7, 0.7))
	# Glow behind the icon (drawn first so z-order puts it under).
	_build_glow(tier, base)
	# Real art first: a tier-tinted category glyph from assets/sprites/loot.png.
	# The glyph fills are light-neutral, so a tier-color modulate reads cleanly.
	var sheet := _load_loot_sheet()
	var idx := _icon_index(String(item_data.get("type", "")))
	if sheet != null and idx >= 0:
		var icon := Sprite2D.new()
		icon.texture = sheet
		icon.region_enabled = true
		icon.region_rect = Rect2(idx * LOOT_ICON, 0, LOOT_ICON, LOOT_ICON)
		icon.modulate = base
		add_child(icon)
		return
	_build_gem_codegen(base)


# Loads assets/sprites/loot.png, or null if absent / unimported / wrong-size.
func _load_loot_sheet() -> Texture2D:
	if not ResourceLoader.exists(LOOT_SHEET):
		return null
	var tex := load(LOOT_SHEET) as Texture2D
	if tex == null:
		return null
	if tex.get_height() != LOOT_ICON or tex.get_width() % LOOT_ICON != 0:
		push_warning("[LootDrop] %s is %d×%d, expected %d-tall multiple of %d — using gem art." % [
			LOOT_SHEET, tex.get_width(), tex.get_height(), LOOT_ICON, LOOT_ICON])
		return null
	return tex


# Item-category name -> icon column in loot.png. -1 for unknown types.
func _icon_index(type: String) -> int:
	match type:
		"drill": return 0
		"weapon": return 1
		"armor": return 2
		"relic": return 3
		"throwable": return 4
		"consumable": return 5
		"scanner": return 6
		_: return -1


# Fallback dev marker: a tier-colored diamond gem with inner shading.
func _build_gem_codegen(base: Color) -> void:
	# Diamond gem shape (12×12, rotated square). Tier-colored with inner shading.
	const S := 12; const MID := 5
	var K  := Color(0.04, 0.05, 0.08)
	var lit := base.lightened(0.28)
	var shd := base.darkened(0.32)
	var wh  := Color(0.94, 0.98, 1.00)     # specular
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in S:
		for x in S:
			# Diamond mask: |x - MID| + |y - MID| <= MID
			var dx: int = abs(x - MID); var dy: int = abs(y - MID)
			if dx + dy > MID:
				continue
			var on_edge: bool = (dx + dy == MID)
			if on_edge:
				img.set_pixel(x, y, K)
			elif dx + dy <= 1:
				img.set_pixel(x, y, lit)    # bright inner center
			elif y < MID:
				img.set_pixel(x, y, lit if x <= MID else base)
			else:
				img.set_pixel(x, y, shd)
	# Specular highlight — top-left corner of gem
	img.set_pixel(MID, 1, wh)
	img.set_pixel(MID - 1, 2, lit)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	add_child(sprite)


func _build_glow(tier: int, tier_col: Color) -> void:
	# Radii and peak alpha scale with tier so rarer items glow more visibly.
	const RADIUS := {
		Constants.Tier.COMMON:    8,
		Constants.Tier.RARE:      13,
		Constants.Tier.EPIC:      18,
		Constants.Tier.LEGENDARY: 26,
	}
	const ALPHA := {
		Constants.Tier.COMMON:    0.10,
		Constants.Tier.RARE:      0.32,
		Constants.Tier.EPIC:      0.50,
		Constants.Tier.LEGENDARY: 0.70,
	}
	var r: int   = RADIUS.get(tier, 8)
	var peak: float = ALPHA.get(tier, 0.10)
	var size := r * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := float(r)
	for y in size:
		for x in size:
			var dist := Vector2(x - center + 0.5, y - center + 0.5).length() / float(r)
			if dist >= 1.0:
				continue
			# Quadratic falloff: full brightness at centre, zero at edge.
			var a := (1.0 - dist) * (1.0 - dist) * peak
			img.set_pixel(x, y, Color(tier_col.r, tier_col.g, tier_col.b, a))
	var glow := Sprite2D.new()
	glow.texture = ImageTexture.create_from_image(img)
	glow.z_index = -1
	add_child(glow)


## Called by AutoCollect when within pickup radius.
func request_pickup() -> void:
	pickup_requested.emit(self)


## Remove this drop from the world after it has been collected.
func consume() -> void:
	queue_free()

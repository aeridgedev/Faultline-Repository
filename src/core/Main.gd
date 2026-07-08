extends Node2D
## Faultline — bootstrap: generates world, spawns local player, starts match.

const PlayerScene: PackedScene = preload("res://src/player/Player.tscn")
const HUDScene: PackedScene = preload("res://src/ui/HUD.tscn")

@onready var _world: Node2D = $World


func _ready() -> void:
	var layer_manager: LayerManager = _world.get_node("LayerManager")
	var terrain_manager: TerrainManager = _world.get_node("TerrainManager")

	var generator := WorldGenerator.new()
	var dummy_positions: Array = generator.generate(terrain_manager, layer_manager, randi())

	_build_background(layer_manager)

	var player: PlayerController = PlayerScene.instantiate() as PlayerController
	add_child(player)
	player.global_position = _spawn_position(layer_manager)
	# Snap camera to spawn position immediately — prevents a visible left-side
	# gap caused by the camera starting at (0,0) and smoothly panning to spawn.
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	player.player_id = GameManager.register_player("You", player, false)
	(player.get_node("PlayerStats") as PlayerStats).layer_changed.connect(
		func(new_layer: int) -> void: GameManager.record_layer_reached(player.player_id, new_layer)
	)
	player.init_world(terrain_manager)
	# Starting loadout (Common Precision Drill in hotbar slot 1, Common Sword in slot 2)
	# is populated by setup_hotbar() below: its add_item calls route through
	# InventoryManager's reserved-slot rules, which also build the in-hand drill/weapon
	# Resources. No separate equip-starter step is needed.
	player.get_node("DescentTracker").init(layer_manager)

	# Per-layer ambient lighting (Part A visual polish): one world CanvasModulate
	# tweened between each layer's approved tint on descent (Core Hollow pulses).
	# Added under _world so the tint lands on canvas layer 0 (the world), not the HUD.
	var layer_visuals := LayerVisuals.new()
	layer_visuals.name = "LayerVisuals"
	_world.add_child(layer_visuals)
	layer_visuals.init(player.stats, _world)

	var stamina := player.get_node("Stamina") as Stamina
	var storm := _init_hazards(player.stats, stamina, layer_manager)
	player.init_storm(storm)
	(_world.get_node("PressureSystem") as PressureSystem).zero_gravity_changed.connect(player.set_zero_gravity)
	ChestSpawner.spawn(terrain_manager, layer_manager, _world)
	for i in dummy_positions.size():
		_spawn_test_dummy(dummy_positions[i], i, layer_manager)

	var hud: HUD = HUDScene.instantiate() as HUD
	add_child(hud)
	hud.init(player, storm, layer_manager)

	# After the HUD is listening, populate the hotbar so its slot labels update.
	player.setup_hotbar()

	GameManager.start_match()


func _init_hazards(stats: PlayerStats, stamina: Stamina, layer_manager: LayerManager) -> StormSystem:
	var depth := _world.get_node("DepthHazard") as DepthHazard
	depth.init(stats, stamina)

	var pressure := _world.get_node("PressureSystem") as PressureSystem
	pressure.init(stats)

	var storm := _world.get_node("StormSystem") as StormSystem
	storm.init(stats, layer_manager)
	storm.start()
	return storm


# Builds a vertical gradient backdrop behind the terrain: sky at the atmosphere,
# darkening through warm crust tones into the molten core. Dev placeholder until
# real parallax art exists, but it kills the flat gray void.
func _build_background(layer_manager: LayerManager) -> void:
	var world_h: Variant = layer_manager.world_height_px()
	if world_h == null:
		return  # layer heights TBD — skip backdrop rather than guess dimensions
	var atmosphere_px := Constants.TILE_SIZE * 8
	var width_px := _world_width_px()
	var total_h := float(world_h) + atmosphere_px

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.04, 0.08, 0.14, 0.30, 0.46, 0.58, 0.72, 0.86, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.22, 0.42, 0.68),  # upper atmosphere — dusky sky
		Color(0.36, 0.50, 0.62),  # lower atmosphere — haze
		Color(0.24, 0.19, 0.14),  # crust entry
		Color(0.30, 0.23, 0.15),  # upper crust — warm earth
		Color(0.18, 0.14, 0.11),  # deep crust — compressed earth
		Color(0.14, 0.11, 0.13),  # mantle — dark purple-gray
		Color(0.20, 0.09, 0.09),  # outer core — heat rising
		Color(0.36, 0.12, 0.05),  # inner core — molten red
		Color(0.48, 0.16, 0.04),  # inner core deep — intense
		Color(0.04, 0.03, 0.05),  # core hollow — void black
	])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)  # vertical
	tex.width = 8
	tex.height = 256

	var bg := Sprite2D.new()
	bg.name = "Background"
	bg.texture = tex
	bg.centered = false
	bg.z_index = -100
	bg.z_as_relative = false
	# Extend far enough in both directions that the player will never see the edge
	# during a match, even walking purely horizontal for 22 minutes.
	var bg_half := width_px * 60.0
	bg.position = Vector2(-bg_half, float(-atmosphere_px))
	bg.scale = Vector2(bg_half * 2.0 / tex.width, total_h / tex.height)
	add_child(bg)


# DEV-ONLY: place a test dummy at a world-space position.
# Positions come from WorldGenerator (WorldGenerator.DUMMIES_PER_LAYER per layer, on cave floors).
# Remove once networked players exist.
func _spawn_test_dummy(pos: Vector2, index: int, layer_manager: LayerManager) -> void:
	var dummy := TestDummy.new()
	dummy.name = "TestDummy%d" % index
	add_child(dummy)
	dummy.global_position = pos
	dummy.setup(index, layer_manager.layer_at_y(pos.y))


func _spawn_position(layer_manager: LayerManager) -> Vector2:
	# Spawn in the atmosphere above the Crust surface so the player drops onto the
	# terrain (parachute landing) instead of starting embedded inside solid soil.
	# TBD: scatter spawn x across the Crust top once 100-player drops are wired.
	var top_y: Variant = layer_manager.get_layer_top_y(Constants.Layer.CRUST)
	var surface_y: float = float(top_y) if top_y != null else 0.0
	var spawn_y: float = surface_y - Constants.TILE_SIZE * 5.0  # 5 tiles of air above
	var world_center_x: float = _world_center_x()
	return Vector2(world_center_x, spawn_y)


func _world_width_px() -> float:
	var width_tiles: int = GameManager.data.get("world_width_tiles", 0) if GameManager.data else 0
	if width_tiles <= 0:
		return 1280.0  # TBD: world_width_tiles not set; fall back to viewport width
	return float(width_tiles) * Constants.TILE_SIZE


func _world_center_x() -> float:
	return _world_width_px() / 2.0

extends Node2D
## Faultline — bootstrap: generates world, spawns local player, starts match.

const PlayerScene: PackedScene = preload("res://src/player/Player.tscn")

@onready var _world: Node2D = $World


func _ready() -> void:
	var layer_manager: LayerManager = _world.get_node("LayerManager")
	var terrain_manager: TerrainManager = _world.get_node("TerrainManager")

	var generator := WorldGenerator.new()
	generator.generate(terrain_manager, layer_manager, randi())

	var player: PlayerController = PlayerScene.instantiate()
	add_child(player)
	player.global_position = _spawn_position(layer_manager)
	player.init_world(terrain_manager)
	player.equip_starter_drill()
	player.equip_starter_weapon()
	player.get_node("DescentTracker").init(layer_manager)

	_init_hazards(player.stats)
	ChestSpawner.spawn(terrain_manager, layer_manager, _world)

	GameManager.start_match()


func _init_hazards(stats: PlayerStats) -> void:
	var depth := DepthHazard.new()
	depth.name = "DepthHazard"
	add_child(depth)
	depth.init(stats)

	var pressure := PressureSystem.new()
	pressure.name = "PressureSystem"
	add_child(pressure)
	pressure.init(stats)

	var storm := StormSystem.new()
	storm.name = "StormSystem"
	add_child(storm)
	storm.init(stats)
	storm.start()


func _spawn_position(layer_manager: LayerManager) -> Vector2:
	# TBD: scatter spawn across Crust top once world width is known; center for now.
	var top_y: Variant = layer_manager.get_layer_top_y(Constants.Layer.CRUST)
	var y := float(top_y) + Constants.TILE_SIZE * 2.0 if top_y != null else 0.0
	return Vector2(640.0, y)  # TBD: x from world width

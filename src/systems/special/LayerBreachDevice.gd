## Faultline — LayerBreachDevice: one-use item that instantly drills through the floor
## of the current layer, dropping the player into the next layer.
## Effect radius and exact mechanics TBD; spawn rate TBD.
class_name LayerBreachDevice
extends Resource

signal breach_triggered(from_layer: Constants.Layer)


func use(stats: PlayerStats, terrain_manager: TerrainManager, player_position: Vector2) -> void:
	if stats.is_dead:
		return
	var from_layer := stats.get_layer() as Constants.Layer
	if from_layer == Constants.Layer.CORE_HOLLOW:
		return  # already in the final layer; no breach possible
	# Destroy tiles in a small column below the player down to the layer boundary.
	# TBD: column width and depth (how many tiles) is TBD — clear 1 tile wide for now.
	var cell := terrain_manager.world_to_cell(player_position)
	# TODO(step 6 balance): breach radius/depth from data["layer_breach_radius"].
	for dy in range(1, 8):
		terrain_manager.destroy_tile(Vector2i(cell.x, cell.y + dy))
	breach_triggered.emit(from_layer)

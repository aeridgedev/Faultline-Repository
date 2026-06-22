class_name DataLoader
extends RefCounted
## Loads tunable balance data from data/*.json.
##
## Keeping numbers in JSON (not GDScript) lets the balance pass retune the
## game without touching code. All values currently in these files are
## PLACEHOLDERS unless the file says otherwise — see each file's "_meta".

const DATA_DIR := "res://data/"

static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("DataLoader: missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: failed to parse JSON: " + path)
		return {}
	return parsed

static func load_all() -> Dictionary:
	return {
		"drills": load_json("drill_stats.json"),
		"weapons": load_json("weapon_stats.json"),
		"armor": load_json("armor_stats.json"),
		"loot": load_json("loot_tables.json"),
		"spawn": load_json("spawn_rates.json"),
		"storm": load_json("storm_timings.json"),
		"terrain": load_json("terrain_stats.json"),
	}

extends Node

## Global game state singleton.
## Stores settings, player data, NPCs, objects, and current scene info.

signal settings_changed
signal game_state_changed

# ── Settings ──────────────────────────────────────────────────────────────────
var language: String = "it"
var llm_backend_url: String = "http://localhost:1234"
var llm_model: String = "local-model"
var invoke_url: String = "http://localhost:9090"
var image_style: String = "anime" # "3d", "realistic", "anime", "custom"
var custom_style: String = ""

# ── Game data ─────────────────────────────────────────────────────────────────
var story_type: String = ""
var story_preamble: String = ""
var story_language: String = ""
var render_style: String = ""

# ── Player character ──────────────────────────────────────────────────────────
var player_character: Dictionary = {
	"name": "",
	"image_path": "",
	"sex": "",
	"height": "",
	"body_type": "",
	"hair_color": "",
	"skin_color": "",
	"eye_color": "",
	"tattoos": [],       # Array of { "description": String, "position": String }
	"breast_size": "",
	"buttocks": "",
	"legs": "",
}

# ── Objective ─────────────────────────────────────────────────────────────────
var objective: String = ""

# ── NPCs ──────────────────────────────────────────────────────────────────────
var npcs: Array = []

# ── Objects ───────────────────────────────────────────────────────────────────
var objects: Array = []

# ── Scene state ───────────────────────────────────────────────────────────────
var current_scene: String = ""
var game_started: bool = false


# ══════════════════════════════════════════════════════════════════════════════
# Settings persistence
# ══════════════════════════════════════════════════════════════════════════════

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "language", language)
	cfg.set_value("settings", "llm_backend_url", llm_backend_url)
	cfg.set_value("settings", "llm_model", llm_model)
	cfg.set_value("settings", "invoke_url", invoke_url)
	cfg.set_value("settings", "image_style", image_style)
	cfg.set_value("settings", "custom_style", custom_style)
	var err := cfg.save("user://settings.cfg")
	if err != OK:
		push_error("GameState: failed to save settings – error %d" % err)
	else:
		settings_changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	if err != OK:
		# First launch – keep defaults.
		return
	language = cfg.get_value("settings", "language", language)
	llm_backend_url = cfg.get_value("settings", "llm_backend_url", llm_backend_url)
	llm_model = cfg.get_value("settings", "llm_model", llm_model)
	invoke_url = cfg.get_value("settings", "invoke_url", invoke_url)
	image_style = cfg.get_value("settings", "image_style", image_style)
	custom_style = cfg.get_value("settings", "custom_style", custom_style)
	settings_changed.emit()


# ══════════════════════════════════════════════════════════════════════════════
# Game save / load
# ══════════════════════════════════════════════════════════════════════════════

func save_game(slot_name: String = "auto") -> void:
	var data := {
		"slot_name": slot_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"story_type": story_type,
		"story_preamble": story_preamble,
		"story_language": story_language,
		"render_style": render_style,
		"player_character": player_character,
		"objective": objective,
		"npcs": npcs,
		"objects": objects,
		"current_scene": current_scene,
		"game_started": game_started,
	}
	var json_string := JSON.stringify(data, "\t")
	var safe_name := slot_name.to_lower().replace(" ", "_").replace("/", "_")
	var path := "user://save_%s.json" % safe_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameState: failed to save to %s – error %d" % [path, FileAccess.get_open_error()])
		return
	file.store_string(json_string)
	file.close()
	game_state_changed.emit()


func load_game(slot_name: String = "auto") -> bool:
	var safe_name := slot_name.to_lower().replace(" ", "_").replace("/", "_")
	var path := "user://save_%s.json" % safe_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("GameState: save '%s' not found." % slot_name)
		return false
	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		push_error("GameState: save JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return false

	var data: Dictionary = json.data
	story_type = data.get("story_type", "")
	story_preamble = data.get("story_preamble", "")
	story_language = data.get("story_language", "")
	render_style = data.get("render_style", "")
	player_character = data.get("player_character", _default_player_character())
	objective = data.get("objective", "")
	npcs = data.get("npcs", [])
	objects = data.get("objects", [])
	current_scene = data.get("current_scene", "")
	game_started = data.get("game_started", false)
	game_state_changed.emit()
	return true


func list_saves() -> Array:
	var saves: Array = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return saves
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("save_") and fname.ends_with(".json"):
			var file := FileAccess.open("user://" + fname, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					saves.append({
						"file": fname,
						"slot_name": json.data.get("slot_name", fname),
						"saved_at": json.data.get("saved_at", ""),
						"player_name": json.data.get("player_character", {}).get("name", ""),
					})
				file.close()
		fname = dir.get_next()
	dir.list_dir_end()
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("saved_at", "") > b.get("saved_at", "")
	)
	return saves


func delete_save(slot_name: String) -> void:
	var safe_name := slot_name.to_lower().replace(" ", "_").replace("/", "_")
	var path := "user://save_%s.json" % safe_name
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ══════════════════════════════════════════════════════════════════════════════
# Reset
# ══════════════════════════════════════════════════════════════════════════════

func reset_game() -> void:
	story_type = ""
	story_preamble = ""
	story_language = ""
	render_style = ""
	player_character = _default_player_character()
	objective = ""
	npcs = []
	objects = []
	current_scene = ""
	game_started = false
	game_state_changed.emit()


func _default_player_character() -> Dictionary:
	return {
		"name": "",
		"image_path": "",
		"sex": "",
		"height": "",
		"body_type": "",
		"hair_color": "",
		"skin_color": "",
		"eye_color": "",
		"tattoos": [],
		"breast_size": "",
		"buttocks": "",
		"legs": "",
	}


# ══════════════════════════════════════════════════════════════════════════════
# NPC helpers
# ══════════════════════════════════════════════════════════════════════════════

func get_npc(npc_name: String) -> Dictionary:
	for npc in npcs:
		if npc.get("name", "") == npc_name:
			return npc
	return {}


func add_npc(data: Dictionary) -> void:
	# Replace existing NPC with the same name if present.
	for i in range(npcs.size()):
		if npcs[i].get("name", "") == data.get("name", ""):
			npcs[i] = data
			game_state_changed.emit()
			return
	npcs.append(data)
	game_state_changed.emit()


func remove_npc(npc_name: String) -> void:
	for i in range(npcs.size()):
		if npcs[i].get("name", "") == npc_name:
			npcs.remove_at(i)
			game_state_changed.emit()
			return


# ══════════════════════════════════════════════════════════════════════════════
# Object helpers
# ══════════════════════════════════════════════════════════════════════════════

func add_object(data: Dictionary) -> void:
	for i in range(objects.size()):
		if objects[i].get("name", "") == data.get("name", ""):
			objects[i] = data
			game_state_changed.emit()
			return
	objects.append(data)
	game_state_changed.emit()


func remove_object(obj_name: String) -> void:
	for i in range(objects.size()):
		if objects[i].get("name", "") == obj_name:
			objects.remove_at(i)
			game_state_changed.emit()
			return


func get_objects_at(location: String) -> Array:
	var result: Array = []
	for obj in objects:
		if obj.get("location", "") == location:
			result.append(obj)
	return result


# ══════════════════════════════════════════════════════════════════════════════
# Scene helpers
# ══════════════════════════════════════════════════════════════════════════════

func find_spawn_point(tag: String) -> Vector2:
	for area in get_tree().get_nodes_in_group("spawn"):
		if area is Area2D and area.get_meta("area_tag", "") == tag:
			return area.global_position
	push_warning("GameState: spawn point with tag '%s' not found." % tag)
	return Vector2.ZERO


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	load_settings()

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
var image_style: String = "anime"
var custom_style: String = ""
var selected_invoke_model: String = ""
var render_width: int = 768
var render_height: int = 512
var default_race: String = "Caucasian"

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
	"slot_head": "",
	"slot_chest": "",
	"slot_legs": "",
	"slot_weapon": "",
	"slot_shield": "",
	"slot_accessory": "",
	"outfit": [],
	"personality": "",
	"strengths": "",
	"weaknesses": "",
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

# ── Runtime state (saved with game) ──────────────────────────────────────────
var player_position: Vector2 = Vector2.ZERO
var chat_history: Array = []
var gallery_images: Array = []
var story_intro: String = ""  # LLM-generated story introduction (max 300 chars)
var story_log: Array = []  # Array of {"type":"dialogue"|"choice"|"event", "text":"...", "npc":"..."}
var met_npcs: Array = []
var fog_path: String = ""

# ── Library database (persistent across games) ──────────────────────────────
var _library_path: String = "user://library.json"


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
	cfg.set_value("settings", "selected_invoke_model", selected_invoke_model)
	cfg.set_value("settings", "render_width", render_width)
	cfg.set_value("settings", "render_height", render_height)
	cfg.set_value("settings", "default_race", default_race)
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
	selected_invoke_model = cfg.get_value("settings", "selected_invoke_model", selected_invoke_model)
	render_width = cfg.get_value("settings", "render_width", render_width)
	render_height = cfg.get_value("settings", "render_height", render_height)
	default_race = cfg.get_value("settings", "default_race", default_race)
	settings_changed.emit()


# ══════════════════════════════════════════════════════════════════════════════
# Game save / load
# ══════════════════════════════════════════════════════════════════════════════

func save_game(slot_name: String = "auto") -> void:
	var safe_name := slot_name.to_lower().replace(" ", "_").replace("/", "_")
	var save_dir := "user://saves/%s" % safe_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))

	# Copy images into save folder so they survive moves/deletes
	var pc_copy := player_character.duplicate(true)
	pc_copy["image_path"] = _persist_image(pc_copy.get("image_path", ""), save_dir, "player")

	var npcs_copy: Array = []
	for i in range(npcs.size()):
		var npc := (npcs[i] as Dictionary).duplicate(true)
		npc["image_path"] = _persist_image(npc.get("image_path", ""), save_dir, "npc_%d" % i)
		npcs_copy.append(npc)

	var objects_copy: Array = []
	for i in range(objects.size()):
		var obj := (objects[i] as Dictionary).duplicate(true)
		obj["image_path"] = _persist_image(obj.get("image_path", ""), save_dir, "obj_%d" % i)
		objects_copy.append(obj)

	# Save gallery images
	var gallery_paths: Array = []
	for i in range(gallery_images.size()):
		var src: String = gallery_images[i]
		var persisted := _persist_image(src, save_dir, "gallery_%d" % i)
		gallery_paths.append(persisted)

	var data := {
		"slot_name": slot_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"story_type": story_type,
		"story_preamble": story_preamble,
		"story_language": story_language,
		"render_style": render_style,
		"player_character": pc_copy,
		"objective": objective,
		"npcs": npcs_copy,
		"objects": objects_copy,
		"current_scene": current_scene,
		"game_started": game_started,
		"player_position": {"x": player_position.x, "y": player_position.y},
		"chat_history": chat_history,
		"gallery_images": gallery_paths,
		"story_intro": story_intro,
		"story_log": story_log,
		"met_npcs": met_npcs,
		"fog_path": fog_path,
	}
	var json_string := JSON.stringify(data, "\t")
	var path := "%s/save.json" % save_dir
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameState: failed to save to %s – error %d" % [path, FileAccess.get_open_error()])
		return
	file.store_string(json_string)
	file.close()
	print("GameState: saved to %s" % path)
	game_state_changed.emit()


func _persist_image(src_path: String, save_dir: String, prefix: String) -> String:
	if src_path.is_empty():
		return ""
	# If already in save dir, keep it
	if src_path.begins_with(save_dir):
		return src_path
	var ext := src_path.get_extension()
	if ext.is_empty():
		ext = "png"
	var dest := "%s/%s.%s" % [save_dir, prefix, ext]
	var abs_src := ProjectSettings.globalize_path(src_path) if src_path.begins_with("user://") else src_path
	# Load and re-save to ensure it's in the save folder
	var img := Image.new()
	if img.load(abs_src) == OK:
		match ext.to_lower():
			"jpg", "jpeg":
				img.save_jpg(dest)
			"webp":
				img.save_webp(dest)
			_:
				img.save_png(dest)
		return ProjectSettings.globalize_path(dest)
	return src_path


func load_game(slot_name: String = "auto") -> bool:
	var safe_name := slot_name.to_lower().replace(" ", "_").replace("/", "_")
	# Try new format first (saves/slot/save.json), then legacy (save_slot.json)
	var path := "user://saves/%s/save.json" % safe_name
	if not FileAccess.file_exists(path):
		path = "user://save_%s.json" % safe_name
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
	chat_history = data.get("chat_history", [])
	gallery_images = data.get("gallery_images", [])
	story_intro = data.get("story_intro", "")
	story_log = data.get("story_log", [])
	met_npcs = data.get("met_npcs", [])
	fog_path = data.get("fog_path", "")

	var pos_data: Dictionary = data.get("player_position", {})
	player_position = Vector2(
		float(pos_data.get("x", 0)),
		float(pos_data.get("y", 0))
	)

	game_state_changed.emit()
	print("GameState: loaded from %s" % path)
	return true


func list_saves() -> Array:
	var saves: Array = []
	# New format: user://saves/{slot}/save.json
	var saves_dir := DirAccess.open("user://saves")
	if saves_dir:
		saves_dir.list_dir_begin()
		var dname := saves_dir.get_next()
		while dname != "":
			if saves_dir.current_is_dir():
				var save_path := "user://saves/%s/save.json" % dname
				var file := FileAccess.open(save_path, FileAccess.READ)
				if file:
					var json := JSON.new()
					if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
						saves.append({
							"file": save_path,
							"slot_name": json.data.get("slot_name", dname),
							"saved_at": json.data.get("saved_at", ""),
							"player_name": json.data.get("player_character", {}).get("name", ""),
						})
					file.close()
			dname = saves_dir.get_next()
		saves_dir.list_dir_end()

	# Legacy format: user://save_{name}.json
	var root_dir := DirAccess.open("user://")
	if root_dir:
		root_dir.list_dir_begin()
		var fname := root_dir.get_next()
		while fname != "":
			if fname.begins_with("save_") and fname.ends_with(".json"):
				var file := FileAccess.open("user://" + fname, FileAccess.READ)
				if file:
					var json := JSON.new()
					if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
						saves.append({
							"file": "user://" + fname,
							"slot_name": json.data.get("slot_name", fname),
							"saved_at": json.data.get("saved_at", ""),
							"player_name": json.data.get("player_character", {}).get("name", ""),
						})
					file.close()
			fname = root_dir.get_next()
		root_dir.list_dir_end()

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
	player_position = Vector2.ZERO
	chat_history = []
	gallery_images = []
	story_intro = ""
	story_log = []
	met_npcs = []
	fog_path = ""
	game_state_changed.emit()


# ══════════════════════════════════════════════════════════════════════════════
# Library — reusable items and characters across games
# ══════════════════════════════════════════════════════════════════════════════

func library_save_item(item: Dictionary) -> void:
	var lib := _load_library()
	var items: Array = lib.get("items", [])
	# Replace if exists, else append
	var found := false
	for i in range(items.size()):
		if items[i].get("name", "") == item.get("name", ""):
			items[i] = item.duplicate(true)
			found = true
			break
	if not found:
		items.append(item.duplicate(true))
	lib["items"] = items
	_save_library(lib)


func library_save_character(char_data: Dictionary) -> void:
	var lib := _load_library()
	var chars: Array = lib.get("characters", [])
	var save_data := char_data.duplicate(true)
	# Include equipped items (not inventory)
	var equipped_items: Array = []
	for slot_key in ["head", "chest", "legs", "weapon", "shield", "accessory"]:
		var item_name: String = save_data.get("slot_%s" % slot_key, "")
		if item_name == "":
			continue
		for obj in objects:
			if obj.get("name", "") == item_name:
				equipped_items.append(obj.duplicate(true))
				break
	save_data["saved_equipped_items"] = equipped_items
	# Replace if exists
	var found := false
	var char_name: String = save_data.get("name", "")
	for i in range(chars.size()):
		if chars[i].get("name", "") == char_name:
			chars[i] = save_data
			found = true
			break
	if not found:
		chars.append(save_data)
	lib["characters"] = chars
	_save_library(lib)


func library_list_items() -> Array:
	var lib := _load_library()
	return lib.get("items", [])


func library_list_characters() -> Array:
	var lib := _load_library()
	return lib.get("characters", [])


func library_delete_item(item_name: String) -> void:
	var lib := _load_library()
	var items: Array = lib.get("items", [])
	lib["items"] = items.filter(func(i: Dictionary) -> bool: return i.get("name", "") != item_name)
	_save_library(lib)


func library_delete_character(char_name: String) -> void:
	var lib := _load_library()
	var chars: Array = lib.get("characters", [])
	lib["characters"] = chars.filter(func(c: Dictionary) -> bool: return c.get("name", "") != char_name)
	_save_library(lib)


func library_load_character_into_game(char_name: String, as_npc: bool = true) -> Dictionary:
	var lib := _load_library()
	for c: Dictionary in lib.get("characters", []):
		if c.get("name", "") == char_name:
			var data := c.duplicate(true)
			# Restore equipped items into game objects
			var saved_items: Array = data.get("saved_equipped_items", [])
			for item in saved_items:
				item["owner"] = char_name
				item["location"] = "equipped"
				add_object(item)
			data.erase("saved_equipped_items")
			if as_npc:
				add_npc(data)
			return data
	return {}


func _load_library() -> Dictionary:
	var file := FileAccess.open(_library_path, FileAccess.READ)
	if file == null:
		return {"items": [], "characters": []}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"items": [], "characters": []}
	if json.data is Dictionary:
		return json.data
	return {"items": [], "characters": []}


func _save_library(lib: Dictionary) -> void:
	var file := FileAccess.open(_library_path, FileAccess.WRITE)
	if file == null:
		push_error("GameState: failed to write library")
		return
	file.store_string(JSON.stringify(lib, "\t"))
	file.close()


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
		"slot_head": "",
		"slot_chest": "",
		"slot_legs": "",
		"slot_weapon": "",
		"slot_shield": "",
		"slot_accessory": "",
		"outfit": [],
		"personality": "",
		"strengths": "",
		"weaknesses": "",
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

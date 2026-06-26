extends Node

## SQLite-based library for reusable items and characters across games.

var _db: SQLite = null
const DB_PATH := "user://library"


func _ready() -> void:
	_db = SQLite.new()
	_db.path = DB_PATH
	_db.open_db()
	_create_tables()


func _create_tables() -> void:
	# Items library
	_db.query(
		"CREATE TABLE IF NOT EXISTS items ("
		+ "name TEXT PRIMARY KEY, "
		+ "description TEXT DEFAULT '', "
		+ "category TEXT DEFAULT '', "
		+ "image_path TEXT DEFAULT '', "
		+ "data TEXT DEFAULT '{}'"
		+ ")"
	)

	# Characters library
	_db.query(
		"CREATE TABLE IF NOT EXISTS characters ("
		+ "name TEXT PRIMARY KEY, "
		+ "image_path TEXT DEFAULT '', "
		+ "sex TEXT DEFAULT '', "
		+ "age TEXT DEFAULT '', "
		+ "race TEXT DEFAULT '', "
		+ "height TEXT DEFAULT '', "
		+ "body_type TEXT DEFAULT '', "
		+ "hair_color TEXT DEFAULT '', "
		+ "skin_color TEXT DEFAULT '', "
		+ "eye_color TEXT DEFAULT '', "
		+ "personality TEXT DEFAULT '', "
		+ "strengths TEXT DEFAULT '', "
		+ "weaknesses TEXT DEFAULT '', "
		+ "data TEXT DEFAULT '{}'"
		+ ")"
	)

	# Equipped items per saved character
	_db.query(
		"CREATE TABLE IF NOT EXISTS character_equipment ("
		+ "character_name TEXT, "
		+ "slot TEXT, "
		+ "item_name TEXT, "
		+ "item_data TEXT DEFAULT '{}', "
		+ "PRIMARY KEY (character_name, slot)"
		+ ")"
	)


# ══════════════════════════════════════════════════════════════════════════════
# Items
# ══════════════════════════════════════════════════════════════════════════════

func save_item(item: Dictionary) -> void:
	var item_name: String = item.get("name", "")
	if item_name == "":
		return
	_db.query_with_bindings(
		"INSERT OR REPLACE INTO items (name, description, category, image_path, data) VALUES (?, ?, ?, ?, ?)",
		[item_name, item.get("description", ""), item.get("category", ""), item.get("image_path", ""), JSON.stringify(item)]
	)


func list_items() -> Array:
	_db.query("SELECT data FROM items ORDER BY name")
	var results: Array = []
	for row in _db.query_result:
		var json := JSON.new()
		if json.parse(row.get("data", "{}")) == OK and json.data is Dictionary:
			results.append(json.data)
	return results


func get_item(item_name: String) -> Dictionary:
	_db.query_with_bindings("SELECT data FROM items WHERE name = ?", [item_name])
	if _db.query_result.size() > 0:
		var json := JSON.new()
		if json.parse(_db.query_result[0].get("data", "{}")) == OK and json.data is Dictionary:
			return json.data
	return {}


func delete_item(item_name: String) -> void:
	_db.query_with_bindings("DELETE FROM items WHERE name = ?", [item_name])


func search_items(query: String) -> Array:
	_db.query_with_bindings(
		"SELECT data FROM items WHERE name LIKE ? OR category LIKE ? OR description LIKE ? ORDER BY name",
		["%" + query + "%", "%" + query + "%", "%" + query + "%"]
	)
	var results: Array = []
	for row in _db.query_result:
		var json := JSON.new()
		if json.parse(row.get("data", "{}")) == OK and json.data is Dictionary:
			results.append(json.data)
	return results


# ══════════════════════════════════════════════════════════════════════════════
# Characters
# ══════════════════════════════════════════════════════════════════════════════

func save_character(char_data: Dictionary, equipped_items: Array = []) -> void:
	var char_name: String = char_data.get("name", "")
	if char_name == "":
		return
	_db.query_with_bindings(
		"INSERT OR REPLACE INTO characters (name, image_path, sex, age, race, height, body_type, hair_color, skin_color, eye_color, personality, strengths, weaknesses, data) "
		+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
		[
			char_name,
			char_data.get("image_path", ""),
			char_data.get("sex", char_data.get("gender", "")),
			str(char_data.get("age", "")),
			char_data.get("race", ""),
			char_data.get("height", ""),
			char_data.get("body_type", char_data.get("build", "")),
			char_data.get("hair_color", ""),
			char_data.get("skin_color", ""),
			char_data.get("eye_color", ""),
			char_data.get("personality", ""),
			char_data.get("strengths", ""),
			char_data.get("weaknesses", ""),
			JSON.stringify(char_data),
		]
	)

	# Save equipped items
	_db.query_with_bindings("DELETE FROM character_equipment WHERE character_name = ?", [char_name])
	for item: Dictionary in equipped_items:
		var slot: String = item.get("_slot", "")
		if slot == "":
			continue
		_db.query_with_bindings(
			"INSERT OR REPLACE INTO character_equipment (character_name, slot, item_name, item_data) VALUES (?, ?, ?, ?)",
			[char_name, slot, item.get("name", ""), JSON.stringify(item)]
		)


func list_characters() -> Array:
	_db.query("SELECT data FROM characters ORDER BY name")
	var results: Array = []
	for row in _db.query_result:
		var json := JSON.new()
		if json.parse(row.get("data", "{}")) == OK and json.data is Dictionary:
			results.append(json.data)
	return results


func get_character(char_name: String) -> Dictionary:
	_db.query_with_bindings("SELECT data FROM characters WHERE name = ?", [char_name])
	if _db.query_result.size() > 0:
		var json := JSON.new()
		if json.parse(_db.query_result[0].get("data", "{}")) == OK and json.data is Dictionary:
			return json.data
	return {}


func get_character_equipment(char_name: String) -> Array:
	_db.query_with_bindings("SELECT item_data FROM character_equipment WHERE character_name = ? ORDER BY slot", [char_name])
	var results: Array = []
	for row in _db.query_result:
		var json := JSON.new()
		if json.parse(row.get("item_data", "{}")) == OK and json.data is Dictionary:
			results.append(json.data)
	return results


func delete_character(char_name: String) -> void:
	_db.query_with_bindings("DELETE FROM characters WHERE name = ?", [char_name])
	_db.query_with_bindings("DELETE FROM character_equipment WHERE character_name = ?", [char_name])


func search_characters(query: String) -> Array:
	_db.query_with_bindings(
		"SELECT data FROM characters WHERE name LIKE ? OR race LIKE ? OR personality LIKE ? ORDER BY name",
		["%" + query + "%", "%" + query + "%", "%" + query + "%"]
	)
	var results: Array = []
	for row in _db.query_result:
		var json := JSON.new()
		if json.parse(row.get("data", "{}")) == OK and json.data is Dictionary:
			results.append(json.data)
	return results


# ══════════════════════════════════════════════════════════════════════════════
# Load into game
# ══════════════════════════════════════════════════════════════════════════════

func load_character_into_game(char_name: String) -> Dictionary:
	var char_data := get_character(char_name)
	if char_data.is_empty():
		return {}
	# Restore equipped items into game objects
	var equipment := get_character_equipment(char_name)
	for item in equipment:
		item["owner"] = char_name
		item["location"] = "equipped"
		GameState.add_object(item)
	return char_data


func load_item_into_game(item_name: String, owner: String = "") -> Dictionary:
	var item := get_item(item_name)
	if item.is_empty():
		return {}
	item["location"] = "inventory"
	item["owner"] = owner
	GameState.add_object(item)
	return item

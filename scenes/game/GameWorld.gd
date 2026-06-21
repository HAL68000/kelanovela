extends Node2D

## Main gameplay scene controller.
## Instances Map, Player, Camera, NPCs, and UI.
## Handles room detection, NPC proximity, LLM actions, and photo generation.

signal player_entered_room(room_name: String, room_desc: String)
signal player_exited_room(room_name: String)
signal npc_nearby(npc_name: String, distance: float)

# ── Configuration ────────────────────────────────────────────────────────────
const NPC_INTERACT_DISTANCE: float = 80.0
const NPC_NEARBY_DISTANCE: float = 200.0

# ── Scene references ─────────────────────────────────────────────────────────
var _map: Node2D = null
var _player: CharacterBody2D = null
var _camera: Camera2D = null
var _ui: CanvasLayer = null

# ── NPC tracking ─────────────────────────────────────────────────────────────
var _npc_sprites: Dictionary = {}  # npc_name -> NPCSprite node
var _nearby_npcs: Array = []       # Array of npc data dicts for currently nearby NPCs
var _closest_npc_name: String = "" # Name of NPC closest to player (within interact range)

# ── Room tracking ────────────────────────────────────────────────────────────
var _current_room_name: String = ""
var _current_room_desc: String = ""
var _room_areas: Array = []        # Cached references to room Area2D nodes

# ── Spawn areas ──────────────────────────────────────────────────────────────
var _spawn_areas: Array = []       # Cached references to spawn Area2D nodes

# ── Photo state ──────────────────────────────────────────────────────────────
var _photo_in_progress: bool = false

# ── Pause menu ───────────────────────────────────────────────────────────────
var _pause_overlay: CanvasLayer = null
var _pause_visible: bool = false

# ── Preloaded scenes ─────────────────────────────────────────────────────────
var _npc_scene: PackedScene = preload("res://scenes/game/NPCSprite.tscn")


func _ready() -> void:
	_setup_map()
	_cache_areas()
	_setup_player()
	_setup_camera()
	_spawn_npcs()
	_setup_ui()
	_build_pause_menu()

	_ui.update_inventory(GameState.objects.filter(
		func(o: Dictionary) -> bool: return o.get("location", "") == "inventory"
	))

	_ui.add_chat_message("Sistema", "Benvenuto nel gioco. Esplora il mondo e interagisci con i personaggi.", Color("4fc3f7"))
	if GameState.objective != "":
		_ui.add_chat_message("Obiettivo", GameState.objective, Color(0.9, 0.8, 0.3))


func _process(_delta: float) -> void:
	_update_camera()
	_update_current_room()
	_update_npc_proximity()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and _closest_npc_name != "" and not _pause_visible:
			_interact_with_npc(_closest_npc_name)
			get_viewport().set_input_as_handled()


func _interact_with_npc(npc_name: String) -> void:
	var npc_data: Dictionary = GameState.get_npc(npc_name)
	if npc_data.is_empty():
		return
	_ui.add_chat_message("Sistema", "Ti avvicini a %s." % npc_name, Color("4fc3f7"))
	var mood: String = npc_data.get("mood", "neutrale")
	var role: String = npc_data.get("role", "")
	var desc: String = npc_data.get("description", "")
	var info := "%s — Umore: %s" % [npc_name, mood]
	if role != "":
		info += " — Ruolo: %s" % role
	if desc != "":
		info += "\n%s" % desc
	_ui.add_chat_message("", info, Color(0.7, 0.8, 0.9))


# ══════════════════════════════════════════════════════════════════════════════
# Setup
# ══════════════════════════════════════════════════════════════════════════════

func _setup_map() -> void:
	var map_scene: PackedScene = load("res://scenes/Map.tscn")
	_map = map_scene.instantiate()
	_map.name = "Map"
	add_child(_map)


func _setup_player() -> void:
	var player_scene: PackedScene = load("res://scenes/Player.tscn")
	_player = player_scene.instantiate()
	_player.name = "Player"
	add_child(_player)

	# Load character image as sprite texture if available
	var pc: Dictionary = GameState.player_character
	var img_path: String = pc.get("image_path", "")
	if img_path != "":
		var img := Image.new()
		if img.load(img_path) == OK:
			var tex := ImageTexture.create_from_image(img)
			var sprite: Sprite2D = _player.get_node_or_null("Sprite2D")
			if sprite:
				sprite.texture = tex
				var max_dim := maxf(img.get_width(), img.get_height())
				var target_size := 48.0
				var s := target_size / max_dim
				sprite.scale = Vector2(s, s)

	await get_tree().process_frame
	_move_player_to_spawn("#entrance")

	# Auto-save after entering the game
	GameState.game_started = true
	GameState.save_game()


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "FollowCamera"
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_camera.zoom = Vector2(1.0, 1.0)

	# Determine map bounds from the Map node (TileMap or similar)
	var map_size := Vector2(1856, 1408)  # Default from FollowCamera.gd
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(map_size.x)
	_camera.limit_bottom = int(map_size.y)

	add_child(_camera)


func _update_camera() -> void:
	if _player and _camera:
		_camera.global_position = _player.global_position


func _setup_ui() -> void:
	var ui_scene: PackedScene = load("res://scenes/game/GameUI.tscn")
	_ui = ui_scene.instantiate()
	_ui.name = "GameUI"
	add_child(_ui)

	# Connect UI signals
	_ui.chat_action_requested.connect(_on_chat_action)
	_ui.photo_requested.connect(take_photo)
	_ui.inventory_item_used.connect(_on_inventory_item_used)


func _cache_areas() -> void:
	_room_areas = get_tree().get_nodes_in_group("room")
	_spawn_areas = get_tree().get_nodes_in_group("spawn")


# ══════════════════════════════════════════════════════════════════════════════
# NPC Spawning
# ══════════════════════════════════════════════════════════════════════════════

func _spawn_npcs() -> void:
	var pc_name: String = GameState.player_character.get("name", "").strip_edges().to_lower()
	for i in range(GameState.npcs.size()):
		var npc_data: Dictionary = GameState.npcs[i]
		var npc_name: String = npc_data.get("name", "NPC_%d" % i)

		if npc_name.strip_edges().to_lower() == pc_name and pc_name != "":
			continue

		var npc_node: CharacterBody2D = _npc_scene.instantiate()
		add_child(npc_node)

		# Position NPC at their assigned location or a spawn area
		var position_tag: String = npc_data.get("position", "")
		var spawn_pos := _find_area_position(position_tag)
		if spawn_pos == Vector2.ZERO:
			# Fallback: distribute across available spawn areas
			var spawn_idx := i % _spawn_areas.size() if _spawn_areas.size() > 0 else 0
			if _spawn_areas.size() > 0:
				spawn_pos = _spawn_areas[spawn_idx].global_position
			else:
				spawn_pos = Vector2(400 + i * 100, 400)

		npc_node.global_position = spawn_pos
		npc_node.setup(npc_data, i)

		_npc_sprites[npc_name] = npc_node


# ══════════════════════════════════════════════════════════════════════════════
# Room Detection
# ══════════════════════════════════════════════════════════════════════════════

func _update_current_room() -> void:
	if not _player:
		return

	var player_pos := _player.global_position
	var found_room := ""
	var found_desc := ""

	for area in _room_areas:
		if not area is Area2D:
			continue
		# Check if player position is inside the area's collision shape
		var col_shape: CollisionShape2D = null
		for child in area.get_children():
			if child is CollisionShape2D:
				col_shape = child
				break

		if col_shape == null:
			continue

		var shape: Shape2D = col_shape.shape
		if shape == null:
			continue

		# Transform player position into area's local space
		var local_pos: Vector2 = area.to_local(player_pos)

		# Check if point is inside the shape
		if _point_in_shape(local_pos, shape):
			found_room = area.get_meta("area_name", area.name)
			found_desc = area.get_meta("area_description", "")
			var tag: String = area.get_meta("area_tag", "")
			if tag != "":
				found_room += " " + tag
			break

	if found_room != _current_room_name:
		if _current_room_name != "":
			player_exited_room.emit(_current_room_name)

		_current_room_name = found_room
		_current_room_desc = found_desc

		if found_room != "":
			player_entered_room.emit(found_room, found_desc)

		_ui.update_room(_current_room_name, _current_room_desc)


func _point_in_shape(point: Vector2, shape: Shape2D) -> bool:
	if shape is RectangleShape2D:
		var rect_shape := shape as RectangleShape2D
		var half := rect_shape.size / 2.0
		return abs(point.x) <= half.x and abs(point.y) <= half.y
	elif shape is CircleShape2D:
		var circle_shape := shape as CircleShape2D
		return point.length() <= circle_shape.radius
	# Fallback: rough bounding check
	return false


# ══════════════════════════════════════════════════════════════════════════════
# NPC Proximity
# ══════════════════════════════════════════════════════════════════════════════

func _update_npc_proximity() -> void:
	if not _player:
		return

	var player_pos := _player.global_position
	var new_nearby: Array = []
	var closest_name := ""
	var closest_dist := INF

	for npc_name: String in _npc_sprites:
		var npc_node: CharacterBody2D = _npc_sprites[npc_name]
		var dist := player_pos.distance_to(npc_node.global_position)

		if dist <= NPC_NEARBY_DISTANCE:
			var npc_data: Dictionary = npc_node.npc_data
			new_nearby.append(npc_data)

			if dist < closest_dist and dist <= NPC_INTERACT_DISTANCE:
				closest_dist = dist
				closest_name = npc_name

	# Update UI if nearby list changed
	if _npcs_changed(new_nearby):
		_nearby_npcs = new_nearby
		_ui.update_nearby_npcs(_nearby_npcs)

	# Update interaction hint
	if closest_name != _closest_npc_name:
		_closest_npc_name = closest_name
		if closest_name != "":
			_ui.show_interaction_hint(closest_name)
		else:
			_ui.hide_interaction_hint()


func _npcs_changed(new_list: Array) -> bool:
	if new_list.size() != _nearby_npcs.size():
		return true
	for npc_data: Dictionary in new_list:
		var found := false
		for existing: Dictionary in _nearby_npcs:
			if existing.get("name", "") == npc_data.get("name", ""):
				found = true
				break
		if not found:
			return true
	return false


# ══════════════════════════════════════════════════════════════════════════════
# LLM Action Handling
# ══════════════════════════════════════════════════════════════════════════════

func _on_chat_action(action: Dictionary) -> void:
	var action_type: String = action.get("type", "")
	var params: Dictionary = action.get("params", {})

	match action_type:
		"change_outfit":
			_action_change_outfit(params)
		"create_object":
			_action_create_object(params)
		"destroy_object":
			_action_destroy_object(params)
		"change_mood":
			_action_change_mood(params)
		"change_status":
			_action_change_status(params)
		"move_npc":
			_action_move_npc(params)
		"move_player":
			_action_move_player(params)
		_:
			push_warning("GameWorld: unknown action type '%s'" % action_type)


func _action_change_outfit(params: Dictionary) -> void:
	var npc_name: String = params.get("npc_name", "")
	var slot: String = params.get("slot", "")
	var item: String = params.get("item", "")

	var npc_data := GameState.get_npc(npc_name)
	if npc_data.is_empty():
		return

	# Ensure outfit is an array
	if not npc_data.has("outfit") or not (npc_data["outfit"] is Array):
		npc_data["outfit"] = []

	if item.is_empty():
		# Remove item from slot
		npc_data["outfit"].erase(slot)
	else:
		# Add or replace outfit item
		var outfit: Array = npc_data["outfit"]
		# Remove old item in same slot if exists
		for i in range(outfit.size()):
			if typeof(outfit[i]) == TYPE_STRING and outfit[i].begins_with(slot + ":"):
				outfit.remove_at(i)
				break
		outfit.append("%s: %s" % [slot, item])

	GameState.add_npc(npc_data)
	_refresh_npc_sprite(npc_name)


func _action_create_object(params: Dictionary) -> void:
	var obj_data := {
		"name": params.get("name", "oggetto"),
		"description": params.get("description", ""),
		"category": params.get("category", "tools"),
		"location": params.get("location", "inventory"),
	}
	GameState.add_object(obj_data)

	# Update inventory UI if it went to inventory
	if obj_data["location"] == "inventory":
		_update_inventory_ui()
		_ui.add_chat_message("Sistema", "Hai ottenuto: %s" % obj_data["name"], Color("4fc3f7"))


func _action_destroy_object(params: Dictionary) -> void:
	var obj_name: String = params.get("name", "")
	GameState.remove_object(obj_name)
	_update_inventory_ui()
	_ui.add_chat_message("Sistema", "Hai perso: %s" % obj_name, Color(0.8, 0.5, 0.5))


func _action_change_mood(params: Dictionary) -> void:
	var npc_name: String = params.get("npc_name", "")
	var mood: String = params.get("mood", "neutral")

	var npc_data := GameState.get_npc(npc_name)
	if npc_data.is_empty():
		return

	npc_data["mood"] = mood
	GameState.add_npc(npc_data)
	_refresh_npc_sprite(npc_name)


func _action_change_status(params: Dictionary) -> void:
	var npc_name: String = params.get("npc_name", "")
	var alive: bool = params.get("alive", true)

	var npc_data := GameState.get_npc(npc_name)
	if npc_data.is_empty():
		return

	npc_data["alive"] = alive
	if not alive:
		npc_data["mood"] = "dead"
	GameState.add_npc(npc_data)
	_refresh_npc_sprite(npc_name)


func _action_move_npc(params: Dictionary) -> void:
	var npc_name: String = params.get("npc_name", "")
	var destination: String = params.get("destination", "")

	if not _npc_sprites.has(npc_name):
		return

	var target_pos := _find_area_position(destination)
	if target_pos == Vector2.ZERO:
		push_warning("GameWorld: move_npc destination '%s' not found" % destination)
		return

	var npc_node: CharacterBody2D = _npc_sprites[npc_name]
	npc_node.move_to(target_pos)

	# Update NPC data
	var npc_data := GameState.get_npc(npc_name)
	if not npc_data.is_empty():
		npc_data["position"] = destination
		GameState.add_npc(npc_data)


func _action_move_player(params: Dictionary) -> void:
	var destination: String = params.get("destination", "")
	_move_player_to_area(destination)


# ══════════════════════════════════════════════════════════════════════════════
# Photo Feature
# ══════════════════════════════════════════════════════════════════════════════

func take_photo() -> void:
	if _photo_in_progress:
		_ui.add_chat_message("Sistema", "Foto in elaborazione, attendi...", Color("4fc3f7"))
		return

	_photo_in_progress = true

	# Capture errors from InvokeService
	var _last_invoke_error := ""
	var _err_cb := func(err: String) -> void: _last_invoke_error = err
	InvokeService.generation_failed.connect(_err_cb)

	# Check InvokeAI connection first
	var invoke_ok: bool = await InvokeService.test_connection()
	if not invoke_ok:
		_ui.add_chat_message("Sistema", "InvokeAI non raggiungibile su %s — avvia InvokeAI o controlla l'URL nelle Opzioni." % GameState.invoke_url, Color(0.8, 0.3, 0.3))
		_photo_in_progress = false
		InvokeService.generation_failed.disconnect(_err_cb)
		return

	_ui.add_chat_message("Sistema", "Scattando una foto della scena...", Color("4fc3f7"))
	_ui.set_loading(true)

	# 1. Gather scene context
	var room_desc := _current_room_desc if _current_room_desc != "" else _current_room_name
	var scene_description := "Location: %s. %s" % [_current_room_name, room_desc]

	var characters: Array = []

	var pc := GameState.player_character
	if pc.get("name", "") != "":
		var player_desc := ""
		if pc.get("physical_traits", "") != "":
			player_desc = pc["physical_traits"]
		else:
			player_desc = "%s, %s hair, %s skin, %s eyes" % [
				pc.get("body_type", ""),
				pc.get("hair_color", ""),
				pc.get("skin_color", ""),
				pc.get("eye_color", ""),
			]
		characters.append({"name": pc["name"], "description": player_desc})

	for npc_data: Dictionary in _nearby_npcs:
		var npc_desc: String = str(npc_data.get("description", npc_data.get("physical_traits", "")))
		var outfit: Array = npc_data.get("outfit", [])
		if outfit.size() > 0:
			npc_desc += " Wearing: %s." % ", ".join(outfit)
		characters.append({"name": npc_data.get("name", ""), "description": npc_desc})

	# 2. Build prompt via LLM
	var style: String = GameState.image_style
	if style == "custom" and GameState.custom_style != "":
		style = GameState.custom_style

	var prompt: String = await LLMService.build_scene_prompt(scene_description, characters, style)

	if prompt.is_empty():
		_ui.add_chat_message("Sistema", "Errore: LLM non ha generato il prompt. Controlla che LM Studio sia attivo su %s" % GameState.llm_backend_url, Color(0.8, 0.3, 0.3))
		_ui.set_loading(false)
		_photo_in_progress = false
		InvokeService.generation_failed.disconnect(_err_cb)
		return

	_ui.add_chat_message("Sistema", "Prompt: %s" % prompt.left(120), Color(0.6, 0.6, 0.7))
	_ui.add_chat_message("Sistema", "Generando immagine su InvokeAI...", Color("4fc3f7"))

	# 3. Generate image via InvokeAI
	_last_invoke_error = ""
	var image_name: String = await InvokeService.generate_image(prompt, 768, 512)

	if image_name.is_empty():
		var detail := _last_invoke_error if _last_invoke_error != "" else "Nessun dettaglio disponibile"
		_ui.add_chat_message("Sistema", "Errore generazione immagine: %s" % detail, Color(0.8, 0.3, 0.3))
		_ui.set_loading(false)
		_photo_in_progress = false
		InvokeService.generation_failed.disconnect(_err_cb)
		return

	# 4. Download and display
	var image_bytes: PackedByteArray = await InvokeService.download_image(image_name)

	InvokeService.generation_failed.disconnect(_err_cb)

	if image_bytes.is_empty():
		_ui.add_chat_message("Sistema", "Errore download immagine '%s' da InvokeAI." % image_name, Color(0.8, 0.3, 0.3))
		_ui.set_loading(false)
		_photo_in_progress = false
		return

	var image := Image.new()
	var load_err := image.load_png_from_buffer(image_bytes)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(image_bytes)
	if load_err != OK:
		load_err = image.load_webp_from_buffer(image_bytes)

	if load_err != OK:
		_ui.add_chat_message("Sistema", "Errore decodifica immagine (formato non riconosciuto).", Color(0.8, 0.3, 0.3))
		_ui.set_loading(false)
		_photo_in_progress = false
		return

	var texture := ImageTexture.create_from_image(image)
	_ui.show_photo(texture)
	_ui.add_chat_message("Sistema", "Foto scattata!", Color(0.3, 0.9, 0.5))

	_ui.set_loading(false)
	_photo_in_progress = false


# ══════════════════════════════════════════════════════════════════════════════
# Inventory
# ══════════════════════════════════════════════════════════════════════════════

func _on_inventory_item_used(item_name: String) -> void:
	# Mention item usage in chat context
	_ui.add_chat_message("Azione", "Usi %s..." % item_name, Color("4fc3f7"))


func _update_inventory_ui() -> void:
	var inv_items: Array = GameState.objects.filter(
		func(o: Dictionary) -> bool: return o.get("location", "") == "inventory"
	)
	_ui.update_inventory(inv_items)


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _find_area_position(tag_or_name: String) -> Vector2:
	if tag_or_name.is_empty():
		return Vector2.ZERO

	# Search by tag first (more specific)
	for area in _spawn_areas:
		if area.get_meta("area_tag", "") == tag_or_name:
			return area.global_position

	# Search rooms by tag
	for area in _room_areas:
		if area.get_meta("area_tag", "") == tag_or_name:
			return area.global_position

	# Search by area_name
	for area in _room_areas:
		if area.get_meta("area_name", "") == tag_or_name:
			return area.global_position

	# Search by node name (fallback)
	for area in _room_areas:
		if area.name == tag_or_name:
			return area.global_position

	for area in _spawn_areas:
		if area.get_meta("area_name", "") == tag_or_name:
			return area.global_position

	return Vector2.ZERO


func _move_player_to_spawn(tag: String) -> void:
	var pos := _find_area_position(tag)
	if pos != Vector2.ZERO and _player:
		_player.global_position = pos


func _move_player_to_area(destination: String) -> void:
	var pos := _find_area_position(destination)
	if pos != Vector2.ZERO and _player:
		# Use the player's navigation agent for smooth movement
		_player.nav_agent.target_position = pos
		_player._navigating = true


func _refresh_npc_sprite(npc_name: String) -> void:
	if _npc_sprites.has(npc_name):
		var npc_node: CharacterBody2D = _npc_sprites[npc_name]
		var updated_data := GameState.get_npc(npc_name)
		if not updated_data.is_empty():
			npc_node.npc_data = updated_data
			npc_node.update_appearance()


# ══════════════════════════════════════════════════════════════════════════════
# Pause Menu
# ══════════════════════════════════════════════════════════════════════════════

const _COL_BG := Color("1a1a2eee")
const _COL_SURFACE := Color("1e2a45")
const _COL_BORDER := Color("2e4070")
const _COL_ACCENT := Color("4fc3f7")
const _COL_TEXT := Color.WHITE
const _COL_BTN := Color("2a2a4e")
const _COL_BTN_HOVER := Color("3a3a6e")

var _pause_panel: PanelContainer
var _pause_save_list: ItemList
var _pause_save_name_edit: LineEdit
var _pause_status_label: Label


func _build_pause_menu() -> void:
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.layer = 100
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	# Dimmed background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.add_child(dim)

	# Center panel
	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.offset_left = -280
	_pause_panel.offset_right = 280
	_pause_panel.offset_top = -260
	_pause_panel.offset_bottom = 260
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = _COL_SURFACE
	panel_style.border_color = _COL_ACCENT
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	_pause_panel.add_theme_stylebox_override("panel", panel_style)
	_pause_overlay.add_child(_pause_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_pause_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", _COL_ACCENT)
	vbox.add_child(title)

	# Save name input
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	vbox.add_child(save_row)

	var save_label := Label.new()
	save_label.text = "Nome salvataggio:"
	save_label.add_theme_font_size_override("font_size", 16)
	save_label.add_theme_color_override("font_color", _COL_TEXT)
	save_row.add_child(save_label)

	_pause_save_name_edit = LineEdit.new()
	_pause_save_name_edit.placeholder_text = "es. prima della torre..."
	_pause_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_save_name_edit.add_theme_font_size_override("font_size", 16)
	_pause_save_name_edit.add_theme_color_override("font_color", _COL_TEXT)
	_pause_save_name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color("0f1525")
	le_style.border_color = _COL_BORDER
	le_style.set_border_width_all(1)
	le_style.set_corner_radius_all(4)
	le_style.content_margin_left = 8
	le_style.content_margin_right = 8
	le_style.content_margin_top = 4
	le_style.content_margin_bottom = 4
	_pause_save_name_edit.add_theme_stylebox_override("normal", le_style)
	var le_focus := le_style.duplicate()
	le_focus.border_color = _COL_ACCENT
	_pause_save_name_edit.add_theme_stylebox_override("focus", le_focus)
	save_row.add_child(_pause_save_name_edit)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var save_btn := _pause_btn("Salva")
	save_btn.pressed.connect(_on_pause_save)
	btn_row.add_child(save_btn)

	var load_btn := _pause_btn("Carica")
	load_btn.pressed.connect(_on_pause_load)
	btn_row.add_child(load_btn)

	var delete_btn := _pause_btn("Elimina")
	delete_btn.add_theme_color_override("font_color", Color("e74c3c"))
	delete_btn.pressed.connect(_on_pause_delete)
	btn_row.add_child(delete_btn)

	# Save list
	var list_label := Label.new()
	list_label.text = "Salvataggi esistenti:"
	list_label.add_theme_font_size_override("font_size", 14)
	list_label.add_theme_color_override("font_color", _COL_ACCENT)
	vbox.add_child(list_label)

	_pause_save_list = ItemList.new()
	_pause_save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pause_save_list.custom_minimum_size = Vector2(0, 120)
	_pause_save_list.add_theme_color_override("font_color", _COL_TEXT)
	_pause_save_list.add_theme_color_override("font_selected_color", _COL_ACCENT)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color("0f1525")
	list_style.border_color = _COL_BORDER
	list_style.set_border_width_all(1)
	list_style.set_corner_radius_all(4)
	_pause_save_list.add_theme_stylebox_override("panel", list_style)
	_pause_save_list.add_theme_stylebox_override("focus", list_style)
	_pause_save_list.item_selected.connect(_on_save_list_selected)
	vbox.add_child(_pause_save_list)

	# Status
	_pause_status_label = Label.new()
	_pause_status_label.text = ""
	_pause_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status_label.add_theme_font_size_override("font_size", 14)
	_pause_status_label.add_theme_color_override("font_color", Color("2ecc71"))
	vbox.add_child(_pause_status_label)

	# Bottom buttons
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom_row)

	var resume_btn := _pause_btn("Riprendi")
	resume_btn.add_theme_color_override("font_color", _COL_ACCENT)
	resume_btn.pressed.connect(_toggle_pause_menu)
	bottom_row.add_child(resume_btn)

	var menu_btn := _pause_btn("Menu Principale")
	menu_btn.pressed.connect(_on_pause_main_menu)
	bottom_row.add_child(menu_btn)


func _pause_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 40)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", _COL_TEXT)
	btn.add_theme_color_override("font_hover_color", _COL_ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = _COL_BTN
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = _COL_BTN_HOVER
	hover.border_color = _COL_ACCENT
	hover.set_border_width_all(1)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = _COL_ACCENT
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	return btn


func _toggle_pause_menu() -> void:
	_pause_visible = not _pause_visible
	_pause_overlay.visible = _pause_visible
	get_tree().paused = _pause_visible
	if _pause_visible:
		_refresh_save_list()
		_pause_status_label.text = ""
		process_mode = Node.PROCESS_MODE_ALWAYS


func _refresh_save_list() -> void:
	_pause_save_list.clear()
	var saves: Array = GameState.list_saves()
	for save_data: Dictionary in saves:
		var slot: String = save_data.get("slot_name", "")
		var when: String = save_data.get("saved_at", "")
		var who: String = save_data.get("player_name", "")
		var label := "%s" % slot
		if who != "":
			label += " — %s" % who
		if when != "":
			label += " (%s)" % when
		_pause_save_list.add_item(label)
		_pause_save_list.set_item_metadata(_pause_save_list.item_count - 1, slot)


func _on_save_list_selected(index: int) -> void:
	var slot: String = _pause_save_list.get_item_metadata(index)
	_pause_save_name_edit.text = slot


func _on_pause_save() -> void:
	var slot := _pause_save_name_edit.text.strip_edges()
	if slot.is_empty():
		_pause_status_label.add_theme_color_override("font_color", Color("e74c3c"))
		_pause_status_label.text = "Inserisci un nome per il salvataggio."
		return
	GameState.call("save_game", slot)
	_pause_status_label.add_theme_color_override("font_color", Color("2ecc71"))
	_pause_status_label.text = "Salvato: %s" % slot
	_refresh_save_list()


func _on_pause_load() -> void:
	var selected: PackedInt32Array = _pause_save_list.get_selected_items()
	if selected.is_empty():
		_pause_status_label.add_theme_color_override("font_color", Color("e74c3c"))
		_pause_status_label.text = "Seleziona un salvataggio dalla lista."
		return
	var slot: String = _pause_save_list.get_item_metadata(selected[0])
	var ok: bool = GameState.call("load_game", slot)
	if ok:
		_toggle_pause_menu()
		get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")
	else:
		_pause_status_label.add_theme_color_override("font_color", Color("e74c3c"))
		_pause_status_label.text = "Errore nel caricamento di '%s'." % slot


func _on_pause_delete() -> void:
	var selected: PackedInt32Array = _pause_save_list.get_selected_items()
	if selected.is_empty():
		_pause_status_label.add_theme_color_override("font_color", Color("e74c3c"))
		_pause_status_label.text = "Seleziona un salvataggio da eliminare."
		return
	var slot: String = _pause_save_list.get_item_metadata(selected[0])
	GameState.delete_save(slot)
	_pause_status_label.add_theme_color_override("font_color", Color("f39c12"))
	_pause_status_label.text = "Eliminato: %s" % slot
	_refresh_save_list()


func _on_pause_main_menu() -> void:
	GameState.call("save_game", "auto")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

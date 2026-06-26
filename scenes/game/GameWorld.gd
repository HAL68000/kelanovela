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

# ── Character sheet ──────────────────────────────────────────────────────────
var _character_sheet: CanvasLayer = null

# ── Pause menu ───────────────────────────────────────────────────────────────
var _pause_overlay: CanvasLayer = null
var _pause_visible: bool = false

# ── Map objects ──────────────────────────────────────────────────────────────
var _map_object_sprites: Dictionary = {}  # obj_name -> Sprite2D
var _containers: Dictionary = {}  # "room_name:container_type" -> Array of obj dicts (max 6)
var _highlight_active: bool = false
var _highlight_outlines: Array = []  # Array of Node2D used for outlines

# ── Story screen ─────────────────────────────────────────────────────────────
var _story_screen: CanvasLayer = null
var _story_screen_visible: bool = false
var _story_log_container: VBoxContainer = null

# ── Dev console ──────────────────────────────────────────────────────────────
var _dev_console: CanvasLayer = null
var _dev_console_visible: bool = false
var _dev_input: LineEdit = null
var _dev_output: RichTextLabel = null
var _dev_temp_labels: Array = []

# ── Preloaded scenes ─────────────────────────────────────────────────────────
var _npc_scene: PackedScene = preload("res://scenes/game/NPCSprite.tscn")


func _ready() -> void:
	_setup_map()
	_cache_areas()
	_setup_player()
	_setup_camera()
	_spawn_npcs()
	_place_map_objects()
	_setup_ui()
	_build_pause_menu()
	_setup_character_sheet()
	_build_dev_console()

	_ui.update_inventory(GameState.objects.filter(
		func(o: Dictionary) -> bool:
			return o.get("location", "") == "inventory" and o.get("owner", "") == GameState.player_character.get("name", "")
	))

	# Restore chat history
	if GameState.chat_history.size() > 0:
		for msg in GameState.chat_history:
			var role: String = msg.get("role", "")
			var content: String = msg.get("content", "")
			if role == "user":
				_ui.add_chat_message(GameState.player_character.get("name", "Tu"), content, Color("4fc3f7"))
			elif role == "assistant":
				_ui.add_chat_message("Narratore", content, Color(0.8, 0.8, 0.9))
	else:
		if GameState.story_intro != "":
			_ui.add_chat_message("Narratore", GameState.story_intro, Color(0.9, 0.85, 0.7))
		else:
			_ui.add_chat_message("Sistema", "Benvenuto nel gioco. Esplora il mondo e interagisci con i personaggi.", Color("4fc3f7"))
		if GameState.objective != "":
			_ui.add_chat_message("Obiettivo", GameState.objective, Color(0.9, 0.8, 0.3))
		_ui.add_chat_message("Sistema", "Premi S per il diario della storia.", Color(0.5, 0.5, 0.6))

	# Restore gallery images
	for img_path: String in GameState.gallery_images:
		if img_path == "":
			continue
		var img := Image.new()
		if img.load(img_path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_ui.add_photo_to_gallery(tex, img_path)


func _process(_delta: float) -> void:
	_update_camera()
	_update_current_room()
	_update_npc_proximity()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Close overlays first, then pause menu
			if _story_screen_visible:
				_toggle_story_screen()
				get_viewport().set_input_as_handled()
				return
			if _dev_console_visible:
				_toggle_dev_console()
				get_viewport().set_input_as_handled()
				return
			if _ui and _ui._container_popup and _ui._container_popup.visible:
				_ui._container_popup.visible = false
				get_viewport().set_input_as_handled()
				return
			if _ui and _ui._photo_popup and _ui._photo_popup.visible:
				_ui._photo_popup.visible = false
				get_viewport().set_input_as_handled()
				return
			if _ui and _ui._photo_modal and _ui._photo_modal.visible:
				_ui._photo_modal.visible = false
				get_viewport().set_input_as_handled()
				return
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_QUOTELEFT and not _pause_visible:
			_toggle_dev_console()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S and not _pause_visible and not _dev_console_visible:
			_toggle_story_screen()
			get_viewport().set_input_as_handled()
		elif (event.keycode == KEY_I or event.keycode == KEY_C) and not _pause_visible:
			_toggle_character_sheet()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and not _pause_visible:
			if _closest_npc_name != "":
				_interact_with_npc(_closest_npc_name)
			else:
				_open_room_containers()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_TAB:
			if event.pressed:
				_show_highlights()
			else:
				_hide_highlights()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.double_click and not _pause_visible:
		var click_pos: Vector2 = _player.get_global_mouse_position() if _player else Vector2.ZERO
		var handled := false
		# Check player first
		if _player and click_pos.distance_to(_player.global_position) < 40.0:
			_toggle_character_sheet()
			handled = true
		# Check NPCs
		if not handled:
			for npc_name_key: String in _npc_sprites:
				var npc_node: Node2D = _npc_sprites[npc_name_key]
				if click_pos.distance_to(npc_node.global_position) < 40.0:
					_show_npc_sheet(npc_name_key)
					handled = true
					break
		# Check interactive furniture (cabinet, basket, table, library)
		if not handled and _player:
			var interact_dist := 120.0
			for obj_node in get_tree().get_nodes_in_group("interactive"):
				if click_pos.distance_to(obj_node.global_position) > interact_dist:
					continue
				if _player.global_position.distance_to(obj_node.global_position) > interact_dist * 2:
					continue
				var obj_name: String = obj_node.name.to_lower()
				var container_type := ""
				if obj_name.contains("cabinet") or obj_name.contains("wardrobe") or obj_name.contains("shelf") or obj_name.contains("library"):
					container_type = "cabinet"
				elif obj_name.contains("basket") or obj_name.contains("crate") or obj_name.contains("box"):
					container_type = "basket"
				elif obj_name.contains("table") or obj_name.contains("desk"):
					container_type = "table"
				if container_type != "":
					_show_container(_current_room_name, container_type)
					handled = true
					break
		if handled:
			get_viewport().set_input_as_handled()


func _interact_with_npc(npc_name: String) -> void:
	var npc_data: Dictionary = GameState.get_npc(npc_name)
	if npc_data.is_empty():
		return

	var first_meeting: bool = not GameState.met_npcs.has(npc_name)
	if first_meeting:
		GameState.met_npcs.append(npc_name)

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

	# First meeting: auto-generate introduction via LLM
	if first_meeting:
		_generate_first_meeting(npc_name, npc_data)


func _generate_first_meeting(npc_name: String, npc_data: Dictionary) -> void:
	_ui.set_loading(true)
	var pc_name: String = GameState.player_character.get("name", "Tu")
	var personality: String = npc_data.get("personality", "")
	var role: String = npc_data.get("role", "")

	var meeting_prompt := (
		"Questo è il primo incontro tra %s (il giocatore) e %s (%s). " % [pc_name, npc_name, role]
		+ "Personalità di %s: %s. " % [npc_name, personality]
		+ "Genera una breve scena di presentazione tra i due personaggi. "
		+ "Rispondi nella lingua della storia."
	)

	var context: Dictionary = _ui.call("_build_chat_context")
	var result: Dictionary = await LLMService.game_chat(meeting_prompt, context)
	_ui.set_loading(false)

	var response_text: String = result.get("response", "")
	if response_text != "":
		_ui.add_chat_message("Narratore", response_text, Color(0.8, 0.8, 0.9))
		GameState.story_log.append({"type": "event", "text": "Primo incontro con %s" % npc_name, "npc": npc_name})
		GameState.story_log.append({"type": "dialogue", "text": response_text, "npc": npc_name})

	var options: Array = result.get("options", [])
	if options.size() > 0:
		_ui.show_options(options)

	# Process actions but only for nearby NPCs
	var actions: Array = result.get("actions", [])
	for action: Dictionary in actions:
		_ui.chat_action_requested.emit(action)

	var movements: Array = result.get("npc_movements", [])
	for movement in movements:
		if not movement is Dictionary:
			continue
		var mn: String = movement.get("npc_name", "")
		var dest: String = movement.get("destination", "")
		if mn != "" and dest != "":
			_ui.chat_action_requested.emit({"type": "move_npc", "params": {"npc_name": mn, "destination": dest, "reason": movement.get("reason", "")}})


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

	# Restore saved position or spawn at entrance
	if GameState.player_position != Vector2.ZERO:
		_player.global_position = GameState.player_position
	else:
		_move_player_to_spawn("#entrance")

	GameState.game_started = true


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
	_ui.container_item_taken.connect(_on_container_item_taken)


func _cache_areas() -> void:
	_room_areas = get_tree().get_nodes_in_group("room")
	_spawn_areas = get_tree().get_nodes_in_group("spawn")
	# Disable input on room/hallway/spawn areas so they don't block clicks on objects
	for area in _room_areas:
		if area is Area2D:
			area.input_pickable = false
			area.monitoring = false
			area.monitorable = false
	for area in get_tree().get_nodes_in_group("hallway"):
		if area is Area2D:
			area.input_pickable = false
			area.monitoring = false
			area.monitorable = false
	for area in _spawn_areas:
		if area is Area2D:
			area.input_pickable = false
			area.monitoring = false
			area.monitorable = false


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

		# Restore saved position, or use assigned location, or fallback
		var saved_x: float = float(npc_data.get("saved_position_x", 0))
		var saved_y: float = float(npc_data.get("saved_position_y", 0))
		var spawn_pos := Vector2.ZERO
		if saved_x != 0 or saved_y != 0:
			spawn_pos = Vector2(saved_x, saved_y)
		else:
			var position_tag: String = npc_data.get("position", "")
			spawn_pos = _find_area_position(position_tag)
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
# Map Objects & Containers
# ══════════════════════════════════════════════════════════════════════════════

const VISIBLE_MAP_CATEGORIES := ["machinery", "statue", "furniture_large"]

func _place_map_objects() -> void:
	_containers.clear()
	for obj in GameState.objects:
		if obj.get("location", "") == "inventory" or obj.get("location", "") == "equipped":
			continue
		var container_type: String = obj.get("container", "none")
		var room: String = obj.get("location", "")

		if container_type != "none" and container_type != "":
			var key := "%s:%s" % [room, container_type]
			if not _containers.has(key):
				_containers[key] = []
			if _containers[key].size() < 6:
				_containers[key].append(obj)
		else:
			# Only show very large objects (statues, machinery) on the map
			var cat: String = obj.get("category", "").to_lower()
			var w: int = int(obj.get("image_width", 64))
			var h: int = int(obj.get("image_height", 64))
			if cat in VISIBLE_MAP_CATEGORIES or w >= 192 or h >= 192:
				_place_object_sprite(obj)
			else:
				# Small standalone object — put in a virtual "floor" container
				var key := "%s:floor" % room
				if not _containers.has(key):
					_containers[key] = []
				if _containers[key].size() < 6:
					_containers[key].append(obj)


func _place_object_sprite(obj: Dictionary) -> void:
	var img_path: String = obj.get("image_path", "")
	if img_path == "":
		return
	var img := Image.new()
	if img.load(img_path) != OK:
		return
	img.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.name = "MapObj_%s" % obj.get("name", "").replace(" ", "_")
	# Limit sprite size on map to max 96px
	var max_map_size := 96.0
	var img_max: float = maxf(img.get_width(), img.get_height())
	if img_max > max_map_size:
		var s: float = max_map_size / img_max
		sprite.scale = Vector2(s, s)
	add_child(sprite)

	# Restore saved position or find one
	var saved_x: float = float(obj.get("map_pos_x", 0))
	var saved_y: float = float(obj.get("map_pos_y", 0))
	if saved_x != 0 or saved_y != 0:
		sprite.global_position = Vector2(saved_x, saved_y)
	else:
		var room: String = obj.get("location", "")
		var pos := _find_area_position(room)
		if pos == Vector2.ZERO and _spawn_areas.size() > 0:
			pos = _spawn_areas[randi() % _spawn_areas.size()].global_position
		if pos != Vector2.ZERO:
			sprite.global_position = pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		# Save position for persistence
		obj["map_pos_x"] = sprite.global_position.x
		obj["map_pos_y"] = sprite.global_position.y

	_map_object_sprites[obj.get("name", "")] = sprite


func get_container_items(room: String, container_type: String) -> Array:
	var key := "%s:%s" % [room, container_type]
	return _containers.get(key, [])


func get_room_containers(room: String) -> Array:
	var types: Array = []
	for key: String in _containers:
		if key.begins_with(room + ":") and _containers[key].size() > 0:
			var parts: PackedStringArray = key.split(":")
			if parts.size() >= 2:
				types.append(parts[1])
	return types


# ══════════════════════════════════════════════════════════════════════════════
# Tab Highlight (Baldur's Gate style)
# ══════════════════════════════════════════════════════════════════════════════

func _show_highlights() -> void:
	if _highlight_active:
		return
	_highlight_active = true
	for obj_node in get_tree().get_nodes_in_group("interactive"):
		if not obj_node is Node2D:
			continue
		var outline := _create_outline(obj_node)
		if outline:
			_highlight_outlines.append(outline)


func _hide_highlights() -> void:
	_highlight_active = false
	for outline in _highlight_outlines:
		if is_instance_valid(outline):
			outline.queue_free()
	_highlight_outlines.clear()


func _create_outline(node: Node2D) -> Node2D:
	var col_shape: CollisionShape2D = null
	for child in node.get_children():
		if child is CollisionShape2D:
			col_shape = child
			break
	if col_shape == null or col_shape.shape == null:
		return null

	var rect := Rect2()
	if col_shape.shape is RectangleShape2D:
		var rs := col_shape.shape as RectangleShape2D
		rect = Rect2(-rs.size / 2, rs.size)
	elif col_shape.shape is CircleShape2D:
		var cs := col_shape.shape as CircleShape2D
		rect = Rect2(-Vector2(cs.radius, cs.radius), Vector2(cs.radius * 2, cs.radius * 2))
	else:
		return null

	# Use a Line2D as outline rectangle
	var line := Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.7, 0.7, 0.7, 0.8)
	line.closed = true
	line.points = PackedVector2Array([
		node.global_position + rect.position,
		node.global_position + Vector2(rect.end.x, rect.position.y),
		node.global_position + rect.end,
		node.global_position + Vector2(rect.position.x, rect.end.y),
	])
	line.z_index = 100
	add_child(line)
	return line


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
			# Notify about containers in the room
			var room_containers: Array = get_room_containers(found_room)
			if room_containers.size() > 0:
				var container_names: Array = []
				for ct: String in room_containers:
					var items: Array = get_container_items(found_room, ct)
					container_names.append("%s (%d)" % [ct.capitalize(), items.size()])
				_ui.add_chat_message("", "In questa stanza: %s. Premi Spazio per cercare." % ", ".join(container_names), Color(0.5, 0.6, 0.7))

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
	var reason: String = params.get("reason", "")

	if not _npc_sprites.has(npc_name):
		return

	var target_pos := Vector2.ZERO
	var dest_label := destination

	# Check if destination is "player" or the player's name
	var pc_name: String = GameState.player_character.get("name", "").strip_edges().to_lower()
	if destination.to_lower() == "player" or destination.to_lower() == pc_name:
		if _player:
			var offset := Vector2(randf_range(-50, 50), randf_range(-50, 50)).limit_length(50)
			target_pos = _player.global_position + offset
			dest_label = GameState.player_character.get("name", "giocatore")

	# Check if destination is another NPC's name
	if target_pos == Vector2.ZERO:
		for other_name: String in _npc_sprites:
			if other_name.to_lower() == destination.to_lower() and other_name != npc_name:
				var other_node: Node2D = _npc_sprites[other_name]
				var offset := Vector2(randf_range(-50, 50), randf_range(-50, 50)).limit_length(50)
				target_pos = other_node.global_position + offset
				dest_label = other_name
				break

	# Try room/area position
	if target_pos == Vector2.ZERO:
		target_pos = _find_area_position(destination)

	# Try spawn areas
	if target_pos == Vector2.ZERO:
		for area in _spawn_areas:
			var tag: String = area.get_meta("area_tag", "")
			var area_name: String = area.get_meta("area_name", "")
			if tag == destination or area_name == destination:
				target_pos = area.global_position
				break

	# Last resort: random room
	if target_pos == Vector2.ZERO:
		if _room_areas.size() > 0:
			var random_area: Node = _room_areas[randi() % _room_areas.size()]
			target_pos = random_area.global_position
			dest_label = random_area.get_meta("area_name", "altrove")

	if target_pos == Vector2.ZERO:
		return

	var npc_node: CharacterBody2D = _npc_sprites[npc_name]
	npc_node.move_to(target_pos)

	var move_msg := "%s si sposta verso %s." % [npc_name, dest_label]
	if reason != "":
		move_msg += " (%s)" % reason
	_ui.add_chat_message("", move_msg, Color(0.6, 0.7, 0.8))

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
	
func take_photo(camera_angle: String = "Eye-Level Angle", aspect_ratio: String = "4:3", extra_details: String = "") -> void:
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
	if extra_details != "":
		scene_description += " Additional details: %s" % extra_details

	var characters: Array = []

	# Always add player character
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
		var has_pc_image: bool = pc.get("image_path", "") != ""
		characters.append({"name": pc["name"], "description": player_desc, "has_ref_image": has_pc_image,
			"sex": pc.get("sex", ""), "age": pc.get("age", ""), "race": pc.get("race", ""),
			"skin_color": pc.get("skin_color", ""), "hair_color": pc.get("hair_color", ""),
			"height": pc.get("height", ""), "body_type": pc.get("body_type", ""),
			"breast_size": pc.get("breast_size", ""), "outfit": pc.get("outfit", []),
		})

	# Only add NPCs that are within interact distance (close enough to be "in frame")
	for npc_data: Dictionary in _nearby_npcs:
		var npc_name: String = npc_data.get("name", "")
		if not _npc_sprites.has(npc_name):
			continue
		var npc_node: Node = _npc_sprites[npc_name]
		var dist: float = _player.global_position.distance_to(npc_node.global_position)
		if dist > NPC_INTERACT_DISTANCE:
			continue
		var npc_desc: String = str(npc_data.get("description", npc_data.get("physical_traits", "")))
		var outfit: Array = npc_data.get("outfit", [])
		if outfit.size() > 0:
			npc_desc += " Wearing: %s." % ", ".join(outfit)
		var has_npc_image: bool = npc_data.get("image_path", "") != ""
		characters.append({"name": npc_data.get("name", ""), "description": npc_desc, "has_ref_image": has_npc_image,
			"sex": npc_data.get("gender", ""), "age": str(npc_data.get("age", "")),
			"race": npc_data.get("race", ""), "skin_color": npc_data.get("skin_color", ""),
			"hair_color": npc_data.get("hair_color", ""), "outfit": outfit,
		})

	# 2. Build prompt via LLM
	var style: String = GameState.image_style
	if style == "custom" and GameState.custom_style != "":
		style = GameState.custom_style

	var ref_char_count := 0
	for c in characters:
		if c.get("has_ref_image", false):
			ref_char_count += 1
	var prompt: String = await LLMService.build_scene_prompt(scene_description, characters, style, ref_char_count)

	if prompt.is_empty():
		_ui.add_chat_message("Sistema", "Errore: LLM non ha generato il prompt. Controlla che LM Studio sia attivo su %s" % GameState.llm_backend_url, Color(0.8, 0.3, 0.3))
		_safe_disconnect_err(_err_cb)
		_cleanup_photo()
		return

	# Append camera angle
	prompt += "\nCamera angle: %s" % camera_angle

	# Calculate resolution from aspect ratio
	var gen_w: int = GameState.render_width
	var gen_h: int = GameState.render_height
	var ratio_parts: PackedStringArray = aspect_ratio.split(":")
	if ratio_parts.size() == 2:
		var rw: float = float(ratio_parts[0])
		var rh: float = float(ratio_parts[1])
		if rw > 0 and rh > 0:
			var long_side: int = maxi(gen_w, gen_h)
			if rw >= rh:
				gen_w = long_side
				gen_h = int(long_side * rh / rw)
			else:
				gen_h = long_side
				gen_w = int(long_side * rw / rh)
			gen_w = floori(gen_w / 64.0) * 64
			gen_h = floori(gen_h / 64.0) * 64
			gen_w = maxi(gen_w, 256)
			gen_h = maxi(gen_h, 256)

	_ui.add_chat_message("Prompt InvokeAI", "%s\n[%s — %dx%d]" % [prompt, aspect_ratio, gen_w, gen_h], Color(0.6, 0.6, 0.7))
	print("InvokeService prompt: ", prompt)

	# 2b. Build composite context images for each character
	_ui.add_chat_message("Sistema", "Preparazione immagini di contesto...", Color("4fc3f7"))
	var ref_image_names: Array = []

	for char_data: Dictionary in characters:
		if not char_data.get("has_ref_image", false):
			continue
		var char_name: String = char_data.get("name", "")
		var composite: Image = _build_character_composite(char_name)
		if composite == null or composite.is_empty():
			continue
		var png_bytes: PackedByteArray = composite.save_png_to_buffer()
		var invoke_name: String = await InvokeService.upload_image(png_bytes, "context_%s.png" % char_name.to_lower().replace(" ", "_"))
		if invoke_name != "":
			ref_image_names.append(invoke_name)
			print("InvokeService: uploaded composite for '%s' as '%s'" % [char_name, invoke_name])

	if ref_image_names.size() > 0:
		_ui.add_chat_message("Sistema", "%d immagini composite caricate." % ref_image_names.size(), Color("4fc3f7"))

	_ui.add_chat_message("Sistema", "Generando immagine su InvokeAI...", Color("4fc3f7"))

	# 3. Generate image via InvokeAI with reference images
	_last_invoke_error = ""
	var image_name: String = await InvokeService.generate_image(prompt, gen_w, gen_h, ref_image_names)

	if image_name.is_empty():
		var detail := _last_invoke_error if _last_invoke_error != "" else "Nessun dettaglio disponibile"
		_ui.add_chat_message("Sistema", "Errore generazione immagine: %s" % detail, Color(0.8, 0.3, 0.3))
		_safe_disconnect_err(_err_cb)
		_cleanup_photo()
		return

	# 4. Download and display
	var image_bytes: PackedByteArray = await InvokeService.download_image(image_name)

	_safe_disconnect_err(_err_cb)

	if image_bytes.is_empty():
		_ui.add_chat_message("Sistema", "Errore download immagine '%s' da InvokeAI." % image_name, Color(0.8, 0.3, 0.3))
		_cleanup_photo()
		return

	var image := Image.new()
	var load_err := image.load_png_from_buffer(image_bytes)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(image_bytes)
	if load_err != OK:
		load_err = image.load_webp_from_buffer(image_bytes)

	if load_err != OK:
		_ui.add_chat_message("Sistema", "Errore decodifica immagine (formato non riconosciuto).", Color(0.8, 0.3, 0.3))
		_cleanup_photo()
		return

	var texture := ImageTexture.create_from_image(image)
	_ui.add_photo_to_gallery(texture)
	_ui.show_photo(texture)
	_ui.add_chat_message("Sistema", "Foto scattata!", Color(0.3, 0.9, 0.5))

	_cleanup_photo()


func _safe_disconnect_err(cb: Callable) -> void:
	if InvokeService.generation_failed.is_connected(cb):
		InvokeService.generation_failed.disconnect(cb)


func _cleanup_photo() -> void:
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
# Containers
# ══════════════════════════════════════════════════════════════════════════════

func _open_room_containers() -> void:
	var containers: Array = get_room_containers(_current_room_name)
	if containers.is_empty():
		_ui.add_chat_message("Sistema", "Non ci sono contenitori in questa stanza.", Color(0.5, 0.5, 0.5))
		return
	if containers.size() == 1:
		_show_container(_current_room_name, containers[0])
	else:
		# Multiple containers — show in chat and let player pick
		_ui.add_chat_message("Sistema", "Contenitori disponibili:", Color("4fc3f7"))
		for ct: String in containers:
			var items: Array = get_container_items(_current_room_name, ct)
			_ui.add_chat_message("", "  %s (%d/6 oggetti)" % [ct.capitalize(), items.size()], Color.WHITE)
		_show_container(_current_room_name, containers[0])


func _show_container(room: String, container_type: String) -> void:
	var items: Array = get_container_items(room, container_type)
	var title := "%s — %s" % [container_type.capitalize(), room]
	_ui.show_container(title, items, "%s:%s" % [room, container_type])


func _on_container_item_taken(item_name: String, container_key: String) -> void:
	var pc_name: String = GameState.player_character.get("name", "")
	# Move from container to player inventory
	for i in range(GameState.objects.size()):
		if GameState.objects[i].get("name", "") == item_name:
			GameState.objects[i]["location"] = "inventory"
			GameState.objects[i]["owner"] = pc_name
			GameState.objects[i]["container"] = "none"
			break
	# Remove from cached containers
	if _containers.has(container_key):
		_containers[container_key] = _containers[container_key].filter(
			func(o: Dictionary) -> bool: return o.get("name", "") != item_name
		)
	_ui.add_chat_message("Sistema", "Hai preso: %s" % item_name, Color("2ecc71"))
	_update_inventory_ui()


# ══════════════════════════════════════════════════════════════════════════════
# Story Screen (S key)
# ══════════════════════════════════════════════════════════════════════════════

func _toggle_story_screen() -> void:
	if _story_screen == null:
		_build_story_screen()
	_story_screen_visible = not _story_screen_visible
	_story_screen.visible = _story_screen_visible
	if _story_screen_visible:
		_refresh_story_screen()


func _build_story_screen() -> void:
	_story_screen = CanvasLayer.new()
	_story_screen.layer = 60
	_story_screen.visible = false
	add_child(_story_screen)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_story_screen.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a1a2e")
	style.border_color = Color("4fc3f7")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	_story_screen.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Diario della Storia"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("4fc3f7"))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_story_log_container = VBoxContainer.new()
	_story_log_container.add_theme_constant_override("separation", 8)
	_story_log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_story_log_container)

	var close_btn := Button.new()
	close_btn.text = "Chiudi (S)"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color("2a2a4e")
	btn_style.set_corner_radius_all(6)
	btn_style.content_margin_left = 16
	btn_style.content_margin_right = 16
	btn_style.content_margin_top = 8
	btn_style.content_margin_bottom = 8
	close_btn.add_theme_stylebox_override("normal", btn_style)
	close_btn.pressed.connect(_toggle_story_screen)
	vbox.add_child(close_btn)


func _refresh_story_screen() -> void:
	for child in _story_log_container.get_children():
		child.queue_free()

	# Story intro
	if GameState.story_intro != "":
		var intro_panel := PanelContainer.new()
		var intro_style := StyleBoxFlat.new()
		intro_style.bg_color = Color("1e2a45")
		intro_style.set_corner_radius_all(6)
		intro_style.content_margin_left = 12
		intro_style.content_margin_right = 12
		intro_style.content_margin_top = 10
		intro_style.content_margin_bottom = 10
		intro_panel.add_theme_stylebox_override("panel", intro_style)
		_story_log_container.add_child(intro_panel)

		var intro_vbox := VBoxContainer.new()
		intro_vbox.add_theme_constant_override("separation", 4)
		intro_panel.add_child(intro_vbox)

		var intro_title := Label.new()
		intro_title.text = "Prologo"
		intro_title.add_theme_font_size_override("font_size", 18)
		intro_title.add_theme_color_override("font_color", Color("f39c12"))
		intro_vbox.add_child(intro_title)

		var intro_text := Label.new()
		intro_text.text = GameState.story_intro
		intro_text.add_theme_font_size_override("font_size", 15)
		intro_text.add_theme_color_override("font_color", Color.WHITE)
		intro_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro_vbox.add_child(intro_text)

	# Separator
	var sep := HSeparator.new()
	_story_log_container.add_child(sep)

	# Story log entries
	if GameState.story_log.is_empty():
		var empty := Label.new()
		empty.text = "(Nessun evento registrato)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		_story_log_container.add_child(empty)
	else:
		for entry: Dictionary in GameState.story_log:
			var entry_type: String = entry.get("type", "")
			var text: String = entry.get("text", "")
			var npc: String = entry.get("npc", "")

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_story_log_container.add_child(row)

			# Type icon
			var icon := Label.new()
			icon.add_theme_font_size_override("font_size", 14)
			icon.custom_minimum_size = Vector2(24, 0)
			match entry_type:
				"event":
					icon.text = ">"
					icon.add_theme_color_override("font_color", Color("f39c12"))
				"dialogue":
					icon.text = "~"
					icon.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
				"choice":
					icon.text = "*"
					icon.add_theme_color_override("font_color", Color("4fc3f7"))
				_:
					icon.text = "-"
					icon.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			row.add_child(icon)

			# NPC name if present
			if npc != "":
				var npc_lbl := Label.new()
				npc_lbl.text = "[%s]" % npc
				npc_lbl.add_theme_font_size_override("font_size", 13)
				npc_lbl.add_theme_color_override("font_color", Color("2ecc71"))
				npc_lbl.custom_minimum_size = Vector2(100, 0)
				row.add_child(npc_lbl)

			# Text (truncated with tooltip)
			var text_lbl := Label.new()
			text_lbl.text = text.left(200) if text.length() > 200 else text
			text_lbl.tooltip_text = text if text.length() > 200 else ""
			text_lbl.add_theme_font_size_override("font_size", 13)
			text_lbl.add_theme_color_override("font_color", Color.WHITE)
			text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(text_lbl)


# ══════════════════════════════════════════════════════════════════════════════
# Dev Console
# ══════════════════════════════════════════════════════════════════════════════

func _build_dev_console() -> void:
	_dev_console = CanvasLayer.new()
	_dev_console.layer = 200
	_dev_console.visible = false
	add_child(_dev_console)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.4
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.85)
	style.border_color = Color("4fc3f7")
	style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	_dev_console.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = " DEV CONSOLE — premi ~ per chiudere"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color("4fc3f7"))
	vbox.add_child(header)

	_dev_output = RichTextLabel.new()
	_dev_output.bbcode_enabled = true
	_dev_output.scroll_following = true
	_dev_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dev_output.add_theme_color_override("default_color", Color.WHITE)
	_dev_output.add_theme_font_size_override("normal_font_size", 13)
	vbox.add_child(_dev_output)

	_dev_input = LineEdit.new()
	_dev_input.placeholder_text = "Scrivi un comando..."
	_dev_input.add_theme_font_size_override("font_size", 14)
	_dev_input.add_theme_color_override("font_color", Color.WHITE)
	_dev_input.add_theme_color_override("caret_color", Color("4fc3f7"))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.05, 0.05, 0.1)
	input_style.border_color = Color("4fc3f7")
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	_dev_input.add_theme_stylebox_override("normal", input_style)
	_dev_input.add_theme_stylebox_override("focus", input_style)
	_dev_input.text_submitted.connect(_on_dev_command)
	vbox.add_child(_dev_input)

	_dev_print("[color=#4fc3f7]Console sviluppatore pronta. Comandi: help[/color]")


func _toggle_dev_console() -> void:
	_dev_console_visible = not _dev_console_visible
	_dev_console.visible = _dev_console_visible
	if _dev_console_visible:
		_dev_input.grab_focus()


func _dev_print(text: String) -> void:
	_dev_output.append_text(text + "\n")


func _on_dev_command(cmd: String) -> void:
	_dev_input.text = ""
	_dev_print("[color=#aaaaaa]> %s[/color]" % cmd)

	var parts: PackedStringArray = cmd.strip_edges().to_lower().split(" ", false)
	if parts.is_empty():
		return

	match parts[0]:
		"help":
			_dev_print("[color=#4fc3f7]Comandi disponibili:[/color]")
			_dev_print("  list objects — mostra oggetti e posizioni")
			_dev_print("  list npcs — mostra NPC e posizioni")
			_dev_print("  list containers — mostra contenitori")
			_dev_print("  list rooms — mostra stanze")
			_dev_print("  tp <x> <y> — teletrasporta il player")
			_dev_print("  tp <npc_name> — teletrasporta vicino a un NPC")
			_dev_print("  spawn <item_name> — crea oggetto nell'inventario")
			_dev_print("  god — mostra tutte le info di debug")
		"list":
			if parts.size() > 1:
				match parts[1]:
					"objects":
						_dev_cmd_list_objects()
					"npcs":
						_dev_cmd_list_npcs()
					"containers":
						_dev_cmd_list_containers()
					"rooms":
						_dev_cmd_list_rooms()
					_:
						_dev_print("[color=#e74c3c]Sconosciuto: list %s[/color]" % parts[1])
			else:
				_dev_print("[color=#e74c3c]Uso: list objects|npcs|containers|rooms[/color]")
		"tp":
			if parts.size() >= 3:
				var tx: float = float(parts[1])
				var ty: float = float(parts[2])
				if _player:
					_player.global_position = Vector2(tx, ty)
					_dev_print("Teletrasportato a %.0f, %.0f" % [tx, ty])
			elif parts.size() == 2:
				var target_name: String = cmd.strip_edges().substr(3).strip_edges()
				for npc_key: String in _npc_sprites:
					if npc_key.to_lower().contains(target_name.to_lower()):
						var npc_node: Node2D = _npc_sprites[npc_key]
						if _player:
							_player.global_position = npc_node.global_position + Vector2(50, 0)
							_dev_print("Teletrasportato vicino a %s" % npc_key)
						break
		"spawn":
			if parts.size() >= 2:
				var item_name: String = cmd.strip_edges().substr(6).strip_edges()
				var pc_name: String = GameState.player_character.get("name", "")
				GameState.add_object({"name": item_name, "description": "Spawned via console", "category": "tools", "location": "inventory", "owner": pc_name})
				_dev_print("[color=#2ecc71]Creato: %s[/color]" % item_name)
		"god":
			_dev_print("Player pos: %.0f, %.0f" % [_player.global_position.x, _player.global_position.y] if _player else "No player")
			_dev_print("Room: %s" % _current_room_name)
			_dev_print("NPCs: %d | Objects: %d" % [GameState.npcs.size(), GameState.objects.size()])
			_dev_print("Containers: %d" % _containers.size())
		_:
			_dev_print("[color=#e74c3c]Comando sconosciuto: %s. Scrivi 'help'.[/color]" % parts[0])


func _dev_cmd_list_objects() -> void:
	_dev_print("[color=#f39c12]═══ OGGETTI (%d) ═══[/color]" % GameState.objects.size())
	for obj: Dictionary in GameState.objects:
		var obj_name: String = obj.get("name", "???")
		var location: String = obj.get("location", "?")
		var container: String = obj.get("container", "none")
		var obj_owner: String = obj.get("owner", "")
		var pos_info := ""
		if location == "inventory":
			pos_info = "inventario di %s" % obj_owner
		elif location == "equipped":
			pos_info = "equipaggiato da %s" % obj_owner
		elif container != "none" and container != "":
			pos_info = "%s in %s" % [container, location]
		else:
			var mx: float = float(obj.get("map_pos_x", 0))
			var my: float = float(obj.get("map_pos_y", 0))
			if mx != 0 or my != 0:
				pos_info = "%s (%.0f, %.0f)" % [location, mx, my]
			else:
				pos_info = location
		_dev_print("  %s — %s" % [obj_name, pos_info])
	# Show labels on map
	_show_object_labels_on_map()


func _dev_cmd_list_npcs() -> void:
	_dev_print("[color=#3498db]═══ NPC (%d) ═══[/color]" % GameState.npcs.size())
	for npc: Dictionary in GameState.npcs:
		var npc_name: String = npc.get("name", "???")
		var mood: String = npc.get("mood", "?")
		var pos_str := "?"
		if _npc_sprites.has(npc_name):
			var node: Node2D = _npc_sprites[npc_name]
			pos_str = "%.0f, %.0f" % [node.global_position.x, node.global_position.y]
		_dev_print("  %s — umore: %s — pos: %s" % [npc_name, mood, pos_str])


func _dev_cmd_list_containers() -> void:
	_dev_print("[color=#9b59b6]═══ CONTENITORI (%d) ═══[/color]" % _containers.size())
	for key: String in _containers:
		var items: Array = _containers[key]
		var names: Array = []
		for it: Dictionary in items:
			names.append(it.get("name", "?"))
		_dev_print("  %s — %d/6: %s" % [key, items.size(), ", ".join(names)])


func _dev_cmd_list_rooms() -> void:
	_dev_print("[color=#2ecc71]═══ STANZE ═══[/color]")
	for area in _room_areas:
		var room_name: String = area.get_meta("area_name", area.name)
		var tag: String = area.get_meta("area_tag", "")
		_dev_print("  %s [%s] — pos: %.0f, %.0f" % [room_name, tag, area.global_position.x, area.global_position.y])
	for area in get_tree().get_nodes_in_group("hallway"):
		var hall_name: String = area.get_meta("area_name", area.name)
		var tag: String = area.get_meta("area_tag", "")
		_dev_print("  %s [%s] — pos: %.0f, %.0f" % [hall_name, tag, area.global_position.x, area.global_position.y])


func _show_object_labels_on_map() -> void:
	for lbl in _dev_temp_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_dev_temp_labels.clear()

	var label_offset := 0
	for obj: Dictionary in GameState.objects:
		var obj_name: String = obj.get("name", "")
		if obj_name == "":
			continue
		var location: String = obj.get("location", "")
		if location == "inventory" or location == "equipped":
			continue

		var pos := Vector2.ZERO
		var mx: float = float(obj.get("map_pos_x", 0))
		var my: float = float(obj.get("map_pos_y", 0))
		if mx != 0 or my != 0:
			pos = Vector2(mx, my)
		else:
			# Try exact match
			pos = _find_area_position(location)
			# Fuzzy match: search room areas by partial name
			if pos == Vector2.ZERO:
				pos = _find_area_fuzzy(location)
			# Try matching interactive objects (cabinet, table, etc.)
			if pos == Vector2.ZERO:
				var container_type: String = obj.get("container", "none")
				if container_type != "none" and container_type != "":
					for iobj in get_tree().get_nodes_in_group("interactive"):
						if iobj.name.to_lower().contains(container_type):
							pos = iobj.global_position
							break

		if pos == Vector2.ZERO:
			continue

		var label := Label.new()
		label.text = obj_name
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("f39c12"))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.position = pos + Vector2(-40, -20 + label_offset * 14)
		label.z_index = 200
		add_child(label)
		_dev_temp_labels.append(label)
		label_offset += 1

	get_tree().create_timer(5.0).timeout.connect(_clear_temp_labels)


func _find_area_fuzzy(search: String) -> Vector2:
	var search_lower := search.to_lower()
	var all_areas: Array = []
	all_areas.append_array(_room_areas)
	all_areas.append_array(get_tree().get_nodes_in_group("hallway"))
	all_areas.append_array(_spawn_areas)
	for area in all_areas:
		var area_name: String = area.get_meta("area_name", area.name).to_lower()
		var area_tag: String = area.get_meta("area_tag", "").to_lower()
		var area_desc: String = area.get_meta("area_description", "").to_lower()
		if area_name.contains(search_lower) or search_lower.contains(area_name):
			return area.global_position
		if area_tag != "" and (area_tag.contains(search_lower) or search_lower.contains(area_tag)):
			return area.global_position
		if area_desc != "" and area_desc.contains(search_lower):
			return area.global_position
	return Vector2.ZERO


func _clear_temp_labels() -> void:
	for lbl in _dev_temp_labels:
		if is_instance_valid(lbl):
			lbl.queue_free()
	_dev_temp_labels.clear()


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _build_character_composite(char_name: String) -> Image:
	var images: Array = []

	var is_player: bool = char_name == GameState.player_character.get("name", "")
	var char_data: Dictionary = GameState.player_character if is_player else GameState.get_npc(char_name)

	# Face image first
	var face_path: String = char_data.get("image_path", "")
	if face_path != "":
		var face_img := Image.new()
		if face_img.load(face_path) == OK:
			face_img.convert(Image.FORMAT_RGBA8)
			images.append(face_img)

	# Equipped item images
	for slot_key in ["head", "chest", "legs", "weapon", "shield", "accessory"]:
		var item_name: String = char_data.get("slot_%s" % slot_key, "")
		if item_name == "":
			continue
		for obj in GameState.objects:
			if obj.get("name", "") == item_name and obj.get("image_path", "") != "":
				var item_img := Image.new()
				if item_img.load(obj["image_path"]) == OK:
					item_img.convert(Image.FORMAT_RGBA8)
					images.append(item_img)
				break

	if images.is_empty():
		return null

	# Convert all to RGBA8 and scale down if needed
	var max_side := 1200
	for i in range(images.size()):
		var img: Image = images[i]
		var sf: float = minf(float(max_side) / img.get_width(), float(max_side) / img.get_height())
		if sf < 1.0:
			img.resize(maxi(1, int(img.get_width() * sf)), maxi(1, int(img.get_height() * sf)))

	var count: int = images.size()
	if count == 1:
		var img: Image = images[0]
		var cw: int = img.get_width() + 20
		var ch: int = img.get_height() + 20
		var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		canvas.fill(Color.WHITE)
		_composite_blit(canvas, img, 10, 10)
		return canvas

	# Layout: face on the left, items stacked on the right (like the reference image)
	var face: Image = images[0]
	var right_items: Array = images.slice(1)
	var right_count: int = right_items.size()
	var right_cols: int = 1 if right_count <= 2 else 2
	var right_rows_count: int = ceili(float(right_count) / right_cols)

	# Compute right side cell sizes
	var col_widths: Array = []
	var row_heights: Array = []
	for _c in range(right_cols):
		col_widths.append(0)
	for _r in range(right_rows_count):
		row_heights.append(0)
	for idx in range(right_count):
		var ri: Image = right_items[idx]
		var c: int = idx % right_cols
		var r: int = idx / right_cols
		if ri.get_width() > col_widths[c]:
			col_widths[c] = ri.get_width()
		if ri.get_height() > row_heights[r]:
			row_heights[r] = ri.get_height()

	var right_w: int = 0
	for w: int in col_widths:
		right_w += w
	right_w += (right_cols - 1) * 10

	var right_h: int = 0
	for h: int in row_heights:
		right_h += h
	right_h += (right_rows_count - 1) * 10

	var gap := 15
	var pad := 10
	var canvas_w: int = face.get_width() + gap + right_w + pad * 2
	var canvas_h: int = maxi(face.get_height(), right_h) + pad * 2

	# Shrink if canvas exceeds 1200x1200
	var canvas_scale: float = minf(1200.0 / canvas_w, 1200.0 / canvas_h)
	if canvas_scale < 1.0:
		canvas_w = int(canvas_w * canvas_scale)
		canvas_h = int(canvas_h * canvas_scale)
		face.resize(maxi(1, int(face.get_width() * canvas_scale)), maxi(1, int(face.get_height() * canvas_scale)))
		for i in range(right_count):
			var ri: Image = right_items[i]
			ri.resize(maxi(1, int(ri.get_width() * canvas_scale)), maxi(1, int(ri.get_height() * canvas_scale)))
		for c in range(right_cols):
			col_widths[c] = int(col_widths[c] * canvas_scale)
		for r in range(right_rows_count):
			row_heights[r] = int(row_heights[r] * canvas_scale)
		right_w = int(right_w * canvas_scale)
		right_h = int(right_h * canvas_scale)

	var canvas := Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.WHITE)

	# Face on the left, vertically centered
	var face_y: int = (canvas_h - face.get_height()) / 2
	_composite_blit(canvas, face, pad, maxi(pad, face_y))

	# Right items
	var rx_start: int = pad + face.get_width() + gap
	var ry_start: int = (canvas_h - right_h) / 2
	var cur_y: int = maxi(pad, ry_start)
	for r in range(right_rows_count):
		var cur_x: int = rx_start
		for c in range(right_cols):
			var idx: int = r * right_cols + c
			if idx >= right_count:
				break
			var ri: Image = right_items[idx]
			var cx: int = cur_x + (col_widths[c] - ri.get_width()) / 2
			var cy: int = cur_y + (row_heights[r] - ri.get_height()) / 2
			_composite_blit(canvas, ri, cx, cy)
			cur_x += col_widths[c] + int(10 * (canvas_scale if canvas_scale < 1.0 else 1.0))
		cur_y += row_heights[r] + int(10 * (canvas_scale if canvas_scale < 1.0 else 1.0))

	print("InvokeService: composite %d images → %dx%d canvas" % [count, canvas_w, canvas_h])
	return canvas


func _composite_blit(canvas: Image, src: Image, x: int, y: int) -> void:
	for py in range(src.get_height()):
		var dy: int = y + py
		if dy < 0 or dy >= canvas.get_height():
			continue
		for px in range(src.get_width()):
			var dx: int = x + px
			if dx < 0 or dx >= canvas.get_width():
				continue
			var sc: Color = src.get_pixel(px, py)
			if sc.a < 0.01:
				continue
			if sc.a >= 0.99:
				canvas.set_pixel(dx, dy, sc)
			else:
				var bg: Color = canvas.get_pixel(dx, dy)
				canvas.set_pixel(dx, dy, Color(
					bg.r * (1.0 - sc.a) + sc.r * sc.a,
					bg.g * (1.0 - sc.a) + sc.g * sc.a,
					bg.b * (1.0 - sc.a) + sc.b * sc.a,
					1.0
				))


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
# Character Sheet
# ══════════════════════════════════════════════════════════════════════════════

func _setup_character_sheet() -> void:
	var cs_scene: PackedScene = load("res://scenes/game/CharacterSheet.tscn")
	_character_sheet = cs_scene.instantiate()
	_character_sheet.name = "CharacterSheet"
	add_child(_character_sheet)
	_character_sheet.visible = false
	_character_sheet.closed.connect(_on_character_sheet_closed)
	_character_sheet.outfit_changed.connect(_on_outfit_changed)
	_ui.character_sheet_requested.connect(_toggle_character_sheet)


func _toggle_character_sheet() -> void:
	if _pause_visible:
		return
	if _character_sheet.visible:
		_character_sheet.hide_sheet()
	else:
		_character_sheet.show_sheet()


func _show_npc_sheet(npc_name: String) -> void:
	if _character_sheet:
		_character_sheet.show_npc_sheet(npc_name)


func _on_character_sheet_closed() -> void:
	_update_inventory_ui()


func _on_outfit_changed(outfit_description: String) -> void:
	var pc: Dictionary = GameState.player_character
	var pc_name: String = pc.get("name", "")
	if pc_name != "":
		# Update player character outfit in GameState for photo prompts
		var outfit: Array = pc.get("outfit", [])
		if outfit.is_empty() and outfit_description == "":
			return
		# Outfit array is already synced by CharacterSheet, just refresh NPC sprites
		for npc_name: String in _npc_sprites:
			_refresh_npc_sprite(npc_name)
	_update_inventory_ui()


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


func _sync_state_before_save() -> void:
	# Save player position
	if _player:
		GameState.player_position = _player.global_position
	# Save NPC positions
	for npc_name_key: String in _npc_sprites:
		var npc_node: Node2D = _npc_sprites[npc_name_key]
		var npc_data: Dictionary = GameState.get_npc(npc_name_key)
		if not npc_data.is_empty():
			npc_data["saved_position_x"] = npc_node.global_position.x
			npc_data["saved_position_y"] = npc_node.global_position.y
			GameState.add_npc(npc_data)
	# Save map object positions
	for obj_name: String in _map_object_sprites:
		var sprite: Node2D = _map_object_sprites[obj_name]
		for i in range(GameState.objects.size()):
			if GameState.objects[i].get("name", "") == obj_name:
				GameState.objects[i]["map_pos_x"] = sprite.global_position.x
				GameState.objects[i]["map_pos_y"] = sprite.global_position.y
				break
	# Save chat history from UI
	if _ui and _ui.has_method("get_chat_history"):
		GameState.chat_history = _ui.get_chat_history()
	# Save gallery image paths
	if _ui and _ui.has_method("get_gallery_paths"):
		GameState.gallery_images = _ui.get_gallery_paths()


func _on_pause_save() -> void:
	var slot := _pause_save_name_edit.text.strip_edges()
	if slot.is_empty():
		_pause_status_label.add_theme_color_override("font_color", Color("e74c3c"))
		_pause_status_label.text = "Inserisci un nome per il salvataggio."
		return
	_sync_state_before_save()
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
	_sync_state_before_save()
	GameState.call("save_game", "auto")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

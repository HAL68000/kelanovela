extends Control

## World builder screen — fourth and final step of the New Game flow.
## Calls LLM to generate NPCs, objects, and prepares the world.

const BG_COLOR := Color("#1a1a2e")
const SURFACE_COLOR := Color("#1e2a45")
const ACCENT_COLOR := Color("#4fc3f7")
const TEXT_COLOR := Color.WHITE
const SUBTITLE_COLOR := Color(0.7, 0.7, 0.7, 1.0)
const BUTTON_BG := Color("#2a2a4e")
const BUTTON_HOVER := Color("#3a3a6e")
const GREEN_COLOR := Color("#2ecc71")
const RED_COLOR := Color("#e74c3c")

# UI references
var step_labels: Array = []       # Array[Label]
var step_checks: Array = []       # Array[CheckBox]
var npc_list_container: VBoxContainer
var object_list_container: VBoxContainer
var start_btn: Button
var loading_label: Label
var spinner_rect: ColorRect
var back_btn: Button

# State
var step_completed := [false, false, false]
var _spinner_angle := 0.0
var _spinner_active := false


func _ready() -> void:
	_build_ui()


func _process(delta: float) -> void:
	if _spinner_active and is_instance_valid(spinner_rect):
		_spinner_angle += delta * 360.0
		if _spinner_angle >= 360.0:
			_spinner_angle -= 360.0
		spinner_rect.rotation_degrees = _spinner_angle


# ══════════════════════════════════════════════════════════════════════════════
# UI Construction
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main scroll
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.anchor_left = 0.08
	scroll.anchor_right = 0.92
	scroll.anchor_top = 0.02
	scroll.anchor_bottom = 0.98
	add_child(scroll)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Costruzione del Mondo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	main_vbox.add_child(title)

	main_vbox.add_child(_make_separator())

	# Progress section
	var progress_panel := PanelContainer.new()
	var pp_style := StyleBoxFlat.new()
	pp_style.bg_color = SURFACE_COLOR
	pp_style.corner_radius_top_left = 8
	pp_style.corner_radius_top_right = 8
	pp_style.corner_radius_bottom_left = 8
	pp_style.corner_radius_bottom_right = 8
	pp_style.content_margin_left = 20
	pp_style.content_margin_right = 20
	pp_style.content_margin_top = 16
	pp_style.content_margin_bottom = 16
	progress_panel.add_theme_stylebox_override("panel", pp_style)
	main_vbox.add_child(progress_panel)

	var progress_vbox := VBoxContainer.new()
	progress_vbox.add_theme_constant_override("separation", 12)
	progress_panel.add_child(progress_vbox)

	var progress_title := Label.new()
	progress_title.text = "Progressi generazione"
	progress_title.add_theme_font_size_override("font_size", 22)
	progress_title.add_theme_color_override("font_color", ACCENT_COLOR)
	progress_vbox.add_child(progress_title)

	var step_names := [
		"Generazione personaggi NPC...",
		"Generazione oggetti...",
		"Preparazione mappa...",
	]

	for i in range(step_names.size()):
		var step_hbox := HBoxContainer.new()
		step_hbox.add_theme_constant_override("separation", 12)
		progress_vbox.add_child(step_hbox)

		var check := CheckBox.new()
		check.disabled = true
		check.add_theme_color_override("font_color", TEXT_COLOR)
		step_hbox.add_child(check)
		step_checks.append(check)

		var step_lbl := Label.new()
		step_lbl.text = step_names[i]
		step_lbl.add_theme_font_size_override("font_size", 18)
		step_lbl.add_theme_color_override("font_color", SUBTITLE_COLOR)
		step_hbox.add_child(step_lbl)
		step_labels.append(step_lbl)

	# Loading indicator
	var loading_hbox := HBoxContainer.new()
	loading_hbox.add_theme_constant_override("separation", 12)
	loading_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	progress_vbox.add_child(loading_hbox)

	spinner_rect = ColorRect.new()
	spinner_rect.color = ACCENT_COLOR
	spinner_rect.custom_minimum_size = Vector2(20, 20)
	spinner_rect.size = Vector2(20, 20)
	spinner_rect.pivot_offset = Vector2(10, 10)
	spinner_rect.visible = false
	loading_hbox.add_child(spinner_rect)

	loading_label = Label.new()
	loading_label.text = "In attesa..."
	loading_label.add_theme_font_size_override("font_size", 16)
	loading_label.add_theme_color_override("font_color", ACCENT_COLOR)
	loading_label.visible = false
	loading_hbox.add_child(loading_label)

	main_vbox.add_child(_make_separator())

	# NPC list section
	main_vbox.add_child(_make_field_label("Personaggi NPC generati"))

	npc_list_container = VBoxContainer.new()
	npc_list_container.add_theme_constant_override("separation", 8)
	main_vbox.add_child(npc_list_container)

	var no_npc_label := Label.new()
	no_npc_label.name = "NoNPCLabel"
	no_npc_label.text = "Nessun NPC generato ancora."
	no_npc_label.add_theme_font_size_override("font_size", 16)
	no_npc_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	npc_list_container.add_child(no_npc_label)

	# Object list section
	main_vbox.add_child(_make_separator())
	main_vbox.add_child(_make_field_label("Oggetti generati"))

	object_list_container = VBoxContainer.new()
	object_list_container.add_theme_constant_override("separation", 8)
	main_vbox.add_child(object_list_container)

	var no_obj_label := Label.new()
	no_obj_label.name = "NoObjLabel"
	no_obj_label.text = "Nessun oggetto generato ancora."
	no_obj_label.add_theme_font_size_override("font_size", 16)
	no_obj_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	object_list_container.add_child(no_obj_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	main_vbox.add_child(spacer)

	# Navigation
	var nav_hbox := HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(nav_hbox)

	back_btn = Button.new()
	back_btn.text = "← Indietro"
	back_btn.custom_minimum_size = Vector2(200, 50)
	_style_button(back_btn)
	back_btn.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(back_btn)

	start_btn = Button.new()
	start_btn.text = "Inizia Avventura →"
	start_btn.custom_minimum_size = Vector2(260, 50)
	_style_button(start_btn, true)
	start_btn.disabled = true
	start_btn.pressed.connect(_on_start_adventure)
	nav_hbox.add_child(start_btn)

	# Start generation automatically
	_start_generation()


# ══════════════════════════════════════════════════════════════════════════════
# Generation pipeline
# ══════════════════════════════════════════════════════════════════════════════

func _start_generation() -> void:
	_set_loading(true, "Generazione personaggi NPC...")
	back_btn.disabled = true

	var llm := get_node_or_null("/root/LLMService")
	if llm == null:
		_set_loading(false)
		_show_error("LLMService non disponibile. Controlla le impostazioni.")
		back_btn.disabled = false
		return

	# Step 1: Generate NPCs
	await _generate_npcs(llm)

	# Step 2: Generate objects
	_set_loading(true, "Generazione oggetti...")
	await _generate_objects(llm)

	# Step 3: Finalize
	_set_loading(true, "Preparazione mappa...")
	await _finalize_world(llm)

	_set_loading(false)
	back_btn.disabled = false
	_check_all_complete()


func _generate_npcs(llm: Node) -> void:
	_update_step(0, "in corso")

	var context := _build_context()
	var prompt := (
		"Genera un array JSON di massimo 6 personaggi NPC per una storia di tipo '%s'. "
		+ "Contesto: %s. "
		+ "Ogni personaggio deve avere: name (string), age (int), role (string), "
		+ "gender (string: Maschile/Femminile), race (string), hair_color (string), skin_color (string), "
		+ "personality (string: detailed psychological profile including temperament and behavior), "
		+ "strengths (string: what they're good at, virtues), "
		+ "weaknesses (string: flaws, fears, vulnerabilities, things that can be exploited). "
		+ "Rispondi SOLO con il JSON array, senza altro testo."
	) % [GameState.story_type, context]

	if llm.has_method("generate_npcs"):
		var result = await llm.generate_npcs(prompt)
		_process_npc_result(result)
	elif llm.has_method("chat"):
		var messages := [{"role": "user", "content": prompt}]
		var result = await llm.chat(messages)
		_process_npc_result(result)
	else:
		_create_placeholder_npcs()

	_update_step(0, "completato")


func _process_npc_result(result) -> void:
	var npcs_data: Array = []

	if result is Array:
		npcs_data = result
	elif result is String and result != "":
		# Extract JSON from response
		var json_str := _extract_json_array(result)
		var json := JSON.new()
		var err := json.parse(json_str)
		if err == OK and json.data is Array:
			npcs_data = json.data

	# Filter out any NPC with the same name as the player character
	var pc_name: String = GameState.player_character.get("name", "").strip_edges().to_lower()
	if pc_name != "":
		npcs_data = npcs_data.filter(func(npc: Dictionary) -> bool:
			return npc.get("name", "").strip_edges().to_lower() != pc_name
		)

	if npcs_data.size() == 0:
		_create_placeholder_npcs()
		return

	GameState.npcs = npcs_data
	_populate_npc_list()


func _create_placeholder_npcs() -> void:
	# Create some default NPCs based on story type so the flow can proceed
	GameState.npcs = [
		{ "name": "NPC Sconosciuto 1", "age": 30, "role": "Alleato", "gender": "Maschile", "race": "Umano", "hair_color": "Nero", "skin_color": "Chiara" },
		{ "name": "NPC Sconosciuto 2", "age": 25, "role": "Mercante", "gender": "Femminile", "race": "Umano", "hair_color": "Biondo", "skin_color": "Chiara" },
	]
	_populate_npc_list()


func _generate_objects(llm: Node) -> void:
	_update_step(1, "in corso")

	var context := _build_context()
	var prompt := (
		"Genera un array JSON di 5-10 oggetti per una storia di tipo '%s'. "
		+ "Contesto: %s. "
		+ "Ogni oggetto deve avere: name (string), description (string), category (string: clothes|tools|weapons|medicine|food|jewelry|scrolls|machinery), "
		+ "location (string: room name), image_width (int: 64|128|192|256), image_height (int: 64|128|192|256), "
		+ "container (string: 'cabinet'|'basket'|'table'|'none'). "
		+ "Scegli la dimensione in base al tipo: piccoli (chiavi, anelli, gioielli) = 64x64, medi (spade, libri, vestiti) = 128x128, grandi (armature, statue) = 192x192 o 256x256. "
		+ "Oggetti piccoli e medi (vestiti, utensili, cibo, medicinali, gioielli, pergamene) vanno in container='cabinet'|'basket'|'table'. "
		+ "Oggetti grandi (>128px, macchinari, statue, armature da esposizione) vanno con container='none' e saranno visibili sulla mappa. "
		+ "Rispondi SOLO con il JSON array, senza altro testo."
	) % [GameState.story_type, context]

	if llm.has_method("generate_objects"):
		var result = await llm.generate_objects(prompt)
		_process_object_result(result)
	elif llm.has_method("chat"):
		var messages := [{"role": "user", "content": prompt}]
		var result = await llm.chat(messages)
		_process_object_result(result)
	else:
		_create_placeholder_objects()

	_update_step(1, "completato")


func _process_object_result(result) -> void:
	var objects_data: Array = []

	if result is Array:
		objects_data = result
	elif result is String and result != "":
		var json_str := _extract_json_array(result)
		var json := JSON.new()
		var err := json.parse(json_str)
		if err == OK and json.data is Array:
			objects_data = json.data

	if objects_data.size() == 0:
		_create_placeholder_objects()
		return

	GameState.objects = objects_data
	_populate_object_list()


func _create_placeholder_objects() -> void:
	GameState.objects = [
		{ "name": "Oggetto misterioso", "description": "Un oggetto dal significato sconosciuto.", "location": "Inizio" },
		{ "name": "Chiave arrugginita", "description": "Una vecchia chiave che potrebbe aprire qualcosa.", "location": "Inizio" },
	]
	_populate_object_list()


func _finalize_world(llm: Node) -> void:
	_update_step(2, "in corso")

	# Auto-generate images for all objects
	var invoke := get_node_or_null("/root/InvokeService")
	if invoke:
		var invoke_ok: bool = await invoke.test_connection()
		if invoke_ok:
			_set_loading(true, "Generazione immagini oggetti...")
			for i in range(GameState.objects.size()):
				var obj: Dictionary = GameState.objects[i]
				if obj.get("image_path", "") != "":
					continue
				var w: int = int(obj.get("image_width", 64))
				var h: int = int(obj.get("image_height", 64))
				_set_loading(true, "Immagine %d/%d: %s..." % [i + 1, GameState.objects.size(), obj.get("name", "?")])
				await _generate_object_image(i, w, h)
			_set_loading(false)
			_populate_object_list()

	# Generate story introduction
	_set_loading(true, "Generazione introduzione storia...")
	if llm and llm.has_method("chat"):
		var intro_prompt := (
			"Scrivi un breve preambolo narrativo (massimo 300 caratteri) per questa storia.\n"
			+ "Tipo: %s\n" % GameState.story_type
			+ "Ambientazione: %s\n" % GameState.story_preamble
			+ "Protagonista: %s\n" % GameState.player_character.get("name", "?")
			+ "Obiettivo: %s\n" % GameState.objective
			+ "Scrivi SOLO il testo narrativo, senza virgolette o formattazione."
		)
		var intro_messages := [{"role": "user", "content": intro_prompt}]
		var intro_result: String = await llm.chat(intro_messages, "You are a narrative writer. Write concise, atmospheric introductions.", 0.7, 500)
		if intro_result != "":
			GameState.story_intro = intro_result.left(300)
	_set_loading(false)

	GameState.game_started = true
	GameState.current_scene = "game_world"
	_update_step(2, "completato")


# ══════════════════════════════════════════════════════════════════════════════
# Populate lists
# ══════════════════════════════════════════════════════════════════════════════

func _populate_npc_list() -> void:
	# Clear existing
	for child in npc_list_container.get_children():
		child.queue_free()

	for i in range(GameState.npcs.size()):
		var npc: Dictionary = GameState.npcs[i]
		var npc_panel := PanelContainer.new()
		var npc_style := StyleBoxFlat.new()
		npc_style.bg_color = SURFACE_COLOR
		npc_style.corner_radius_top_left = 6
		npc_style.corner_radius_top_right = 6
		npc_style.corner_radius_bottom_left = 6
		npc_style.corner_radius_bottom_right = 6
		npc_style.content_margin_left = 12
		npc_style.content_margin_right = 12
		npc_style.content_margin_top = 8
		npc_style.content_margin_bottom = 8
		npc_panel.add_theme_stylebox_override("panel", npc_style)
		npc_list_container.add_child(npc_panel)

		var npc_hbox := HBoxContainer.new()
		npc_hbox.add_theme_constant_override("separation", 16)
		npc_panel.add_child(npc_hbox)

		var info_label := Label.new()
		info_label.text = "%s — Età: %s — Ruolo: %s" % [
			npc.get("name", "???"),
			str(npc.get("age", "?")),
			npc.get("role", "?"),
		]
		info_label.add_theme_font_size_override("font_size", 16)
		info_label.add_theme_color_override("font_color", TEXT_COLOR)
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		npc_hbox.add_child(info_label)

		var edit_btn := Button.new()
		edit_btn.text = "Modifica"
		edit_btn.custom_minimum_size = Vector2(100, 32)
		_style_button(edit_btn)
		edit_btn.pressed.connect(_on_edit_npc.bind(i))
		npc_hbox.add_child(edit_btn)


func _populate_object_list() -> void:
	for child in object_list_container.get_children():
		child.queue_free()

	for i in range(GameState.objects.size()):
		var obj: Dictionary = GameState.objects[i]
		var obj_panel := PanelContainer.new()
		var obj_style := StyleBoxFlat.new()
		obj_style.bg_color = SURFACE_COLOR
		obj_style.set_corner_radius_all(6)
		obj_style.content_margin_left = 12
		obj_style.content_margin_right = 12
		obj_style.content_margin_top = 8
		obj_style.content_margin_bottom = 8
		obj_panel.add_theme_stylebox_override("panel", obj_style)
		object_list_container.add_child(obj_panel)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		obj_panel.add_child(hbox)

		# Thumbnail if image exists
		var img_path: String = obj.get("image_path", "")
		if img_path != "":
			var thumb := TextureRect.new()
			thumb.custom_minimum_size = Vector2(40, 40)
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var img := Image.new()
			if img.load(img_path) == OK:
				thumb.texture = ImageTexture.create_from_image(img)
			hbox.add_child(thumb)

		# Info
		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)

		var name_lbl := Label.new()
		name_lbl.text = obj.get("name", "???")
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", TEXT_COLOR)
		info_vbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		var desc_text: String = obj.get("description", "")
		var cat_text: String = obj.get("category", "")
		var size_text := "%dx%d" % [int(obj.get("image_width", 64)), int(obj.get("image_height", 64))]
		desc_lbl.text = "%s [%s] %s" % [desc_text, cat_text, size_text] if cat_text != "" else "%s %s" % [desc_text, size_text]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", SUBTITLE_COLOR)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(desc_lbl)

		# Size spinboxes
		var size_row := HBoxContainer.new()
		size_row.add_theme_constant_override("separation", 4)
		hbox.add_child(size_row)

		var w_spin := SpinBox.new()
		w_spin.min_value = 64
		w_spin.max_value = 256
		w_spin.step = 64
		w_spin.value = int(obj.get("image_width", 64))
		w_spin.custom_minimum_size = Vector2(70, 28)
		w_spin.tooltip_text = "Larghezza"
		size_row.add_child(w_spin)

		var x_lbl := Label.new()
		x_lbl.text = "x"
		x_lbl.add_theme_font_size_override("font_size", 12)
		x_lbl.add_theme_color_override("font_color", SUBTITLE_COLOR)
		size_row.add_child(x_lbl)

		var h_spin := SpinBox.new()
		h_spin.min_value = 64
		h_spin.max_value = 256
		h_spin.step = 64
		h_spin.value = int(obj.get("image_height", 64))
		h_spin.custom_minimum_size = Vector2(70, 28)
		h_spin.tooltip_text = "Altezza"
		size_row.add_child(h_spin)

		# Generate button
		var gen_btn := Button.new()
		gen_btn.text = "Genera" if img_path == "" else "Rigenera"
		gen_btn.custom_minimum_size = Vector2(90, 36)
		_style_button(gen_btn)
		gen_btn.add_theme_color_override("font_color", ACCENT_COLOR)
		var obj_idx: int = i
		var ws: SpinBox = w_spin
		var hs: SpinBox = h_spin
		gen_btn.pressed.connect(func() -> void:
			await _generate_object_image(obj_idx, int(ws.value), int(hs.value))
		)
		hbox.add_child(gen_btn)

	# "Genera Tutte" button
	var gen_all_btn := Button.new()
	gen_all_btn.text = "Genera Tutte le Immagini"
	gen_all_btn.custom_minimum_size = Vector2(260, 40)
	_style_button(gen_all_btn, true)
	gen_all_btn.pressed.connect(_generate_all_object_images)
	object_list_container.add_child(gen_all_btn)


# ══════════════════════════════════════════════════════════════════════════════
# Object image generation
# ══════════════════════════════════════════════════════════════════════════════

func _generate_object_image(obj_index: int, width: int, height: int) -> void:
	if obj_index < 0 or obj_index >= GameState.objects.size():
		return
	var obj: Dictionary = GameState.objects[obj_index]
	var obj_name: String = obj.get("name", "")
	var desc: String = obj.get("description", obj_name)
	var cat: String = obj.get("category", "")

	var style: String = GameState.image_style
	if style == "custom" and GameState.custom_style != "":
		style = GameState.custom_style

	var prompt := "%s, %s, %s style, white background, game item icon, centered, simple, no text" % [obj_name, desc, style]
	if cat != "":
		prompt += ", %s" % cat

	_set_loading(true, "Generando immagine: %s..." % obj_name)

	var invoke := get_node_or_null("/root/InvokeService")
	if invoke == null:
		_set_loading(false)
		return

	var image_name: String = await invoke.generate_image(prompt, width, height)
	if image_name.is_empty():
		_set_loading(false)
		return

	var image_bytes: PackedByteArray = await invoke.download_image(image_name)
	_set_loading(false)

	if image_bytes.is_empty():
		return

	var safe_name := obj_name.to_lower().replace(" ", "_").replace("/", "_")
	var save_path := "user://obj_%s.png" % safe_name
	var img := Image.new()
	if img.load_png_from_buffer(image_bytes) != OK:
		if img.load_jpg_from_buffer(image_bytes) != OK:
			img.load_webp_from_buffer(image_bytes)
	if img.is_empty():
		return

	_remove_white_background(img)
	img.save_png(save_path)
	GameState.objects[obj_index]["image_path"] = ProjectSettings.globalize_path(save_path)
	GameState.objects[obj_index]["image_width"] = width
	GameState.objects[obj_index]["image_height"] = height
	_populate_object_list()


func _remove_white_background(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var threshold := 0.88
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.r > threshold and c.g > threshold and c.b > threshold:
				var whiteness: float = minf(minf(c.r, c.g), c.b)
				var alpha: float = 1.0 - ((whiteness - threshold) / (1.0 - threshold))
				alpha = clampf(alpha, 0.0, c.a)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, alpha))


func _generate_all_object_images() -> void:
	for i in range(GameState.objects.size()):
		var obj: Dictionary = GameState.objects[i]
		if obj.get("image_path", "") != "":
			continue
		var w: int = int(obj.get("image_width", 64))
		var h: int = int(obj.get("image_height", 64))
		await _generate_object_image(i, w, h)


# ══════════════════════════════════════════════════════════════════════════════
# NPC Edit popup
# ══════════════════════════════════════════════════════════════════════════════

func _on_edit_npc(npc_index: int) -> void:
	var npc: Dictionary = GameState.npcs[npc_index]

	var popup := Window.new()
	popup.title = "Modifica NPC: %s" % npc.get("name", "NPC")
	popup.size = Vector2i(500, 480)
	popup.unresizable = false
	popup.transient = true
	popup.exclusive = true
	add_child(popup)

	var popup_bg := ColorRect.new()
	popup_bg.color = BG_COLOR
	popup_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(popup_bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Fields
	var fields := {}
	var field_defs := [
		["Nome", "name"],
		["Sesso", "gender"],
		["Razza", "race"],
		["Età", "age"],
		["Colore capelli", "hair_color"],
		["Colore pelle", "skin_color"],
	]

	for fd in field_defs:
		var lbl := Label.new()
		lbl.text = fd[0]
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", ACCENT_COLOR)
		vbox.add_child(lbl)

		var le := LineEdit.new()
		le.text = str(npc.get(fd[1], ""))
		_style_line_edit(le)
		vbox.add_child(le)
		fields[fd[1]] = le

	# Save and cancel buttons
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	var save_btn := Button.new()
	save_btn.text = "Salva"
	save_btn.custom_minimum_size = Vector2(120, 40)
	_style_button(save_btn, true)
	save_btn.pressed.connect(func():
		var updated_npc := npc.duplicate()
		for key in fields:
			var value = fields[key].text.strip_edges()
			if key == "age":
				updated_npc[key] = int(value) if value.is_valid_int() else npc.get("age", 0)
			else:
				updated_npc[key] = value
		GameState.npcs[npc_index] = updated_npc
		popup.queue_free()
		_populate_npc_list()
	)
	btn_hbox.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Annulla"
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	_style_button(cancel_btn)
	cancel_btn.pressed.connect(popup.queue_free)
	btn_hbox.add_child(cancel_btn)

	popup.popup_centered()


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _build_context() -> String:
	var parts: Array = []
	if GameState.story_preamble != "":
		parts.append(GameState.story_preamble)
	if GameState.player_character.get("name", "") != "":
		parts.append("Protagonista: %s" % GameState.player_character["name"])
	if GameState.objective != "":
		parts.append("Obiettivo: %s" % GameState.objective)
	return ". ".join(parts) if parts.size() > 0 else "Nessun contesto aggiuntivo"


func _extract_json_array(text: String) -> String:
	# Try to extract a JSON array from potentially wrapped text
	var start := text.find("[")
	var end := text.rfind("]")
	if start >= 0 and end > start:
		return text.substr(start, end - start + 1)
	return text


func _set_loading(active: bool, msg: String = "") -> void:
	_spinner_active = active
	spinner_rect.visible = active
	loading_label.visible = active
	if msg != "":
		loading_label.text = msg


func _update_step(index: int, status: String) -> void:
	if index < 0 or index >= step_labels.size():
		return
	if status == "in corso":
		step_labels[index].add_theme_color_override("font_color", ACCENT_COLOR)
		step_checks[index].button_pressed = false
		step_completed[index] = false
	elif status == "completato":
		step_labels[index].add_theme_color_override("font_color", GREEN_COLOR)
		step_checks[index].button_pressed = true
		step_completed[index] = true


func _check_all_complete() -> void:
	var all_done := true
	for done in step_completed:
		if not done:
			all_done = false
			break
	start_btn.disabled = not all_done
	if all_done:
		# Re-style the start button to be more prominent
		var style := StyleBoxFlat.new()
		style.bg_color = GREEN_COLOR
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		start_btn.add_theme_stylebox_override("normal", style)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/new_game/ObjectiveSetup.tscn")


func _on_start_adventure() -> void:
	GameState.save_game()
	# Change to the game world scene
	get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")


# ══════════════════════════════════════════════════════════════════════════════
# Styling helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_field_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	return lbl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE_COLOR
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", style)
	return sep


func _style_button(btn: Button, accent: bool = false) -> void:
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT_COLOR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = ACCENT_COLOR if accent else BUTTON_BG
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = BUTTON_HOVER
	hover.border_width_bottom = 2
	hover.border_width_top = 2
	hover.border_width_left = 2
	hover.border_width_right = 2
	hover.border_color = ACCENT_COLOR
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate()
	pressed_style.bg_color = ACCENT_COLOR
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var focus := hover.duplicate()
	btn.add_theme_stylebox_override("focus", focus)


func _style_line_edit(le: LineEdit) -> void:
	le.add_theme_font_size_override("font_size", 16)
	le.add_theme_color_override("font_color", TEXT_COLOR)
	le.add_theme_color_override("font_placeholder_color", SUBTITLE_COLOR)
	le.custom_minimum_size = Vector2(0, 36)

	var normal := StyleBoxFlat.new()
	normal.bg_color = SURFACE_COLOR
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	normal.border_width_bottom = 1
	normal.border_width_top = 1
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_color = ACCENT_COLOR
	le.add_theme_stylebox_override("normal", normal)

	var focus := normal.duplicate()
	focus.border_color = GREEN_COLOR
	le.add_theme_stylebox_override("focus", focus)


func _show_error(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = msg
	dialog.min_size = Vector2i(400, 150)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

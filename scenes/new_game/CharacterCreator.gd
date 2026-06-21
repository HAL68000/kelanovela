extends Control

## Character creation screen — second step of the New Game flow.

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
var character_image: TextureRect
var image_file_dialog: FileDialog
var name_edit: LineEdit
var sex_option: OptionButton
var height_spin: SpinBox
var body_type_option: OptionButton
var hair_color_edit: LineEdit
var skin_color_edit: LineEdit
var eye_color_edit: LineEdit
var tattoo_container: VBoxContainer
var breast_size_option: OptionButton
var breast_size_label: Label
var breast_size_row: HBoxContainer
var buttocks_option: OptionButton
var legs_option: OptionButton
var error_label: Label

# Data
var character_image_path: String = ""
var tattoo_entries: Array = []  # Array of { "hbox": HBoxContainer, "desc": LineEdit, "pos": LineEdit }

# Options
var _sex_options := ["Maschile", "Femminile"]
var _body_types := ["Esile", "Normale", "Atletica", "Robusta", "Formosa"]
var _breast_sizes := ["Piccolo", "Medio", "Grande"]
var _buttocks_options := ["Non specificato", "Piccoli", "Medi", "Grandi"]
var _legs_options := ["Non specificato", "Corte", "Normali", "Lunghe"]


func _ready() -> void:
	_build_ui()


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
	scroll.anchor_left = 0.05
	scroll.anchor_right = 0.95
	scroll.anchor_top = 0.02
	scroll.anchor_bottom = 0.98
	add_child(scroll)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Personalizzazione Personaggio"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	main_vbox.add_child(title)

	main_vbox.add_child(_make_separator())

	# Content: image left, fields right
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 30)
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# ── Left side: image ──
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 12)
	left_vbox.custom_minimum_size = Vector2(300, 0)
	content_hbox.add_child(left_vbox)

	left_vbox.add_child(_make_field_label("Immagine personaggio *"))

	# Image preview panel
	var image_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = SURFACE_COLOR
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = ACCENT_COLOR
	image_panel.add_theme_stylebox_override("panel", panel_style)
	image_panel.custom_minimum_size = Vector2(256, 256)
	left_vbox.add_child(image_panel)

	character_image = TextureRect.new()
	character_image.custom_minimum_size = Vector2(256, 256)
	character_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	image_panel.add_child(character_image)

	var img_buttons := HBoxContainer.new()
	img_buttons.add_theme_constant_override("separation", 8)
	left_vbox.add_child(img_buttons)

	var load_img_btn := Button.new()
	load_img_btn.text = "Carica Immagine"
	load_img_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_img_btn.custom_minimum_size = Vector2(0, 40)
	_style_button(load_img_btn)
	load_img_btn.pressed.connect(_on_load_image_pressed)
	img_buttons.add_child(load_img_btn)

	var paste_btn := Button.new()
	paste_btn.text = "Incolla (Ctrl+V)"
	paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste_btn.custom_minimum_size = Vector2(0, 40)
	_style_button(paste_btn)
	paste_btn.pressed.connect(_paste_from_clipboard)
	img_buttons.add_child(paste_btn)

	# AI extract button
	var ai_btn := Button.new()
	ai_btn.text = "Estrai dall'IA"
	ai_btn.custom_minimum_size = Vector2(256, 40)
	_style_button(ai_btn, true)
	ai_btn.pressed.connect(_on_extract_ai_pressed)
	left_vbox.add_child(ai_btn)

	# Image file dialog
	image_file_dialog = FileDialog.new()
	image_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_file_dialog.filters = PackedStringArray([
		"*.png ; Immagini PNG",
		"*.jpg ; Immagini JPG",
		"*.jpeg ; Immagini JPEG",
		"*.webp ; Immagini WebP",
		"*.bmp ; Immagini BMP",
	])
	image_file_dialog.title = "Seleziona immagine personaggio"
	image_file_dialog.min_size = Vector2i(700, 500)
	image_file_dialog.file_selected.connect(_on_image_selected)
	add_child(image_file_dialog)

	# ── Right side: fields ──
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 12)
	content_hbox.add_child(right_vbox)

	# Nome
	right_vbox.add_child(_make_field_label("Nome *"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nome del personaggio"
	_style_line_edit(name_edit)
	right_vbox.add_child(name_edit)

	# Sesso
	right_vbox.add_child(_make_field_label("Sesso"))
	sex_option = OptionButton.new()
	for s in _sex_options:
		sex_option.add_item(s)
	_style_option_button(sex_option)
	sex_option.item_selected.connect(_on_sex_changed)
	right_vbox.add_child(sex_option)

	# Altezza
	right_vbox.add_child(_make_field_label("Altezza (cm) *"))
	height_spin = SpinBox.new()
	height_spin.min_value = 140
	height_spin.max_value = 220
	height_spin.value = 170
	height_spin.step = 1
	height_spin.custom_minimum_size = Vector2(200, 40)
	height_spin.add_theme_color_override("font_color", TEXT_COLOR)
	# Style the inner LineEdit of SpinBox
	var spin_line := height_spin.get_line_edit()
	if spin_line:
		_style_line_edit(spin_line)
	right_vbox.add_child(height_spin)

	# Corporatura
	right_vbox.add_child(_make_field_label("Corporatura"))
	body_type_option = OptionButton.new()
	for bt in _body_types:
		body_type_option.add_item(bt)
	_style_option_button(body_type_option)
	body_type_option.selected = 1  # "Normale" default
	right_vbox.add_child(body_type_option)

	# Colore capelli
	right_vbox.add_child(_make_field_label("Colore capelli"))
	hair_color_edit = LineEdit.new()
	hair_color_edit.placeholder_text = "Derivato dall'immagine"
	_style_line_edit(hair_color_edit)
	right_vbox.add_child(hair_color_edit)

	# Colore pelle
	right_vbox.add_child(_make_field_label("Colore pelle"))
	skin_color_edit = LineEdit.new()
	skin_color_edit.placeholder_text = "Derivato dall'immagine"
	_style_line_edit(skin_color_edit)
	right_vbox.add_child(skin_color_edit)

	# Colore occhi
	right_vbox.add_child(_make_field_label("Colore occhi"))
	eye_color_edit = LineEdit.new()
	eye_color_edit.placeholder_text = "Derivato dall'immagine"
	_style_line_edit(eye_color_edit)
	right_vbox.add_child(eye_color_edit)

	# Breast size (shown only for female)
	breast_size_row = HBoxContainer.new()
	breast_size_row.add_theme_constant_override("separation", 12)
	breast_size_row.visible = false
	right_vbox.add_child(breast_size_row)

	var breast_vbox := VBoxContainer.new()
	breast_vbox.add_theme_constant_override("separation", 4)
	breast_size_row.add_child(breast_vbox)

	breast_size_label = _make_field_label("Grandezza Seno *")
	breast_vbox.add_child(breast_size_label)

	breast_size_option = OptionButton.new()
	for bs in _breast_sizes:
		breast_size_option.add_item(bs)
	_style_option_button(breast_size_option)
	breast_size_option.selected = 1  # "Medio" default
	breast_vbox.add_child(breast_size_option)

	# Glutei
	right_vbox.add_child(_make_field_label("Glutei"))
	buttocks_option = OptionButton.new()
	for bo in _buttocks_options:
		buttocks_option.add_item(bo)
	_style_option_button(buttocks_option)
	right_vbox.add_child(buttocks_option)

	# Gambe
	right_vbox.add_child(_make_field_label("Gambe"))
	legs_option = OptionButton.new()
	for lo in _legs_options:
		legs_option.add_item(lo)
	_style_option_button(legs_option)
	right_vbox.add_child(legs_option)

	# Tattoos section
	right_vbox.add_child(_make_separator())
	right_vbox.add_child(_make_field_label("Tatuaggi"))

	tattoo_container = VBoxContainer.new()
	tattoo_container.add_theme_constant_override("separation", 8)
	right_vbox.add_child(tattoo_container)

	var add_tattoo_btn := Button.new()
	add_tattoo_btn.text = "Aggiungi Tatuaggio"
	add_tattoo_btn.custom_minimum_size = Vector2(220, 36)
	_style_button(add_tattoo_btn)
	add_tattoo_btn.pressed.connect(_on_add_tattoo)
	right_vbox.add_child(add_tattoo_btn)

	# Error label
	error_label = Label.new()
	error_label.text = ""
	error_label.add_theme_font_size_override("font_size", 16)
	error_label.add_theme_color_override("font_color", RED_COLOR)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(error_label)

	# Navigation
	main_vbox.add_child(_make_separator())

	var nav_hbox := HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(nav_hbox)

	var back_btn := Button.new()
	back_btn.text = "← Indietro"
	back_btn.custom_minimum_size = Vector2(200, 50)
	_style_button(back_btn)
	back_btn.pressed.connect(_on_back_pressed)
	nav_hbox.add_child(back_btn)

	var next_btn := Button.new()
	next_btn.text = "Avanti →"
	next_btn.custom_minimum_size = Vector2(200, 50)
	_style_button(next_btn, true)
	next_btn.pressed.connect(_on_next_pressed)
	nav_hbox.add_child(next_btn)

	# Restore state
	_restore_state()


# ══════════════════════════════════════════════════════════════════════════════
# State restore
# ══════════════════════════════════════════════════════════════════════════════

func _restore_state() -> void:
	var pc: Dictionary = GameState.player_character
	if pc.get("name", "") != "":
		name_edit.text = pc["name"]
	if pc.get("sex", "") != "":
		var idx := _sex_options.find(pc["sex"])
		if idx >= 0:
			sex_option.selected = idx
			_on_sex_changed(idx)
	if pc.get("height", "") != "":
		height_spin.value = float(pc["height"])
	if pc.get("body_type", "") != "":
		var idx := _body_types.find(pc["body_type"])
		if idx >= 0:
			body_type_option.selected = idx
	if pc.get("hair_color", "") != "":
		hair_color_edit.text = pc["hair_color"]
	if pc.get("skin_color", "") != "":
		skin_color_edit.text = pc["skin_color"]
	if pc.get("eye_color", "") != "":
		eye_color_edit.text = pc["eye_color"]
	if pc.get("breast_size", "") != "":
		var idx := _breast_sizes.find(pc["breast_size"])
		if idx >= 0:
			breast_size_option.selected = idx
	if pc.get("buttocks", "") != "":
		var idx := _buttocks_options.find(pc["buttocks"])
		if idx >= 0:
			buttocks_option.selected = idx
	if pc.get("legs", "") != "":
		var idx := _legs_options.find(pc["legs"])
		if idx >= 0:
			legs_option.selected = idx
	if pc.get("image_path", "") != "":
		character_image_path = pc["image_path"]
		_load_image_from_path(character_image_path)
	# Restore tattoos
	var tattoos: Array = pc.get("tattoos", [])
	for t in tattoos:
		_add_tattoo_entry(t.get("description", ""), t.get("position", ""))


# ══════════════════════════════════════════════════════════════════════════════
# Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_V:
			_paste_from_clipboard()
			get_viewport().set_input_as_handled()


func _paste_from_clipboard() -> void:
	var img := DisplayServer.clipboard_get_image()
	if img == null or img.is_empty():
		_show_error("Nessuna immagine trovata nella clipboard.")
		return
	var save_path := "user://character_pasted.png"
	img.save_png(save_path)
	character_image_path = ProjectSettings.globalize_path(save_path)
	var tex := ImageTexture.create_from_image(img)
	character_image.texture = tex


func _on_load_image_pressed() -> void:
	image_file_dialog.popup_centered()


func _on_image_selected(path: String) -> void:
	character_image_path = path
	_load_image_from_path(path)


func _load_image_from_path(path: String) -> void:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		_show_error("Impossibile caricare l'immagine: %s" % path)
		return
	var tex := ImageTexture.create_from_image(img)
	character_image.texture = tex


func _on_sex_changed(index: int) -> void:
	breast_size_row.visible = (index == 1)  # "Femminile" is index 1


func _on_add_tattoo() -> void:
	_add_tattoo_entry("", "")


func _add_tattoo_entry(desc_text: String = "", pos_text: String = "") -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var desc := LineEdit.new()
	desc.placeholder_text = "Descrizione"
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.text = desc_text
	_style_line_edit(desc)
	hbox.add_child(desc)

	var pos := LineEdit.new()
	pos.placeholder_text = "Posizione"
	pos.custom_minimum_size = Vector2(160, 0)
	pos.text = pos_text
	_style_line_edit(pos)
	hbox.add_child(pos)

	var remove_btn := Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size = Vector2(36, 36)
	_style_button(remove_btn)
	remove_btn.add_theme_color_override("font_color", RED_COLOR)
	var entry := { "hbox": hbox, "desc": desc, "pos": pos }
	remove_btn.pressed.connect(_on_remove_tattoo.bind(entry))
	hbox.add_child(remove_btn)

	tattoo_entries.append(entry)
	tattoo_container.add_child(hbox)


func _on_remove_tattoo(entry: Dictionary) -> void:
	tattoo_entries.erase(entry)
	entry["hbox"].queue_free()


func _on_extract_ai_pressed() -> void:
	if GameState.story_preamble == "":
		_show_error("Devi prima compilare il preambolo della storia nella schermata precedente.")
		return
	# Check if LLMService autoload exists
	if not Engine.has_singleton("LLMService") and not has_node("/root/LLMService"):
		var llm_node := get_node_or_null("/root/LLMService")
		if llm_node == null:
			_show_error("LLMService non disponibile. Controlla le impostazioni.")
			return
		llm_node.call("extract_characters", GameState.story_preamble)
	else:
		var llm := get_node("/root/LLMService")
		if llm.has_method("extract_characters"):
			llm.call("extract_characters", GameState.story_preamble)
		else:
			_show_error("LLMService non supporta extract_characters.")


func _on_back_pressed() -> void:
	_save_to_game_state()
	get_tree().change_scene_to_file("res://scenes/new_game/StorySetup.tscn")


func _on_next_pressed() -> void:
	# Validate required fields
	error_label.text = ""
	if character_image_path == "":
		error_label.text = "Devi caricare un'immagine del personaggio."
		return
	if name_edit.text.strip_edges() == "":
		error_label.text = "Il nome del personaggio è obbligatorio."
		return
	if sex_option.selected == 1 and breast_size_option.selected < 0:
		error_label.text = "La grandezza del seno è obbligatoria per personaggi femminili."
		return

	_save_to_game_state()
	get_tree().change_scene_to_file("res://scenes/new_game/ObjectiveSetup.tscn")


func _save_to_game_state() -> void:
	var tattoos: Array = []
	for entry in tattoo_entries:
		var desc_text: String = entry["desc"].text.strip_edges()
		var pos_text: String = entry["pos"].text.strip_edges()
		if desc_text != "" or pos_text != "":
			tattoos.append({ "description": desc_text, "position": pos_text })

	GameState.player_character = {
		"name": name_edit.text.strip_edges(),
		"image_path": character_image_path,
		"sex": _sex_options[sex_option.selected],
		"height": str(int(height_spin.value)),
		"body_type": _body_types[body_type_option.selected],
		"hair_color": hair_color_edit.text.strip_edges(),
		"skin_color": skin_color_edit.text.strip_edges(),
		"eye_color": eye_color_edit.text.strip_edges(),
		"tattoos": tattoos,
		"breast_size": _breast_sizes[breast_size_option.selected] if sex_option.selected == 1 else "",
		"buttocks": _buttocks_options[buttocks_option.selected],
		"legs": _legs_options[legs_option.selected],
	}


# ══════════════════════════════════════════════════════════════════════════════
# Styling helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_field_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
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


func _style_option_button(opt: OptionButton) -> void:
	opt.add_theme_font_size_override("font_size", 16)
	opt.add_theme_color_override("font_color", TEXT_COLOR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = SURFACE_COLOR
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	normal.border_width_bottom = 1
	normal.border_width_top = 1
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_color = ACCENT_COLOR
	opt.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = BUTTON_HOVER
	opt.add_theme_stylebox_override("hover", hover)

	var focus := normal.duplicate()
	opt.add_theme_stylebox_override("focus", focus)


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

extends Control

## Story setup screen — first step of the New Game flow.

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
var story_type_option: OptionButton
var preamble_edit: TextEdit
var language_option: OptionButton
var render_style_option: OptionButton
var pdf_button: Button
var pdf_label: Label
var file_dialog: FileDialog

# Data
var loaded_pdf_content: String = ""
var loaded_pdf_filename: String = ""

# Style / language maps
var _story_types := ["Avventura", "Mistero", "Horror", "Erotico", "Fantasy", "Sci-fi", "Storico"]
var _languages := ["Italiano", "English", "Deutsch", "Français", "Español", "Português", "日本語"]
var _language_codes := ["it", "en", "de", "fr", "es", "pt", "ja"]
var _render_styles := ["3D", "Realistico", "Anime", "Personalizzato"]
var _render_codes := ["3d", "realistic", "anime", "custom"]


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

	# Main scroll container
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.anchor_left = 0.1
	scroll.anchor_right = 0.9
	scroll.anchor_top = 0.02
	scroll.anchor_bottom = 0.98
	add_child(scroll)

	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 20)
	scroll.add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Nuova Partita — Configurazione Storia"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	main_vbox.add_child(title)

	# Separator
	main_vbox.add_child(_make_separator())

	# Story type
	main_vbox.add_child(_make_field_label("Tipo di storia"))
	story_type_option = OptionButton.new()
	for st in _story_types:
		story_type_option.add_item(st)
	_style_option_button(story_type_option)
	story_type_option.custom_minimum_size = Vector2(400, 40)
	main_vbox.add_child(story_type_option)

	# Preamble
	main_vbox.add_child(_make_field_label("Preambolo della storia"))
	preamble_edit = TextEdit.new()
	preamble_edit.placeholder_text = "Descrivi l'ambientazione e la premessa della tua storia..."
	preamble_edit.custom_minimum_size = Vector2(0, 180)
	preamble_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_text_edit(preamble_edit)
	main_vbox.add_child(preamble_edit)

	# Language
	main_vbox.add_child(_make_field_label("Lingua della storia"))
	language_option = OptionButton.new()
	for lang in _languages:
		language_option.add_item(lang)
	_style_option_button(language_option)
	language_option.custom_minimum_size = Vector2(400, 40)
	# Set default from GameState
	var default_lang_idx := _language_codes.find(GameState.language)
	if default_lang_idx >= 0:
		language_option.selected = default_lang_idx
	main_vbox.add_child(language_option)

	# Render style
	main_vbox.add_child(_make_field_label("Stile rendering"))
	render_style_option = OptionButton.new()
	for rs in _render_styles:
		render_style_option.add_item(rs)
	_style_option_button(render_style_option)
	render_style_option.custom_minimum_size = Vector2(400, 40)
	# Set default from GameState
	var default_style_idx := _render_codes.find(GameState.image_style)
	if default_style_idx >= 0:
		render_style_option.selected = default_style_idx
	main_vbox.add_child(render_style_option)

	# PDF upload
	main_vbox.add_child(_make_field_label("Documento ambientazione (PDF)"))
	var pdf_hbox := HBoxContainer.new()
	pdf_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(pdf_hbox)

	pdf_button = Button.new()
	pdf_button.text = "Carica PDF"
	pdf_button.custom_minimum_size = Vector2(180, 40)
	_style_button(pdf_button)
	pdf_button.pressed.connect(_on_load_pdf_pressed)
	pdf_hbox.add_child(pdf_button)

	pdf_label = Label.new()
	pdf_label.text = "Nessun file caricato"
	pdf_label.add_theme_font_size_override("font_size", 16)
	pdf_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	pdf_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pdf_hbox.add_child(pdf_label)

	# File dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.pdf ; File PDF", "*.txt ; File di testo"])
	file_dialog.title = "Seleziona documento ambientazione"
	file_dialog.min_size = Vector2i(700, 500)
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer)

	# Navigation buttons
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

	# Restore any previously saved state
	_restore_state()


# ══════════════════════════════════════════════════════════════════════════════
# State restore (so going back then forward preserves data)
# ══════════════════════════════════════════════════════════════════════════════

func _restore_state() -> void:
	if GameState.story_type != "":
		var idx := _story_types.find(GameState.story_type)
		if idx >= 0:
			story_type_option.selected = idx
	if GameState.story_preamble != "":
		preamble_edit.text = GameState.story_preamble
	if GameState.story_language != "":
		var idx := _language_codes.find(GameState.story_language)
		if idx >= 0:
			language_option.selected = idx
	if GameState.render_style != "":
		var idx := _render_codes.find(GameState.render_style)
		if idx >= 0:
			render_style_option.selected = idx


# ══════════════════════════════════════════════════════════════════════════════
# Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_load_pdf_pressed() -> void:
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error("Impossibile aprire il file: %s" % path)
		return
	loaded_pdf_content = file.get_as_text()
	file.close()
	loaded_pdf_filename = path.get_file()
	pdf_label.text = loaded_pdf_filename
	pdf_label.add_theme_color_override("font_color", GREEN_COLOR)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")


func _on_next_pressed() -> void:
	# Save to GameState
	GameState.story_type = _story_types[story_type_option.selected]
	GameState.story_preamble = preamble_edit.text
	GameState.story_language = _language_codes[language_option.selected]
	GameState.render_style = _render_codes[render_style_option.selected]
	get_tree().change_scene_to_file("res://scenes/new_game/CharacterCreator.tscn")


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


func _style_text_edit(te: TextEdit) -> void:
	te.add_theme_font_size_override("font_size", 16)
	te.add_theme_color_override("font_color", TEXT_COLOR)
	te.add_theme_color_override("font_placeholder_color", SUBTITLE_COLOR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = SURFACE_COLOR
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	normal.border_width_bottom = 1
	normal.border_width_top = 1
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_color = ACCENT_COLOR
	te.add_theme_stylebox_override("normal", normal)

	var focus := normal.duplicate()
	focus.border_color = GREEN_COLOR
	te.add_theme_stylebox_override("focus", focus)


func _show_error(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Errore"
	dialog.dialog_text = msg
	dialog.min_size = Vector2i(400, 150)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

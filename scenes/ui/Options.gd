extends Control

const BG_COLOR := Color("#1a1a2e")
const ACCENT_COLOR := Color("#4fc3f7")
const TEXT_COLOR := Color.WHITE
const SUBTITLE_COLOR := Color(0.7, 0.7, 0.7, 1.0)
const SECTION_COLOR := Color("#4fc3f7")
const BUTTON_BG := Color("#2a2a4e")
const BUTTON_HOVER := Color("#3a3a6e")
const INPUT_BG := Color("#0d0d1a")
const INPUT_BORDER := Color("#3a3a6e")

const LANGUAGES := ["Italiano", "English", "Español", "Français", "Deutsch", "日本語"]
const LANGUAGE_CODES := ["it", "en", "es", "fr", "de", "ja"]
const STYLES := ["3D", "Realistico", "Anime", "Personalizzato"]
const STYLE_CODES := ["3d", "realistic", "anime", "custom"]

# UI references
var _language_option: OptionButton
var _llm_url_edit: LineEdit
var _llm_model_edit: LineEdit
var _llm_status_label: Label
var _invoke_url_edit: LineEdit
var _invoke_status_label: Label
var _style_option: OptionButton
var _custom_style_edit: LineEdit
var _custom_style_container: Control

# HTTP request nodes
var _llm_http: HTTPRequest
var _invoke_http: HTTPRequest


func _ready() -> void:
	_build_background()
	_build_ui()
	_load_from_game_state()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_ui() -> void:
	# Scrollable container for the whole page
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Opzioni"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(title)

	_add_spacer(vbox, 20)

	# ── Section: Lingua ──────────────────────────────────────────────────────
	_add_section_label(vbox, "Lingua")

	_language_option = OptionButton.new()
	for lang in LANGUAGES:
		_language_option.add_item(lang)
	_style_option_button(_language_option)
	_language_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language_option.custom_minimum_size = Vector2(300, 40)
	vbox.add_child(_language_option)

	_add_spacer(vbox, 16)

	# ── Section: Backend LLM ─────────────────────────────────────────────────
	_add_section_label(vbox, "Backend LLM")

	var llm_desc := Label.new()
	llm_desc.text = "URL del server LLM"
	llm_desc.add_theme_font_size_override("font_size", 14)
	llm_desc.add_theme_color_override("font_color", SUBTITLE_COLOR)
	vbox.add_child(llm_desc)

	_llm_url_edit = _create_line_edit("http://localhost:1234")
	vbox.add_child(_llm_url_edit)

	var model_desc := Label.new()
	model_desc.text = "Nome del modello"
	model_desc.add_theme_font_size_override("font_size", 14)
	model_desc.add_theme_color_override("font_color", SUBTITLE_COLOR)
	vbox.add_child(model_desc)

	_llm_model_edit = _create_line_edit("local-model")
	vbox.add_child(_llm_model_edit)

	var llm_test_row := HBoxContainer.new()
	llm_test_row.add_theme_constant_override("separation", 12)
	vbox.add_child(llm_test_row)

	var llm_test_btn := Button.new()
	llm_test_btn.text = "Test Connessione"
	llm_test_btn.custom_minimum_size = Vector2(200, 40)
	_style_button(llm_test_btn)
	llm_test_btn.pressed.connect(_on_test_llm)
	llm_test_row.add_child(llm_test_btn)

	_llm_status_label = Label.new()
	_llm_status_label.text = ""
	_llm_status_label.add_theme_font_size_override("font_size", 14)
	_llm_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	llm_test_row.add_child(_llm_status_label)

	_add_spacer(vbox, 16)

	# ── Section: Backend Immagini ────────────────────────────────────────────
	_add_section_label(vbox, "Backend Immagini (InvokeAI)")

	var invoke_desc := Label.new()
	invoke_desc.text = "URL del server InvokeAI"
	invoke_desc.add_theme_font_size_override("font_size", 14)
	invoke_desc.add_theme_color_override("font_color", SUBTITLE_COLOR)
	vbox.add_child(invoke_desc)

	_invoke_url_edit = _create_line_edit("http://localhost:9090")
	vbox.add_child(_invoke_url_edit)

	var invoke_test_row := HBoxContainer.new()
	invoke_test_row.add_theme_constant_override("separation", 12)
	vbox.add_child(invoke_test_row)

	var invoke_test_btn := Button.new()
	invoke_test_btn.text = "Test Connessione"
	invoke_test_btn.custom_minimum_size = Vector2(200, 40)
	_style_button(invoke_test_btn)
	invoke_test_btn.pressed.connect(_on_test_invoke)
	invoke_test_row.add_child(invoke_test_btn)

	_invoke_status_label = Label.new()
	_invoke_status_label.text = ""
	_invoke_status_label.add_theme_font_size_override("font_size", 14)
	_invoke_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	invoke_test_row.add_child(_invoke_status_label)

	_add_spacer(vbox, 16)

	# ── Section: Stile Rendering ─────────────────────────────────────────────
	_add_section_label(vbox, "Stile Rendering")

	_style_option = OptionButton.new()
	for s in STYLES:
		_style_option.add_item(s)
	_style_option_button(_style_option)
	_style_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option.custom_minimum_size = Vector2(300, 40)
	_style_option.item_selected.connect(_on_style_selected)
	vbox.add_child(_style_option)

	_custom_style_container = HBoxContainer.new()
	_custom_style_container.add_theme_constant_override("separation", 8)
	_custom_style_container.visible = false
	vbox.add_child(_custom_style_container)

	var custom_label := Label.new()
	custom_label.text = "Stile personalizzato:"
	custom_label.add_theme_font_size_override("font_size", 14)
	custom_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	custom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_custom_style_container.add_child(custom_label)

	_custom_style_edit = _create_line_edit("")
	_custom_style_edit.placeholder_text = "Descrivi lo stile desiderato..."
	_custom_style_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_style_container.add_child(_custom_style_edit)

	_add_spacer(vbox, 30)

	# ── Back button ──────────────────────────────────────────────────────────
	var back_btn := Button.new()
	back_btn.text = "← Indietro"
	back_btn.custom_minimum_size = Vector2(200, 50)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(back_btn)
	back_btn.pressed.connect(_on_back)
	vbox.add_child(back_btn)

	# ── HTTP request nodes ───────────────────────────────────────────────────
	_llm_http = HTTPRequest.new()
	_llm_http.request_completed.connect(_on_llm_test_completed)
	add_child(_llm_http)

	_invoke_http = HTTPRequest.new()
	_invoke_http.request_completed.connect(_on_invoke_test_completed)
	add_child(_invoke_http)


# ══════════════════════════════════════════════════════════════════════════════
# UI helpers
# ══════════════════════════════════════════════════════════════════════════════

func _add_spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)


func _add_section_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", SECTION_COLOR)
	parent.add_child(label)

	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(SECTION_COLOR, 0.3)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)


func _create_line_edit(default_text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = default_text
	edit.custom_minimum_size = Vector2(400, 40)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 16)
	edit.add_theme_color_override("font_color", TEXT_COLOR)
	edit.add_theme_color_override("caret_color", ACCENT_COLOR)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = INPUT_BG
	normal_style.border_color = INPUT_BORDER
	normal_style.border_width_bottom = 1
	normal_style.border_width_top = 1
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	normal_style.corner_radius_top_left = 4
	normal_style.corner_radius_top_right = 4
	normal_style.corner_radius_bottom_left = 4
	normal_style.corner_radius_bottom_right = 4
	normal_style.content_margin_left = 10
	normal_style.content_margin_right = 10
	normal_style.content_margin_top = 6
	normal_style.content_margin_bottom = 6
	edit.add_theme_stylebox_override("normal", normal_style)

	var focus_style := normal_style.duplicate()
	focus_style.border_color = ACCENT_COLOR
	focus_style.border_width_bottom = 2
	focus_style.border_width_top = 2
	focus_style.border_width_left = 2
	focus_style.border_width_right = 2
	edit.add_theme_stylebox_override("focus", focus_style)

	return edit


func _style_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT_COLOR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_BG
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.content_margin_left = 14
	normal.content_margin_right = 14
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
	normal.bg_color = INPUT_BG
	normal.border_color = INPUT_BORDER
	normal.border_width_bottom = 1
	normal.border_width_top = 1
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	opt.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.border_color = ACCENT_COLOR
	opt.add_theme_stylebox_override("hover", hover)

	var focus := normal.duplicate()
	focus.border_color = ACCENT_COLOR
	focus.border_width_bottom = 2
	focus.border_width_top = 2
	focus.border_width_left = 2
	focus.border_width_right = 2
	opt.add_theme_stylebox_override("focus", focus)


# ══════════════════════════════════════════════════════════════════════════════
# State loading / saving
# ══════════════════════════════════════════════════════════════════════════════

func _load_from_game_state() -> void:
	# Language
	var lang_idx := LANGUAGE_CODES.find(GameState.language)
	if lang_idx >= 0:
		_language_option.selected = lang_idx

	# LLM
	_llm_url_edit.text = GameState.llm_backend_url
	_llm_model_edit.text = GameState.llm_model

	# InvokeAI
	_invoke_url_edit.text = GameState.invoke_url

	# Style
	var style_idx := STYLE_CODES.find(GameState.image_style)
	if style_idx >= 0:
		_style_option.selected = style_idx
	_custom_style_edit.text = GameState.custom_style
	_update_custom_style_visibility()


func _save_to_game_state() -> void:
	# Language
	var lang_idx := _language_option.selected
	if lang_idx >= 0 and lang_idx < LANGUAGE_CODES.size():
		GameState.language = LANGUAGE_CODES[lang_idx]

	# LLM
	GameState.llm_backend_url = _llm_url_edit.text.strip_edges()
	GameState.llm_model = _llm_model_edit.text.strip_edges()

	# InvokeAI
	GameState.invoke_url = _invoke_url_edit.text.strip_edges()

	# Style
	var style_idx := _style_option.selected
	if style_idx >= 0 and style_idx < STYLE_CODES.size():
		GameState.image_style = STYLE_CODES[style_idx]
	GameState.custom_style = _custom_style_edit.text.strip_edges()

	GameState.save_settings()


# ══════════════════════════════════════════════════════════════════════════════
# Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_style_selected(_index: int) -> void:
	_update_custom_style_visibility()


func _update_custom_style_visibility() -> void:
	var idx := _style_option.selected
	_custom_style_container.visible = (idx == STYLES.find("Personalizzato"))


func _on_test_llm() -> void:
	var url := _llm_url_edit.text.strip_edges()
	if url.is_empty():
		_set_status(_llm_status_label, "URL vuoto", false)
		return

	_set_status(_llm_status_label, "Connessione in corso...", null)

	# Try to reach the LLM server (OpenAI-compatible /v1/models endpoint)
	var test_url := url.trim_suffix("/") + "/v1/models"
	var err := _llm_http.request(test_url)
	if err != OK:
		_set_status(_llm_status_label, "Errore di richiesta: %d" % err, false)


func _on_llm_test_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status(_llm_status_label, "Connessione fallita (errore rete)", false)
		return
	if response_code >= 200 and response_code < 300:
		_set_status(_llm_status_label, "Connesso! (HTTP %d)" % response_code, true)
	else:
		_set_status(_llm_status_label, "Errore server (HTTP %d)" % response_code, false)


func _on_test_invoke() -> void:
	var url := _invoke_url_edit.text.strip_edges()
	if url.is_empty():
		_set_status(_invoke_status_label, "URL vuoto", false)
		return

	_set_status(_invoke_status_label, "Connessione in corso...", null)

	# InvokeAI health check endpoint
	var test_url := url.trim_suffix("/") + "/api/v1/app/version"
	var err := _invoke_http.request(test_url)
	if err != OK:
		_set_status(_invoke_status_label, "Errore di richiesta: %d" % err, false)


func _on_invoke_test_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status(_invoke_status_label, "Connessione fallita (errore rete)", false)
		return
	if response_code >= 200 and response_code < 300:
		_set_status(_invoke_status_label, "Connesso! (HTTP %d)" % response_code, true)
	else:
		_set_status(_invoke_status_label, "Errore server (HTTP %d)" % response_code, false)


func _set_status(label: Label, text: String, success) -> void:
	label.text = text
	if success == null:
		label.add_theme_color_override("font_color", Color.YELLOW)
	elif success:
		label.add_theme_color_override("font_color", Color.GREEN)
	else:
		label.add_theme_color_override("font_color", Color.RED)


func _on_back() -> void:
	_save_to_game_state()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

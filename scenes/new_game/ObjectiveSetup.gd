extends Control

## Objective setup screen — third step of the New Game flow.

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
var suggestions_list: ItemList
var custom_objective_edit: TextEdit
var generate_btn: Button
var error_label: Label
var loading_label: Label


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
	title.text = "Definizione Obiettivo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	main_vbox.add_child(title)

	main_vbox.add_child(_make_separator())

	# Description
	var desc := Label.new()
	desc.text = "Scegli o definisci l'obiettivo del tuo personaggio in questa avventura."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", SUBTITLE_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(desc)

	# AI suggestions section
	main_vbox.add_child(_make_field_label("Suggerimenti IA"))

	generate_btn = Button.new()
	generate_btn.text = "Genera suggerimenti IA"
	generate_btn.custom_minimum_size = Vector2(300, 44)
	_style_button(generate_btn, true)
	generate_btn.pressed.connect(_on_generate_pressed)
	main_vbox.add_child(generate_btn)

	loading_label = Label.new()
	loading_label.text = "Generazione in corso..."
	loading_label.add_theme_font_size_override("font_size", 16)
	loading_label.add_theme_color_override("font_color", ACCENT_COLOR)
	loading_label.visible = false
	main_vbox.add_child(loading_label)

	suggestions_list = ItemList.new()
	suggestions_list.custom_minimum_size = Vector2(0, 200)
	suggestions_list.max_columns = 1
	suggestions_list.select_mode = ItemList.SELECT_SINGLE
	suggestions_list.allow_reselect = true
	_style_item_list(suggestions_list)
	main_vbox.add_child(suggestions_list)

	# Custom objective
	main_vbox.add_child(_make_separator())
	main_vbox.add_child(_make_field_label("Obiettivo personalizzato"))

	var hint := Label.new()
	hint.text = "Esempi: Scappare da un dungeon, Guadagnare 1000 crediti, Risolvere un omicidio, Rubare un oggetto prezioso, Salvare un personaggio, Sviluppare una cura"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", SUBTITLE_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(hint)

	custom_objective_edit = TextEdit.new()
	custom_objective_edit.placeholder_text = "Scrivi il tuo obiettivo personalizzato..."
	custom_objective_edit.custom_minimum_size = Vector2(0, 120)
	custom_objective_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_text_edit(custom_objective_edit)
	main_vbox.add_child(custom_objective_edit)

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
	if GameState.objective != "":
		custom_objective_edit.text = GameState.objective


# ══════════════════════════════════════════════════════════════════════════════
# Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_generate_pressed() -> void:
	var llm := get_node_or_null("/root/LLMService")
	if llm == null:
		_show_error("LLMService non disponibile. Controlla le impostazioni.")
		return
	if not llm.has_method("generate_objectives"):
		_show_error("LLMService non supporta generate_objectives.")
		return

	loading_label.visible = true
	generate_btn.disabled = true
	suggestions_list.clear()

	# Build context for the LLM
	var context := {
		"story_type": GameState.story_type,
		"story_preamble": GameState.story_preamble,
		"character_name": GameState.player_character.get("name", ""),
	}

	var result = await llm.generate_objectives(context)
	loading_label.visible = false
	generate_btn.disabled = false

	if result is Array:
		for obj in result:
			suggestions_list.add_item(str(obj))
	elif result is String and result != "":
		# Try parsing as JSON array
		var json := JSON.new()
		var err := json.parse(result)
		if err == OK and json.data is Array:
			for obj in json.data:
				suggestions_list.add_item(str(obj))
		else:
			suggestions_list.add_item(result)
	else:
		_show_error("Nessun suggerimento ricevuto dall'IA.")


func _on_back_pressed() -> void:
	_save_objective()
	get_tree().change_scene_to_file("res://scenes/new_game/CharacterCreator.tscn")


func _on_next_pressed() -> void:
	error_label.text = ""
	var objective := _get_selected_objective()
	if objective == "":
		error_label.text = "Devi selezionare o scrivere un obiettivo."
		return
	_save_objective()
	get_tree().change_scene_to_file("res://scenes/new_game/WorldBuilder.tscn")


func _get_selected_objective() -> String:
	# Custom objective takes priority if filled
	var custom := custom_objective_edit.text.strip_edges()
	if custom != "":
		return custom
	# Check if an item is selected in the suggestions list
	var selected_items := suggestions_list.get_selected_items()
	if selected_items.size() > 0:
		return suggestions_list.get_item_text(selected_items[0])
	return ""


func _save_objective() -> void:
	GameState.objective = _get_selected_objective()


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


func _style_item_list(il: ItemList) -> void:
	il.add_theme_font_size_override("font_size", 16)
	il.add_theme_color_override("font_color", TEXT_COLOR)
	il.add_theme_color_override("font_selected_color", BG_COLOR)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = SURFACE_COLOR
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel_style.border_width_bottom = 1
	panel_style.border_width_top = 1
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_color = ACCENT_COLOR
	il.add_theme_stylebox_override("panel", panel_style)

	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = ACCENT_COLOR
	selected_style.corner_radius_top_left = 4
	selected_style.corner_radius_top_right = 4
	selected_style.corner_radius_bottom_left = 4
	selected_style.corner_radius_bottom_right = 4
	il.add_theme_stylebox_override("selected", selected_style)
	il.add_theme_stylebox_override("selected_focus", selected_style)


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

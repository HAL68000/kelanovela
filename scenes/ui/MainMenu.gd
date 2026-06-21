extends Control

const BG_COLOR := Color("#1a1a2e")
const ACCENT_COLOR := Color("#4fc3f7")
const TEXT_COLOR := Color.WHITE
const SUBTITLE_COLOR := Color(0.7, 0.7, 0.7, 1.0)
const BUTTON_BG := Color("#2a2a4e")
const BUTTON_HOVER := Color("#3a3a6e")

func _ready() -> void:
	_build_background()
	_build_menu()
	_build_version_label()

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

func _build_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "INVOKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Un'avventura generata dall'IA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", SUBTITLE_COLOR)
	vbox.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	# Continue button (only if any save exists)
	var saves: Array = GameState.call("list_saves")
	if saves.size() > 0:
		var continue_btn := Button.new()
		continue_btn.text = "Continua"
		continue_btn.custom_minimum_size = Vector2(300, 50)
		continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_style_button(continue_btn)
		continue_btn.add_theme_color_override("font_color", ACCENT_COLOR)
		continue_btn.pressed.connect(_on_continua)
		vbox.add_child(continue_btn)

	# Buttons
	var buttons_data := [
		["Nuova Partita", _on_nuova_partita],
		["Opzioni", _on_opzioni],
		["Info", _on_info],
		["Esci", _on_esci],
	]

	for data in buttons_data:
		var btn := Button.new()
		btn.text = data[0]
		btn.custom_minimum_size = Vector2(300, 50)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_style_button(btn)
		btn.pressed.connect(data[1])
		vbox.add_child(btn)

func _style_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT_COLOR)

	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON_BG
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

func _build_version_label() -> void:
	var version_label := Label.new()
	version_label.text = "v0.1.0"
	version_label.add_theme_font_size_override("font_size", 14)
	version_label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version_label.position = Vector2(-80, -40)
	add_child(version_label)

# --- Button callbacks ---

func _on_continua() -> void:
	var saves: Array = GameState.call("list_saves")
	if saves.size() > 0:
		var latest: Dictionary = saves[0]
		GameState.call("load_game", latest.get("slot_name", "auto"))
	get_tree().change_scene_to_file("res://scenes/game/GameWorld.tscn")


func _on_nuova_partita() -> void:
	GameState.reset_game()
	get_tree().change_scene_to_file("res://scenes/new_game/StorySetup.tscn")

func _on_opzioni() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Options.tscn")

func _on_info() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Informazioni"
	dialog.dialog_text = (
		"INVOKER - Un'avventura generata dall'IA\n\n"
		+ "Versione: 0.1.0\n"
		+ "Motore: Godot 4.6\n\n"
		+ "Un gioco narrativo dove le storie vengono\n"
		+ "generate dinamicamente dall'intelligenza artificiale.\n\n"
		+ "Sviluppato con amore e creatività."
	)
	dialog.min_size = Vector2(450, 300)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _on_esci() -> void:
	get_tree().quit()

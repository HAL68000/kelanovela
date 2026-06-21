extends CanvasLayer

## Main gameplay HUD overlay.
## All UI is built programmatically with a dark theme.
## Text in Italian.

signal chat_action_requested(action: Dictionary)
signal photo_requested
signal inventory_item_used(item_name: String)

# ── Theme colors ─────────────────────────────────────────────────────────────
const COL_BG := Color("1a1a2e")
const COL_SURFACE := Color("1e2a45")
const COL_BORDER := Color("2e4070")
const COL_TEXT := Color.WHITE
const COL_ACCENT := Color("4fc3f7")
const COL_DIM := Color(1, 1, 1, 0.5)
const COL_INPUT_BG := Color("0f1525")
const COL_BUTTON_BG := Color("2e4070")
const COL_BUTTON_HOVER := Color("3e5590")
const COL_OPTION_BG := Color("1e3060")

# ── Node references (built in _ready) ────────────────────────────────────────
var _root: Control

# Top bar
var _top_bar: PanelContainer
var _room_label: Label
var _objective_label: Label
var _photo_button: Button

# Chat panel
var _chat_panel: PanelContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _send_button: Button
var _options_container: HBoxContainer
var _option_buttons: Array[Button] = []
var _chat_content: MarginContainer
var _chat_visible: bool = false

# Bottom bar
var _bottom_bar: PanelContainer
var _btn_chat: Button
var _btn_inventory: Button
var _btn_photo: Button

# Right panel
var _right_panel: PanelContainer
var _right_visible: bool = false
var _inventory_list: ItemList
var _npc_list_container: VBoxContainer

# Photo viewer
var _photo_popup: PanelContainer
var _photo_texture_rect: TextureRect
var _photo_close_button: Button

# Interaction hint
var _hint_label: Label

# Chat history for LLM context
var _chat_history: Array = []

# Loading indicator
var _loading_label: Label


func _ready() -> void:
	_build_ui()
	_connect_signals()


# ══════════════════════════════════════════════════════════════════════════════
# UI Construction
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "UIRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_top_bar()
	_build_chat_panel()
	_build_right_panel()
	_build_bottom_bar()
	_build_photo_popup()
	_build_interaction_hint()
	_build_loading_indicator()


func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.name = "TopBar"
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 48
	_top_bar.add_theme_stylebox_override("panel", _make_flat_style(COL_BG, 0, Color.TRANSPARENT, 0, 0, 0, 4))
	_root.add_child(_top_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_top_bar.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)

	# Room name with prefix
	var room_prefix := Label.new()
	room_prefix.text = "Luogo:"
	room_prefix.add_theme_color_override("font_color", COL_DIM)
	room_prefix.add_theme_font_size_override("font_size", 16)
	hbox.add_child(room_prefix)

	_room_label = Label.new()
	_room_label.text = "..."
	_room_label.add_theme_color_override("font_color", COL_ACCENT)
	_room_label.add_theme_font_size_override("font_size", 18)
	_room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(_room_label)

	# Objective
	_objective_label = Label.new()
	_objective_label.text = ""
	_objective_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_objective_label.add_theme_font_size_override("font_size", 14)
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_objective_label)

	# Photo button (kept in top bar as shortcut, also in bottom bar)
	_photo_button = _make_button("", COL_ACCENT)
	_photo_button.visible = false
	hbox.add_child(_photo_button)


func _build_chat_panel() -> void:
	# Chat starts hidden — toggled by bottom bar icon
	_chat_panel = PanelContainer.new()
	_chat_panel.name = "ChatPanel"
	_chat_panel.anchor_left = 0.0
	_chat_panel.anchor_top = 1.0
	_chat_panel.anchor_right = 1.0
	_chat_panel.anchor_bottom = 1.0
	_chat_panel.offset_top = -360
	_chat_panel.offset_left = 8
	_chat_panel.offset_right = -8
	_chat_panel.offset_bottom = -52
	_chat_panel.add_theme_stylebox_override("panel", _make_flat_style(COL_BG, 1, COL_BORDER, 6, 6, 6, 6))
	_chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat_panel.visible = false
	_root.add_child(_chat_panel)

	_chat_content = MarginContainer.new()
	_chat_content.name = "ChatContent"
	_chat_content.add_theme_constant_override("margin_left", 8)
	_chat_content.add_theme_constant_override("margin_right", 8)
	_chat_content.add_theme_constant_override("margin_top", 8)
	_chat_content.add_theme_constant_override("margin_bottom", 8)
	_chat_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_panel.add_child(_chat_content)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_chat_content.add_child(vbox)

	# Chat log
	_chat_log = RichTextLabel.new()
	_chat_log.name = "ChatLog"
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_color_override("default_color", COL_TEXT)
	_chat_log.add_theme_font_size_override("normal_font_size", 20)
	_chat_log.add_theme_font_size_override("bold_font_size", 20)
	vbox.add_child(_chat_log)

	# Options row
	_options_container = HBoxContainer.new()
	_options_container.name = "Options"
	_options_container.add_theme_constant_override("separation", 6)
	_options_container.visible = false
	vbox.add_child(_options_container)

	# Input row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Scrivi qualcosa..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size = Vector2(0, 40)
	_chat_input.add_theme_font_size_override("font_size", 18)
	_chat_input.add_theme_color_override("font_color", COL_TEXT)
	_chat_input.add_theme_color_override("font_placeholder_color", COL_DIM)
	_chat_input.add_theme_color_override("caret_color", COL_ACCENT)
	_chat_input.add_theme_stylebox_override("normal", _make_flat_style(COL_INPUT_BG, 1, COL_BORDER, 4, 4, 4, 4))
	_chat_input.add_theme_stylebox_override("focus", _make_flat_style(COL_INPUT_BG, 1, COL_ACCENT, 4, 4, 4, 4))
	input_row.add_child(_chat_input)

	_send_button = _make_button("Invia", COL_ACCENT)
	input_row.add_child(_send_button)


func _build_right_panel() -> void:
	_right_panel = PanelContainer.new()
	_right_panel.name = "RightPanel"
	_right_panel.anchor_left = 1.0
	_right_panel.anchor_top = 0.0
	_right_panel.anchor_right = 1.0
	_right_panel.anchor_bottom = 1.0
	_right_panel.offset_left = -260
	_right_panel.offset_top = 56
	_right_panel.offset_right = -8
	_right_panel.offset_bottom = -52
	_right_panel.add_theme_stylebox_override("panel", _make_flat_style(COL_BG, 1, COL_BORDER, 6, 6, 6, 6))
	_right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_right_panel.visible = false
	_root.add_child(_right_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_right_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var panel_title := Label.new()
	panel_title.text = "Inventario & NPC"
	panel_title.add_theme_color_override("font_color", COL_ACCENT)
	panel_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(panel_title)

	# Inventory section
	var inv_label := Label.new()
	inv_label.text = "Inventario"
	inv_label.add_theme_color_override("font_color", COL_ACCENT)
	inv_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(inv_label)

	_inventory_list = ItemList.new()
	_inventory_list.custom_minimum_size = Vector2(0, 120)
	_inventory_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_inventory_list.add_theme_color_override("font_color", COL_TEXT)
	_inventory_list.add_theme_color_override("font_hovered_color", COL_ACCENT)
	_inventory_list.add_theme_color_override("font_selected_color", COL_ACCENT)
	var inv_bg := _make_flat_style(COL_SURFACE, 1, COL_BORDER, 4, 4, 4, 4)
	_inventory_list.add_theme_stylebox_override("panel", inv_bg)
	_inventory_list.add_theme_stylebox_override("focus", inv_bg)
	vbox.add_child(_inventory_list)

	# NPC section
	var npc_title := Label.new()
	npc_title.text = "NPC Vicini"
	npc_title.add_theme_color_override("font_color", COL_ACCENT)
	npc_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(npc_title)

	var npc_scroll := ScrollContainer.new()
	npc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	npc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(npc_scroll)

	_npc_list_container = VBoxContainer.new()
	_npc_list_container.add_theme_constant_override("separation", 4)
	_npc_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	npc_scroll.add_child(_npc_list_container)


func _build_bottom_bar() -> void:
	_bottom_bar = PanelContainer.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.anchor_left = 0.0
	_bottom_bar.anchor_top = 1.0
	_bottom_bar.anchor_right = 1.0
	_bottom_bar.anchor_bottom = 1.0
	_bottom_bar.offset_top = -44
	_bottom_bar.add_theme_stylebox_override("panel", _make_flat_style(COL_BG, 1, COL_BORDER, 0, 0, 0, 0))
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_bottom_bar)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	_bottom_bar.add_child(hbox)

	_btn_chat = _make_icon_button("Chat", "[ ]")
	_btn_chat.pressed.connect(_toggle_chat)
	hbox.add_child(_btn_chat)

	_btn_inventory = _make_icon_button("Inventario", "{ }")
	_btn_inventory.pressed.connect(_toggle_right_panel)
	hbox.add_child(_btn_inventory)

	_btn_photo = _make_icon_button("Foto", "(o)")
	_btn_photo.pressed.connect(_on_photo_pressed)
	hbox.add_child(_btn_photo)


func _make_icon_button(label_text: String, icon_text: String) -> Button:
	var btn := Button.new()
	btn.text = "%s  %s" % [icon_text, label_text]
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COL_DIM)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.add_theme_stylebox_override("normal", _make_flat_style(COL_SURFACE, 1, COL_BORDER, 6, 6, 6, 6))
	btn.add_theme_stylebox_override("hover", _make_flat_style(COL_SURFACE, 1, COL_ACCENT, 6, 6, 6, 6))
	btn.add_theme_stylebox_override("pressed", _make_flat_style(COL_BG, 1, COL_ACCENT, 6, 6, 6, 6))
	btn.add_theme_stylebox_override("focus", _make_flat_style(COL_SURFACE, 1, COL_ACCENT, 6, 6, 6, 6))
	btn.custom_minimum_size = Vector2(140, 32)
	return btn


func _build_photo_popup() -> void:
	_photo_popup = PanelContainer.new()
	_photo_popup.name = "PhotoPopup"
	_photo_popup.set_anchors_preset(Control.PRESET_CENTER)
	_photo_popup.offset_left = -320
	_photo_popup.offset_top = -240
	_photo_popup.offset_right = 320
	_photo_popup.offset_bottom = 240
	_photo_popup.add_theme_stylebox_override("panel", _make_flat_style(COL_BG, 2, COL_ACCENT, 8, 8, 8, 8))
	_photo_popup.visible = false
	_photo_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_photo_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_photo_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var photo_title := Label.new()
	photo_title.text = "Foto"
	photo_title.add_theme_color_override("font_color", COL_ACCENT)
	photo_title.add_theme_font_size_override("font_size", 16)
	photo_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(photo_title)

	_photo_close_button = Button.new()
	_photo_close_button.text = "X"
	_photo_close_button.flat = true
	_photo_close_button.add_theme_color_override("font_color", COL_TEXT)
	_photo_close_button.add_theme_font_size_override("font_size", 16)
	header.add_child(_photo_close_button)

	# Image display
	_photo_texture_rect = TextureRect.new()
	_photo_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo_texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo_texture_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vbox.add_child(_photo_texture_rect)


func _build_interaction_hint() -> void:
	_hint_label = Label.new()
	_hint_label.name = "InteractionHint"
	_hint_label.anchor_left = 0.5
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_right = 0.5
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = -200
	_hint_label.offset_top = -50
	_hint_label.offset_right = 200
	_hint_label.offset_bottom = -30
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", COL_ACCENT)
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_hint_label.visible = false
	_root.add_child(_hint_label)


func _build_loading_indicator() -> void:
	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.anchor_left = 0.5
	_loading_label.anchor_top = 0.5
	_loading_label.anchor_right = 0.5
	_loading_label.anchor_bottom = 0.5
	_loading_label.offset_left = -100
	_loading_label.offset_top = -15
	_loading_label.offset_right = 100
	_loading_label.offset_bottom = 15
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.text = "Pensando..."
	_loading_label.add_theme_color_override("font_color", COL_ACCENT)
	_loading_label.add_theme_font_size_override("font_size", 16)
	_loading_label.visible = false
	_root.add_child(_loading_label)


# ══════════════════════════════════════════════════════════════════════════════
# Signal wiring
# ══════════════════════════════════════════════════════════════════════════════

func _connect_signals() -> void:
	_send_button.pressed.connect(_on_send_pressed)
	_chat_input.text_submitted.connect(_on_text_submitted)
	_photo_button.pressed.connect(_on_photo_pressed)
	_photo_close_button.pressed.connect(_on_photo_close)
	_inventory_list.item_activated.connect(_on_inventory_item_activated)


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

func update_room(room_name: String, _room_desc: String) -> void:
	_room_label.text = room_name if room_name != "" else "..."

	# Update the objective from GameState
	var obj_text: String = GameState.objective
	if obj_text.length() > 80:
		obj_text = obj_text.left(77) + "..."
	_objective_label.text = obj_text


func update_nearby_npcs(npcs: Array) -> void:
	# Clear previous entries
	for child in _npc_list_container.get_children():
		child.queue_free()

	for npc_data: Dictionary in npcs:
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override("separation", 6)

		# Mood indicator
		var mood_text: String = npc_data.get("mood", "neutral")
		var mood_map: Dictionary = {
			"happy": ":)",
			"sad": ":(",
			"angry": ">:(",
			"neutral": ":|",
			"scared": "D:",
			"love": "<3",
			"confused": "?",
			"excited": ":D",
			"dead": "X_X",
		}
		var mood_emoji: String = mood_map.get(mood_text, ":|")

		var mood_label := Label.new()
		mood_label.text = mood_emoji
		mood_label.add_theme_font_size_override("font_size", 14)
		mood_label.custom_minimum_size = Vector2(30, 0)
		entry.add_child(mood_label)

		# Name
		var name_btn := Button.new()
		name_btn.text = npc_data.get("name", "???")
		name_btn.flat = true
		name_btn.add_theme_color_override("font_color", COL_TEXT)
		name_btn.add_theme_color_override("font_hover_color", COL_ACCENT)
		name_btn.add_theme_font_size_override("font_size", 13)
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var npc_name_captured: String = npc_data.get("name", "")
		name_btn.pressed.connect(_on_npc_inspect.bind(npc_name_captured))
		entry.add_child(name_btn)

		_npc_list_container.add_child(entry)


func add_chat_message(speaker: String, text: String, color: Color = COL_TEXT) -> void:
	var color_hex := color.to_html(false)
	if speaker != "":
		_chat_log.append_text("[color=#%s][b]%s:[/b][/color] " % [color_hex, speaker])
	_chat_log.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])


func show_options(options: Array) -> void:
	hide_options()
	_options_container.visible = true

	for i in range(mini(options.size(), 4)):
		var btn := _make_button(options[i], COL_OPTION_BG)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 12)
		var opt_text: String = options[i]
		btn.pressed.connect(_on_option_selected.bind(opt_text))
		_option_buttons.append(btn)
		_options_container.add_child(btn)


func hide_options() -> void:
	for btn in _option_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_option_buttons.clear()
	_options_container.visible = false


func show_photo(texture: ImageTexture) -> void:
	_photo_texture_rect.texture = texture
	_photo_popup.visible = true


func update_inventory(items: Array) -> void:
	_inventory_list.clear()
	for item: Dictionary in items:
		var item_name: String = item.get("name", "???")
		var item_desc: String = item.get("description", "")
		_inventory_list.add_item(item_name)
		_inventory_list.set_item_tooltip(_inventory_list.item_count - 1, item_desc)


func show_interaction_hint(npc_name: String) -> void:
	_hint_label.text = "Premi Spazio per interagire con %s" % npc_name
	_hint_label.visible = true


func hide_interaction_hint() -> void:
	_hint_label.visible = false


func set_loading(loading: bool) -> void:
	_loading_label.visible = loading
	_send_button.disabled = loading
	_chat_input.editable = not loading


# ══════════════════════════════════════════════════════════════════════════════
# Internal callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_send_pressed() -> void:
	_submit_chat()


func _on_text_submitted(_text: String) -> void:
	_submit_chat()


func _submit_chat() -> void:
	var text := _chat_input.text.strip_edges()
	if text.is_empty():
		return

	_chat_input.text = ""
	hide_options()
	add_chat_message(GameState.player_character.get("name", "Tu"), text, COL_ACCENT)

	# Store in history
	_chat_history.append({"role": "user", "content": text})

	# Send to LLM via GameWorld
	_send_to_llm(text)


func _send_to_llm(message: String) -> void:
	set_loading(true)

	var context := _build_chat_context()
	var result: Dictionary = await LLMService.game_chat(message, context)

	set_loading(false)

	# Display narrative response
	var response_text: String = result.get("response", "...")
	add_chat_message("Narratore", response_text, Color(0.8, 0.8, 0.9))

	# Store assistant response in history
	_chat_history.append({"role": "assistant", "content": response_text})

	# Show options
	var options: Array = result.get("options", [])
	if options.size() > 0:
		show_options(options)

	# Process actions
	var actions: Array = result.get("actions", [])
	for action: Dictionary in actions:
		chat_action_requested.emit(action)


func _build_chat_context() -> Dictionary:
	return {
		"current_room": _room_label.text,
		"nearby_npcs": _get_nearby_npc_names(),
		"inventory": _get_inventory_names(),
		"story_state": GameState.story_preamble,
		"history": _chat_history.duplicate(),
	}


func _get_nearby_npc_names() -> Array:
	var names: Array = []
	for child in _npc_list_container.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			var btn: Button = child.get_child(1) as Button
			if btn:
				names.append(btn.text)
	return names


func _get_inventory_names() -> Array:
	var names: Array = []
	for i in range(_inventory_list.item_count):
		names.append(_inventory_list.get_item_text(i))
	return names


func _on_option_selected(option_text: String) -> void:
	_chat_input.text = option_text
	_submit_chat()


func _on_photo_pressed() -> void:
	photo_requested.emit()


func _on_photo_close() -> void:
	_photo_popup.visible = false


func _toggle_chat() -> void:
	_chat_visible = not _chat_visible
	_chat_panel.visible = _chat_visible
	_btn_chat.add_theme_color_override("font_color", COL_ACCENT if _chat_visible else COL_DIM)
	if _chat_visible and _right_visible:
		_toggle_right_panel()


func _toggle_right_panel() -> void:
	_right_visible = not _right_visible
	_right_panel.visible = _right_visible
	_btn_inventory.add_theme_color_override("font_color", COL_ACCENT if _right_visible else COL_DIM)
	if _right_visible and _chat_visible:
		_toggle_chat()


func _on_npc_inspect(npc_name_str: String) -> void:
	var npc_data: Dictionary = GameState.get_npc(npc_name_str)
	if npc_data.is_empty():
		return

	# Show NPC info in chat
	var info := "[b]%s[/b]\n" % npc_name_str
	info += "Umore: %s\n" % npc_data.get("mood", "neutrale")
	var outfit: Array = npc_data.get("outfit", [])
	if outfit.size() > 0:
		info += "Vestiti: %s\n" % ", ".join(outfit)
	var desc: String = npc_data.get("description", "")
	if desc != "":
		info += desc
	add_chat_message("", info, COL_DIM)


func _on_inventory_item_activated(index: int) -> void:
	var item_name := _inventory_list.get_item_text(index)
	inventory_item_used.emit(item_name)


# ══════════════════════════════════════════════════════════════════════════════
# UI Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_button(text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.add_theme_stylebox_override("normal", _make_flat_style(bg_color, 1, COL_BORDER, 4, 4, 8, 8))
	btn.add_theme_stylebox_override("hover", _make_flat_style(bg_color.lightened(0.15), 1, COL_ACCENT, 4, 4, 8, 8))
	btn.add_theme_stylebox_override("pressed", _make_flat_style(bg_color.darkened(0.1), 1, COL_ACCENT, 4, 4, 8, 8))
	btn.add_theme_stylebox_override("focus", _make_flat_style(bg_color, 1, COL_ACCENT, 4, 4, 8, 8))
	return btn


func _make_flat_style(
	bg: Color,
	border_width: int,
	border_color: Color,
	corner_tl: int,
	corner_tr: int,
	corner_bl: int = -1,
	corner_br: int = -1
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_tl
	style.corner_radius_top_right = corner_tr
	style.corner_radius_bottom_left = corner_bl if corner_bl >= 0 else corner_tl
	style.corner_radius_bottom_right = corner_br if corner_br >= 0 else corner_tr
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

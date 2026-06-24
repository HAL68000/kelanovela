extends CanvasLayer

## Character sheet / inventory overlay.
## Displayed on layer 50 over the game world.
## All UI built programmatically in _ready(). Italian text, dark theme.

signal outfit_changed(outfit_description: String)
signal closed

# ── Theme colors ─────────────────────────────────────────────────────────────
const COL_BG := Color("1a1a2e")
const COL_SURFACE := Color("1e2a45")
const COL_BORDER := Color("2e4070")
const COL_ACCENT := Color("4fc3f7")
const COL_TEXT := Color.WHITE
const COL_DIM := Color(1, 1, 1, 0.5)
const COL_INPUT_BG := Color("0f1525")
const COL_SLOT_EMPTY := Color("1a2035")
const COL_SLOT_FILLED := Color("1e3050")
const COL_BADGE_CLOTHES := Color("2e7d32")
const COL_BADGE_WEAPONS := Color("c62828")
const COL_BADGE_TOOLS := Color("ef6c00")
const COL_BADGE_FOOD := Color("558b2f")
const COL_BADGE_MEDICINE := Color("00838f")
const COL_BADGE_JEWELRY := Color("6a1b9a")
const COL_BADGE_SCROLLS := Color("4e342e")
const COL_BADGE_MACHINERY := Color("37474f")
const COL_BADGE_DEFAULT := Color("455a64")

# ── Equipment slot map ───────────────────────────────────────────────────────
const SLOT_MAP := {
	"head": "Testa",
	"chest": "Busto",
	"legs": "Gambe",
	"weapon": "Arma",
	"shield": "Scudo",
	"accessory": "Accessorio",
}

# ── Category -> slot auto-detection ──────────────────────────────────────────
const CATEGORY_TO_SLOT := {
	"clothes": "chest",
	"weapons": "weapon",
	"jewelry": "accessory",
	"scrolls": "accessory",
	"medicine": "accessory",
	"machinery": "weapon",
}

# ── Node references ──────────────────────────────────────────────────────────
var _root: Control
var _dim_bg: ColorRect
var _main_panel: PanelContainer

# Left column
var _char_image: TextureRect
var _char_name_label: Label
var _stats_container: VBoxContainer
var _mood_label: Label

# Center column — equipment
var _slot_panels: Dictionary = {}  # slot_key -> PanelContainer
var _slot_labels: Dictionary = {}  # slot_key -> Label (item name)

# Right column — inventory
var _inventory_scroll: ScrollContainer
var _inventory_vbox: VBoxContainer

# Bottom
var _outfit_label: Label

# Popups
var _item_popup: PanelContainer
var _item_popup_vbox: VBoxContainer
var _item_popup_name: String = ""

var _add_dialog: PanelContainer
var _add_name_edit: LineEdit
var _add_desc_edit: LineEdit
var _add_category_option: OptionButton

var _generating_items: bool = false

var _item_image_dialog: FileDialog
var _item_image_target: String = ""

var _mode: String = "player"  # "player" or "npc"
var _npc_name: String = ""     # NPC name when mode == "npc"

var _title_label: Label
var _image_file_dialog: FileDialog


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

func show_sheet() -> void:
	_mode = "player"
	_npc_name = ""
	visible = true
	_refresh_all()


func show_npc_sheet(npc_name: String) -> void:
	_mode = "npc"
	_npc_name = npc_name
	visible = true
	_refresh_all()


func hide_sheet() -> void:
	_save_outfit_to_state()
	visible = false
	closed.emit()


func _get_char_data() -> Dictionary:
	if _mode == "npc":
		return GameState.get_npc(_npc_name)
	return GameState.player_character


# ══════════════════════════════════════════════════════════════════════════════
# UI Construction
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dimmed background
	_dim_bg = ColorRect.new()
	_dim_bg.color = Color(0, 0, 0, 0.7)
	_dim_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim_bg)

	# Main panel
	_main_panel = PanelContainer.new()
	_main_panel.anchor_left = 0.05
	_main_panel.anchor_top = 0.03
	_main_panel.anchor_right = 0.95
	_main_panel.anchor_bottom = 0.97
	_main_panel.add_theme_stylebox_override("panel", _make_panel_style(COL_BG, COL_ACCENT, 2, 8))
	_root.add_child(_main_panel)

	var main_margin := MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 16)
	main_margin.add_theme_constant_override("margin_right", 16)
	main_margin.add_theme_constant_override("margin_top", 12)
	main_margin.add_theme_constant_override("margin_bottom", 12)
	_main_panel.add_child(main_margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	main_margin.add_child(outer_vbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "Scheda Personaggio"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", COL_ACCENT)
	outer_vbox.add_child(_title_label)

	# Columns container
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(columns)

	_build_left_column(columns)
	_build_center_column(columns)
	_build_right_column(columns)

	# Bottom row
	_build_bottom_row(outer_vbox)

	# Popups (hidden by default)
	_build_item_popup()
	_build_add_dialog()


func _build_left_column(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.3
	panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SURFACE, COL_BORDER, 1, 6))
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Character image
	_char_image = TextureRect.new()
	_char_image.custom_minimum_size = Vector2(0, 180)
	_char_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_char_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_char_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_char_image)

	# Image change buttons
	var img_btn_row := HBoxContainer.new()
	img_btn_row.add_theme_constant_override("separation", 4)
	img_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(img_btn_row)

	var change_img_btn := _make_action_button("Cambia Foto")
	change_img_btn.custom_minimum_size = Vector2(0, 28)
	change_img_btn.pressed.connect(_on_change_image)
	img_btn_row.add_child(change_img_btn)

	var paste_img_btn := _make_action_button("Incolla")
	paste_img_btn.custom_minimum_size = Vector2(0, 28)
	paste_img_btn.pressed.connect(_on_paste_image)
	img_btn_row.add_child(paste_img_btn)

	# File dialog for image selection
	_image_file_dialog = FileDialog.new()
	_image_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_file_dialog.filters = PackedStringArray(["*.png", "*.jpg", "*.jpeg", "*.webp"])
	_image_file_dialog.title = "Seleziona immagine"
	_image_file_dialog.min_size = Vector2i(600, 400)
	_image_file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(_image_file_dialog)

	# Character name
	_char_name_label = Label.new()
	_char_name_label.text = ""
	_char_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_name_label.add_theme_font_size_override("font_size", 22)
	_char_name_label.add_theme_color_override("font_color", COL_ACCENT)
	vbox.add_child(_char_name_label)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", COL_BORDER)
	vbox.add_child(sep)

	# Stats container
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_stats_container)

	# Mood
	var mood_row := HBoxContainer.new()
	mood_row.add_theme_constant_override("separation", 6)
	vbox.add_child(mood_row)

	var mood_prefix := Label.new()
	mood_prefix.text = "Umore:"
	mood_prefix.add_theme_font_size_override("font_size", 14)
	mood_prefix.add_theme_color_override("font_color", COL_DIM)
	mood_row.add_child(mood_prefix)

	_mood_label = Label.new()
	_mood_label.text = "---"
	_mood_label.add_theme_font_size_override("font_size", 14)
	_mood_label.add_theme_color_override("font_color", COL_ACCENT)
	mood_row.add_child(_mood_label)


func _build_center_column(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.4
	panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SURFACE, COL_BORDER, 1, 6))
	parent.add_child(panel)

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
	title.text = "Equipaggiamento"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	vbox.add_child(title)

	# 2x3 grid of equipment slots
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var slot_order := ["head", "chest", "legs", "weapon", "shield", "accessory"]
	for slot_key in slot_order:
		var slot_label_text: String = SLOT_MAP[slot_key]
		var slot_panel := _build_equipment_slot(slot_key, slot_label_text)
		grid.add_child(slot_panel)


func _build_equipment_slot(slot_key: String, label_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 60)
	panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SLOT_EMPTY, COL_BORDER, 1, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# Slot name
	var slot_name_lbl := Label.new()
	slot_name_lbl.text = label_text
	slot_name_lbl.add_theme_font_size_override("font_size", 13)
	slot_name_lbl.add_theme_color_override("font_color", COL_DIM)
	slot_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(slot_name_lbl)

	# Item name
	var item_lbl := Label.new()
	item_lbl.text = "(vuoto)"
	item_lbl.add_theme_font_size_override("font_size", 15)
	item_lbl.add_theme_color_override("font_color", COL_TEXT)
	item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(item_lbl)

	# Click button (invisible, covers the panel)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.pressed.connect(_on_slot_clicked.bind(slot_key))
	panel.add_child(click_btn)

	_slot_panels[slot_key] = panel
	_slot_labels[slot_key] = item_lbl

	return panel


func _build_right_column(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.3
	panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SURFACE, COL_BORDER, 1, 6))
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Inventario"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_ACCENT)
	vbox.add_child(title)

	# Scrollable inventory list
	_inventory_scroll = ScrollContainer.new()
	_inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_inventory_scroll)

	_inventory_vbox = VBoxContainer.new()
	_inventory_vbox.add_theme_constant_override("separation", 4)
	_inventory_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_scroll.add_child(_inventory_vbox)

	# Action buttons
	var btn_row := VBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var add_btn := _make_action_button("Aggiungi Oggetto")
	add_btn.pressed.connect(_on_add_item_pressed)
	btn_row.add_child(add_btn)

	var ai_btn := _make_action_button("Genera con IA")
	ai_btn.add_theme_color_override("font_color", COL_ACCENT)
	ai_btn.pressed.connect(_on_generate_items_pressed)
	btn_row.add_child(ai_btn)


func _build_bottom_row(parent: VBoxContainer) -> void:
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(bottom)

	var outfit_prefix := Label.new()
	outfit_prefix.text = "Outfit attuale:"
	outfit_prefix.add_theme_font_size_override("font_size", 14)
	outfit_prefix.add_theme_color_override("font_color", COL_DIM)
	bottom.add_child(outfit_prefix)

	_outfit_label = Label.new()
	_outfit_label.text = "(nessuno)"
	_outfit_label.add_theme_font_size_override("font_size", 14)
	_outfit_label.add_theme_color_override("font_color", COL_TEXT)
	_outfit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outfit_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bottom.add_child(_outfit_label)

	var close_btn := _make_action_button("Chiudi")
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.pressed.connect(hide_sheet)
	bottom.add_child(close_btn)


func _build_item_popup() -> void:
	_item_popup = PanelContainer.new()
	_item_popup.set_anchors_preset(Control.PRESET_CENTER)
	_item_popup.offset_left = -140
	_item_popup.offset_right = 140
	_item_popup.offset_top = -100
	_item_popup.offset_bottom = 100
	_item_popup.add_theme_stylebox_override("panel", _make_panel_style(COL_BG, COL_ACCENT, 2, 8))
	_item_popup.visible = false
	_item_popup.z_index = 10
	_item_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_item_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_item_popup.add_child(margin)

	_item_popup_vbox = VBoxContainer.new()
	_item_popup_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(_item_popup_vbox)


func _build_add_dialog() -> void:
	_add_dialog = PanelContainer.new()
	_add_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_add_dialog.offset_left = -200
	_add_dialog.offset_right = 200
	_add_dialog.offset_top = -160
	_add_dialog.offset_bottom = 160
	_add_dialog.add_theme_stylebox_override("panel", _make_panel_style(COL_BG, COL_ACCENT, 2, 8))
	_add_dialog.visible = false
	_add_dialog.z_index = 10
	_add_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_add_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_add_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var dlg_title := Label.new()
	dlg_title.text = "Nuovo Oggetto"
	dlg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlg_title.add_theme_font_size_override("font_size", 20)
	dlg_title.add_theme_color_override("font_color", COL_ACCENT)
	vbox.add_child(dlg_title)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = "Nome:"
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(name_lbl)

	_add_name_edit = LineEdit.new()
	_add_name_edit.placeholder_text = "es. Spada di ferro"
	_add_name_edit.add_theme_font_size_override("font_size", 16)
	_add_name_edit.add_theme_color_override("font_color", COL_TEXT)
	_add_name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	_add_name_edit.add_theme_stylebox_override("normal", _make_panel_style(COL_INPUT_BG, COL_BORDER, 1, 4))
	_add_name_edit.add_theme_stylebox_override("focus", _make_panel_style(COL_INPUT_BG, COL_ACCENT, 1, 4))
	vbox.add_child(_add_name_edit)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "Descrizione:"
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(desc_lbl)

	_add_desc_edit = LineEdit.new()
	_add_desc_edit.placeholder_text = "es. Una spada robusta"
	_add_desc_edit.add_theme_font_size_override("font_size", 16)
	_add_desc_edit.add_theme_color_override("font_color", COL_TEXT)
	_add_desc_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.3))
	_add_desc_edit.add_theme_stylebox_override("normal", _make_panel_style(COL_INPUT_BG, COL_BORDER, 1, 4))
	_add_desc_edit.add_theme_stylebox_override("focus", _make_panel_style(COL_INPUT_BG, COL_ACCENT, 1, 4))
	vbox.add_child(_add_desc_edit)

	# Category
	var cat_lbl := Label.new()
	cat_lbl.text = "Categoria:"
	cat_lbl.add_theme_font_size_override("font_size", 14)
	cat_lbl.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(cat_lbl)

	_add_category_option = OptionButton.new()
	_add_category_option.add_theme_font_size_override("font_size", 14)
	_add_category_option.add_theme_color_override("font_color", COL_TEXT)
	var categories := ["clothes", "weapons", "tools", "food", "medicine", "jewelry", "scrolls", "machinery"]
	for cat in categories:
		_add_category_option.add_item(cat)
	vbox.add_child(_add_category_option)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var confirm_btn := _make_action_button("Conferma")
	confirm_btn.pressed.connect(_on_add_dialog_confirm)
	btn_row.add_child(confirm_btn)

	var cancel_btn := _make_action_button("Annulla")
	cancel_btn.pressed.connect(_on_add_dialog_cancel)
	btn_row.add_child(cancel_btn)


# ══════════════════════════════════════════════════════════════════════════════
# Data Refresh
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_all() -> void:
	if _mode == "npc":
		_title_label.text = "Scheda NPC: %s" % _npc_name
	else:
		_title_label.text = "Scheda Personaggio"
	_refresh_character_info()
	_refresh_slots()
	_refresh_inventory()
	_refresh_outfit_label()


func _refresh_character_info() -> void:
	var data: Dictionary = _get_char_data()
	if data.is_empty():
		return

	# Image
	var img_path: String = data.get("image_path", "")
	if img_path != "":
		var img := Image.new()
		if img.load(img_path) == OK:
			_char_image.texture = ImageTexture.create_from_image(img)
		else:
			_char_image.texture = null
	else:
		_char_image.texture = null

	# Name
	_char_name_label.text = data.get("name", "Sconosciuto")

	# Stats - clear and rebuild
	for child in _stats_container.get_children():
		child.queue_free()

	# Editable stats
	_add_editable_stat("Sesso", data.get("sex", data.get("gender", "---")), "sex")
	_add_editable_stat("Altezza", data.get("height", "---"), "height")
	_add_editable_stat("Corporatura", data.get("body_type", data.get("build", "---")), "body_type")
	_add_editable_stat("Razza", data.get("race", GameState.default_race), "race")
	_add_editable_stat("Età", str(data.get("age", "---")), "age")

	# Mood
	var mood: String = data.get("mood", "neutrale")
	_mood_label.text = mood if mood != "" else "neutrale"


func _add_editable_stat(label_text: String, value: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var key_lbl := Label.new()
	key_lbl.text = label_text + ":"
	key_lbl.add_theme_font_size_override("font_size", 13)
	key_lbl.add_theme_color_override("font_color", COL_DIM)
	key_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(key_lbl)

	var val_text: String = value if value != "" else "---"

	var val_btn := Button.new()
	val_btn.text = val_text
	val_btn.flat = true
	val_btn.add_theme_font_size_override("font_size", 13)
	val_btn.add_theme_color_override("font_color", COL_TEXT)
	val_btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	val_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	val_btn.pressed.connect(_on_stat_edit.bind(key, row, val_btn))
	row.add_child(val_btn)

	_stats_container.add_child(row)


func _on_stat_edit(key: String, row: HBoxContainer, btn: Button) -> void:
	# Replace button with LineEdit for inline editing
	var edit := LineEdit.new()
	edit.text = btn.text if btn.text != "---" else ""
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_color_override("font_color", COL_TEXT)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_stylebox_override("normal", _make_panel_style(COL_INPUT_BG, COL_ACCENT, 1, 3))
	edit.add_theme_stylebox_override("focus", _make_panel_style(COL_INPUT_BG, COL_ACCENT, 1, 3))

	btn.visible = false
	row.add_child(edit)
	edit.grab_focus()

	edit.text_submitted.connect(func(new_val: String) -> void:
		_apply_stat_change(key, new_val.strip_edges())
		edit.queue_free()
		btn.visible = true
		btn.text = new_val.strip_edges() if new_val.strip_edges() != "" else "---"
	)
	edit.focus_exited.connect(func() -> void:
		var new_val := edit.text.strip_edges()
		_apply_stat_change(key, new_val)
		edit.queue_free()
		btn.visible = true
		btn.text = new_val if new_val != "" else "---"
	)


func _apply_stat_change(key: String, value: String) -> void:
	var data: Dictionary = _get_char_data()
	if data.is_empty():
		return
	# Map some key aliases
	match key:
		"sex":
			data["sex"] = value
			data["gender"] = value
		"body_type":
			data["body_type"] = value
			data["build"] = value
		_:
			data[key] = value

	if _mode == "npc":
		GameState.add_npc(data)
	GameState.game_state_changed.emit()


func _on_change_image() -> void:
	_image_file_dialog.popup_centered()


func _on_image_file_selected(path: String) -> void:
	var data: Dictionary = _get_char_data()
	data["image_path"] = path
	data["_invoke_image_name"] = ""  # Reset cached InvokeAI image
	if _mode == "npc":
		GameState.add_npc(data)
	_refresh_character_info()


func _on_paste_image() -> void:
	var img := DisplayServer.clipboard_get_image()
	if img == null or img.is_empty():
		return
	var save_path := "user://char_%s.png" % _get_char_data().get("name", "unknown").to_lower().replace(" ", "_")
	img.save_png(save_path)
	var data: Dictionary = _get_char_data()
	data["image_path"] = ProjectSettings.globalize_path(save_path)
	data["_invoke_image_name"] = ""
	if _mode == "npc":
		GameState.add_npc(data)
	_refresh_character_info()


func _refresh_slots() -> void:
	var pc: Dictionary = _get_char_data()

	for slot_key in SLOT_MAP:
		var state_key := "slot_%s" % slot_key
		var item_name: String = pc.get(state_key, "")
		var label: Label = _slot_labels[slot_key]
		var panel: PanelContainer = _slot_panels[slot_key]

		if item_name != "":
			label.text = item_name
			label.add_theme_color_override("font_color", COL_TEXT)
			panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SLOT_FILLED, COL_ACCENT, 1, 4))
		else:
			label.text = "(vuoto)"
			label.add_theme_color_override("font_color", COL_DIM)
			panel.add_theme_stylebox_override("panel", _make_panel_style(COL_SLOT_EMPTY, COL_BORDER, 1, 4))


func _refresh_inventory() -> void:
	for child in _inventory_vbox.get_children():
		child.queue_free()

	var char_name: String = _get_char_data().get("name", "")
	var items: Array = GameState.objects.filter(
		func(o: Dictionary) -> bool:
			return o.get("location", "") == "inventory" and o.get("owner", "") == char_name
	)

	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(inventario vuoto)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", COL_DIM)
		_inventory_vbox.add_child(empty_lbl)
		return

	for item in items:
		var row := _build_inventory_row(item)
		_inventory_vbox.add_child(row)


func _build_inventory_row(item: Dictionary) -> PanelContainer:
	var row_panel := PanelContainer.new()
	row_panel.add_theme_stylebox_override("panel", _make_panel_style(COL_INPUT_BG, COL_BORDER, 1, 4))
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.tooltip_text = item.get("description", "")

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	row_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	margin.add_child(hbox)

	# Item name
	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "???")
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_lbl)

	# Category badge
	var category: String = item.get("category", "")
	if category != "":
		var badge := Label.new()
		badge.text = category
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", COL_TEXT)
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = _get_badge_color(category)
		badge_style.set_corner_radius_all(3)
		badge_style.content_margin_left = 4
		badge_style.content_margin_right = 4
		badge_style.content_margin_top = 1
		badge_style.content_margin_bottom = 1
		badge.add_theme_stylebox_override("normal", badge_style)
		hbox.add_child(badge)

	# Click button (left click for options, right click for image)
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	click_btn.pressed.connect(_on_inventory_item_clicked.bind(item.get("name", "")))
	click_btn.gui_input.connect(_on_inventory_row_gui_input.bind(item.get("name", "")))
	row_panel.add_child(click_btn)

	return row_panel


func _refresh_outfit_label() -> void:
	var pc: Dictionary = _get_char_data()
	var equipped: Array = []
	for slot_key in SLOT_MAP:
		var state_key := "slot_%s" % slot_key
		var item_name: String = pc.get(state_key, "")
		if item_name != "":
			equipped.append(item_name)
	if equipped.is_empty():
		_outfit_label.text = "(nessuno)"
	else:
		_outfit_label.text = ", ".join(equipped)


# ══════════════════════════════════════════════════════════════════════════════
# Equipment Logic
# ══════════════════════════════════════════════════════════════════════════════

func _equip_item(item_name: String, slot: String) -> void:
	var pc: Dictionary = _get_char_data()
	var char_name: String = pc.get("name", "")
	var state_key := "slot_%s" % slot

	# Unequip current item in that slot first
	var current: String = pc.get(state_key, "")
	if current != "":
		_unequip_item(slot)

	# Move item from inventory to slot
	pc[state_key] = item_name

	# Update item location and owner in objects
	for i in range(GameState.objects.size()):
		if GameState.objects[i].get("name", "") == item_name:
			GameState.objects[i]["location"] = "equipped"
			GameState.objects[i]["owner"] = char_name
			break

	if _mode == "npc":
		GameState.add_npc(pc)
	_sync_outfit_array()
	_refresh_all()
	_emit_outfit_changed()


func _unequip_item(slot: String) -> void:
	var pc: Dictionary = _get_char_data()
	var char_name: String = pc.get("name", "")
	var state_key := "slot_%s" % slot
	var item_name: String = pc.get(state_key, "")
	if item_name == "":
		return

	pc[state_key] = ""

	# Move item back to inventory, keep owner
	var found := false
	for i in range(GameState.objects.size()):
		if GameState.objects[i].get("name", "") == item_name:
			GameState.objects[i]["location"] = "inventory"
			GameState.objects[i]["owner"] = char_name
			found = true
			break

	# If item doesn't exist in objects, recreate it
	if not found:
		GameState.objects.append({"name": item_name, "description": "", "category": "", "location": "inventory", "owner": char_name})

	if _mode == "npc":
		GameState.add_npc(pc)
	_sync_outfit_array()
	_refresh_all()
	_emit_outfit_changed()


func _add_item(item_data: Dictionary) -> void:
	item_data["location"] = "inventory"
	item_data["owner"] = _get_char_data().get("name", "")
	GameState.add_object(item_data)
	_refresh_inventory()


func _discard_item(item_name: String) -> void:
	GameState.remove_object(item_name)
	_refresh_inventory()


func _detect_slot_for_category(category: String) -> String:
	return CATEGORY_TO_SLOT.get(category.to_lower(), "")


func _sync_outfit_array() -> void:
	var pc: Dictionary = _get_char_data()
	var outfit: Array = []
	for slot_key in SLOT_MAP:
		var state_key := "slot_%s" % slot_key
		var item_name: String = pc.get(state_key, "")
		if item_name != "":
			outfit.append("%s: %s" % [SLOT_MAP[slot_key], item_name])
	pc["outfit"] = outfit


func _save_outfit_to_state() -> void:
	_sync_outfit_array()
	GameState.game_state_changed.emit()


func _emit_outfit_changed() -> void:
	var pc: Dictionary = _get_char_data()
	var equipped: Array = []
	for slot_key in SLOT_MAP:
		var state_key := "slot_%s" % slot_key
		var item_name: String = pc.get(state_key, "")
		if item_name != "":
			equipped.append(item_name)
	var desc := ", ".join(equipped) if equipped.size() > 0 else ""
	outfit_changed.emit(desc)


# ══════════════════════════════════════════════════════════════════════════════
# UI Callbacks
# ══════════════════════════════════════════════════════════════════════════════

func _on_slot_clicked(slot_key: String) -> void:
	var pc: Dictionary = _get_char_data()
	var state_key := "slot_%s" % slot_key
	var item_name: String = pc.get(state_key, "")
	if item_name != "":
		_unequip_item(slot_key)


func _on_inventory_item_clicked(item_name: String) -> void:
	_item_popup_name = item_name
	_show_item_popup(item_name)


func _show_item_popup(item_name: String) -> void:
	# Clear old content
	for child in _item_popup_vbox.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = item_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COL_ACCENT)
	_item_popup_vbox.add_child(title)

	# Find item data
	var item_data: Dictionary = {}
	for obj in GameState.objects:
		if obj.get("name", "") == item_name:
			item_data = obj
			break

	var category: String = item_data.get("category", "")
	var desc: String = item_data.get("description", "")

	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", COL_DIM)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_item_popup_vbox.add_child(desc_lbl)

	# Equip button (if equipment category)
	var target_slot := _detect_slot_for_category(category)
	if target_slot != "":
		var equip_btn := _make_action_button("Equipaggia (%s)" % SLOT_MAP.get(target_slot, target_slot))
		equip_btn.pressed.connect(_on_popup_equip.bind(item_name, target_slot))
		_item_popup_vbox.add_child(equip_btn)
	else:
		# Show slot selection for manual equip
		var equip_lbl := Label.new()
		equip_lbl.text = "Equipaggia in:"
		equip_lbl.add_theme_font_size_override("font_size", 13)
		equip_lbl.add_theme_color_override("font_color", COL_DIM)
		_item_popup_vbox.add_child(equip_lbl)

		var slot_row := HBoxContainer.new()
		slot_row.add_theme_constant_override("separation", 4)
		_item_popup_vbox.add_child(slot_row)

		for slot_key in SLOT_MAP:
			var slot_btn := Button.new()
			slot_btn.text = SLOT_MAP[slot_key]
			slot_btn.add_theme_font_size_override("font_size", 11)
			slot_btn.add_theme_color_override("font_color", COL_TEXT)
			slot_btn.add_theme_color_override("font_hover_color", COL_ACCENT)
			var btn_style := StyleBoxFlat.new()
			btn_style.bg_color = COL_SURFACE
			btn_style.border_color = COL_BORDER
			btn_style.set_border_width_all(1)
			btn_style.set_corner_radius_all(3)
			btn_style.content_margin_left = 4
			btn_style.content_margin_right = 4
			btn_style.content_margin_top = 2
			btn_style.content_margin_bottom = 2
			slot_btn.add_theme_stylebox_override("normal", btn_style)
			var hover_style := btn_style.duplicate()
			hover_style.border_color = COL_ACCENT
			slot_btn.add_theme_stylebox_override("hover", hover_style)
			slot_btn.pressed.connect(_on_popup_equip.bind(item_name, slot_key))
			slot_row.add_child(slot_btn)

	# Use button
	var use_btn := _make_action_button("Usa")
	use_btn.pressed.connect(_on_popup_use.bind(item_name))
	_item_popup_vbox.add_child(use_btn)

	# Discard button
	var discard_btn := _make_action_button("Scarta")
	discard_btn.add_theme_color_override("font_color", Color("e74c3c"))
	discard_btn.pressed.connect(_on_popup_discard.bind(item_name))
	_item_popup_vbox.add_child(discard_btn)

	# Close button
	var close_btn := _make_action_button("Chiudi")
	close_btn.pressed.connect(_hide_item_popup)
	_item_popup_vbox.add_child(close_btn)

	_item_popup.visible = true


func _hide_item_popup() -> void:
	_item_popup.visible = false


func _on_popup_equip(item_name: String, slot: String) -> void:
	_equip_item(item_name, slot)
	_hide_item_popup()


func _on_popup_use(item_name: String) -> void:
	# Use item: just close the popup — usage handled externally
	_hide_item_popup()


func _on_popup_discard(item_name: String) -> void:
	_discard_item(item_name)
	_hide_item_popup()


func _on_add_item_pressed() -> void:
	_add_name_edit.text = ""
	_add_desc_edit.text = ""
	_add_category_option.selected = 0
	_add_dialog.visible = true


func _on_add_dialog_confirm() -> void:
	var item_name := _add_name_edit.text.strip_edges()
	if item_name.is_empty():
		return
	var item_data := {
		"name": item_name,
		"description": _add_desc_edit.text.strip_edges(),
		"category": _add_category_option.get_item_text(_add_category_option.selected),
	}
	_add_item(item_data)
	_add_dialog.visible = false


func _on_add_dialog_cancel() -> void:
	_add_dialog.visible = false


func _on_generate_items_pressed() -> void:
	if _generating_items:
		return
	_generating_items = true

	# Build context for LLM
	var pc: Dictionary = _get_char_data()
	var context := "Character: %s. " % pc.get("name", "unknown")
	context += "Story: %s. " % GameState.story_preamble
	context += "Objective: %s. " % GameState.objective

	var current_items: Array = []
	for obj in GameState.objects:
		if obj.get("location", "") == "inventory":
			current_items.append(obj.get("name", ""))
	if current_items.size() > 0:
		context += "Current inventory: %s. " % ", ".join(current_items)

	var system := (
		"You are an RPG item generator. Respond ONLY with valid JSON. "
		+ "Generate 3-5 items that fit the story context. "
		+ 'Return: {"items":[{"name":"...","description":"...","category":"clothes|weapons|tools|food|medicine|jewelry|scrolls|machinery"}]}'
	)
	var messages := [{"role": "user", "content": "Generate items for this context:\n" + context}]
	var result: Dictionary = await LLMService.chat_json(messages, system)
	_generating_items = false

	var items: Array = result.get("items", [])
	for item in items:
		if item is Dictionary and item.get("name", "") != "":
			_add_item(item)


# ══════════════════════════════════════════════════════════════════════════════
# Item Image (right-click menu)
# ══════════════════════════════════════════════════════════════════════════════

func _on_inventory_row_gui_input(event: InputEvent, item_name: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_show_item_image_menu(item_name)


func _show_item_image_menu(item_name: String) -> void:
	_item_image_target = item_name
	# Build a simple popup
	for child in _item_popup_vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Immagine: %s" % item_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COL_ACCENT)
	_item_popup_vbox.add_child(title)

	var choose_btn := _make_action_button("Scegli Immagine")
	choose_btn.pressed.connect(_on_item_choose_image)
	_item_popup_vbox.add_child(choose_btn)

	var paste_btn := _make_action_button("Incolla Immagine")
	paste_btn.pressed.connect(_on_item_paste_image)
	_item_popup_vbox.add_child(paste_btn)

	# Show current image if exists
	var item_data: Dictionary = _find_item(item_name)
	var img_path: String = item_data.get("image_path", "")
	if img_path != "":
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(80, 80)
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var img := Image.new()
		if img.load(img_path) == OK:
			preview.texture = ImageTexture.create_from_image(img)
			_item_popup_vbox.add_child(preview)

	var close_btn := _make_action_button("Chiudi")
	close_btn.pressed.connect(_hide_item_popup)
	_item_popup_vbox.add_child(close_btn)

	_item_popup.visible = true


func _find_item(item_name: String) -> Dictionary:
	for obj in GameState.objects:
		if obj.get("name", "") == item_name:
			return obj
	return {}


func _on_item_choose_image() -> void:
	_hide_item_popup()
	if not _item_image_dialog:
		_item_image_dialog = FileDialog.new()
		_item_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_item_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_item_image_dialog.filters = PackedStringArray(["*.png", "*.jpg", "*.jpeg", "*.webp"])
		_item_image_dialog.title = "Immagine oggetto"
		_item_image_dialog.min_size = Vector2i(600, 400)
		_item_image_dialog.file_selected.connect(_on_item_image_selected)
		add_child(_item_image_dialog)
	_item_image_dialog.popup_centered()


func _on_item_image_selected(path: String) -> void:
	if _item_image_target == "":
		return
	for i in range(GameState.objects.size()):
		if GameState.objects[i].get("name", "") == _item_image_target:
			GameState.objects[i]["image_path"] = path
			break
	_refresh_inventory()


func _on_item_paste_image() -> void:
	_hide_item_popup()
	var img := DisplayServer.clipboard_get_image()
	if img == null or img.is_empty():
		return
	var safe_name := _item_image_target.to_lower().replace(" ", "_")
	var save_path := "user://item_%s.png" % safe_name
	img.save_png(save_path)
	var abs_path := ProjectSettings.globalize_path(save_path)
	for i in range(GameState.objects.size()):
		if GameState.objects[i].get("name", "") == _item_image_target:
			GameState.objects[i]["image_path"] = abs_path
			break
	_refresh_inventory()


# ══════════════════════════════════════════════════════════════════════════════
# Input
# ══════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			hide_sheet()
			get_viewport().set_input_as_handled()


# ══════════════════════════════════════════════════════════════════════════════
# Style Helpers
# ══════════════════════════════════════════════════════════════════════════════

func _make_panel_style(bg: Color, border: Color, border_width: int, corner_radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _make_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ACCENT)
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2a2a4e")
	normal.border_color = COL_BORDER
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color("3a3a6e")
	hover.border_color = COL_ACCENT
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = COL_ACCENT
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_stylebox_override("focus", hover)
	return btn


func _get_badge_color(category: String) -> Color:
	match category.to_lower():
		"clothes": return COL_BADGE_CLOTHES
		"weapons": return COL_BADGE_WEAPONS
		"tools": return COL_BADGE_TOOLS
		"food": return COL_BADGE_FOOD
		"medicine": return COL_BADGE_MEDICINE
		"jewelry": return COL_BADGE_JEWELRY
		"scrolls": return COL_BADGE_SCROLLS
		"machinery": return COL_BADGE_MACHINERY
		_: return COL_BADGE_DEFAULT

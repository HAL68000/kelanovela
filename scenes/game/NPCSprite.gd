extends CharacterBody2D

## Visual representation of an NPC on the map.
## Handles pathfinding movement, mood-based coloring, and name display.

@export var speed: float = 120.0

var npc_name: String = ""
var npc_data: Dictionary = {}

var _target_position: Vector2 = Vector2.ZERO
var _moving: bool = false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
var _name_label: Label = null
var _mood_label: Label = null

# ── Color palette for distinguishing NPCs ────────────────────────────────────
const NPC_COLORS: Array[Color] = [
	Color(0.90, 0.30, 0.35),  # red
	Color(0.30, 0.75, 0.45),  # green
	Color(0.35, 0.55, 0.90),  # blue
	Color(0.90, 0.70, 0.20),  # gold
	Color(0.75, 0.35, 0.85),  # purple
	Color(0.90, 0.50, 0.20),  # orange
	Color(0.30, 0.80, 0.80),  # teal
	Color(0.85, 0.45, 0.65),  # pink
]

# Mood → emoji mapping
const MOOD_EMOJIS: Dictionary = {
	"happy": ":)",
	"sad": ":(",
	"angry": ">:(",
	"scared": "D:",
	"neutral": ":|",
	"surprised": ":O",
	"disgusted": ":/",
	"love": "<3",
	"confused": "?",
	"tired": "-_-",
	"excited": ":D",
	"dead": "X_X",
}

var _base_color: Color = Color.WHITE
var _npc_index: int = 0


func _ready() -> void:
	# Build label nodes programmatically
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(-50, -45)
	_name_label.size = Vector2(100, 20)
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_name_label)

	_mood_label = Label.new()
	_mood_label.name = "MoodLabel"
	_mood_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mood_label.position = Vector2(-50, -58)
	_mood_label.size = Vector2(100, 16)
	_mood_label.add_theme_font_size_override("font_size", 10)
	_mood_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	add_child(_mood_label)


func setup(data: Dictionary, index: int = 0) -> void:
	npc_data = data
	npc_name = data.get("name", "NPC")
	_npc_index = index
	_base_color = NPC_COLORS[index % NPC_COLORS.size()]

	if _name_label:
		_name_label.text = npc_name
	update_appearance()


func move_to(pos: Vector2) -> void:
	_target_position = pos
	nav_agent.target_position = pos
	_moving = true


func update_appearance() -> void:
	var mood: String = npc_data.get("mood", "neutral")
	var color := get_mood_color()
	# Modulate will be applied via _draw
	queue_redraw()

	if _mood_label:
		_mood_label.text = MOOD_EMOJIS.get(mood, ":|")

	if _name_label:
		_name_label.text = npc_name


func get_mood_color() -> Color:
	var mood: String = npc_data.get("mood", "neutral")
	match mood:
		"happy":
			return _base_color.lightened(0.2)
		"sad":
			return _base_color.darkened(0.3)
		"angry":
			return _base_color.lerp(Color.RED, 0.4)
		"scared":
			return _base_color.lerp(Color.YELLOW, 0.3)
		"love":
			return _base_color.lerp(Color(1, 0.4, 0.6), 0.4)
		"dead":
			return Color(0.3, 0.3, 0.3, 0.6)
		"excited":
			return _base_color.lightened(0.3)
		_:
			return _base_color


func _draw() -> void:
	# Body circle
	var body_color := get_mood_color()
	draw_circle(Vector2.ZERO, 18.0, body_color)
	# Outline
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 32, body_color.lightened(0.3), 2.0)
	# Inner highlight
	draw_circle(Vector2(-5, -5), 5.0, Color(1, 1, 1, 0.15))


func _physics_process(_delta: float) -> void:
	if not _moving:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if nav_agent.is_navigation_finished():
		_moving = false
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next_pos: Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = next_pos - global_position

	if direction.length() < 4.0:
		_moving = false
		velocity = Vector2.ZERO
	else:
		velocity = direction.normalized() * speed

	move_and_slide()

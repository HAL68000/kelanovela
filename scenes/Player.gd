extends CharacterBody2D

@export var speed: float = 200.0
@export var door_opacity: float = 0.4

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D

var _navigating := false
var _in_door := false

func _ready():
	nav_agent.path_desired_distance = 8.0
	nav_agent.target_desired_distance = 12.0
	nav_agent.avoidance_enabled = false

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		nav_agent.target_position = get_global_mouse_position()
		_navigating = true

func _physics_process(_delta):
	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1

	if direction.length() > 0:
		_navigating = false
		velocity = direction.normalized() * speed
		move_and_slide()
		return

	if _navigating:
		if nav_agent.is_navigation_finished():
			_navigating = false
			velocity = Vector2.ZERO
		else:
			var next = nav_agent.get_next_path_position()
			var dir = (next - global_position)
			if dir.length() < 4.0:
				_navigating = false
				velocity = Vector2.ZERO
			else:
				velocity = dir.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

	# Door transparency
	var target_opacity = door_opacity if _in_door else 1.0
	sprite.modulate.a = move_toward(sprite.modulate.a, target_opacity, 0.08)

func _on_door_entered():
	_in_door = true

func _on_door_exited():
	_in_door = false

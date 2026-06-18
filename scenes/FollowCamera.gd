extends Camera2D

@export var target: Node2D
@export var map_size: Vector2 = Vector2(1856, 1408)

func _ready():
	limit_left = 0
	limit_top = 0
	limit_right = int(map_size.x)
	limit_bottom = int(map_size.y)
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	if target:
		global_position = target.global_position

func _process(_delta):
	if target:
		global_position = target.global_position
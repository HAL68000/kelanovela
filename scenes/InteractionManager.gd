extends Node2D

@export var interaction_distance: float = 50.0
@onready var player = get_node("../Player")

func _ready():
	# Connect door signals to player for transparency effect
	await get_tree().process_frame
	for obj in get_tree().get_nodes_in_group("interactive"):
		if obj is Area2D and obj.get_meta("category", "") == "door":
			obj.body_entered.connect(_on_door_body_entered)
			obj.body_exited.connect(_on_door_body_exited)

func _on_door_body_entered(body):
	if body == player:
		player._on_door_entered()

func _on_door_body_exited(body):
	if body == player:
		player._on_door_exited()

func _process(_delta):
	if Input.is_action_just_pressed("interact"):
		check_interaction()

func check_interaction():
	var player_position = player.global_position
	var objects = get_tree().get_nodes_in_group("interactive")

	for obj in objects:
		var distance = player_position.distance_to(obj.global_position)
		if distance <= interaction_distance:
			interact_with_object(obj)
			break

func interact_with_object(object):
	print("Interagendo con: ", object.name)

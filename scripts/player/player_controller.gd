extends CharacterBody3D
class_name PlayerController

## 第一人称移动占位实现：WASD 移动、鼠标视角、重力。
## 后续替换为步行/骑行状态机时保持 collision_layer 与 collision_mask 不变。

@export var move_speed := 5.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 9.8

@onready var camera: Camera3D = $Camera3D

var _pitch := 0.0


func _ready() -> void:
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_MASK
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	var input := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	if direction.length_squared() > 0.0:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

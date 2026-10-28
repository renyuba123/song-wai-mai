
extends CharacterBody3D
class_name PlayerController

## 第一人称移动 + 电鸡车头转向动画

@export_group("Movement")
@export var move_speed := 5.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 9.8

@export_group("Scooter Steering")
## 在 Inspector 中拖入 GLB 里的 Empty 节点
@export var steering_pivot: Node3D

## 车头最大左右转向角度
@export var max_steer_angle := 25.0

## 鼠标转向对车头的影响程度
@export var steer_response := 3.0

## 车头跟随目标角度的平滑速度
@export var steer_smooth_speed := 12.0

## 鼠标停止后车头回正的速度（度/秒）
@export var steer_return_speed := 25.0

@onready var camera: Camera3D = $Camera3D

## 菜单、接单和结算期间关闭移动与视角，避免鼠标操作界面时角色跟着转。
var controls_enabled := true

var _pitch := 0.0
var _steer_target := 0.0
var _steer_base_y := 0.0


func _ready() -> void:
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_MASK

	if controls_enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if steering_pivot:
		_steer_base_y = steering_pivot.rotation.y
	else:
		push_warning("未指定 Steering Pivot！")


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_steer_target = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion \
	and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:

		# 1. 原来的第一人称水平视角控制
		var yaw_delta: float = (
			-event.relative.x * mouse_sensitivity
		)

		rotate_y(yaw_delta)

		# 2. 原来的上下视角控制
		_pitch = clampf(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)

		camera.rotation.x = _pitch

		# 3. 根据鼠标左右移动控制车头
		_steer_target += yaw_delta * steer_response

		_steer_target = clampf(
			_steer_target,
			deg_to_rad(-max_steer_angle),
			deg_to_rad(max_steer_angle)
		)


func _process(delta: float) -> void:
	if steering_pivot == null:
		return

	# 平滑跟随转向目标
	var weight := 1.0 - exp(
		-steer_smooth_speed * delta
	)

	steering_pivot.rotation.y = lerp_angle(
		steering_pivot.rotation.y,
		_steer_base_y + _steer_target,
		weight
	)

	# 停止鼠标移动后逐渐回正
	_steer_target = move_toward(
		_steer_target,
		0.0,
		deg_to_rad(steer_return_speed) * delta
	)


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector(
			"move_left",
			"move_right",
			"move_forward",
			"move_back"
		)

	var direction := (
		transform.basis * Vector3(
			input.x,
			0.0,
			input.y
		)
	).normalized()

	if direction.length_squared() > 0.0:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(
			velocity.x, 0.0, move_speed
		)
		velocity.z = move_toward(
			velocity.z, 0.0, move_speed
		)

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()


func reset_to(start: SpawnPoint) -> void:
	if start == null:
		return

	global_position = start.position
	rotation = Vector3(
		0.0,
		start.facing_yaw,
		0.0
	)

	velocity = Vector3.ZERO

	_pitch = 0.0
	_steer_target = 0.0

	camera.rotation.x = 0.0

	if steering_pivot:
		steering_pivot.rotation.y = _steer_base_y

	reset_physics_interpolation()

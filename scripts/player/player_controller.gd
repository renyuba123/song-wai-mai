
extends CharacterBody3D
class_name PlayerController

## 第一人称移动 + 电鸡车头转向动画

@export_group("Movement")
@export var move_speed := 5.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 9.8

@export_group("Touch Look")
## 触屏拖动一屏宽转过的角度；按视口比例换算，避免高像素密度手机上一划就转好几圈。
@export var touch_yaw_per_screen := TAU * 0.6
## 触屏拖动一屏高转过的角度。
@export var touch_pitch_per_screen := PI * 0.55
## 触屏低头极限，比鼠标小，避免镜头一路压到车顶。
@export var touch_pitch_limit := deg_to_rad(60.0)
## 低头超过这个角度时隐藏自己的车模，否则车身占满视野。
@export var model_hide_pitch := deg_to_rad(-35.0)

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
@onready var body_model: Node3D = get_node_or_null("电鸡模型")

## 菜单、接单和结算期间关闭移动与视角，避免鼠标操作界面时角色跟着转。
var controls_enabled := true

var _pitch := 0.0
var _steer_target := 0.0
var _steer_base_y := 0.0


func _ready() -> void:
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.PLAYER_MASK

	if controls_enabled:
		_capture_mouse_if_supported()

	if steering_pivot:
		_steer_base_y = steering_pivot.rotation.y
	else:
		push_warning("未指定 Steering Pivot！")


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if enabled:
		_capture_mouse_if_supported()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_steer_target = 0.0


## 触屏设备没有可捕获的鼠标，保持可见指针，视角交给 TouchControls。
func _capture_mouse_if_supported() -> void:
	if DisplayServer.is_touchscreen_available():
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion \
	and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)


## 鼠标视角入口；参数为像素位移。
func apply_look(relative: Vector2) -> void:
	if not controls_enabled or relative == Vector2.ZERO:
		return
	_apply_look_radians(
		-relative.x * mouse_sensitivity,
		-relative.y * mouse_sensitivity,
		deg_to_rad(89.0)
	)


## 触屏视角入口；参数为画布像素位移，按视口尺寸归一化后再换算角度。
func apply_look_touch(relative: Vector2) -> void:
	if not controls_enabled or relative == Vector2.ZERO:
		return
	var view_size := get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	_apply_look_radians(
		-relative.x / view_size.x * touch_yaw_per_screen,
		-relative.y / view_size.y * touch_pitch_per_screen,
		touch_pitch_limit
	)


func _apply_look_radians(
	yaw_delta: float,
	pitch_delta: float,
	pitch_limit: float
) -> void:
	if not controls_enabled or (yaw_delta == 0.0 and pitch_delta == 0.0):
		return

	# 1. 第一人称水平视角控制
	rotate_y(yaw_delta)

	# 2. 上下视角控制
	_pitch = clampf(
		_pitch + pitch_delta,
		-pitch_limit,
		pitch_limit
	)

	camera.rotation.x = _pitch
	_update_body_visibility()

	# 3. 根据视角左右移动控制车头
	_steer_target += yaw_delta * steer_response

	_steer_target = clampf(
		_steer_target,
		deg_to_rad(-max_steer_angle),
		deg_to_rad(max_steer_angle)
	)


## 低头越过阈值时隐藏自己的车，避免第一人称视野被车身占满。
func _update_body_visibility() -> void:
	if body_model:
		body_model.visible = _pitch > model_hide_pitch


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
	_update_body_visibility()

	if steering_pivot:
		steering_pivot.rotation.y = _steer_base_y

	reset_physics_interpolation()

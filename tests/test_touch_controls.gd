extends SceneTree

## 触屏控制测试：摇杆轴向换算、死区和长度截断，以及触屏视角接口。

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_joystick_axis()
	await _check_touch_look()
	if _failed:
		printerr("FAIL touch controls")
	else:
		print("PASS touch controls")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)


func _check_joystick_axis() -> void:
	var forward := TouchControls.joystick_axis(Vector2(0.0, -90.0))
	_expect(forward.is_equal_approx(Vector2(0.0, -1.0)), "向上拖满应得到前进 -1")

	var diagonal := TouchControls.joystick_axis(Vector2(90.0, -90.0))
	_expect(
		diagonal.length() <= 1.0001,
		"斜向拖动的长度不应超过 1：%s" % diagonal
	)
	_expect(
		diagonal.x > 0.0 and diagonal.y < 0.0,
		"斜向拖动应同时产生右和前进：%s" % diagonal
	)

	var inside_deadzone := TouchControls.joystick_axis(Vector2(10.0, 0.0))
	_expect(inside_deadzone == Vector2.ZERO, "死区内应输出零向量")

	var over_radius := TouchControls.joystick_axis(Vector2(400.0, 0.0))
	_expect(
		over_radius.is_equal_approx(Vector2(1.0, 0.0)),
		"超出摇杆半径应截断为 1：%s" % over_radius
	)


func _check_touch_look() -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载玩家场景")
		return
	var player := packed.instantiate() as PlayerController
	root.add_child(player)
	await process_frame

	var yaw_before := player.rotation.y
	player.apply_look(Vector2(100.0, 0.0))
	_expect(
		not is_equal_approx(player.rotation.y, yaw_before),
		"触屏水平拖动应改变玩家朝向"
	)
	player.apply_look(Vector2(0.0, 100.0))
	_expect(
		player.camera.rotation.x < 0.0,
		"触屏向下拖动应让镜头低头"
	)

	player.set_controls_enabled(false)
	var yaw_disabled := player.rotation.y
	player.apply_look(Vector2(100.0, 0.0))
	_expect(
		is_equal_approx(player.rotation.y, yaw_disabled),
		"菜单期间触屏视角不应生效"
	)

	player.queue_free()
	await process_frame

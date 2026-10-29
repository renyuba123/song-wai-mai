extends SceneTree

## 车辆操控测试：W/S 是油门和刹车，A/D 转车把并带动整车转向，
## 转率随车速变化，静止时不能原地转身，松手后车把回正、车速滑行下降。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_handling()
	quit(1 if _failed else 0)


var _failed := false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL player handling: ", message)


func _physics_steps(player: PlayerController, count: int) -> void:
	for _step in count:
		player._physics_process(1.0 / 60.0)


func _process_steps(player: PlayerController, count: int) -> void:
	for _step in count:
		player._process(0.1)


func _planar_speed(player: PlayerController) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _check_handling() -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载玩家场景")
		return
	var player := packed.instantiate() as PlayerController
	root.add_child(player)
	await process_frame
	if player.steering_pivot == null:
		_expect(false, "玩家场景缺少车把节点")
		player.queue_free()
		return

	# 1. 满油门四秒后接近最高车速，且不会超过。
	Input.action_press("move_forward")
	_physics_steps(player, 240)
	var top_speed := _planar_speed(player)
	_expect(
		top_speed > player.move_speed * 0.9,
		"满油门后车速应接近最高车速，实际 %.2f" % top_speed
	)
	_expect(
		top_speed <= player.move_speed + 0.01,
		"车速不应超过最高车速，实际 %.2f" % top_speed
	)

	# 2. 转动视角只动相机，不改车头方向和前进方向。
	var heading_before_look := player.rotation.y
	player.apply_look(Vector2(160.0, 0.0))
	_expect(
		is_equal_approx(player.rotation.y, heading_before_look),
		"转动视角不应改变车头方向"
	)
	_expect(
		not is_zero_approx(player.camera.rotation.y),
		"鼠标视角应转动相机"
	)

	# 3. 行驶中按 A：车把向左转，整车也向左转，两者方向一致。
	var yaw_before := player.rotation.y
	Input.action_press("move_left")
	_physics_steps(player, 30)
	_process_steps(player, 8)
	_expect(
		player.rotation.y > yaw_before + 0.1,
		"按住 A 时整车应向左转"
	)
	_expect(
		player.steering_pivot.rotation.y > 0.02,
		"按住 A 时车把应向左转"
	)

	# 4. 松开 A 后车把回正。
	Input.action_release("move_left")
	_physics_steps(player, 12)
	_process_steps(player, 4)
	_expect(
		absf(player.steering_pivot.rotation.y) < 0.03,
		"松开 A 后车把应回正，实际 %.3f" % player.steering_pivot.rotation.y
	)

	# 5. 松开油门后滑行减速并停下。
	Input.action_release("move_forward")
	_physics_steps(player, 180)
	_expect(
		_planar_speed(player) < 0.1,
		"松开油门后应滑行停下，实际 %.2f" % _planar_speed(player)
	)

	# 6. 静止时按 A 只转车把，不原地转身。
	var stopped_yaw := player.rotation.y
	Input.action_press("move_left")
	_physics_steps(player, 30)
	_process_steps(player, 6)
	Input.action_release("move_left")
	_expect(
		is_equal_approx(player.rotation.y, stopped_yaw),
		"静止时不应原地转身"
	)
	_expect(
		player.steering_pivot.rotation.y > 0.02,
		"静止时车把仍应能转动"
	)
	_process_steps(player, 12)

	# 7. 按 S 先刹车再倒车，速度方向朝车尾。
	Input.action_press("move_forward")
	_physics_steps(player, 90)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	_physics_steps(player, 150)
	Input.action_release("move_back")
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_expect(
		player.velocity.dot(forward) < -0.5,
		"按住 S 应倒车，沿车头方向的速度 %.2f" % player.velocity.dot(forward)
	)

	player.queue_free()
	await process_frame
	if not _failed:
		print("PASS player handling")

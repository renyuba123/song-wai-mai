extends SceneTree

## 输入映射测试：确认动作存在、按键正确，并验证玩家移动读取的是动作而不是物理按键。

const EXPECTED := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"interact": KEY_E,
	"pause": KEY_ESCAPE,
	"restart": KEY_R,
	"order_accept": KEY_Y,
	"order_reject": KEY_N,
}

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_actions()
	await _check_player_movement()
	if _failed:
		printerr("FAIL input actions")
	else:
		print("PASS input actions count=", EXPECTED.size())
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)


func _check_actions() -> void:
	for action in EXPECTED:
		if not InputMap.has_action(action):
			_expect(false, "缺少输入动作 %s" % action)
			continue
		var found := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode == EXPECTED[action]:
				found = true
		_expect(found, "输入动作 %s 未绑定物理键码 %d" % [action, EXPECTED[action]])


func _check_player_movement() -> void:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	if packed == null:
		_expect(false, "无法加载玩家场景")
		return
	var player := packed.instantiate() as PlayerController
	root.add_child(player)
	await process_frame
	Input.action_press("move_forward")
	player._physics_process(0.016)
	Input.action_release("move_forward")
	_expect(player.velocity.z < 0.0, "按下前进动作后玩家没有向前移动")
	player.queue_free()
	await process_frame

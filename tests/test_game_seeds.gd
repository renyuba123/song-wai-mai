extends SceneTree

## 种子随机性测试：固定、启动参数、环境变量和随机取值范围。

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	GameSeeds.release_pins()
	_expect(GameSeeds.is_city_random(), "没有固定和参数时城市种子应随机")
	var first := GameSeeds.city_seed()
	var second := GameSeeds.order_seed()
	_expect(
		first >= 1 and first <= GameSeeds.MAX_SEED,
		"随机城市种子应在 1..%d：%d" % [GameSeeds.MAX_SEED, first]
	)
	_expect(
		second >= 1 and second <= GameSeeds.MAX_SEED,
		"随机订单种子应在 1..%d：%d" % [GameSeeds.MAX_SEED, second]
	)

	GameSeeds.pin(118, 1)
	_expect(GameSeeds.city_seed() == 118, "固定后城市种子应保持不变")
	_expect(GameSeeds.order_seed() == 1, "固定后订单种子应保持不变")
	_expect(not GameSeeds.is_city_random(), "固定种子时不应再自动换种子")
	GameSeeds.release_pins()

	_expect(
		GameSeeds.override_seed(PackedStringArray(["--city-seed", "2024"]), "--city-seed", "")
		== 2024,
		"启动参数应能指定城市种子"
	)
	_expect(
		GameSeeds.override_seed(PackedStringArray(["--order-seed"]), "--order-seed", "") == 0,
		"参数缺值时应回落到随机"
	)
	_expect(
		GameSeeds.override_seed(PackedStringArray(), "--order-seed", " 42 ") == 42,
		"环境变量应能指定订单种子"
	)
	_expect(
		GameSeeds.override_seed(PackedStringArray(["--order-seed", "abc"]), "--order-seed", "") == 0,
		"非法参数值应忽略"
	)
	_expect(
		GameSeeds.override_seed(PackedStringArray(["--city-seed", "0"]), "--city-seed", "") == 0,
		"0 表示随机，不作为固定值"
	)

	if _failed:
		printerr("FAIL game seeds")
	else:
		print("PASS game seeds city=%d order=%d" % [first, second])
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL ", message)

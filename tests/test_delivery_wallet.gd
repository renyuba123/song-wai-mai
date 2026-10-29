extends SceneTree

## 配送账户测试：初始余额、收入累计、撞车赔偿、清零和重置。

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_starting_state()
	_check_income()
	_check_compensation()
	_check_reset()
	if _failed:
		printerr("FAIL delivery wallet")
	else:
		print("PASS delivery wallet")
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL delivery wallet: ", message)


func _check_starting_state() -> void:
	var wallet := DeliveryWallet.new()
	_expect(
		is_equal_approx(wallet.balance, 500.0),
		"初始余额应为 500，实际 %s" % wallet.balance
	)
	_expect(is_zero_approx(wallet.order_income), "初始本单收入应为 0")
	_expect(is_zero_approx(wallet.total_income), "初始累计收入应为 0")
	_expect(is_zero_approx(wallet.total_compensation), "初始累计赔偿应为 0")


func _check_income() -> void:
	var wallet := DeliveryWallet.new()
	var changes := [0]
	wallet.changed.connect(func() -> void: changes[0] += 1)

	wallet.add_income(12.5)
	_expect(is_equal_approx(wallet.balance, 512.5), "收入应加到余额：%s" % wallet.balance)
	_expect(is_equal_approx(wallet.order_income, 12.5), "本单收入应更新")
	_expect(is_equal_approx(wallet.total_income, 12.5), "累计收入应更新")

	wallet.add_income(7.5)
	_expect(is_equal_approx(wallet.balance, 520.0), "第二单收入应继续累加")
	_expect(is_equal_approx(wallet.order_income, 7.5), "本单收入应只保留最后一单")
	_expect(is_equal_approx(wallet.total_income, 20.0), "累计收入应为两单之和")

	wallet.clear_order_income()
	_expect(is_zero_approx(wallet.order_income), "清零后本单收入应为 0")
	_expect(is_equal_approx(wallet.balance, 520.0), "清零不应影响余额")
	_expect(is_equal_approx(wallet.total_income, 20.0), "清零不应影响累计收入")

	wallet.add_income(-5.0)
	_expect(is_equal_approx(wallet.balance, 520.0), "负数收入不应扣钱")

	_expect(changes[0] == 4, "每次变动都应发一次 changed，实际 %d 次" % changes[0])


func _check_compensation() -> void:
	var wallet := DeliveryWallet.new()
	wallet.add_income(9.0)
	wallet.add_compensation(DeliveryWallet.HIT_COMPENSATION)
	_expect(
		is_equal_approx(wallet.balance, 500.0 + 9.0 - 50.0),
		"撞车赔偿应从余额里扣：%s" % wallet.balance
	)
	_expect(is_zero_approx(wallet.order_income), "赔偿后本单收入应清零")
	_expect(
		is_equal_approx(wallet.total_compensation, 50.0),
		"累计赔偿应为 50：%s" % wallet.total_compensation
	)
	_expect(is_equal_approx(wallet.total_income, 9.0), "赔偿不应影响累计收入")

	wallet.add_compensation(0.0)
	_expect(
		is_equal_approx(wallet.total_compensation, 50.0),
		"零赔偿不应累计"
	)


func _check_reset() -> void:
	var wallet := DeliveryWallet.new()
	wallet.add_income(30.0)
	wallet.add_compensation(50.0)
	wallet.reset()
	_expect(is_equal_approx(wallet.balance, 500.0), "重置后余额应回到 500")
	_expect(is_zero_approx(wallet.order_income), "重置后本单收入应为 0")
	_expect(is_zero_approx(wallet.total_income), "重置后累计收入应为 0")
	_expect(is_zero_approx(wallet.total_compensation), "重置后累计赔偿应为 0")

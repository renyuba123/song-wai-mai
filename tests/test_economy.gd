extends SceneTree

## Delivery income and pedestrian compensation accounting.

var _failed := false
var _hud: EconomyHUD = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_hud = EconomyHUD.new()
	_hud.starting_balance = 500
	root.add_child(_hud)
	await process_frame
	_check_economy()
	if _failed:
		printerr("FAIL economy")
	else:
		print("PASS economy")
	if _hud != null:
		_hud.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL economy: ", message)


func _check_economy() -> void:
	_expect(_hud.get_balance() == 500, "初始余额错误")
	_expect(_hud.get_current_order_income() == 0, "初始本单收入应为 0")
	_hud.begin_order()
	var income := _hud.record_successful_delivery(100.0, 20.0)
	_expect(income == 316, "订单收入公式错误")
	_expect(DeliveryIncome.calculate(100.0, 20.0) == income, "收支面板与 DeliveryIncome 公式不一致")
	_expect(DeliveryIncome.calculate(0.0, 0.0) == 180, "保底收入错误")
	_expect(DeliveryIncome.calculate(-5.0, -5.0) == 180, "负值路程和时间应按 0 处理")
	_expect(_hud.get_total_income() == 316, "累计收入没有增加")
	_expect(_hud.get_current_order_income() == 316, "本单收入没有更新")
	_expect(_hud.get_balance() == 816, "订单完成后余额错误")
	_hud.add_compensation(120)
	_expect(_hud.get_total_compensation() == 120, "累计赔偿没有增加")
	_expect(_hud.get_balance() == 696, "赔偿后余额错误")
	var summary := _hud.get_summary_text()
	_expect(summary.contains("¥316") and summary.contains("¥120"), "收支摘要缺少带 ¥ 的关键数值")
	_hud.begin_order()
	_expect(_hud.get_current_order_income() == 0, "开始新订单没有清空本单收入")
	_expect(_hud.get_balance() == 696, "开始新订单不应改变余额")
	_hud.reset_economy()
	_expect(_hud.get_balance() == 500, "重置后余额错误")
	_expect(_hud.get_total_income() == 0, "重置后累计收入错误")
	_expect(_hud.get_total_compensation() == 0, "重置后累计赔偿错误")

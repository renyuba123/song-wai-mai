extends RefCounted
class_name DeliveryWallet

## 配送账户：初始余额、本单收入、累计收入和撞车赔偿。
## 只负责记账，不碰界面；OrderHUD 订阅 changed 信号刷新右上角面板，
## 其他模块（如行为采集）也可以直接读这些字段。

signal changed

## 每局开始时骑手身上的余额。
const STARTING_BALANCE := 500.0
## 被汽车撞倒后要赔的钱。
const HIT_COMPENSATION := 50.0

var balance := STARTING_BALANCE
## 当前这一单的收入；新订单、失败和重开都会清零。
var order_income := 0.0
var total_income := 0.0
var total_compensation := 0.0


## 回到主菜单或重新开局时把账户恢复成初始状态。
func reset() -> void:
	balance = STARTING_BALANCE
	order_income = 0.0
	total_income = 0.0
	total_compensation = 0.0
	changed.emit()


## 订单结束时登记收入。
func add_income(amount: float) -> void:
	var value := maxf(amount, 0.0)
	order_income = value
	balance += value
	total_income += value
	changed.emit()


## 撞车失败时扣赔偿，同时清掉本单收入。
func add_compensation(amount: float) -> void:
	var value := maxf(amount, 0.0)
	if value <= 0.0:
		return
	order_income = 0.0
	balance -= value
	total_compensation += value
	changed.emit()


## 只清掉“本单收入”，累计值保留；超时失败和新订单开始时用。
func clear_order_income() -> void:
	if is_zero_approx(order_income):
		return
	order_income = 0.0
	changed.emit()

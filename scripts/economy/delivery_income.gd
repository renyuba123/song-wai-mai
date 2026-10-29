extends RefCounted
class_name DeliveryIncome

## 配送收入公式：成功送达按路程和剩余时间入账。
## 手机接单页的“预计收入”、结算页的“本单收入”和右上角收支面板
## 都调用这里，保证显示金额和实际入账完全一致。

const BASE_INCOME := 180
const INCOME_PER_METER := 1.2
const BONUS_PER_SECOND := 0.8


static func calculate(distance_m: float, remaining_s: float) -> int:
	var distance_bonus := roundi(maxf(distance_m, 0.0) * INCOME_PER_METER)
	var time_bonus := roundi(maxf(remaining_s, 0.0) * BONUS_PER_SECOND)
	return BASE_INCOME + distance_bonus + time_bonus

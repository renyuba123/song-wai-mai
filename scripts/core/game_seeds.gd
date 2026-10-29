extends RefCounted
class_name GameSeeds

## 每局开始时给城市和订单重新取随机种子，避免每次都是同一座城市、同一串订单。
##
## 需要复现某一局时（调试、录像、写测试），用启动参数写在 `--` 之后：
##
##     Godot_v4.7.2-stable_win64_console.exe --path . -- --city-seed 118 --order-seed 1
##
## 也可以设置环境变量 SWM_CITY_SEED / SWM_ORDER_SEED，方便在编辑器里运行。
## 测试和录制脚本用 pin() 固定种子，行为和旧版一致。

const CITY_FLAG := "--city-seed"
const ORDER_FLAG := "--order-seed"
const CITY_ENV := "SWM_CITY_SEED"
const ORDER_ENV := "SWM_ORDER_SEED"
## 种子取值上限，用质数，种子短一点方便在 HUD 上读和记。
const MAX_SEED := 999983

static var _city_pin := 0
static var _order_pin := 0


## 固定种子。测试和录制脚本在加载主场景之前调用。
static func pin(city: int, order: int) -> void:
	_city_pin = maxi(city, 0)
	_order_pin = maxi(order, 0)


static func release_pins() -> void:
	_city_pin = 0
	_order_pin = 0


## 本局城市种子：固定值优先，其次启动参数/环境变量，最后随机。
static func city_seed() -> int:
	if _city_pin > 0:
		return _city_pin
	var override := override_seed(OS.get_cmdline_user_args(), CITY_FLAG, OS.get_environment(CITY_ENV))
	return override if override > 0 else random_seed()


## 本局第一个订单的种子。后续订单在它基础上递增，保证同一局可以复现。
static func order_seed() -> int:
	if _order_pin > 0:
		return _order_pin
	var override := override_seed(OS.get_cmdline_user_args(), ORDER_FLAG, OS.get_environment(ORDER_ENV))
	return override if override > 0 else random_seed()


## 城市种子是否由程序随机决定；随机时才允许生成失败后自动换种子。
static func is_city_random() -> bool:
	if _city_pin > 0:
		return false
	return override_seed(OS.get_cmdline_user_args(), CITY_FLAG, OS.get_environment(CITY_ENV)) <= 0


## 从 `flag value` 形式的参数或环境变量里取正整数；没有或格式不对时返回 0。
static func override_seed(args: PackedStringArray, flag: String, env_value: String) -> int:
	var index := args.find(flag)
	if index >= 0 and index + 1 < args.size():
		var from_arg := args[index + 1].strip_edges().to_int()
		if from_arg > 0:
			return from_arg
	var from_env := env_value.strip_edges().to_int()
	return from_env if from_env > 0 else 0


static func random_seed() -> int:
	var bytes := Crypto.new().generate_random_bytes(4)
	return int(bytes.decode_u32(0) % MAX_SEED) + 1

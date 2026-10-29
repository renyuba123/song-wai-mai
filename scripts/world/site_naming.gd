extends RefCounted
class_name SiteNaming

## 给商家/顾客站点分配稳定的中文店名。店名由最终选中的建筑模型决定，
## 再用站点 ID 做确定性挑选，因此同一城市种子和布局总是得到同一组名字。

const NAMES := {
	"bakery": ["麦香面包房", "晴天烘焙坊", "老街面包店"],
	"coffee": ["转角咖啡", "晨光咖啡", "街角咖啡"],
	"Pizza": ["火光披萨", "芝士披萨屋", "街坊披萨"],
	"Resturant": ["家常菜馆", "巷口餐厅", "好味餐厅"],
	"mini_market": ["邻里便利店", "小满超市", "24 小时便利店"],
	"confectionery": ["甜心甜品店", "奶油甜品屋", "糖霜烘焙"],
	"mall": ["城市广场", "万象商场"],
	"hotel": ["云栖酒店", "城市酒店"],
	"school": ["实验小学", "育才学校"],
	"bank": ["城市银行", "民生储蓄所"],
	"book_shop": ["拾光书店", "学海书店"],
	"gym": ["动力健身房", "活力健身"],
	"cinema": ["星光影城", "城市影院"],
	"bar": ["夜航酒吧", "街尾酒吧"],
}


static func apply(city: CityContent, layout: CityPopulationLayout) -> void:
	## 布局生成后把店名写回 CitySite，HUD、订单目标和三维标牌共用同一份。
	if city == null or layout == null:
		return
	var items := {}
	for item in layout.buildings:
		var site_id := String(item.get("site_id", ""))
		if not site_id.is_empty():
			items[site_id] = item
	for site in city.sites:
		if site == null:
			continue
		var item: Dictionary = items.get(String(site.id), {})
		if item.is_empty():
			site.display_name = ""
			continue
		site.display_name = name_for_path(
			String(item.get("path", "")), String(site.id)
		)


static func name_for_path(path: String, site_id: String) -> String:
	var model_name := path.get_file().get_basename()
	var choices: Array = NAMES.get(model_name, [])
	if choices.is_empty():
		return ""
	var index := _hash(site_id) % choices.size()
	return String(choices[index])


static func _hash(text: String) -> int:
	## 不依赖 String.hash() 的实现细节，保证跨平台、跨运行稳定。
	var value := 0
	for index in text.length():
		value = (value * 31 + text.unicode_at(index)) % 2147483647
	return value

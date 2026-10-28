# 城市建筑布置（Seed 118）

> 历史静态样例保留。当前主场景已升级为任意 Seed 与区块加载，操作方法见 [CITY_STREAMING.md](CITY_STREAMING.md)。下文记录静态布置阶段的实现。

这是已接入 `scenes/main/main.tscn` 的实际布置，资源位于 `assets/models/`，不是 `assets/model/`。直接打开主场景即可看到编辑器生成的道路及保存的模型；无需先运行生成工具。

## 查看与编辑

使用 Godot 4.7.2 打开项目，打开 `scenes/main/main.tscn`。展开 `World/CityPopulation`，或直接打开 `scenes/city/city_population.tscn`，选择 `GeneratedBuildings/merchant_007` 后按 F 聚焦。主场景 F5 可运行，F3 为已有俯视调试视角。独立布置场景只保存建筑、碰撞、入口和绿化，道路由主场景的 World 工具脚本预览。

`GeneratedBuildings` 下的 merchant/customer 节点对应实际站点 ID；`GeneratedDecorations` 为绿化。逐点坐标和模型映射见 `scenes/city/delivery_sites.json`。编辑独立布置场景可以持久保存；重新运行烘焙工具会覆盖此布置场景，不应在手工编辑后直接重烘焙。

## 已完成内容

- 12 个取餐点：bakery、coffee、Pizza、Resturant、mini_market、confectionery，各 2 栋。保留原资源名称拼写。
- 20 个送餐点：hotel、school、bank、book_shop、gym、cinema 各 3 栋，bar 2 栋。这些是仓库现有的送餐目的地建筑，并非全部为住宅。
- 208 栋其他建筑：使用其他建筑目录的公寓楼、Asset_0002、Asset_0011，形成住宅与高层轮廓。
- 174 个树木实例：装饰目录 Asset_0004。通过模型几何投影识别为树木，放在建筑侧边退让带，入口中轴留空。
- 32 条门前铺装和 32 个近距离地址标识，不计入树木数量。

从真实主场景导航生成首单（订单 Seed 1，merchant_007 到 customer_007），优先覆盖该导航路线 85 米范围的地块，再补齐其他任务点周围临街建筑。所有 32 个站点为最高优先级。其余 1397 栋原有占位建筑保留为远景，未追求整张 2400 米地图的高精度模型替换。未布置用途尚未可靠辨认的匿名装饰；未新增交通灯逻辑。

## 地图与功能兼容

原 World 仍生成 RoadNetwork、CityContent、导航和交通。CityBuilder 仅跳过本次已保存的 240 个建筑 ID 的占位视觉和碰撞；实际模型具有与包围盒匹配的简单实体碰撞。城市地块、玩家起点、任务坐标、订单状态机与车辆逻辑不变。

模型统一按完整层级变换后的包围盒等比缩放、贴地，限制在已验证的建筑矩形内，并向临街侧对齐。绿化限制在地块侧边。烘焙检查所有模型投影的相互重叠；测试进一步检查道路红线（含人行道与交叉口）、任务点一米净空及门前路径。入口铺装通向原人行道触发点，因此接单、取餐、送餐仍使用原任务系统。

布置只适用于原尺寸/路网参数的 Seed 118。切换 Seed 时，已烘焙场景隐藏并关闭碰撞，恢复原有占位生成；不会把旧建筑留在新道路上。若修改地图尺寸、生成算法或地块契约，必须重新烘焙并运行空间检查。

## 重建和验证

在仓库根目录运行（先激活本环境的 Godot 4.7.2）：

```sh
godot --headless --path . --script res://scripts/dev/bake_city_population.gd
godot --headless --path . --import
godot --headless --path . --script res://tests/test_city_population.gd
```

烘焙工具读取已经接入的主场景来获得实际首单导航，不修改源模型。已运行原有九组测试，并增加空间布局与 Seed 切换回归测试。最后调整布局后重新检查主场景、订单、导航、交通和空间布局。

尚未进行 GPU 图形界面的最终视觉验收：模型真实正门是否与选定临街面一致、材质贴图、透视下细部穿插、玩家视角遮挡及实际帧率需要在 Godot 编辑器人工检查。包围盒碰撞偏保守，不支持进入建筑内部。当前保留已有玩法；没有新增手机或骑行系统。

# 大城市送外卖

一款计划以第一人称游玩的 3D 外卖配送游戏。玩家在程序化生成的城市里扮演外卖员：从随机位置出发，前往商家取餐，再把餐送到随机生成的目的地。每次生成的路网和订单路线都可以不同；路上的车辆、行人和其他障碍让配送过程需要观察、绕行与选择路线。

> **当前状态：阶段二最小可玩配送闭环（实现完成，等待 PR 合并）。** 路网数据、城市、玩家、导航、交通和订单已经拆成独立模块；城市会生成人行道、地块、建筑和商家/顾客站点，每张订单从多个安全起点中随机选择，玩家可以按 E 取餐、送达，按 R 重开或生成下一单。详细里程碑见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 计划中的玩法

1. **生成城市。** 根据地图尺寸、随机种子和道路密度生成连通的主干路、次干路与支路，再按真实街道几何生成地块、出入口、建筑、商家和住宅站点。
2. **生成订单。** 每局随机选择外卖员起点、商家取餐点和顾客送达点。三处位置必须可由路网抵达，并避开交叉口与不安全的道路位置。订单距离和预计配送时间随地图规模调整。
3. **第一人称配送。** 玩家以外卖员视角观察道路、寻找商家、取餐并前往终点。计划支持步行或骑行、路线提示和基本交互。
4. **应对城市交通。** 车辆沿道路行驶，行人在人行区域活动；施工围挡、停靠车辆、临时封路等障碍改变可走路线。玩家需要绕行、遵守交通规则，并在限定时间内安全送达。
5. **结算与重玩。** 送达后根据用时和安全情况结算，再生成新订单。随机种子可用于复现同一座城市，便于测试和分享。

## 目录与模块

```text
assets/                 模型、贴图、音频（二进制资源走 Git LFS）
.githooks/              阻止直接提交/推送 main 的本地 hooks
scripts/
  core/                 main.gd、碰撞层常量等共享装配
  world/                RoadNetwork / CityContent 数据、城市生成、出生点契约与绘制
  orders/               订单数据契约、确定性生成、状态机、HUD 与运行时管理器
  player/               第一人称控制
  navigation/           导航网格烘焙与导航查询服务
  traffic/              车辆/行人入口
  demo/                 路网演示的相机、灯光和调试 UI
  dev/                  分支管理 hooks、本地清理脚本与测试用工具
scenes/
  main/main.tscn        主场景，按 F5 运行
  world/world.tscn      可复用的世界生成场景（含天空环境）
  world/sky_environment.tres  程序化天空、环境光与反射
  player/player.tscn
  navigation/navigation_system.tscn
  traffic/traffic_system.tscn
  demo/city_road_demo.tscn  路网演示，按 F6 单独运行
tests/
  test_road_network.gd      路网生成、校验、寻路测试
  test_main_scene.gd        主场景启动与导航就绪冒烟测试
  test_contracts.gd         出生点、站点和订单数据契约测试
  test_input_actions.gd     输入动作与玩家移动测试
  test_navigation_queries.gd 导航查询接口测试
  test_city.gd              城市地块、建筑、站点、随机起点与可达性测试
  test_god_view.gd          测试用上帝视角开关与状态恢复测试
  test_orders.gd            订单确定性、状态机、HUD 与重开/超时测试
docs/
  ROADMAP.md            已确认的开发路线图
  DEVELOPMENT_LOG.md    每轮开发日志
  USER_GUIDE.md         各角色操作方法与注意事项
```

模块边界与文件所有权、日志和提交流程见 [CONTRIBUTING.md](CONTRIBUTING.md)；建模、世界生成、玩家、导航、技术美术的具体操作见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

## 运行与校验

使用 Godot 4.7 打开本目录。按 **F5** 运行 `scenes/main/main.tscn`；按 **F6** 单独运行 `scenes/demo/city_road_demo.tscn` 查看路网演示。

运行自动校验：

```powershell
godot --headless --path . --import
godot --headless --path . --script res://tests/test_road_network.gd
godot --headless --path . --script res://tests/test_main_scene.gd
godot --headless --path . --script res://tests/test_contracts.gd
godot --headless --path . --script res://tests/test_input_actions.gd
godot --headless --path . --script res://tests/test_navigation_queries.gd
godot --headless --path . --script res://tests/test_city.gd
godot --headless --path . --script res://tests/test_god_view.gd
godot --headless --path . --script res://tests/test_orders.gd
```

路网、道路绘制、碰撞和导航共用同一份 `RoadNetwork`。所有距离单位为米，**1 个 Godot 世界单位 = 1 米**。相同参数和随机种子生成相同的路网。

## 当前实现范围

- 主干路、次干路、支路三种等级，红线宽度与车行道宽度分别处理。
- 地图宽高、随机种子、道路密度和红线宽度可在 `WorldGenerator` 的 Inspector 中调整。
- 道路中心线、交叉口和可碰撞几何来自同一份节点与路段数据。
- `RoadNetwork.find_route(起点节点编号, 终点节点编号)` 返回连通路径。
- 运行时校验道路宽度、连通性、交叉口连接数与夹角、交叉口间距及几何相交。
- 阶段零已定义 `SpawnPoint`、`CitySite`、`DeliveryOrder` 数据契约，冻结 `RoadNetwork` 字段，并增加移动、交互、暂停、重开输入动作。
- `NavigationService` 提供就绪判断、最近可导航点、路径、可达性和路径长度查询，其他模块不直接读取 `NavigationRegion3D`。
- `CityGenerator` 从真实路段生成 `CityContent`：地块、出入口、建筑、商家/顾客站点和多个安全玩家起点；相同城市种子结果一致。
- `CityContent.validate(network)` 校验地块重叠、建筑归属、出入口退让、站点交叉引用和玩家起点安全位置；`player_start` 与 `player_starts` 首项保持兼容。
- `OrderGenerator` 使用独立的订单种子和 RNG 盐，从可达的随机起点/商家/顾客组合中确定性生成订单；`OrderSession` 处理取餐、送达、单笔倒计时和超时。
- `OrderManager` 等待导航就绪后生成首单、把玩家传送到订单起点、维护目标信标和 HUD；按 E 交互，配送中按 R 重开同一单，结算后按 R 生成下一单。
- `CityBuilder` 绘制人行道、方块建筑和站点标记；人行道与建筑有碰撞，但阶段一不加入导航源，导航网格仍只覆盖车行道。
- `World` 场景包含 `WorldEnvironment`，引用 `sky_environment.tres` 的程序化天空，提供可见天空、环境光和反射；主场景和路网演示共用。
- 调试/测试构建中按 **F3** 打开测试用上帝视角：正交俯视、WASD 平移、滚轮缩放，再按 F3 返回玩家。正式导出不会创建该节点，也不注册额外输入动作。
- 玩家第一人称移动、导航网格烘焙、交通模块入口和阶段二订单闭环已经接好；车辆/行人资产尚未实现。
- 阶段二 HUD 显示当前目标、距离、倒计时、城市/订单种子、方向箭头和 E 提示；成功或失败后显示结算面板。

当前主场景示例输出约为 152 个地块、152 栋建筑、40 个出入口、32 个站点和 12 个安全玩家起点（2400 米地图、种子 42、密度 0.5）。所有可走表面统一在 `RoadNetwork.SURFACE_Y = 0`，视觉网格只做几厘米的错层以避免闪烁。为使支路接入次干路，部分次干路交叉口间距低于建议的 300 米，但仍满足 150 米硬下限。当前城市没有高架、匝道或交通信号，建筑内部和人行道导航留给后续阶段。

## 后续开发顺序

详细到阶段目标、负责人和验收标准的版本见 [docs/ROADMAP.md](docs/ROADMAP.md)。下面是高层顺序：

- 阶段二订单闭环已完成，等待 PR 合并；下一步完善路线提示和玩家移动体验。
- 加入车辆、行人、交通规则及动态障碍，让配送过程需要观察和绕行。
- 补齐正式美术、界面素材和发布检查。

## Git 与资源文件

`.gitattributes` 将模型、贴图、音频、字体及 Godot 二进制资源交给 Git LFS；`.gd`、`.tscn`、`.tres`、`.svg` 等文本文件仍由普通 Git 管理。新克隆本仓库的电脑需要安装 Git LFS，并在仓库中执行 `git lfs install --local`。

`.tscn` 和 `.tres` 使用 `gdmerge` 处理本地三方合并。每位协作者需在自己的电脑安装并运行一次 `gdmerge git-install`。安装命令：`cargo install gdmerge --version 0.3.6 --locked`。

## Pull Request 检查

`.github/workflows/repository-integrity.yml` 会在 Pull Request 上运行 `git lfs fsck --pointers`，发现损坏的 LFS 指针时让检查失败。它还会读取同一目标分支上的其他开放 Pull Request；如果多个 PR 同时修改同一个 `.tscn`，会在对应文件上给出 GitHub Actions 警告，提醒合并前一起检查场景文件。同一任务会安装固定版本 Godot 4.7.2，执行 headless 导入并运行全部八个测试脚本，任一测试非零退出都会让检查失败。

团队协作规则、每轮日志和远端同步要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。各角色从环境准备到交付的具体步骤和注意事项见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

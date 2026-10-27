# 大城市送外卖

一款计划以第一人称游玩的 3D 外卖配送游戏。玩家在程序化生成的城市里扮演外卖员：从随机位置出发，前往商家取餐，再把餐送到随机生成的目的地。每次生成的路网和订单路线都可以不同；路上的车辆、行人和其他障碍让配送过程需要观察、绕行与选择路线。

> **当前状态：模块化基础。** 路网数据、生成、绘制、玩家、导航和交通已经拆成独立模块，主场景可以运行；外卖订单、建筑、车辆与行人的具体玩法仍在开发中。

## 计划中的玩法

1. **生成城市。** 根据地图尺寸、随机种子和道路密度生成连通的主干路、次干路与支路；后续在街区中生成建筑、商家、住宅和可进入的地块。
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
  world/                RoadNetwork 数据、RoadGenerator、RoadBuilder、WorldGenerator
  player/               第一人称控制
  navigation/           导航网格烘焙与导航服务
  traffic/              车辆/行人入口
  demo/                 路网演示的相机、灯光和调试 UI
  dev/                  分支管理 hooks 安装与本地清理脚本
scenes/
  main/main.tscn        主场景，按 F5 运行
  world/world.tscn      可复用的世界生成场景
  player/player.tscn
  navigation/navigation_system.tscn
  traffic/traffic_system.tscn
  demo/city_road_demo.tscn  路网演示，按 F6 单独运行
tests/
  test_road_network.gd  路网生成、校验、寻路测试
docs/
  DEVELOPMENT_LOG.md    每轮开发日志
  USER_GUIDE.md         各角色操作方法与注意事项
```

模块边界与文件所有权、日志和提交流程见 [CONTRIBUTING.md](CONTRIBUTING.md)；建模、世界生成、玩家、导航、技术美术的具体操作见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

## 运行与校验

使用 Godot 4.7 打开本目录。按 **F5** 运行 `scenes/main/main.tscn`；按 **F6** 单独运行 `scenes/demo/city_road_demo.tscn` 查看路网演示。

运行路网自动校验：

```powershell
godot --headless --path . --script res://tests/test_road_network.gd
godot --headless --path . --script res://tests/test_main_scene.gd
```

路网、道路绘制、碰撞和导航共用同一份 `RoadNetwork`。所有距离单位为米，**1 个 Godot 世界单位 = 1 米**。相同参数和随机种子生成相同的路网。

## 当前实现范围

- 主干路、次干路、支路三种等级，红线宽度与车行道宽度分别处理。
- 地图宽高、随机种子、道路密度和红线宽度可在 `WorldGenerator` 的 Inspector 中调整。
- 道路中心线、交叉口和可碰撞几何来自同一份节点与路段数据。
- `RoadNetwork.find_route(起点节点编号, 终点节点编号)` 返回连通路径。
- 运行时校验道路宽度、连通性、交叉口连接数与夹角、交叉口间距及几何相交。
- 玩家第一人称移动、导航网格烘焙、交通模块入口已经接好；车辆/行人资产和订单逻辑尚未实现。

当前尚未生成地块或出入口，所以出入口规则报告为“未适用”。为使支路接入次干路，部分次干路交叉口间距低于建议的 300 米，但仍满足 150 米硬下限。当前城市没有高架、匝道或交通信号。

## 后续开发顺序

- 在路网之上生成地块、建筑、商家和顾客位置，并校验出入口规则。
- 加入随机订单、取餐与送达交互，以及可复现的起点和终点选择。
- 完善第一人称步行/骑行、相机和路线指引。
- 加入车辆、行人、交通规则及动态障碍，再完成任务计时和结算。

## Git 与资源文件

`.gitattributes` 将模型、贴图、音频、字体及 Godot 二进制资源交给 Git LFS；`.gd`、`.tscn`、`.tres`、`.svg` 等文本文件仍由普通 Git 管理。新克隆本仓库的电脑需要安装 Git LFS，并在仓库中执行 `git lfs install --local`。

`.tscn` 和 `.tres` 使用 `gdmerge` 处理本地三方合并。每位协作者需在自己的电脑安装并运行一次 `gdmerge git-install`。安装命令：`cargo install gdmerge --version 0.3.6 --locked`。

## Pull Request 检查

`.github/workflows/repository-integrity.yml` 会在 Pull Request 上运行 `git lfs fsck --pointers`，发现损坏的 LFS 指针时让检查失败。它还会读取同一目标分支上的其他开放 Pull Request；如果多个 PR 同时修改同一个 `.tscn`，会在对应文件上给出 GitHub Actions 警告，提醒合并前一起检查场景文件。

团队协作规则、每轮日志和远端同步要求见 [CONTRIBUTING.md](CONTRIBUTING.md)。各角色从环境准备到交付的具体步骤和注意事项见 [docs/USER_GUIDE.md](docs/USER_GUIDE.md)。

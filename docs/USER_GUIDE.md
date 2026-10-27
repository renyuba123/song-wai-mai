# 开发者使用指南

本指南面向参与《大城市送外卖》的所有开发者。不同职位负责的文件不同，但都必须遵守同一套环境、场景和提交流程。团队规则以 [CONTRIBUTING.md](../CONTRIBUTING.md) 为准，本指南补充分工后的具体操作。

## 0. 先找到自己的角色

| 角色 | 主要负责 | 对应章节 |
|---|---|---|
| 建模手 | `assets/models/`、`assets/textures/` 中交付的 `.glb` 和贴图 | 第 3 节 |
| 世界与交通生成 | `scripts/world/`、`scripts/traffic/`、对应场景 | 第 4 节 |
| 玩家、物理与整合 | `scripts/player/`、`scripts/core/`、`main.tscn`、`project.godot` | 第 5 节 |
| 导航 | `scripts/navigation/`、对应场景 | 第 6 节 |
| 技术美术 / 资源整合 | 资产规范、LFS、导入设置、CI 和场景合并 | 第 7 节 |
| 所有人 | 环境准备、日常流程、提交前检查 | 第 1、2、9 节 |

一个人可能同时承担多个角色，但同一时间只改自己当前负责的目录，跨模块改动先沟通。

## 1. 所有人：环境准备

### 1.1 必需软件

- **Godot 4.7.x**：团队统一使用同一小版本，当前机器使用 4.7.2。版本不一致可能导致 `.tscn` 格式和导入行为不同。
- **Git**：用于版本控制。
- **Git LFS**：模型、贴图、音频等二进制资源必须走 LFS。
- **gdmerge 0.3.6**：解决 Godot `.tscn` / `.tres` 的合并冲突。

### 1.2 第一次克隆

```powershell
git clone https://github.com/renyuba123/song-wai-mai.git
cd song-wai-mai
git lfs install --local
gdmerge git-install
sh scripts/dev/setup-git-hooks.sh
```

检查环境：

```powershell
gdmerge --version
git lfs status
```

`gdmerge --version` 应输出 `gdmerge 0.3.6`。如果本机没有 Rust，可以使用官方 Release 的 Windows 预编译包，但不要混用不同版本。

### 1.3 打开项目

用 Godot 4.7 打开仓库根目录。第一次打开会生成 `.godot/` 导入缓存，这个目录不会提交。

- **F5**：运行主场景 `scenes/main/main.tscn`。
- **F6**：单独运行当前打开的场景，例如 `scenes/demo/city_road_demo.tscn`。

### 1.4 运行自动校验

```powershell
godot --headless --path . --script res://tests/test_road_network.gd
godot --headless --path . --script res://tests/test_main_scene.gd
godot --headless --path . --script res://tests/test_contracts.gd
godot --headless --path . --script res://tests/test_input_actions.gd
godot --headless --path . --script res://tests/test_navigation_queries.gd
```

前两条检查路网生成、校验、寻路和主场景启动；后三条分别检查共享数据契约、输入映射与玩家移动、导航查询接口。新增脚本后先执行一次 `godot --headless --path . --import`，让 Godot 注册 `class_name` 并生成 `.gd.uid`。

## 2. 所有人：日常操作流程

### 2.1 开始工作前

```powershell
git fetch origin --prune
git status
```

- 工作区干净、远端有新提交时：`git pull --rebase`。
- 有未提交改动时：先提交或暂存，再同步。
- 不确认远端状态就直接改代码，是冲突的主要来源。

### 2.2 建分支

从最新 `main` 建短生命周期分支：

```powershell
git switch main
git pull --rebase
git switch -c <type>/<github-id>-<topic>
```

类型使用 `feature`、`fix`、`docs`、`chore`、`refactor`，并带上自己的 GitHub 用户名，避免多人分支重名。示例：`feature/jzy-worldgen-blocks`、`fix/lisi-player-capsule`、`feature/wang-navigation-query`。

一个分支只做一件事，且只有一个负责人。不要往别人的功能分支追加提交；需要协作时先沟通。

### 2.3 修改范围

只改自己负责的目录和场景。文件所有权见 [CONTRIBUTING.md](../CONTRIBUTING.md) 的表格。共享文件（`main.tscn`、`project.godot`、`collision_layers.gd`、`.gitattributes`、`.gitignore`）由整合者统一修改，其他人先提出需求。

### 2.4 完成工作后

1. 运行相关测试，打开场景确认没有报错。
2. 清理调试残留：临时 `print`、临时改数值、`@tool` 调试节点、注释掉的实验代码。
3. 在 [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md) 追加本轮记录。
4. 提交并推送当前分支。
5. 一个模块或修复完成后，尽快创建 PR。
6. PR 合并后删除本地和远端分支；本地可执行 `sh scripts/dev/cleanup-merged-branches.sh`，远端分支确认已合并后再删除。

提交前检查：

```powershell
git status
git diff --check
```

### 2.5 场景文件规则

- 同一个 `.tscn` 同一时间只允许一个人编辑。
- 不直接编辑导入的 `.glb` 原始场景；在实例化它的上层场景里加碰撞、脚本、灯光和材质覆盖。
- 不用文本编辑器手改 `.tscn`，需要改就在 Godot 编辑器里改。
- 拉取后如果自己的场景被合并过，立即在 Godot 里打开看一遍，不要等写完代码才发现节点丢了。
- 调试场景放在 `scenes/dev/<名字>/`，不要混进共享场景。

### 2.6 二进制资源规则

- `.glb`、`.png`、`.jpg`、`.wav`、`.ogg` 等必须走 Git LFS；提交前用 `git lfs status` 确认。
- 不提交 `.godot/`、导出产物和临时缓存。
- `.import` 文件和 `.uid` 文件是项目元数据，按仓库现有规则提交，不要随手删除。
- 大文件先确认是否真的需要进仓库，能压缩就压缩。

## 3. 建模手（SketchUp / Rhino）

建模手交付的是**视觉资产**，不是 Godot 场景。仓库里只提交导出的 `.glb`，源文件（`.skp` / `.3dm`）留在本地版本管理中，除非团队另外约定归档方式。

### 3.1 交付位置与命名

```text
assets/models/
  buildings/      建筑外壳、商铺、住宅
  props/          路障、招牌、垃圾桶、外卖箱等
  vehicles/       车辆
  characters/     行人、骑手
  vegetation/     树、灌木
```

如果对应目录还没有建立，按上面的结构新建，并在 `assets/README.md` 登记用途。文件名使用小写英文和下划线，例如：

```text
assets/models/buildings/building_apartment_a.glb
assets/models/props/street_lamp_01.glb
```

不要用中文、空格或临时名字（`新建模型2.glb`）。同一资产更新时保持原路径，Godot 会重新导入；随意改名会让场景里的引用失效。

### 3.2 导出契约

每个 `.glb` 必须满足：

1. **单位是米**。Godot 中 1 个单位 = 1 米。SketchUp/Rhino 建模前先把文档单位改成米。
2. **Y 轴向上、朝向一致**。建模软件可能是 Z 轴向上，导出 glTF 时会转换；导出后在 Godot 里检查正面是否朝向预期的 -Z 方向，必要时在建模软件里先旋转好。
3. **原点放在物体底部中心**，不要放在世界原点或模型中心。这样程序摆放时不会一半埋进地面。
4. **应用所有变换**：旋转、缩放归零，避免导入 Godot 后尺寸和碰撞对不上。
5. **导出前三角化**，不要在 Godot 里依赖自动三角化处理 N 边形。
6. **只导出需要的几何**：隐藏图层、辅助线、相机、灯光、施工参考不要带进 `.glb`。
7. **法线、UV、材质完整**：检查没有黑面、反面、拉伸的 UV 和丢失的贴图。
8. **保留组件/块实例**：SketchUp 组件和 Rhino 块能复用就复用，不要为了“干净”全部炸开；复用能减少源文件维护量，导出后是否保留实例以 Godot 里的实际导入结果为准。
9. **控制面数和贴图**：建筑外壳、车辆、道具按项目预算控制；远处物体准备 LOD 或简化版本。贴图优先 1K/2K，非必要不用 4K/8K。
10. **不把碰撞体塞进视觉模型**。碰撞由程序在 Godot 里加；如果确实需要自定义碰撞网格，另存为 `_collision.glb` 并在交付说明里写清楚。

### 3.3 SketchUp 操作要点

- 模型信息 → 单位 → 米。
- 用组件组织重复元素（窗户、椅子、路灯），保留实例。
- 用标签/图层区分需要导出的部分，导出前关闭不需要的标签。
- 导出 glTF/GLB 时勾选三角化、导出纹理、应用变换相关选项。
- 导出后用 Godot 的 1 米参考物检查比例。

### 3.4 Rhino 操作要点

- 文档单位改为米。
- 导出前设置渲染网格：最大角度约 10–20°，大而平缓的曲面加最大边缘长度限制，避免产生大量微三角面。
- 导出 glTF 时包含法线和纹理坐标。
- NURBS 曲面会被网格化，导出后到 Godot 里检查轮廓和面数。
- 块实例如果导出后变成独立网格，和程序确认是否需要简化。

### 3.5 交付与验收

在提交信息里写清楚：

```text
feat(asset): add building_apartment_a

- 尺寸：24m × 12m × 9m
- 三角面：约 12k
- 贴图：2048 PBR，内嵌
- 碰撞：由程序按盒体生成
```

交付后由程序或技术美术在 Godot 里导入检查：

- 比例是否正确（门高约 2m，层高约 3m）。
- 原点是否在底部中心。
- 正面朝向是否正确。
- 材质、贴图是否丢失。
- 面数是否在预算内。

### 3.6 建模手不要做的事

- 不打开或修改 `.tscn`。
- 不在 Godot 里手动给关卡摆模型后提交场景（除非团队明确把这项任务交给你）。
- 不提交 `.skp` / `.3dm` 源文件到主仓库。
- 不把相机、灯光、施工线、隐藏对象带进 `.glb`。
- 不用超大贴图和未清理的重复几何。

## 4. 世界与交通生成开发者

负责地图、路网、地块、车辆和人流的生成逻辑。主要目录：

```text
scripts/world/
scripts/traffic/
scenes/world/
scenes/traffic/
```

### 4.1 数据契约

`RoadNetwork` 是共享数据，字段包括：

- `nodes`：路网节点（`Vector2`，X/Z 平面，单位米）
- `edges`：路段（`a`、`b`、`kind`）
- `widths`：三类道路红线宽度
- `seed_value`、`density`、`map_size`
- `x_axes`、`y_axes`：道路轴线
- `entrances`：地块出入口（后续生成）

生成、绘制、碰撞和导航都读这一份数据。字段已经冻结，只做新增；修改字段或含义前，先通知玩家/整合和导航负责人，并同步更新测试。

出生点和站点使用独立的纯数据资源，不保存 `Node` 引用：

- `SpawnPoint`：`kind`（玩家起点/商家/顾客）、`site_id`、`position`、`facing_yaw`、`road_edge_id`、`road_offset_m`。
- `CitySite`：`id`、`kind`（商家/住宅）、`position`、`facing_yaw`、`lot_id`、`road_edge_id`、`spawn_point`。

`position` 是世界坐标，单位米；`facing_yaw` 是弧度，0 朝向 -Z。`CitySite.position` 是建筑锚点，`spawn_point.position` 才是玩家实际可站的位置。商家/顾客出生点必须关联站点编号，并避开交叉口退让区。生成新的出生点后调用 `validate(network)`，不要继续从路网节点随机取出生位置。

### 4.2 生成规则

- 使用 `RoadGenerator.generate(...)`，不要在别的模块里复制一套路网生成逻辑。
- 所有随机都使用 `RandomNumberGenerator` 并显式设置 `seed`，不要用全局 `randi()`。
- 同一组参数和种子必须生成同一份路网；测试会检查这一点。
- 新增地块、建筑、商家的生成时，优先扩展 `RoadNetwork` 的数据或新增独立资源，不要把逻辑塞进 `RoadBuilder`。
- 生成失败、路网为空、路径不存在时要安全返回，不要让整个主场景崩溃。

### 4.3 交通与行人

- 车辆/行人从 `RoadNetwork` 的节点、路段和出生点生成，不要自己再随机一套地图。
- 动态对象使用 `CollisionLayers.VEHICLE` / `PEDESTRIAN` 和对应掩码。
- 寻路使用 `NavigationService` 提供的导航区域或查询接口，不要自己写一套 A* 绕过导航模块。
- 大量行人优先用 `MultiMesh` 或实例化池，避免每帧创建节点。
- 车辆、行人的 `.tscn` 由本模块负责；不要修改 `player.tscn` 或 `navigation_system.tscn`。

### 4.4 场景与测试

- 在 `scenes/world/world.tscn` 或 `scenes/traffic/traffic_system.tscn` 内增加子场景，不要往 `main.tscn` 里直接加节点。
- 新增生成规则时扩展 `tests/test_road_network.gd` 或新增测试，至少覆盖：相同种子可复现、路网连通、路径存在。
- 调试用场景放在 `scenes/dev/<名字>/`，不要提交临时场景。

## 5. 玩家、物理与整合开发者

负责第一人称操作、碰撞层、主场景装配和共享配置。主要目录：

```text
scripts/player/
scripts/core/
scenes/player/
scenes/main/main.tscn
project.godot
```

### 5.1 碰撞层

统一使用 `scripts/core/collision_layers.gd`：

| 常量 | 用途 |
|---|---|
| `WORLD_STATIC` | 道路、地面、建筑等静态几何 |
| `PLAYER` | 玩家 |
| `VEHICLE` | 车辆 |
| `PEDESTRIAN` | 行人 |
| `TRIGGER` | 任务、交互触发器 |
| `NAVIGATION_OBSTACLE` | 动态导航障碍 |

不要在别的脚本里直接写 `1`、`2`、`4` 这类数字。新增对象时先确认层和掩码，必要时先在团队里讨论。

### 5.2 玩家控制

- 玩家是 `CharacterBody3D`，碰撞体和相机在 `scenes/player/player.tscn`。
- 移动、视角、跳跃/重力逻辑放在 `scripts/player/`。
- 后续步行/骑行状态机也放在这个模块，不要改 `WorldGenerator`。
- 输入映射由整合者统一维护；正式功能必须通过 `InputMap` 动作读取，不要直接轮询物理按键。
- 玩家出生点、任务起点由世界或订单模块提供，玩家模块只负责“被放在哪里之后怎么走”。

阶段零已经定义的输入动作：

| 动作 | 按键 | 用途 |
|---|---|---|
| `move_forward` / `move_back` | W / S | 前后移动 |
| `move_left` / `move_right` | A / D | 左右移动 |
| `interact` | E | 取餐、送达等交互（阶段二实现） |
| `pause` | Esc | 暂停（阶段二实现） |
| `restart` | R | 重开（阶段二实现） |

移动使用 `Input.get_vector("move_left", "move_right", "move_forward", "move_back")`，不要退回 `Input.is_physical_key_pressed`。

### 5.3 主场景装配

`scenes/main/main.tscn` 只做装配：

```text
Main
  Player
  NavigationSystem
  TrafficSystem
  World
```

`scripts/core/main.gd` 连接信号：

1. 世界生成完成，发出 `world_generated(network)`。
2. 导航接收同一份 `RoadNetwork` 并烘焙。
3. 交通接收同一份 `RoadNetwork` 并生成车辆/行人。

不要把业务逻辑写进 `main.gd`；它只负责接线。新增模块时，先在模块内部提供入口场景和信号，再在 `main.tscn` 里实例化。

### 5.4 整合者职责

- 维护 `project.godot`、输入映射、碰撞层、`main.tscn`、`.gitattributes`、`.gitignore`。
- 审核 PR：是否只改自己负责的目录、是否夹带调试残留、是否更新日志。
- 处理复杂 `.tscn` 合并冲突，必要时用 `git mergetool --tool=gdmerge`。
- 监控 LFS 配额和 CI 结果。
- 发布前打 tag，确认主场景能启动、测试通过。

## 6. 导航开发者

负责导航网格、路径查询和动态障碍。主要目录：

```text
scripts/navigation/
scenes/navigation/
```

### 6.1 当前实现

`NavigationService.build(network)` 会：

1. 创建 `NavigationMesh`。
2. 使用 4 米体素（城市级地图的默认值）。
3. 只解析 `CollisionLayers.WORLD_STATIC` 的静态碰撞体。
4. 从 `navigation_source` 组读取道路碰撞体；地面不参与导航。
5. 同步烘焙、强制更新导航地图，再根据导航网格多边形数量设置就绪状态。
6. 发出 `navigation_baked`。

其他模块只通过 `NavigationService` 查询，不直接读取 `NavigationRegion3D`：

```gdscript
func is_ready() -> bool
func get_closest_point(world_position: Vector3) -> Vector3
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array
func is_reachable(from: Vector3, to: Vector3) -> bool
static func get_path_length(path: PackedVector3Array) -> float
```

未就绪时 `find_path()` 返回空数组，`is_reachable()` 返回 `false`，`get_closest_point()` 返回 `Vector3.INF`，调用方要先判断 `is_ready()`。查询参数和返回值都是世界坐标，单位米。路径长度按导航路径逐段累加，不额外加站点锚点到导航网格的直线距离。

### 6.2 注意事项

- 不要修改 `RoadBuilder` 里的碰撞体结构；需要新增导航源时，把静态碰撞体加入 `navigation_source` 组。
- 导航网格依赖世界生成结果，必须在 `world_generated` 之后烘焙。
- 车辆/行人使用 `NavigationAgent3D` 时，代理半径、高度要与导航网格参数一致。
- 动态障碍使用 `NavigationObstacle3D`，不要每帧重烘焙整个导航网格。
- 大地图不要使用默认 0.25 米体素，会触发 Godot 的烘焙崩溃保护。
- 查询接口放在导航模块内，供车辆/行人调用；不要让交通模块直接操作 `NavigationRegion3D` 内部节点。

### 6.3 调试

- 在编辑器里打开导航调试显示，检查道路是否连通、交叉口是否断开。
- 写一个临时 `scenes/dev/navigation/` 测试场景，放两个标记点，验证 `NavigationAgent3D` 能到达。
- 测试至少覆盖：主场景能烘焙出多边形、随机两点之间有路径、动态障碍不会让代理卡死。`tests/test_navigation_queries.gd` 已经覆盖未就绪行为、主场景路径查询和路径长度计算。

## 7. 技术美术 / 资源整合

如果团队单独设技术美术，负责资产规范和管线；如果由程序兼任，也按同样标准执行。

- 维护导入预设、材质规范、LOD 和面数预算。
- 审核建模交付：单位、原点、朝向、三角化、贴图、命名、面数。
- 维护 `assets/README.md` 和资源目录结构。
- 监控 Git LFS 存储和流量；大文件先确认是否必要。
- 维护 `gdmerge` 配置和 CI 检查，处理场景合并冲突。
- 统一材质：避免每个资产自带一套不兼容的材质；需要覆盖时在实例化场景里做，不改 `.glb` 源文件。
- 发布前检查：没有缺失贴图、没有重复资源、没有误提交的缓存和源文件。

## 8. 常见问题

### 8.1 Godot 打开后大量报错

先确认版本是 4.7.x。删除本地 `.godot/` 后重新打开项目，让 Godot 重新导入。

### 8.2 模型导入后太大或太小

检查建模软件文档单位是否为米，导出前是否应用缩放。Godot 中 1 单位 = 1 米，不要靠导入面板的 Scale 临时补偿，否则碰撞和导航都会对不上。

### 8.3 `.glb` 贴图丢失

检查贴图是否随 `.glb` 一起导出或放在同目录；检查贴图路径是否被移动；重新导入后确认材质。

### 8.4 场景合并冲突

先确认冲突的是哪个节点、双方的修改意图。可以用：

```powershell
git mergetool --tool=gdmerge
```

不要用“全部接受一边”的方式处理不理解的场景冲突。合并后在 Godot 里打开场景验证。

### 8.5 UID 或资源引用错乱

统一接受一方的 `.uid` 文件，删除本地 `.godot/uid_cache.bin`，重启 Godot 让编辑器重建缓存。不要手改 `.tscn` 里的 `uid://`。

### 8.6 导航烘焙失败

检查导航体素是否过小、源几何是否过大。当前默认 4 米体素；不要把地面加入 `navigation_source` 组，否则导航网格会覆盖整张地图。

### 8.7 玩家掉出地面

检查地面碰撞体是否生成、玩家 `collision_mask` 是否包含 `WORLD_STATIC`、玩家出生点是否在地面以上。

### 8.8 推送被拒绝

如果 GitHub 提示 `Permission denied`，说明当前 Git 账号没有仓库写权限。让仓库 owner 把你加为 collaborator，或切换到有权限的账号；不要把 token 写进仓库或提交历史。

### 8.9 推送时提示 LFS locking API 不支持

如果推送报错：

```text
Remote "origin" does not support the Git LFS locking API.
```

在本仓库关闭 LFS 锁验证后再推送：

```powershell
git config lfs.https://github.com/renyuba123/song-wai-mai.git/info/lfs.locksverify false
git push
```

这是本地配置，不会提交到仓库；它只关闭 Git LFS 的锁检查，不影响文件通过 LFS 上传。

## 9. 提交前检查清单

- [ ] 已执行 `git fetch origin --prune`，并同步了远端更新。
- [ ] 只改了自己负责的目录和场景。
- [ ] 没有直接修改别人的 `.tscn`。
- [ ] 运行了相关测试，主场景能打开。
- [ ] 清理了调试 `print`、临时数值和调试节点。
- [ ] 二进制资源走 LFS，`.godot/` 没有被提交。
- [ ] 在 `docs/DEVELOPMENT_LOG.md` 追加了本轮记录。
- [ ] 提交信息说明了改了什么。
- [ ] 推送后在合适的时机创建 PR。

## 10. 相关文档

- [README.md](../README.md)：项目目标、目录、运行方式。
- [ROADMAP.md](ROADMAP.md)：已确认的开发路线图、阶段目标和验收标准。
- [CONTRIBUTING.md](../CONTRIBUTING.md)：分支、日志、提交、PR、远端同步和文件所有权。
- [DEVELOPMENT_LOG.md](DEVELOPMENT_LOG.md)：每轮开发记录。
- [assets/README.md](../assets/README.md)：资源目录说明。

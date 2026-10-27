# 开发日志

本文件按轮次追加。每轮记录需求、改动、校验结果和对应提交，规则见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 2026-10-27 16:36 模块化改造与协作规则

**本轮需求（原文）：** 执行改造操作，同时新增规则：编写log，每轮对话完成后编写，简要说明修改，并同步提交并推送；定期提交推送与PR，时机自行确认；监控远端，出现新的更新时拉取更新。

**做了什么：**

- 从 `road` 分支建立 `refactor/modular-base`，合并 `main` 的最新基础提交，保留路网原型并解决删除/修改冲突。
- 将 `scripts/road_network.gd` 从静态工具类改为 `RoadNetwork` Resource，作为生成、绘制、碰撞和导航共享的数据。
- 新增 `RoadGenerator`（只生成数据）、`RoadBuilder`（只绘制道路和碰撞）、`WorldGenerator`（参数入口与信号）。
- 新增 `scenes/main/main.tscn`、`scenes/world/world.tscn`，主场景负责装配世界、玩家、导航和交通。
- 新增第一人称玩家骨架 `scripts/player/player_controller.gd` 和 `scenes/player/player.tscn`。
- 新增导航模块 `scripts/navigation/navigation_service.gd`，从静态道路碰撞体烘焙导航网格；车辆/行人入口 `scripts/traffic/traffic_spawner.gd` 暂为占位。
- 新增碰撞层常量和层名，统一玩家、车辆、行人、静态几何等掩码。
- 路网演示移到 `scenes/demo/city_road_demo.tscn`，保持按 F6 可运行。
- 新增 `CONTRIBUTING.md`，写明分支、每轮日志、提交推送、PR、远端同步和文件所有权规则。
- 更新 `README.md`，补充目录结构、运行方式和测试命令。

**修改目录：** `scripts/core/`、`scripts/world/`、`scripts/player/`、`scripts/navigation/`、`scripts/traffic/`、`scripts/demo/`、`scenes/main/`、`scenes/world/`、`scenes/player/`、`scenes/navigation/`、`scenes/traffic/`、`scenes/demo/`、`tests/`、`docs/`、`project.godot`、`README.md`、`CONTRIBUTING.md`。

**校验：**

- 路网测试通过：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
```

- 主场景冒烟测试通过：`PASS main scene nodes=153 nav_polygons=624`。
- 导航烘焙一度因默认体素过细触发 Godot 崩溃保护，改为 4 米体素，并把地面从导航源中分离后通过。

**提交：** `ec9e9e5 refactor: split road prototype into modular world skeleton`

**远端同步：** 准备推送时发现 `origin/road` 新增 `fd164ad Add LFS and Godot scene integrity checks`，已合并进本分支并解决 `README.md` 冲突；新增的 `.github/workflows/repository-integrity.yml` 已纳入。

**推送：** 尝试 `git push -u origin refactor/modular-base` 失败，GitHub 返回 `Permission to renyuba123/song-wai-mai.git denied to jzy070407`（403）。本地提交已就绪，需要仓库 owner 把 `jzy070407` 加为 collaborator，或切换到有写权限的账号后重新推送并创建 PR。

**下一步：** 获得推送权限后推送 `refactor/modular-base` 并创建 PR；之后按 A（世界与交通）、B（玩家/物理/整合）、C（导航）划分目录继续开发，先补地块和订单起点/终点选择。

## 2026-10-27 16:47 新增各角色开发者使用指南

**本轮需求（原文）：** 顺手先加一个使用指南，详细写出各类型开发者的操作方法与注意事项。

**做了什么：**

- 新增 `docs/USER_GUIDE.md`，按建模手、世界与交通生成、玩家/物理/整合、导航、技术美术/资源整合分别写明职责目录、操作步骤、交付标准、协作边界和常见问题。
- 指南包含所有人共用的环境准备、分支与同步、场景文件规则、LFS 规则、提交前检查清单和故障排查。
- 建模部分写清 SketchUp/Rhino 导出 `.glb` 的单位、朝向、原点、三角化、变换、命名、面数、贴图和交付验收要求。
- 在 `README.md` 的目录结构和文档链接、`CONTRIBUTING.md` 开头补上使用指南入口。

**修改目录：** `docs/`、`README.md`、`CONTRIBUTING.md`。

**远端同步：** 开始本轮前监控到 `origin/main` 从 `2212daf` 前进到 `67bc997 Add LFS and scene overlap checks to CI`，已合并进 `refactor/modular-base`，合并提交为 `e2111bf`。

**校验：** 文档改动不涉及运行时代码，仍重新执行了两项检查：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
PASS main scene nodes=153 nav_polygons=624
```

**提交：** `f7e73fe docs: add role-based developer guide`；本条日志单独提交。

**推送：** `refactor/modular-base` 已成功推送到 `origin`，并设置为跟踪 `origin/refactor/modular-base`。首次推送因远端 LFS locking API 返回 EOF 失败，按 Git LFS 提示在本仓库设置 `lfs.https://github.com/renyuba123/song-wai-mai.git/info/lfs.locksverify=false` 后成功；此前 GitHub 403 写权限问题已不再出现。

**PR：** 分支已推送，PR 创建入口为 <https://github.com/renyuba123/song-wai-mai/compare/main...refactor/modular-base?expand=1>。当前环境没有 `gh` CLI，PR 尚未自动创建；安装并登录 `gh`，或由有权限的成员打开上述链接即可补建。

## 2026-10-27 16:54 确认每轮日志、推送与远端同步规则

**本轮需求（原文）：** 本机对话新增规则：编写log，每轮对话完成后编写，简要说明修改，并同步提交并推送；定期提交推送与PR，时机自行确认；监控远端，出现新的更新时拉取更新

**做了什么：**

- 将这条规则写入本机长期记忆，后续每轮按此执行。
- 本轮开始前检查远端，发现 `origin/main` 和 `origin/refactor/modular-base` 都有新提交，已用快进方式同步到本地。
- 将原本只在当前会话内生效的远端监控改为持久定时任务 `855c72c4`：每 2 小时检查一次 `origin/main` 和 `origin/refactor/modular-base`；有更新时先保留本地改动，再安全整合、运行测试、追加日志、提交并推送；遇到冲突或权限问题停止并报告。
- 仓库现有的 `CONTRIBUTING.md` 和 `docs/DEVELOPMENT_LOG.md` 规则与本条一致，本轮不需要改代码。

**修改目录：** `docs/DEVELOPMENT_LOG.md`。本机记忆和定时任务配置在仓库外。

**远端同步：**

- `origin/main`：`67bc997` → `a720b65 Document CI integrity checks`。
- `origin/refactor/modular-base`：`2bddb89` → `50eb89c Merge branch 'main' into refactor/modular-base`。
- 本地已快进到 `50eb89c`，工作区干净。

**校验：** 同步后重新运行了两项检查：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
PASS main scene nodes=153 nav_polygons=624
```

**提交：** `docs: record recurring round workflow rules`（本条日志）。

**推送：** 提交后推送到 `origin/refactor/modular-base`。

**PR：** 分支已推送，PR 创建入口见上一轮记录；PR 尚未自动创建。

## 2026-10-27 17:08 配置本机 PR 自动化与通知

**本轮需求（原文）：** 配置本机，实现自动创建PR，注意尽量不要占用C盘空间，同时新增本机规则：在创建PR时使用通知栏进行提醒

**做了什么：**

- 安装 GitHub CLI 2.103.3 到 `D:\Tools\gh\2.103.3`，下载后按官方 `gh_2.103.3_checksums.txt` 校验 SHA-256。
- 将 GitHub CLI 配置目录设为 `D:\Tools\gh\config`，避免认证和缓存写入 C 盘。
- 将 D 盘的 `gh.exe` 加入用户 PATH；在 `C:\Users\ASUS\bin` 只放两个很小的转发脚本（共 240 字节），负责设置 `GH_CONFIG_DIR` 后调用 D 盘 CLI，不复制 CLI 主体到 C 盘。
- 通过 `gh auth login --web` 以 `jzy070407` 登录，token 存入系统凭据库。
- 新增 `D:\Tools\gh\notify-pr.ps1`：用 Windows 通知栏显示 PR 创建结果；新增 `D:\Tools\gh\pr-create.sh`：先检查当前分支是否已有 PR，没有才创建，并在结束后发送通知。
- 检查时发现 `refactor/modular-base` 的 PR #1 已由 `jzy070407` 创建并合并到 `main`；本地 `main` 已快进到 `7e2d4d3`。
- 新增本机规则记忆：创建 PR 时使用通知栏提醒。

**修改目录：** `docs/DEVELOPMENT_LOG.md`。GitHub CLI、通知脚本和定时任务配置在仓库外。

**校验：**

- `gh auth status` 显示已登录 `jzy070407`，token scopes 包含 `repo`、`read:org`、`gist`。
- 通知栏测试脚本已执行，命令返回 0。
- `pr-create.sh` 成功识别出 PR #1 已存在，没有重复创建。
- 从合并后的 `main` 重新运行测试：

```text
PASS seed=42 nodes=153 edges=220 kinds=[48, 108, 64]
PASS seed=1 nodes=27 edges=32 kinds=[8, 20, 4]
PASS seed=73 nodes=307 edges=466 kinds=[110, 196, 160]
PASS main scene nodes=153 nav_polygons=624
```

**提交：** `docs: record local PR automation setup`（本条日志）。

**推送：** 推送到 `origin/chore/pr-automation`。

**PR：** 使用 `D:\Tools\gh\pr-create.sh` 自动创建，并在通知栏提醒结果。

**下一步：** 后续从最新 `main` 拉分支，完成模块后推送并运行 `pr-create.sh`；车辆/行人资产、订单和地块生成仍按原计划推进。

## 2026-10-27 17:15 加强本地与远端分支管理

**本轮需求（原文）：** 目前项目开发人数较多，请在本地与远端务必做好分支管理

**做了什么：**

- 审计本地和远端分支：本地只剩 `main`，远端保留 `main`、`road`、`chore/pr-automation`、`refactor/modular-base`；后两个分支对应的 PR #1、#2 都已合并。
- 删除本地已合并的 `chore/pr-automation` 和 `refactor/modular-base` 分支，并执行 `git fetch --prune`。
- 新增 `.githooks/pre-commit` 和 `.githooks/pre-push`：阻止在 `main` 上直接提交或推送。
- 新增 `scripts/dev/setup-git-hooks.sh`，每位开发者克隆后执行一次即可启用 hooks。
- 新增 `scripts/dev/cleanup-merged-branches.sh`，先确认工作区干净，再同步 `main` 并删除已合并的本地分支。
- 更新 `CONTRIBUTING.md`：分支命名改为 `<type>/<github-id>-<topic>`，明确一分支一任务、单负责人、同步、强推、PR 合并后清理，以及 owner 需要配置的远端保护和自动删除。
- 更新 `docs/USER_GUIDE.md`：补充 hooks 安装、带用户名的分支命名和合并后清理步骤。
- 远端检查发现 `main` 当前没有启用分支保护（GitHub API 返回 404），当前账号 `jzy070407` 只有 `push` 权限，没有 `admin` / `maintain`，无法代为配置。
- 远端两个已合并分支尚未删除；远端删除属于共享引用操作，本轮未擅自执行。

**修改目录：** `.githooks/`、`scripts/dev/`、`CONTRIBUTING.md`、`docs/USER_GUIDE.md`、`README.md`、`docs/DEVELOPMENT_LOG.md`。

**校验：**

- 四个 shell 脚本通过 `sh -n` 语法检查。
- 已执行 `sh scripts/dev/setup-git-hooks.sh`，`core.hooksPath` 为 `.githooks`。
- 模拟推送 `refs/heads/main` 时 `pre-push` 返回 1，成功拦截。
- 在 `main` 上直接运行 `pre-commit` 返回 1，成功拦截。
- 本轮只改分支管理和文档，未改运行时代码，未重跑 Godot 测试。

**提交：** `chore: enforce branch management workflow`（本条日志随该提交）。

**推送与 PR：** 使用 `git pushpr` 推送并自动创建 PR，同时发送通知栏提醒。

**待确认：** 是否删除远端已合并分支 `chore/pr-automation` 和 `refactor/modular-base`；以及请仓库 owner 在 GitHub 设置中为 `main` 启用分支保护并开启合并后自动删除 head branch。

## 2026-10-27 17:20 补回未进入 main 的分支管理文档提交

**原因：** PR #3 在第二个提交 `838dcac docs: list branch hooks and dev scripts` 推送前已经合并，导致 README 的目录索引和日志中的“修改目录”补充没有进入 `main`；该提交仍留在远端分支 `chore/branch-management` 上。

**处理：**

- 从最新 `main` 建立 `docs/jzy-branch-management-index`，cherry-pick `838dcac`，得到提交 `90b54e1`。
- 本条目随该分支提交，说明漏合并的原因，避免以后把远端旧分支误判为已全部合并。
- 新 PR 合并后再删除远端 `chore/branch-management`；删除前要确认 `838dcac` 已进入 `main`。

**校验：** `git log main..origin/chore/branch-management` 显示 `838dcac` 尚未进入 `main`；cherry-pick 后工作区干净，README 和日志改动已恢复。本轮不涉及运行时代码。

**提交：** `90b54e1 docs: list branch hooks and dev scripts` 及本条日志提交。

**推送与 PR：** 使用 `pr-create.sh` 推送并自动创建 PR，同时发送通知栏提醒。

## 2026-10-27 17:39 确认并落库开发路线图

**本轮需求（原文）：** 认可此路线图

**做了什么：**

- 新增 `docs/ROADMAP.md`，按阶段零到阶段五记录目标、工作项、验收标准、主责、依赖、风险和发布切点。
- 在 README 增加路线图入口、目录索引，并在“后续开发顺序”中说明详细版本的位置。
- 在开发者使用指南的“相关文档”中加入路线图入口。
- 本轮只记录规划，不创建 GitHub Issues 或里程碑；进入阶段零时再按负责人和分支拆分，避免产生无人负责的空跟踪项。

**修改目录：** `docs/`、`README.md`。本轮不涉及运行时代码。

**校验：** 文档改动，未运行 Godot 测试；检查了 README 中的相对链接和目录索引。

**提交：** `docs: add approved development roadmap`（本条日志随该提交）。

**推送与 PR：** 使用 `git pushpr` 推送并自动创建 PR，同时发送通知栏提醒。

## 2026-10-27 18:01 实施阶段零：共享契约与工程基线

**本轮需求（原文）：** 开始阶段零

**做了什么：**

- 新增 `SpawnPoint`、`CitySite`、`DeliveryOrder` 三个纯数据契约，带 `validate()` / `is_valid()`，不保存 `Node` 引用。
- 冻结 `RoadNetwork` 字段和坐标约定，只补说明，不改行为和校验；删除未被调用的 `WorldGenerator.get_random_spawn_point()`，避免出现第二套出生点来源。
- `NavigationService` 增加 `is_ready()`、`get_closest_point()`、`find_path()`、`is_reachable()` 和静态 `get_path_length()`；同步烘焙后强制更新导航地图并设置就绪状态，外部模块不再直接读取 `NavigationRegion3D`。
- `project.godot` 增加 `move_forward`、`move_back`、`move_left`、`move_right`、`interact`、`pause`、`restart` 七个输入动作；`PlayerController` 改用 `Input.get_vector`，不再轮询物理按键。
- 新增 `test_contracts.gd`、`test_input_actions.gd`、`test_navigation_queries.gd`；`test_main_scene.gd` 改为通过 `NavigationService.is_ready()` 判断导航。
- 持续集成在现有 `integrity` 任务中安装固定版本 Godot 4.7.2，执行 headless 导入和全部五个测试，并增加 15 分钟超时。
- 更新 `CONTRIBUTING.md` 的文件所有权、`docs/USER_GUIDE.md` 的契约与接口说明、`README.md` 的目录与测试命令、`docs/ROADMAP.md` 的阶段状态。

**修改目录：** `scripts/world/`、`scripts/orders/`、`scripts/navigation/`、`scripts/player/`、`tests/`、`project.godot`、`.github/workflows/`、`CONTRIBUTING.md`、`README.md`、`docs/`。本轮不修改任何 `.tscn`。

**校验：**

- `godot --headless --path . --import` 成功，注册 `SpawnPoint`、`CitySite`、`DeliveryOrder` 全局类名并生成 `.gd.uid`。
- 五个 headless 测试全部 `exit=0`：路网生成（3 个种子）、主场景冒烟、数据契约、输入动作与玩家移动、导航查询。
- `git diff --check` 和 `git lfs fsck --pointers` 通过。
- 搜索确认没有 `is_physical_key_pressed` 和 `get_random_spawn_point` 残留；`NavigationRegion3D` 只出现在导航模块。
- 首轮 CI 在 Linux 上发现刚就绪时 `find_path()` 返回空路径（本地未复现）；已在 `is_ready()` 中检查导航地图激活状态并强制同步，并让导航查询测试在最多 30 个物理帧内重试，避免新烘焙地图跨平台同步时机差异。

**提交：** `d9014a6 feat(world): add spawn and city site contracts`、`715f4d8 feat(orders): add delivery order contract`、`01e697b feat(navigation): add query interface and readiness gate`、`a77ee86 feat(input): add gameplay input actions`、`5b6603b test: cover phase-zero contracts, input, and navigation`、`eac5c91 ci: run Godot 4.7.2 headless tests`；文档与本条日志随 `docs: document phase-zero contracts and ownership` 提交。

**推送与 PR：** 使用 `git pushpr` 推送分支并自动创建 PR，同时发送通知栏提醒；等待 `integrity`（含 Godot 4.7.2 headless 测试）通过后再合并。

## 2026-10-27 19:57 实施阶段一：城市地块、建筑、商家和顾客站点

**本轮需求（原文）：** 开始阶段一

**做了什么：**

- `RoadNetwork` 新增 `SURFACE_Y`、`CARRIAGEWAY_RATIO`、`sidewalk_offset()` 和 `get_entrance_setback()`；入口可选键 `width`、`facing_yaw`、`lot_id` 加入校验。主干路、次干路、支路和困难模式的退让规则集中到同一函数，出生点不再各写一套。
- `SpawnPoint` 新增 `lateral_offset_m`，用路段左法线计算人行道位置；位置与偏移不一致、横向偏移超出红线时校验失败。出入口退让改用 `network.get_entrance_setback()`，支路出生点不再固定按 30 米处理。
- 新增 `CityContent` 纯数据契约，统一保存地块、建筑、站点、玩家起点和出入口交叉引用；校验地块重叠、建筑超出地块、入口退让、站点与入口关联、站点/玩家出生点不在建筑内、玩家起点不在道路中心。
- 新增 `CityGenerator`，从真实路段和轴线生成城市。每条非支路最多一个入口；地块临街宽 18～40 米、进深 18～28 米，全局最多 240 个；商家最多 12、顾客最多 20；同种子逐字段可复现。种子 42、2400 米、密度 0.5 生成 152 个地块、152 栋建筑、40 个出入口、32 个站点（16 商家 + 16 顾客）；1200 米、种子 1、密度 1.0 生成 16 个地块、16 栋建筑、4 个出入口、4 个站点。
- 新增 `CityBuilder`：绘制人行道、方块建筑和商家/顾客标记；人行道和建筑使用 `WORLD_STATIC` 碰撞，但不加入 `navigation_source`。`world.tscn` 增加 `CityBuilder` 兄弟节点。
- `RoadBuilder` 把所有可走碰撞体顶面统一到 `RoadNetwork.SURFACE_Y = 0`，视觉网格只抬高几厘米；修掉人行道与车行道之间约 20 厘米、玩家无法自然跨越的台阶。
- `WorldGenerator` 生成顺序改为路网 → 城市 → 校验 → 道路绘制 → 城市绘制 → 报告 → `world_generated`；新增 `generate_city`、`city` 和 `city_report`，信号签名不变。
- `main.gd` 在世界生成后把玩家放到 `CityContent.player_start` 的位置和朝向；`city_demo.gd` 增加地块、建筑、站点和出入口数量。
- 新增 `tests/test_city.gd`，覆盖同种子确定性、不同种子差异、两组地图参数、入口/地块/建筑/站点交叉引用、六类反向数据、主场景城市装配、导航源分组隔离，以及玩家起点到每个站点的 30 帧有界可达性查询。扩展 `test_contracts.gd` 和 `test_main_scene.gd`，CI 测试列表加入 `test_city`。

**共享契约变化：** `RoadNetwork.entrances` 的 `width`、`facing_yaw`、`lot_id` 已成为阶段一城市必要键；`SpawnPoint` 新增 `lateral_offset_m`；新增 `CityContent`。旧的“新生成路网不应已有出入口”测试保留，因为入口只在 `CityGenerator` 中写入。导航源仍只有 `RoadCollision`。

**修改目录：** `scripts/world/`、`scripts/core/`、`scripts/demo/`、`scenes/world/`、`tests/`、`.github/workflows/`、`README.md`、`CONTRIBUTING.md`、`docs/`。

**本地校验：**

- `godot --headless --path . --import` 成功，注册 `CityContent`、`CityGenerator`、`CityBuilder` 并生成 `.uid`。
- 六个 headless 测试全部 `exit=0`：`test_road_network` 三种子通过；`test_main_scene` 输出 `nodes=153 lots=152 sites=32`；`test_contracts` 通过；`test_input_actions` 通过；`test_navigation_queries` 通过；`test_city` 两组种子通过，主场景全部 32 个站点可达。
- `git diff --check` 通过，`git lfs fsck --pointers` 输出 `Git LFS fsck OK`。
- 边界搜索确认 `navigation_source` 仍只用于道路和碰撞层常量；建筑/人行道没有加入导航源；没有 `get_random_spawn_point` 或 `is_physical_key_pressed` 残留。
- 本轮以 headless 测试验证主场景装配和可达性，未在图形窗口中手动漫游；F5 的视觉效果和“从人行道走上车行道”留给 PR 评审时确认。

**提交：** `369a5cb feat(world): add entrance setback and surface metrics`、`daf5c42 feat(world): add spawn lateral offset and city content contract`、`0cd534c feat(world): generate city lots, buildings, and sites`、`1fe23af feat(world): render sidewalks, buildings, and site markers`、`2a52eb0 feat(core): spawn player at the generated city start`、`bbc9ab1 test: cover stage-one city generation and reachability`；文档与本条日志随 `docs: document stage-one city generation` 提交。

**推送与 PR：** 使用 `D:\Tools\gh\pr-create.sh` 推送当前分支并创建 PR，标题为 `feat: implement stage one city lots and sites`，同时发送通知栏提醒；CI 结果回填到本条日志。

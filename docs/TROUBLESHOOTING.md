# 故障排查：main 城市契约回归与恢复

本文记录 2026-10-28 处理 `main` 被旧项目快照覆盖的问题，供后续遇到同类情况时定位和恢复。已知良好的完整状态是 `bf5bc7e`（本地标签 `known-good-20261028`），阶段二代码的最后一个正常合并提交是 `96522dc`。

## 常见症状

- `test_orders` 无法加载：`Cannot find member "MAX_PLAYER_STARTS" in base "CityGenerator"`，或 `Cannot infer the type of "starts"`。
- `test_god_view` 输出 `FAIL 玩家不应被上帝视角移动到地下`。
- `test_main_scene` 输出缺少 `starts=`、`order_seed=`，或者没有 `OrderSystem` 节点。
- `test_city` 虽然通过，但不再检查多起点。
- CI 在 `Verify Git LFS pointers` 步骤失败：`should have been a pointer but was not`。
- 主场景的 `World` 节点从 `generate_on_ready = false` 变成别人上传的 `seed = ...`，`OrderSystem` 节点消失。

## 快速定位

在仓库根目录执行：

```bash
git log --oneline -S'player_starts' -- scripts/world/city_content.gd
git log --oneline -S'test_orders' -- .github/workflows/repository-integrity.yml
git log --oneline -S'1.3682455' -- scenes/player/player.tscn
git grep -n "get_available_player_starts" -- scripts tests
git lfs fsck --pointers
```

判断标准：

- 如果 `get_available_player_starts` 只在 `scripts/orders/order_generator.gd` 出现、没有定义，说明 `CityContent` 契约被删。
- 如果 CI 列表里没有 `test_orders`，说明测试也被一起删掉了。
- 如果 `player.tscn` 的胶囊中心不是 `0.9`，玩家会下沉到路面以下；胶囊高度 1.8 时中心应等于 0.9。
- `git lfs fsck --pointers` 报普通 blob，说明 `.glb` 被网页上传绕过 LFS。

## 恢复步骤

### 1. 从最新 main 建分支

```bash
git fetch origin --prune
git switch -c fix/<github-id>-restore-city-contracts origin/main
```

不要直接在旧功能分支上继续，也不要在 `main` 上提交。

### 2. 恢复城市契约与测试

如果 `main` 自 `96522dc` 以来没有修改过这些文件，可以直接恢复：

```bash
git checkout 96522dc -- \
  scripts/world/city_content.gd \
  scripts/world/city_generator.gd \
  tests/test_city.gd \
  tests/test_main_scene.gd
```

如果 `main` 后来对同一文件有新功能，先对比再手工补回：

```bash
git diff 96522dc..origin/main -- scripts/world/city_content.gd
```

只恢复被删掉的 `player_starts`、`get_available_player_starts()`、`MAX_PLAYER_STARTS` 和多起点生成，不要整文件覆盖别人的新代码。

### 3. 恢复主场景订单接线

- `scripts/core/main.gd`：增加 `@onready var orders: OrderManager = $OrderSystem`，在 `_ready()` 里调用 `orders.setup(world, navigation, player)`，玩家落位改用 `player.reset_to(world.city.player_start)`。
- `scenes/main/main.tscn`：恢复 `OrderSystem` 节点和 `order_manager.gd` 的 `ext_resource`，同时保留新的 `seed` 编辑器字段。
- `scenes/player/player.tscn`：把 `CollisionShape3D` 的 Y 改为 `0.9`；如果模型或胶囊尺寸变化，按“胶囊中心 = 高度 / 2”重新计算，保证胶囊底部落在玩家原点。

### 4. 恢复 CI 与 LFS

- `.github/workflows/repository-integrity.yml` 的测试列表必须包含 `test_orders`。
- 如果 `.glb` 被写成普通 blob：

```bash
git lfs install --local
git add --renormalize -- '*.glb'
git lfs push origin <branch>
git push
```

先上传 LFS 对象再推送提交，否则 GitHub 会以 `GH008: unknown Git LFS object` 拒绝。

### 5. 运行校验

```bash
GODOT="/d/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
"$GODOT" --headless --path . --import
for test in test_road_network test_main_scene test_contracts test_input_actions test_navigation_queries test_city test_god_view test_orders; do
  "$GODOT" --headless --path . --script "res://tests/${test}.gd"
done
git lfs fsck --pointers
```

期望结果：

- 导入退出码为 0。
- 八个测试全部 `exit=0`。
- `test_main_scene` 输出包含 `starts=12`、`order_seed=...`、`sky=true`。
- `test_god_view` 输出 `PASS god view debug=true`。
- `test_orders` 输出 `PASS orders starts=12`。
- `Git LFS fsck OK`。

## 防止再次发生

- 不使用 GitHub 网页 “Add files via upload” 覆盖项目文件；统一 `git fetch`、短分支、PR。
- 每个 PR 只做一件事，评审时重点检查删除行、契约字段、测试和 CI 列表。
- `main` 开启分支保护，要求 PR、`integrity` 和至少一名评审，禁止强推。
- CI 测试列表建议改为自动发现 `tests/test_*.gd`，避免删掉测试项后 CI 仍然变绿。
- 修改 `scripts/world/`、`scripts/core/`、`main.tscn`、`player.tscn`、CI 等共享文件前，按 `CONTRIBUTING.md` 通知对应负责人。

## 本地留存位置

- `E:/Project/Game Work Team/backups/song-wai-mai-20261028.bundle`
- `E:/Project/Game Work Team/backups/song-wai-mai-20261028-lfs-objects/`
- 恢复说明：`E:/Project/Game Work Team/backups/README.md`

# 3D 手机接单通知

## 运行与交互

Godot 4.7.2，打开项目后 F5。无须手动配置材质或拖入节点。

- 启动后，现有 OrderManager 生成的真实订单先在手机待确认，接单后才创建配送会话和启动计时。
- **O**：调试构建生成模拟订单（小镇披萨店／商业街 12 号／幸福小区／1.2 km／¥8.50）。
- **Y**：接受当前通知；**N**：拒绝当前通知。
- 正式订单被拒绝后，按原有 **R** 获取下一单；配送中的 R 保持原来的重开行为。
- 模拟订单 ID 使用 phone-demo/ 前缀，不会启动、拒绝或替换真实配送。模拟操作结束约 2 秒后，如果还有正式待接订单，会恢复其通知。
- 临时快捷键只在 scripts/ui/phone_screen.gd 定义。关闭现有屏幕节点的 enable_test_orders 即禁用 O；正式导出也不会响应 O。
- 保留原生 Button，但本轮未增加 3D 射线点击转发。鼠标点击 3D 屏幕不会自动变成 UI 点击，第一版使用 Y/N；未来可把映射后的事件传给已有 SubViewport.push_input。

## 最终节点结构

```text
Player（原控制器、车辆与 Camera3D 保持原关系）
└── MeshInstance3D（现有手机屏幕，PhoneOrderScreen）
    └── SubViewport（现有，720×1080，唯一）
        └── Phone_Ui（现有根 Control，撑满屏幕）
            └── OrderNotification（复用场景，PhoneOrderNotification）
                ├── ScreenBackground
                ├── StatusBar / IdleLabel / Feedback / KeyboardHint
                └── PanelContainer
                    └── MarginContainer
                        └── VBoxContainer
                            ├── Header / 英文副标题 / 分隔线
                            ├── ShopLabel
                            ├── PickupLabel
                            ├── DestinationLabel
                            ├── DistanceLabel
                            ├── Earnings
                            │   ├── 预计收入
                            │   └── RewardLabel
                            └── ButtonContainer
                                ├── RejectButton
                                └── AcceptButton
```

卡片由可复用场景脚本在 ready 时构建一次。重复通知只更新数据并取消旧 Tween，不增建卡片或 SubViewport。UI 与订单数据分离，进场为顶部滑入与淡入，出场为轻微上移与淡出，接受后显示 1.5 秒成功提示。长名称与地址最多显示两行并截断。

## 外部订单接口

从主场景调用现有屏幕适配器，或者直接调用通知组件：

```gdscript
var screen := $Player/MeshInstance3D as PhoneOrderScreen
var displayed := screen.show_order({
    "id": "backend-order-20261028-001",
    "shop_name": "小镇披萨店",
    "pickup_address": "商业街 12 号",
    "destination_address": "幸福小区",
    "distance_m": 1200.0,
    "reward_yuan": 8.50,
})
```

`show_order` 返回 bool；缺失必填字段、空 ID、无效/负数距离或报酬会返回 false，并保留已有通知。距离单位为米，报酬单位为人民币元。ID 由调用方保证唯一。组件发出 `order_accepted(order_id: String)` 与 `order_rejected(order_id: String)`，重复按键不会重复发信号。

显示任意字典本身不创建导航、配送会话或订单资源。外部后端应连接上述信号完成自己的业务确认。已接好的本地 OrderManager 只接受它当前待确认 ID，未知或过期 ID 返回 false：

- `order_offered(order_data)`：正式订单生成后通知屏幕。
- `get_phone_offer()`：返回当前待接数据副本。
- `accept_phone_order(id)`：匹配当前订单才进入已有 `_activate_order` 流程。
- `reject_phone_order(id)`：清空当前候选，不启动配送。
- `phone_notifications_enabled` 默认 false，保持未连接手机的既有消费者行为；main.gd 在 setup 前绑定现有手机时启用。

当前 CitySite 没有真实店名、街道地址或报酬字段：正式订单暂用站点 ID／地块编号，收入为 **5 元 + 每公里 2.5 元的展示估算**，集中在 OrderManager 常量中，不代表已实现结算或收益系统。接真实数据时替换 `_offer_on_phone` 的映射即可；模拟数据只在测试入口中定义。

## 手机与材质

复用原 BoxMesh、原 SubViewport 和原 Phone_Ui，不改 GLB、Mesh 顶点、Camera3D、车辆控制、项目设置或 PlayerController。

原 BoxMesh 的可见 +Z 面 UV 范围为 U 0～1/3、V 0～1/2，因此仅直接绑定纹理会裁掉 UI。本轮使用材质 `uv1_scale=(3,2,1)` 映射整张屏幕，禁用纹理重复，并使用独立的 Local to Scene / Unshaded 材质。运行时绑定已有 viewport.get_texture()，防止多实例共享错误纹理。

为确保第一人称可读，调整了现有屏幕节点的位置和缩放（不是 Mesh 几何）：位置 `(-0.20,1.86,-0.554344)`，缩放 `(3.125,2.5,1)`。屏幕仍挂在 Player 下；实际显示比例与 720×1080 一致。未改车体或相机。以后需要更真实的手机尺寸时，可在该屏幕节点调整 Transform，但应同时复查第一人称文字可读性。

## 修改清单

新增：
- scripts/ui/order_notification.gd 及 UID
- scripts/ui/phone_screen.gd 及 UID
- scenes/ui/order_notification.tscn
- tests/test_phone_ui.gd 及 UID
- docs/PHONE_ORDER_UI.md

修改：
- scenes/player/player.tscn：复用现有节点接入 UI、材质和屏幕显示变换。
- scripts/core/main.gd：在现有订单 setup 前连接手机。
- scripts/orders/order_manager.gd：最小待接单入口与 ID 校验；保留已有配送状态机。
- tests/test_orders.gd、tests/test_main_scene.gd：在既有配送断言前显式接受候选订单；不删减原配送断言。

## 验证与已知问题

- Godot 4.7.2 D3D12 Forward+ 实际运行主场景，保存第一人称手机、UI 全图和接单反馈截图；确认整个卡片映射到已有 3D 屏幕。
- 图形模式输入回归输出 `GRAPHICAL mouse steering preserved: true`。玩家移动与转向脚本、车辆 GLB 均未修改。
- `test_phone_ui` 通过：原 Viewport/材质关联、原 Mesh 尺寸、O/Y/N 真实输入分发、进出场动画、接单成功反馈、连续更新不叠加、按钮信号、非法数据、长内容适配、正式接单/拒单、旧 ID 拒绝、模拟单不改变真实配送、移动未暂停。
- 订单、主场景、输入、城市、契约、导航、道路、几何边界、编辑器 Seed 预览测试通过；共 10 项通过。
- `test_god_view` 的“玩家根节点不低于地面”断言失败。在未写入手机改动的原项目中复测也失败，确认为现有基线问题；未修改玩家位置、碰撞或该断言来掩盖它。
- headless 沙箱有 Windows 根证书读取提示；编辑器可能继续报告已有 FBX 导入器和退出 RID 提示。图形主场景验证未出现项目脚本解析、节点路径或资源引用错误。

运行专项：`godot --headless --path . --script res://tests/test_phone_ui.gd`。

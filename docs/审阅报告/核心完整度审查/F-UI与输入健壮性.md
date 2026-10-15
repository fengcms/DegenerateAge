# 核心完整度审查 · 问题域 F：UI / 输入健壮性

> 配套：`00-总体方法论.md`、`01-审计计划.md` §2 问题域 F。
> 基线快照：`773b7d1`（工作区含协作者未提交改动，见 §1 与 §6）。
> 审查方式：静态阅读为主、对照既有测试断言为辅，未运行任何测试命令。
> 范围：**只审交互健壮性**——面板互斥、输入接管、层级、缩放、本地化、中间状态回退。**纯美术观感不计为系统缺陷**。

---

## 1. 覆盖范围与未覆盖项

**覆盖（已核对）**

- 面板互斥与登记：`set_panel_open` / `_open_panels` / `panel_open` / `close_all_panels` / `npc_dialog_open`。
- 输入接管：`player.gd` 面板期屏蔽手动移动/攻击；`game.gd` 世界点击、右键、F/G、E、Tab、坐骑、Esc；`menu_panel.gd` 暂停。
- 自动战斗手动接管语义：`auto_battle.gd` 全 `_physics_process` 分支（关闭/死亡/打坐/NPC 会话/暂停/手动接管计时）。
- 层级：`floating_window.gd`（`bring_forward` / `is_top_window` / `_on_box_input` / `_clamp`）、`drag_ghost.gd`、`ui_layer.gd`、`Main.tscn` 的 DragLayer / EquipmentConfirmation / Hud `ToastBox`。
- 缩放：`settings_runtime.gd` 三轴倍率与 `apply_ui_scale_to`；`settings_test.gd::_check_panels_matrix` 的越界断言范围。
- 本地化：`localization.gd` 缺 key 回退与可检测性。
- 中间状态回退：货郎出售托盘（`shop_panel.gd`）、换装确认浮层（`equipment_confirmation.gd`）、通用确认层（`panel_confirm_dialog.gd`）。
- 暂停语义：暂停菜单冻结 `world_time`、普通面板不冻结。
- 历史问题闭环核实：`docs/素材设计/08`、`docs/素材设计/10`。

**未覆盖 / 说明**

- 未实际运行任何测试（任务要求），缩放的极端组合结论部分标注「（推断）」。
- 手感、动画观感、SVG 视觉表现不评。
- 协作者未提交改动 `scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`、`docs/测试反馈.md` 本次只读不改；结论基于当前工作区内容，若其改动进入正式提交需复核。
- 排除项（美术资源、后续章节、数值配置、第二章开发）不作为缺陷。

---

## 2. 完整度评估

**F 域整体：B（基本可用）**

依据：

- 主路径可走通且有自动化验证：面板互斥、浮窗拖动/命中一致性、Toast/拖拽层级、四边贴合与缩放，均有对应断言（`floating_window_input_test.gd`、`panel_chrome_layout_test.gd`、`settings_test.gd::_check_panels_matrix`、`input_feedback_test.gd`、`flow_feedback_test.gd`、`hotbar_ui_test.gd`）。
- 历史层级/对齐问题已闭环（见 §6），无残留状态残留路径。
- 未达 A 的原因：存在未处理的边界（缺 key 带参报错、极端倍率组合越界未覆盖、面板互斥登记分散），且以下问题为 P2（非阻断交付）。
- 无 P0/P1：未发现进度丢失、崩溃或核心循环中断。

---

## 3. 问题清单

### P2-1 · 手动接管恢复时长与需求文档冲突，且与产品 04 §4.6 不一致

- **位置**：[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L53)（`MANUAL_RESUME_DELAY := 1.5`，注释标「(s，4.6)」）。
- **现象**：代码手动接管后恢复延迟为 **1.5 秒**；而 [产品 04 §4.6 L92](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/04-角色成长系统.md#L92) 写「连续 **3 秒** 无手动输入后恢复」，[产品 03 §硬性异常规则 L165](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/03-核心循环与战斗系统.md#L165) 写「松手后 **1.5 秒** 恢复」。
- **复现**：开启自动战斗，手动移动/攻击后松手，约 1.5 秒即恢复自动决策（`auto_battle.gd#L199-L205`）。
- **影响**：需求基准不唯一，玩家感知的接管手感与产品 04 描述不符；后续调参易两头对不上。
- **建议**：确认唯一目标值（3 s 还是 1.5 s），统一 04 与 03，并同步常量与注释。
- **证据等级**：E2（代码）+ E3（文档）。

> 用户手动补充，这里我调整为 1.5 秒了。

### P2-2 · 缺本地化 key 且带参数时，回退路径会触发字符串格式化错误

- **位置**：[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L43-L51)。
- **现象**：`tr_key` 未命中时回退为 key 本身（`text = key`，L48），随后若 `args` 非空直接执行 `return text % args`（L51）。当该 key 文案中不含 `%` 占位符时，`"ui.xxx" % [..]` 会触发 GDScript 格式化错误，而非优雅降级。
- **复现条件**：任意带 `args` 的调用（如 `tr_key("ui.shop_panel.p016", [...])`）在 key 缺失/文案无占位符时触发。
- **影响**：正常态文案齐全时不显现，但作为「缺 key 可检测」健壮性承诺，缺 key 的失败模式是脚本错误而非安全回退；`missing_keys()`（[L57-L58](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L57-L58)）能记录但无测试断言消费（全仓未见 `missing_keys` 使用）。
- **建议**：`tr_key` 在未命中时若 `args` 非空，只返回 key 不做 `%` 填充（或先校验占位符），并在冒烟中补一条 `missing_keys()` 为空的断言。
- **证据等级**：E2（代码）。

### P2-3 · 高倍率组合下面板最小尺寸可能超出逻辑视口，右下控件/关闭键落到屏外（覆盖上限未测到 3.0）

- **位置**：[floating_window.gd `_clamp`](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L102-L105) 与 [`_layout`](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L87-L100)；倍率来源 [settings_runtime.gd L11-L20](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L11-L20)、[L234-L235](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L234-L235)。
- **机制**：`apply_ui_scale_to` 把 UI 直接子控件尺寸设为逻辑尺寸 `viewport / scale`（[L219-L232](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L219-L232)）；`_clamp` 只在 `[0, owner.size - panel_min]` 内夹紧位置。当 `panel_min > owner.size` 时 `max(0, …) = 0`，面板被钉在 `(0,0)` 并向右下溢出——关闭键在标题行右侧、背包底部按钮（整理/扩容/出售/筛选，[inventory_panel.gd L198-L215](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/inventory_panel.gd#L198-L215)）会落到屏外。
- **复现条件**：`uiScale = 2.0`（UI_SCALE_MAX）且 `displayScaleMode = manual`、`displayScale = 1.5`（DISPLAY_SCALE_MAX）→ 最终倍率 3.0；在 1280×800 时逻辑视口仅约 426×266。
- **覆盖缺口**：[settings_test.gd `_check_panels_matrix` L336-L391](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/settings_test.gd#L336-L391) 只测 `factor ∈ {0.8,1.0,1.5,2.0}`（未乘 manual displayScale），且「面板完整落在可见区域」的四边断言只对 `QuestPanel / MapBigPanel / WarehousePanel / SettingsPanel` 施加；背包、货郎、车夫等含关闭键/底部按钮的面板**未做越界断言**。
- **影响**：极端缩放档下关键按钮可能不可点（Esc 仍可关面板，缓解但不等于可用）。
- **建议**：`_clamp` 在 `panel_min > owner.size` 时按内容自适应（缩放面板本体或启用滚动），并把「面板含关闭键的标题行完整落在可见区域」的断言扩展到四常驻浮窗与货郎/车夫面板；把倍率矩阵补到 3.0 组合。
- **证据等级**：E2 + E1（现有测试覆盖面，L336-L391）。

### P3-1 · 面板互斥登记分散，新增面板需手动登记例外名单

- **位置**：[game_state.gd `set_panel_open` L960-L967](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L960-L967)；例外名单散落于各面板 `_on_panel_opened`：[inventory_panel.gd L92-L100](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/inventory_panel.gd#L92-L100)、[skill_panel.gd L35-L37](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/skill_panel.gd#L35-L37)、[character_panel.gd L48-L52](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L48-L52)、[mount_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/mount_panel.gd)、[shop_panel.gd L106-L112](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L106-L112)。
- **现象**：`_open_panels` 仅做集合登记，互斥规则靠「每个面板订阅 `panel_opened` 各自实现例外」；多处硬编码 `["shop","character","skill","mount"]` 之类列表。注释亦承认此分工（[L961](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L961)）。
- **影响**：新增面板时若漏登记例外，会出现在不该互斥/该互斥时行为不一致；规则无单一事实源。
- **建议**：把「可并开集合」收敛为 `GameState` 侧的一张表（面板注册时声明所属组），各面板只查询不各自维护列表。
- **证据等级**：E2。

### P3-2 · `close_all_panels` 只清登记、不回退面板中间态，正确性依赖「调用点必伴随场景重载」

- **位置**：[game_state.gd close_all_panels L95-L99](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L95-L99)。
- **现象**：`close_all_panels` 仅 `cancel_equipment_change()` + 清空 `_open_panels` / `panel_open`，不关闭面板节点、不触发货郎托盘的退回。当前三个调用点都伴随场景重载（[travel_item.gd L35](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L35)、[map_service.gd L368](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L368)、[save_manager.gd L649](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L649)），面板随场景销毁，因此**当前不会丢托盘**（[shop_panel.gd L99-L103](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L99-L103) 的退回逻辑在正常关面板时生效）。
- **影响**：属结构性脆弱——若未来新增「不重载场景」的调用点，货郎出售托盘内已从背包移出的装备会被静默丢弃（推断：目前无可达路径）。
- **建议**：`close_all_panels` 改为广播统一关闭事件（或直接调用各面板 `set_open(false)`），使中间态回退与登记清空成对。
- **证据等级**：E2（结构）+ 推断（未来路径）。

### P3-3 · 面板打开期可操作性差异（坐骑切换不受限；F/G 开关不一致）

- **位置**：[game.gd L330-L334](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L330-L334)（`mount_toggle` 不检查 `panel_open`）、[game.gd L373-L385](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L373-L385)（F 面板打开也可用，G 仅面板关闭时可用）。
- **现象**：面板打开时手动移动/攻击/世界点击/右键/E/Tab 均被屏蔽（见 §4 结论），但坐骑切换仍生效，F 与 G 的可操作性也不一致。
- **影响**：注释已注明为有意设计（[L329](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L329)），但与「面板打开屏蔽角色操控」的统一语义不完全一致；是否保留需产品确认，不单独判缺陷。
- **证据等级**：E2。

---

## 4. 关键问题逐条结论（含证据）

### 4.1 面板互斥是否正确？多面板/关闭其一/嵌套确认是否有残留？是否可操控角色？

**互斥实现正确、无残留。** `set_panel_open` 以集合登记，`panel_open = not _open_panels.is_empty()`（[game_state.gd L962-L967](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L962-L967)）；读档/重载前 `close_all_panels` 清空（[L95-L99](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L95-L99)）。

- **并开是既定语义**：背包 / 人物 / 技能 / 坐骑可并开（各 `_on_panel_opened` 互相 return 不关）；交易会话中货郎 + 背包并排（[shop_panel.gd L105-L112](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L105-L112)、[inventory_panel.gd L91-L100](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/inventory_panel.gd#L91-L100)）。
- **关闭其一不残留**：`set_open(false)` 即从集合移除；Esc 在多个并开浮窗中由 `is_top_window()` 决定唯一目标（[floating_window.gd L65-L71](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L65-L71)；[skill_panel.gd L18-L22](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/skill_panel.gd#L18-L22)），事件未被处理则交由下一个并开面板。
- **嵌套确认弹层无残留**：换装确认打开时置 `equipment_confirm=true` 并暂停（[equipment_confirmation.gd L132-L136](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L132-L136)）；关闭/Cancel 时 `cancel_equipment_change` 清空 `pending_equipment_change` 并广播 `equipment_confirmation_closed`（[game_state.gd L642-L646](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L642-L646)），`_close` 注销登记（[L141-L151](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L141-L151)）、`_exit_tree` 兜底取消（[L166-L170](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L166-L170)）；通用确认层 Esc 只取消自身、不外溢关闭父面板（[panel_confirm_dialog.gd L36-L39](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/panel_confirm_dialog.gd#L36-L39)）。
- **「面板打开仍可操控角色」漏洞：手动操控无漏洞。** 手动移动被屏蔽（[player.gd L272-L279](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L272-L279)：`panel_open and not auto_battle_on` → 速度归零）、方向输入归零（[L282](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L282)）、普攻/施法被屏蔽（[L292](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L292)、[L312](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L312)）；世界点击/右键/E/Tab/坐姿被 `not GameState.panel_open` 屏蔽（[game.gd L335-L390](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L335-L390)）。**唯一例外**：`mount_toggle` 不受限（P3-3）。**自动战斗开启时角色仍自主移动/战斗**（[player.gd L272 注释](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L272)、产品 03 L168「普通面板打开仍继续」），属既定设计。

### 4.2 自动战斗手动接管语义（立即接管 / 恢复）

**实现与边界基本正确**，但恢复时长存在文档冲突（P2-1）。

- `begin_manual_override` 在输入到达即清空目标/寻路并进入接管态（[auto_battle.gd L209-L217](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L209-L217)），`_physics_process` 持续检测手动输入刷新计时、松手后倒计时（[L195-L206](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L195-L206)）。
- **边界**：关闭优先于接管计时（[L150-L159](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L150-L159)）；死亡先于接管（[L161-L168](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L161-L168)）避免计时未走完漏关；打坐（[L169-L174](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L169-L174)）、NPC 会话（[L175-L187](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L175-L187)）、真暂停（[L189-L193](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L189-L193)）分别暂停决策。
- **面板打开**：普通面板**不**暂停决策（L196 以 `not panel_open` 为手动检测前提、且不被拦截），与产品 03 L168 一致；但此时手动接管无法触发（被面板屏蔽），属于「面板期间自动继续、手动让位」的自洽结果。
- **潜在交互**：面板打开 + 自动战斗开启时，松开按键不会进入 `MANUAL_OVERRIDE`（`_has_manual_input` 因 `panel_open` 被跳过，[L608-L615](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L608-L615)），角色持续自动行动——非缺陷，但需产品确认体验。

### 4.3 层级：拖拽 / 浮窗 / 右键 / Esc / Toast

**稳定，历史问题已闭环**（详见 §6）。

- **浮窗置顶**：`bring_forward` 先把宿主 `move_child` 到最后一个可见浮窗位置，再按树序重算 `z_index = i+1`，使**视觉层级与鼠标命中序同源**（[floating_window.gd L45-L63](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L45-L63)）；`is_top_window` 据此判前台（[L65-L71](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L65-L71)）。移动仅到「最后常驻浮窗」位置，不越过后面的设置/模态层（[L53-L56 注释](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L53-L56)）。
- **标题上沿可拖**：`_on_box_input` 以 `header_top` 判定可见标题带并起拖，按钮区仍交回按钮处理（[L107-L119](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L107-L119)）。
- **拖拽幽灵**：挂 UI 层最高专用层（[Main.tscn L90-L98 DragLayer z=4096](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scenes/Main.tscn#L90-L98)），`z_index=Z(4096)`、`mouse_filter=IGNORE`、宽限期自毁（[drag_ghost.gd L15-L21](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/drag_ghost.gd#L15-L21)、[L85-L125](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/drag_ghost.gd#L85-L125)）。
- **Toast 不被面板遮挡**：`ToastBox z_index=2048`（[Hud.tscn L323-L333](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scenes/ui/Hud.tscn#L323-L333)），普通面板 `z_index=0`、换装确认 4095、拖拽层 4096；由于 z_index 沿祖先累加，Toast 有效层级 2048 高于所有普通面板，绘制在面板之上。该约定有专门断言（[settings_test.gd L327-L335](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/settings_test.gd#L327-L335)）。仅换装确认遮罩（4095）与拖拽幽灵（4096）会短暂覆盖 Toast，属模态/拖拽期间的预期表现。
- **右键不越权**：右键世界意图仅在 `not panel_open` 下派发（[game.gd L359-L364](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L359-L364)）。
- **Esc**：面板（背包/人物/技能）经 `is_top_window` 决定关闭目标，暂停经 `menu_panel`（[menu_panel.gd L29-L37](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/menu_panel.gd#L29-L37)）；`UI` CanvasLayer 为 `process_mode=3`（ALWAYS）故暂停时仍收键（[Main.tscn L31-L32](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scenes/Main.tscn#L31-L32)）。

### 4.4 高分辨率 / 缩放 / 长文本 / 缺 key

- 三轴倍率：界面 `0.8–2.0`、地图 `0.8–2.0`、文字 `0.8–2.0`，最终值再乘 manual 显示系数 `0.75–1.5`（[settings_runtime.gd L11-L20](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L11-L20)、[L88-L93](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L88-L93)、[L234-L235](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L234-L235)）。
- 逻辑视口随倍率收窄、文字轴按「目标/当前界面」补偿避免叠乘（[L253-L270](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L253-L270)）；窗口 `size_changed` 同帧合并重排（[main.gd L25-L37](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd#L25-L37)）。
- **长文本**：面板与提示普遍启用 `AUTOWRAP_WORD_SMART` 且容器内换行（如 [shop_panel.gd L219-L224](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L219-L224)、[equipment_confirmation.gd L100-L105](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L100-L105)）；换装确认的滚动区高度随视口收缩（[L107-L112](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L107-L112)）。
- **越界风险与覆盖缺口**：见 **P2-3**；现有测试对关键面板的四边越界断言不全（[settings_test.gd L336-L391](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/settings_test.gd#L336-L391)）。
- **缺 key 可检测**：`tr_key` 未命中 `push_warning` 并回退为 key，`missing_keys()` 供测试断言（[localization.gd L41-L58](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L41-L58)）——检测机制在，但**带参缺 key 会格式化报错**（P2-2），且未见测试消费 `missing_keys()`。

### 4.5 关闭面板未确认的中间状态

- **货郎出售托盘**：关闭即 `_return_tray()`，逐件退回背包；背包满的件保留并提示（[shop_panel.gd L89-L103](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L89-L103)、[L549-L561](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L549-L561)）；托盘操作以实例反查下标防位移误移（[L464-L491](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L464-L491)）。**正确回退**，但 `close_all_panels` 路径不回退（P3-2，当前不可达）。
- **装备更换确认浮层**：Cancel/关闭/Esc/死亡均取消并恢复暂停态（[equipment_confirmation.gd L138-L160](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L138-L160)、[L24](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L24)）；确认前二次校验物品与已穿戴快照，条件变化即取消（[game_state.gd L616-L640](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L616-L640)）。**正确**。

### 4.6 面板打开时世界时钟 / 战斗暂停语义

**一致**。`world_time` 与冷却心跳在 Autoload `_process` 推进，面板打开照常、`get_tree().paused` 时停止（[game_state.gd 字段注释 L64-L68](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L64-L68)、[L106-L111](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L106-L111)）。

- 暂停菜单冻结世界：`_show` 置 `paused=true`（[menu_panel.gd L62-L66](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/menu_panel.gd#L62-L66)），`resume_game` 解冻（[L56-L60](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/menu_panel.gd#L56-L60)）；死亡面板同样暂停并解冻（[death_panel.gd L57-L64](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L57-L64)、[L115-L118](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/death_panel.gd#L115-L118)）。
- 普通面板不冻结：`panel_open` 不改变 `paused`，自动战斗决策仅在真暂停停止（[auto_battle.gd L189-L193](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L189-L193)），与产品 03/04 及工程文档 14 结论一致。
- 换装确认临时暂停并**按打开前状态**恢复（不抢占主菜单/死亡/加载的暂停，[equipment_confirmation.gd L147-L151](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/equipment_confirmation.gd#L147-L151)）——需注意它强制暂停会同时冻结 `world_time`，属短时模态的预期代价。

---

## 5. 落地优化方案

1. **统一手动接管时长（P2-1）**：定稿 3 s 或 1.5 s；同步 `MANUAL_RESUME_DELAY`（[auto_battle.gd L53](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L53)）与产品 04 §4.6 / 03 §硬性异常规则。
2. **本地化回退安全化（P2-2）**：`tr_key` 未命中且含 `args` 时直接返回 key，不做 `%`；补冒烟断言 `Localization.missing_keys().is_empty()`。
3. **缩放越界保护与覆盖补齐（P2-3）**：`FloatingWindow._clamp` 在 `panel_min > owner.size` 时对面板本体做等比缩放或启用滚动；把「含关闭键标题行四边在屏内」断言扩展到四常驻浮窗 + 货郎/车夫；倍率矩阵补到 `uiScale×displayScale` 的上限组合（3.0）。
4. **面板互斥单一事实源（P3-1）**：在 `GameState` 侧维护「可并开组」声明，各面板只查询，去掉四处硬编码例外列表。
5. **`close_all_panels` 与中间态成对（P3-2）**：改为广播统一关闭/直接调 `set_open(false)`，使托盘退回与登记清空一致。
6. **可操作性语义确认（P3-3）**：确认 `mount_toggle` 与 F/G 在面板打开期的期望行为，必要时统一或补注释说明。

> 全部改动为建议，本次不修改源码/配置/数据。

---

## 6. 与既有文档的差异说明

### 6.1 历史问题闭环核实（`docs/素材设计/08` / `10`）

| 历史问题（08/10） | 现状 | 结论 |
|---|---|---|
| 08 蓝圈：标题渐变矩形压住/覆盖内层折线 | `PanelChrome._draw` 改为按切角多边形绘制标题带（[panel_chrome.gd L53-L66](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/panel_chrome.gd#L53-L66)） | **已闭环** |
| 08 红框：标题上沿可见却拖不动 | `_on_box_input` 按 `header_top` 接管标题带拖动（[floating_window.gd L107-L119](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L107-L119)），测试断言「标题上沿能起拖、按钮不起拖」（[floating_window_input_test.gd L65-L85](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/floating_window_input_test.gd#L65-L85)） | **已闭环** |
| 08 黄框：`z_index` 与鼠标命中序不一致、Esc 目标不一致 | `bring_forward` 先 `move_child` 再按树序重算 `z_index`（[floating_window.gd L45-L63](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/floating_window.gd#L45-L63)），测试断言「视觉层级=命中序=前台」（[floating_window_input_test.gd L30-L62](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/floating_window_input_test.gd#L30-L62)） | **已闭环** |
| 10 标题行落在 12/16/18 三种上边距、压分隔线、帮助/关闭按钮不同径 | `PanelChrome` 新增统一标题行入口 `style_header_layout`（[panel_chrome.gd L94-L98](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/panel_chrome.gd#L94-L98)），上边距由 `HEADER_MARGIN_TOP=57-40-7` 推导（[L11-L15](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/panel_chrome.gd#L11-L15)）；`style_help` 直径改为 40 与关闭钮一致（[L101-L106](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/panel_chrome.gd#L101-L106)）；测试断言四个浮窗统一上边距、行底不越分隔线、两钮同高（[panel_chrome_layout_test.gd L45-L65](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/panel_chrome_layout_test.gd#L45-L65)） | **已闭环** |

> 结论：08/10 所述的三类边界不一致与对齐漂移在代码与测试层面均已闭环，未发现回归。

### 6.2 与本次其他文档的差异

- 与 `01-审计计划.md` §2 F 的 5 条要查问题全部作答，无额外新增问题域。
- **需求文档内部冲突**（新增记录）：产品 04 §4.6「3 秒恢复」vs 产品 03 §硬性异常规则「1.5 秒恢复」，代码取 1.5（P2-1）。建议在 04/03 间定稿，避免后续按 04 调参引入回归。
- **与既有结论一致**：工程文档 14 §2/R-b「面板打开照常走、Esc 暂停冻结 world_time」经本次静态复核成立（§4.6）。
- **工作区快照提示**：`scripts/ui/shop_panel.gd` 为协作者未提交改动文件，本文对其结论（托盘退回、层级）仅覆盖当前工作区内容；若该文件正式提交内容变化，§4.3/§4.5 相关结论需复核。

---

## 7. 证据与复核方法

**静态复核入口（不需运行测试）**

- 面板互斥：`grep -n "set_panel_open\|_open_panels\|panel_opened" autoload/game_state.gd scripts/ui/*.gd`
- 输入接管：阅读 [player.gd L272-L313](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L272-L313)、[game.gd L328-L390](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L328-L390)。
- 自动战斗接管：阅读 [auto_battle.gd L145-L218](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L145-L218)、[L608-L615](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L608-L615)。
- 层级：`grep -n "z_index" scenes/Main.tscn scenes/ui/Hud.tscn scripts/ui/drag_ghost.gd scripts/ui/equipment_confirmation.gd`
- 缩放：阅读 [settings_runtime.gd L201-L270](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L201-L270)。
- 本地化：阅读 [localization.gd L41-L58](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L41-L58)。

**可复核的既有测试断言（供他人核对，本次未运行）**

- [floating_window_input_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/floating_window_input_test.gd)：拖动、命中序、前台一致。
- [panel_chrome_layout_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/panel_chrome_layout_test.gd)：标题行统一上边距/不越线/圆钮。
- [settings_test.gd L300-L391](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/settings_test.gd#L300-L391)：四边贴合、z_index 约定、设置窗口在屏内。
- [input_feedback_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/input_feedback_test.gd)、[flow_feedback_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/flow_feedback_test.gd)、[hotbar_ui_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/hotbar_ui_test.gd)：目标/提示反馈与快捷栏。`map_canvas_cache_test.gd` 属性能域，本域不引用。

> 建议的实际验证（需另行确认后执行，本次未运行）：**P2-3 的越界**可用「临时在 `tests/` 放置探针场景」实测：把 `uiScale=2.0`、`displayScaleMode=manual`、`displayScale=1.5`，逐个打开四常驻浮窗与货郎/车夫面板，读取其 `PanelContainer` 的 `global_position`/`size` 与逻辑视口对比；分析完删除探针（`tests/` 屏蔽自动存档，安全）。**P2-2 的缺 key** 可用临时探针调用 `tr_key("ui.__missing__", [1])` 观察是否报格式化错误。

# B · 系统架构与数据驱动

> 问题域：`01-审计计划.md` §2 问题域 B。
> 基线快照：`773b7d1`；执行日期：2026-10-15。
> 判定标准：完整度 A–E、缺陷 P0–P3、证据等级 E1–E4 —— 均取自 `00-总体方法论.md` §4。
> 证据手段：静态阅读（E2）+ 全库文本扫描（E2/E3，命令见 §4）。本域为结构审查，不含运行表现，故基本无 E1。

---

## 1. 覆盖范围与未覆盖项

### 1.1 已覆盖

- 8 个 Autoload 的职责与越界核查： [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L1-L60)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L1-L8)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1-L118)、[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L1-L45)、[quest_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/quest_service.gd#L1-L23)、[event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L1-L84)、[audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L1-L86)、[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L1-L65)。
- 数据加载器启动校验全量规则： [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L102-L243) 及其 6 个子校验函数（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L250-L352)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L355-L464)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L467-L495)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L508-L600)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L602-L720)、[warehouse.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/warehouse.gd#L50-L57)）。校验结果消费点 [main.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd#L16-L21)。
- 模块分层与职责边界：`scripts/systems/`（规则结算）、`autoload/`（运行状态 / 服务）、`scripts/ui/`（表现）、`scripts/entities/`、`scripts/world/`。
- 公共接口稳定性：EventBus 53 个信号的「定义 / emit / connect」全库计数（见 §4）。
- 共用规则唯一入口：伤害 [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L30-L49)、售价 [shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L76-L120)、派生属性 [equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd#L1-L30)、等距投影 [iso.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/iso.gd#L1-L50)。
- 全局类组织：62 个 `class_name` 的名字唯一性与双向引用扫描（见 §4）。
- 产品基准：`产品文档/10` §10.1 数据驱动原则、§10.2 配置清单与 Schema、§10.4「配置校验：ID 唯一 / 权重 / 引用合法 / 等级范围」；`AGENT.md` §2、§6、§9。

### 1.2 未覆盖（本域不评或标推断）

- 具体数值配置正确性（属 E 域与调平范围）；本域只判「字段是否有校验」。
- 存档 schema / 迁移正确性（属 C 域）；本域只引用其字段名作为校验对照。
- 性能热路径与缓存键（属 D 域）；本域仅在涉及「双份加载」时引用。
- UI 布局、输入接管细节（属 F 域）。
- 未跑完整手动流程；凡「运行期是否真的触发」均标（推断）。

---

## 2. 完整度评估（A–E 逐项 + 依据）

### 2.1 问题 B-1 · Autoload 职责与越界

| Autoload | 一句话职责 | 是否越界 |
|---|---|---|
| save_manager | 3 槽单机存档、原子写、备份恢复、版本迁移（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L1-L23)） | 否 |
| data_loader | 读取 `res://data/` 各 JSON 并在启动时校验，非法明确报错（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L1-L8)） | 否 |
| game_state | 跨场景运行时状态（角色/经济/进度/设置），不持久化节点对象（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1-L6)） | 轻微偏宽（见 P3-4） |
| map_service | 地图查询 + 车夫出行 + 场景重载，因需 `get_tree()` 故为 Autoload（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L11-L13)） | 否 |
| quest_service | 「薄接线」，把战斗/拾取信号桥接到 `Quest` 静态层，无业务逻辑（[quest_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/quest_service.gd#L1-L23)） | 否 |
| event_bus | 全局信号集中定义，解耦系统通信（[event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L1-L7)） | 否 |
| audio_cues | 事件音效；自建 `AudioStreamPlayer` 作为**自身子节点**（[audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L17-L36)） | 否（非地图节点） |
| localization | 文案外置 key→text，缺失回退 key 并警告（[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L1-L13)） | 否（但与 DataLoader 重复加载同一文件，见 P3-2） |

- **无「把地图节点 / 临时对象长期挂全局」**：全库扫描 Autoload 内无 `Node` 类型字段持有；唯一 `p as Node2D` 出现在 [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L161)，为**保存瞬间**的局部取坐标，不驻留。
- `game_state` 内部承载的 `unclaimed_loot` / `spawn_respawn` / `world_time`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L59-L82)）是**有意上提**的地图运行态（工程文档 14 §1.1 记录根因），属跨场景状态而非节点，符合 AGENT §9。
- 分级：**A**（无越界挂节点；仅 `game_state` 承载 UI 会话状态，见 P3-4）。

### 2.2 问题 B-2 · 启动校验覆盖（对照产品 10 schema）

已覆盖的**正面结论**（均 E2）：

| 校验维度 | 覆盖位置 | 覆盖对象 |
|---|---|---|
| ID 唯一 + 缺键 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L107-L122)、唯一表清单 [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L33) | 13 张数组表（含 skills/quests/potions/miscItems/upgrade 之外的全部数组表） |
| 跨表引用存在性 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L124-L177)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L179-L213)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L355-L464)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L467-L495)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L674-L720) | monsters→dropTables；maps→monsters；maps npc→shops；dropTables→potions/runes/miscItems/mounts/lootPools/equipments；lootPools→equipments；affixes→monsters；elite affixPool→affixes |
| 数值范围 / 取整 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L152-L168)（tierRange 与刷新等级）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L219-L238)（runes/mounts）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L291-L301)（星级/品质） | 等级区间、概率 (0,1]、倍率 >0、品质词条数 0–4 |
| 权重合计 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L451-L463) | dropTables 品质概率合计 =100（容差 0.5） |
| 重复项 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L113-L122)（ID）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L323-L332)（词条池）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L629-L632)（出口 id）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L534-L541)（hubLinks） | 多表 |
| 结构 / 双向配对 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L602-L656)（出口↔入口双向）、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L508-L566)（hub/spoke 拓扑与费用） | maps 连通性 |

**未覆盖（缺口，E2）**：以下表在启动校验中**没有任何结构化校验**（既无类型、也无范围、也无引用检查），仅在 [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L33) 做 ID 唯一（其中 `upgrade` / `localization` 连 ID 唯一也不在列）：

- `skills.json`：`unlockLevel / kind / coefficient / cooldown / manaCost / shape / range / targetType` 全无校验。对照产品 10 §10.2 该表有明确字段清单。
- `quests.json`：`giver / objective.targetId / reward.item / mapScope` 无跨表引用校验；`targetId` 指向怪物/物品的存在性只在**运行期**零散判断（[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L150)、[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L269)），坏配置要到玩到该任务才暴露，与 §10.4「启动校验引用合法」不符。
- `potions.json`：`restoreAmount / cooldown / stackMax / price / kind` 无校验（仅被 dropTables 引用时校验**存在性**）。
- `miscItems.json`：`useType / animation` 无校验。
- `upgrade.json`：`successRate[13]`、`costParams.UP_BASE/UP_R` 无校验；[upgrade.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/upgrade.gd#L16-L18) 越界时静默返回 0.0，属「静默兜底」。
- `localization.json`：由 DataLoader 载入 `tables`（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L29)）却**无 key/结构校验**；同时 `Localization` 又独立读同一文件（见 P3-2）。
- 产品 §10.4 要求「类型、范围、重复项、默认值」四类；**默认值覆盖**（缺省字段是否合法）本域未见任何校验，缺省含义散落在各消费方的 `get(key, default)` 中。

- 分级：**B**（核心装备/掉落/地图表覆盖扎实，但 5 张表零结构化校验 + 任务引用不校验，存在「配置错到玩到才炸」的风险面）。

### 2.3 问题 B-3 · 模块职责边界

- 正向结论：**数据模板 / 运行状态 / 规则结算 / 视觉 / UI 分层清晰**。
  - 数据模板 = JSON + [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L40-L86)；运行状态 = [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L22-L88)；规则结算 = `scripts/systems/*` 纯静态层；实例唯一生成入口 [item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L1-L8)、[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L1-L10)、[loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd#L1-L19)、[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L1-L5) 的文件头均显式声明「只做语义、不依赖 UI」。
  - UI 只做**展示与意图**，动作统一经 `GameState` 服务：换装 [character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L225)、[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L240)；一键出售 [inventory_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/inventory_panel.gd#L351)；升星 [upgrade_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/upgrade_panel.gd#L261)。
  - **未发现 UI 重复结算业务逻辑**：UI 对「装备/掉落/伤害/奖励」均只调用规则层或 `GameState`：售价展示读同一入口 [shop_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L449)、[shop_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L598)；换装预览用纯函数 [item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L268)、[inventory_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/inventory_panel.gd#L310)；结算实收全库仅一份（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L461)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1005)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1021) 均调 `Shop.sell_price`）。
- **越界点（E2，见 P2-2 / P3-4）**：规则/服务层反向依赖场景树结构——`settings_runtime.gd` 用深路径 `"Game/Entities/Player/Camera2D"`（[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L280)）；`travel_item.gd` 用 `"Game"` / `"Ground"` / `"Camera2D"`（[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L23)、[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L56)、[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L70)）；`auto_battle.gd` / `monster.gd` 直接取 `"Ground"`（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L484-L502)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L896)）。这违反 AGENT §9「避免靠散落的节点路径、字符串或临时兼容分支串联系统」。
- 分级：**B**（分层设计正确，UI 未越权结算；扣分在系统层反向抓场景节点）。

### 2.4 问题 B-4 · 公共接口稳定性

- **信号重复定义：无**（`event_bus.gd` 53 个信号名 `uniq -d` 为空，E2）。
- **载荷与调用方一致**（抽查 E2）：`damage_dealt` 定义 [event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L9)，发出 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L566)，订阅 [audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L69) 三处一致；`boss_hp_changed` 定义 [event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L27)，发出 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L418)，订阅 [audio_cues.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/audio_cues.gd#L78)、[boss_health_bar.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/boss_health_bar.gd#L46) 一致。
- **定义并发出、但全库无订阅者（死广播）4 个（E2，见 P2-1）**：
  - `xp_gained` 仅 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1069) 发出，`connect=0`；
  - `buff_changed` 仅 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L118)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L141)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L146) 发出，`connect=0`，而 HUD 改用 `_process` 轮询（[hud.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hud.gd#L88-L89)）；
  - `item_dropped` 仅 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L883) 发出，`connect=0`（注意：UI 内另有**同名局部信号** `ItemSlot.item_dropped`，属不同作用域，见 [item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L28)，易混淆）；
  - `loot_spawned` 仅 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L884) 发出，`connect=0`。
  - **无「只 connect 无 emit」的信号**（全库扫描：所有 53 个信号均至少被发出一次）。
- **散落字符串 / 节点路径串联系统（E2，见 P2-2）**：`toast_requested` 的 `kind` 用字面量散写（`"danger"`×10、`"pickup"`×3、`"info"`×2），未在 `event_bus.gd` 集中为常量；节点路径耦合见 §2.3。
- 分级：**B**（无重复定义、载荷一致，但 4 个死信号 + 字符串/路径散落）。

### 2.5 问题 B-5 · 共用规则唯一入口

| 共用规则 | 唯一入口 | 是否存在第二处实现 / 重复常量 |
|---|---|---|
| 伤害公式 | [combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L30-L49) | 调用方玩家 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L496)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L557)，怪物 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L614)。**无第二套公式**；但暴击参数来源不一致（怪物侧硬编码 `1.0, 0.0, 1.5`，[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L617)；玩家侧读 `GameState.player`，[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L497-L498)）——见 P3-1。 |
| 售价公式 | [shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L114-L120) | 实收三处均调同一入口（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L461)…）。**字段名不匹配**：品质回退读模板 `tpl.get("quality")`（[shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L105-L111)），而 equipments.json 实际字段为 `defaultQuality`（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L321)、[equipments.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipments.json#L10)）——见 P3-3。 |
| 派生属性 | [equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd#L5-L30) + [equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L204-L213) + [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L272-L294) | 展示层 [item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L129-L156) 自算 `raw×quality×star_factor`（与 `base_attrs` 等价，未复用 `base_attrs`）——见 P3-5。 |
| 等距投影 / 瓦片尺寸 | [iso.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/iso.gd#L11-L12)（`TILE_W=64`、`TILE_H=32`） | **64 px 常量被多处独立复制**：[loot_burst.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot_burst.gd#L43) `TILE := 64.0`、[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L25) `1.5 * 64.0`、[npc.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/npc.gd#L12) `2.0 * 64.0`、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L70) `attack_range_px: float = 64.0`、[skill_range_fx.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/skill_range_fx.gd#L5) `radius := 64.0`、[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L441-L446) 硬编码 64/32——见 P2-3。 |
| 等级差经验 / 升级公式 | [level_gap.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/level_gap.gd#L5-L9)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L263-L264) | 未发现重复实现。 |
| 物品品质枚举 / 颜色 | [item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L8-L25) | `Shop.QUALITY_ORDER`（[shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L17)）与 `data_loader` 的 `quality_enum`（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L364)）/ `expected_slots`（[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L294)）各维护一份五品质字面量，属轻度重复（见 P3-6）。 |

- 分级：**B**（核心公式基本单一入口；扣分在瓦片常量多处复制 + 怪侧参数硬编码 + 字段名不匹配）。

### 2.6 问题 B-6 · class_name 全局类

- **命名冲突：无**。62 个 `class_name` 名字 `uniq -d` 为空（E2，命令见 §4）；Autoload 名（DataLoader/EventBus/GameState/MapService/SaveManager/AudioCues/Localization/QuestService）与任何 `class_name` 均不重名。
- **循环依赖（`class_name` 之间）**：静态扫描命中 7 组**双向引用**（E2 抽样 + 部分推断）：

| 双向对 | 证据（A→B / B→A） |
|---|---|
| ItemSlot ↔ DragGhost | [drag_ghost.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/drag_ghost.gd#L35)、[drag_ghost.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/drag_ghost.gd#L51-L52) / [item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L219)、[item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L232) |
| PlayerCharacter ↔ AutoBattle | [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L110)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L661) / [auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L68)、[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L100) |
| Monster ↔ MonsterProjectile | [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L639) / [monster_projectile.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster_projectile.gd#L5) |
| Monster ↔ MonsterActorArt / LootBurst / LootNotify / GroundItem | 扫描命中，语义合理（Monster 调用表现层），未逐一手工复核，**标（推断）** |

  GDScript 4 允许此类互相引用（非编译错误），故**不构成阻断**；但按 AGENT §9「一个模块承担明确职责」，实体↔表现↔UI 双向持有会放大切场景/释放期的耦合风险。
- **纯逻辑静态类依赖 Autoload 单例**：`Equipment` 读 `Localization`（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L119)）、`ItemUtil` 读 `GameState.settings`（[item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L53)）、`Shop`/`Loot`/`ItemFactory` 读 `DataLoader`。这使「纯逻辑层」实际依赖全局单例，隔离单测必须先装配 Autoload（**推断**，未见编译级环，仅耦合度问题）。
- 分级：**A-/B**（命名零冲突、无编译级环；扣分在 7 组双向耦合）。

### 2.7 汇总

| 子项 | 分级 |
|---|---|
| B-1 Autoload 职责与越界 | **A** |
| B-2 启动校验覆盖 | **B** |
| B-3 模块职责边界 | **B** |
| B-4 公共接口稳定性 | **B** |
| B-5 共用规则唯一入口 | **B** |
| B-6 class_name 组织 | **B** |

> **本域结论：核心架构「基本完整（B）」**。分层设计与数据驱动主路径成立，Autoload 未越界挂节点，无 P0/P1 阻断；扣分集中在**校验缺口（5 表零校验 + 任务引用不校验）**、**接口冗余（4 死信号）**、**常量/参数重复与字段名不一致**、**系统层节点路径耦合**。B 级项均不阻断交付，但建议按 §5 排期收敛。

---

## 3. 问题清单

> 本域**未发现 P0 / P1**。以下按严重度排列。

### P2-1 EventBus 有 4 个「定义并广播、全库无订阅」的死信号

- **位置**：定义 [event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L14)、[event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L21)、[event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L30)、[event_bus.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/event_bus.gd#L32)；发出 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1069)（xp_gained）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L118)（buff_changed）、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L883)（item_dropped）、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L884)（loot_spawned）。
- **现象**：四个信号全库 `connect=0`；其中 `buff_changed` 无订阅者，HUD 改以 `_process` 轮询 `GameState.buff_remaining`（[hud.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hud.gd#L88)）；`item_dropped` 与 UI 内同名局部信号 `ItemSlot.item_dropped`（[item_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/item_slot.gd#L28)）易混淆。
- **影响**：接口噪声，后续若有人误改为订阅来源会产生双重反馈；`xp_gained`/`item_dropped` 与既有 `player_xp_changed`/任务接线重叠，属维护陷阱。非功能故障。
- **建议**：确认无跨模块用途后从 `event_bus.gd` 删除，或在文件头标注「预留」。保留 `buff_changed` 则应让 HUD 改为订阅而非轮询。
- **证据等级**：E2。

### P2-2 规则/服务层用硬编码节点路径耦合场景树

- **位置**：[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L280)（`"Game/Entities/Player/Camera2D"`）、[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L23)、[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L56)、[travel_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/travel_item.gd#L70)、[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L484-L502)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L896)；UI 侧同类： [hud.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hud.gd#L563)（`get_node_or_null("../" + nodes[index-12])` 拼接路径）、[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L44)。
- **现象**：系统层直接按字符串取 `Ground` / `Camera2D` / `Game` 等子节点；`settings_runtime` 甚至写入完整三级深路径。
- **影响**：场景重命名/重排即静默失效（返回 null 后各调用方各自兜底）；违反 AGENT §9「避免靠散落的节点路径、字符串或临时兼容分支串联系统」；换机/重命名资源时难以定位。
- **建议**：改用以 `group`（如 `map_world` / `player`，项目已大量使用）或由 `Game` 在 `_ready` 完成后经单例注入引用的方式；把 `"Game/Entities/Player/Camera2D"` 收敛为 `Game` 暴露的相机 getter。
- **证据等级**：E2。

### P2-3 等距瓦片尺寸 64/32 被多处独立定义，非单一入口

- **位置**：权威入口 [iso.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/iso.gd#L11-L12)；重复项 [loot_burst.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot_burst.gd#L43)、[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L25)、[npc.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/npc.gd#L12)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L70)、[skill_range_fx.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/skill_range_fx.gd#L5)、[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L441)、[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L446)。
- **现象**：`Iso.TILE_W` 已是唯一换算入口（大量正确引用见 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L226)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L158)），但另有多处把 `64.0` 直接写成常数或自定义常量（`loot_burst.TILE`、`ground_item.PICKUP_RANGE_PX = 1.5*64.0`、`npc.INTERACT_RANGE = 2.0*64.0`）。
- **影响**：AGENT §3 明确「当前 `IsoGround` 地面图集入口使用 64×32 瓦片，变更地面规格必须同步修改图集构建、UV、投影和测试」。改动瓦片规格时，上述独立常量不会被 IDE 统一重构（尤其字符串外的散落数值），易产生「投影已改、射程/拾取距离未改」的错位。当前功能正确，属维护风险。
- **建议**：所有格↔像素换算改为 `Iso.TILE_W / Iso.TILE_H`；`loot_burst.TILE`、`ground_item.PICKUP_RANGE_PX`、`npc.INTERACT_RANGE`、`monster.attack_range_px` 默认值、`skill_range_fx.radius` 默认值统一引用 `Iso`。
- **证据等级**：E2。

### P3-1 同一伤害公式的暴击参数，敌我来源不一致

- **位置**：玩家侧 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L497-L498)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L561-L562) 读 `GameState.player.get("criticalChance"/"criticalMultiplier")`；怪物侧 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L617) 硬编码 `1.0, 0.0, 1.5`。
- **现象**：怪物的暴击率恒为 0、暴击倍率恒为 1.5，未读怪物模板字段；玩家侧走数据。
- **影响**：公式入口虽唯一，但参数策略分裂；若后续给怪物配置 `criticalChance` 将不生效（**推断**：当前设计可能有意「怪物不暴击」）。属可维护性与一致性风险。
- **建议**：怪物暴击参数改为读模板（缺省 0/1.0），或在 `combat.gd` 注释/怪物模板 schema 中明确「怪物不暴击」的正式约定，避免留白。
- **证据等级**：E2（现象）+ E4（设计意图推断）。

### P3-2 localization.json 被两个模块各自加载

- **位置**：DataLoader 把它登记为普通表 [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L29)；Localization 又独立读同一文件 [localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L13)、[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L24-L39)。
- **现象**：同一 `res://data/localization.json` 被解析两遍，形成两份内存副本与两个「事实源」入口。
- **影响**：双份 I/O 与内存；热重载 `Localization.reload()` 不会刷新 `DataLoader.tables["localization"]`，两份可能不一致；且 `tables` 中的这份无人校验。违反 AGENT §9「共用规则有唯一入口」。
- **建议**：二选一——要么 `DataLoader` 移除 `localization` 登记（文案统一走 `Localization.tr_key`），要么 `Localization` 改为从 `DataLoader.tables["localization"]` 读表并让 `data_loaded` 触发重载。
- **证据等级**：E2。

### P3-3 售价品质回退读错模板字段名（`quality` vs `defaultQuality`）

- **位置**：[shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L105-L111)；对照数据字段 [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L321)、[equipments.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipments.json#L10)。
- **现象**：`Shop.item_quality` 的模板回退分支读 `tpl.get("quality", "common")`，而装备模板的品质字段实际名为 `defaultQuality`（`quality` 在模板中不存在）→ 一旦实例**自身缺 `quality`**，回退恒返回 `"common"`，售价按普通品质计（1.0 倍）。
- **影响**：正常实例由 `ItemFactory` 写入 `quality`（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L95)），当前不触发，故未观察到错价；但该回退分支实质失效，对「旧档/异常实例」会低估售价。属潜在错误（**推断影响路径**）。
- **建议**：回退改读 `defaultQuality`；并让 `data_loader` 的 schema 校验名与消费名一致。
- **证据等级**：E2（字段名不一致事实）+ E4（触发条件推断）。

### P3-4 GameState 承载 UI 会话状态，状态层与 UI 层边界偏宽

- **位置**：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L39-L40)（`panel_open` / `_open_panels`）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L53)（`menu_mode`）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L36）(`skip_equipment_downgrade_prompt`)。
- **现象**：面板互斥集合与菜单流程态放在状态单例里，与「运行状态层」混合。
- **影响**：AGENT §9 要求「运行状态、规则结算、视觉表现和 UI 分开维护」。当前可运行且注释已说明「会话状态、不入档」，属分层清晰度问题，不阻断。
- **建议**：长期可把面板流程态迁至 `UI` 层（`ui_layer.gd` 已在承担面板管理），`GameState` 只保留可序列化的业务状态。
- **证据等级**：E2。

### P3-5 属性展示层并行实现同一合成公式

- **位置**：[item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L129-L156) 自算 `raw × quality × (star_factor)`；权威 [equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd#L8-L30)。
- **现象**：展示拆分为「基底 / 品质增量 / 升星增量」时手写合成，未复用 `EquipmentMath.base_attrs`；数值结果与权威一致（同乘同序）。
- **影响**：属展示特例（需分项文本），但与权威层平行维护，未来改合成顺序需改两处。AGENT §9「共用规则有唯一入口」的轻度偏离。
- **建议**：把「基底/品质/升星」分项也做成 `EquipmentMath` 的纯函数（如 `base_breakdown(item)`），展示层只取数。
- **证据等级**：E2。

### P3-6 五品质枚举与十部位清单在多处各自维护

- **位置**：品质： [item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L8)、[shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L17)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L364)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L294)；部位： [equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L13-L28)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L265)、[equipmentRules.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipmentRules.json) 的 `slotOrder`。
- **现象**：`common/uncommon/rare/epic/legendary` 与十部位顺序以字面量在 3–4 处硬编码，未从 `equipmentRules.json` 单一读取。
- **影响**：AGENT §9「不重复维护相互冲突的数值」。当前四处取值一致，属可维护性风险（新增品质/部位时需同步改多处）。
- **建议**：以 `equipmentRules.json` 为唯一来源，代码侧保留由它派生的只读常量。
- **证据等级**：E2。

### P3-7 实体↔表现↔UI 之间 7 组双向 `class_name` 引用

- **位置**：见 §2.6 表格；已人工复核三组（ItemSlot↔DragGhost、PlayerCharacter↔AutoBattle、Monster↔MonsterProjectile），其余标（推断）。
- **现象**：全局类之间互相持有/引用，GDScript 4 允许（非编译错误）。
- **影响**：AGENT §9「明确谁创建节点、谁持有引用、谁负责释放」的清晰度下降；切场景/释放期易出现互相调用的悬垂风险。
- **建议**：把「表现层」对实体的回调改为信号/接口而非直接强引用（如 DragGhost 不必反向 `ItemSlot.new()`）；`AutoBattle` 经 `PlayerCharacter` 暴露的接口驱动即可，避免反向类型标注成环。
- **证据等级**：E2（已复核三组）+ E4（其余为静态扫描推断）。

---

## 4. 证据与复核方法

### 4.1 使用的扫描命令（均只读，未改动仓库）

```bash
# 1) EventBus 信号全库使用计数（定义/发出/订阅）
cd /Users/fungleo/Sites/GameProjects/DegenerateAge
for s in $(grep -oE '^signal [a-z_]+' autoload/event_bus.gd | awk '{print $2}'); do
  e=$(grep -rE "EventBus\.$s\.emit"   --include='*.gd' . | wc -l)
  c=$(grep -rE "EventBus\.$s\.connect" --include='*.gd' . | wc -l)
  echo "$s emit=$e connect=$c"
done
# 结论：xp_gained / buff_changed / item_dropped / loot_spawned 的 connect=0

# 2) 信号名重复检测（空 = 无重复）
grep -oE '^signal [a-z_]+' autoload/event_bus.gd | awk '{print $2}' | sort | uniq -d

# 3) class_name 重复检测（空 = 无冲突）与总数
grep -rhoE '^class_name .*' --include='*.gd' . | sed 's/class_name //' | sort | uniq -d
grep -rhoE '^class_name .*' --include='*.gd' . | wc -l      # 62

# 4) class_name 双向引用扫描（python，脚本用完即删，不入库）
#    输出 mutual pairs: AutoBattle↔PlayerCharacter / DragGhost↔ItemSlot / GroundItem↔Monster /
#    LootBurst↔Monster / LootNotify↔Monster / Monster↔MonsterActorArt / Monster↔MonsterProjectile

# 5) 64px 瓦片常量分布
grep -rnE '64\.0|TILE := 64|Iso\.TILE_W' --include='*.gd' scripts

# 6) toast kind 字面量分布
grep -rhoE 'toast_requested\.emit\([^)]*,\s*"[a-z]+"' --include='*.gd' scripts autoload \
  | grep -oE '"[a-z]+"$' | sort | uniq -c   # danger×10 / pickup×3 / info×2
```

### 4.2 关键文件行号索引

| 结论 | 文件:行 |
|---|---|
| Autoload 无 Node 驻留 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L161)（局部取坐标） |
| 有意上提的地图运行态 | [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L59-L82) |
| validate_all 主流程 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L102-L243) |
| 校验结果仅警告不阻断 | [main.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd#L16-L21) |
| skills/quests 无校验 | [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L33)（仅 ID 唯一） |
| 售价品质字段名不匹配 | [shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L105-L111) vs [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L321) |
| 怪物暴击硬编码 | [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L614-L618) |
| 深路径耦合 | [settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L280) |

### 4.3 未使用的验证手段（诚实声明）

- 未执行隔离测试：本域结论均为结构/静态事实，`SmokeTest.gd` 中相关断言（如 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L90) 调用 `validate_all`）仅作 E3 佐证，未实跑（E1 缺席）。
- 「事件在设计上是否真的需要」类判断标（推断）；「是否触发」类影响标（推断）。
- 既有失败基线（`ArtSampleTest`/`ChapterOneArtTest`/`QualityFrameTest`/`IconIntegrationTest`）与本域无关，未重新评估。

---

## 5. 落地优化方案

按「先事实源、再接口、后常量」顺序，均为低风险改动，可独立提交：

1. **补齐启动校验（对应 P2-1 之外的 B-2 缺口）**
   - 在 `data_loader.gd` 增加 `skills` / `quests` / `potions` / `miscItems` / `upgrade` 的字段类型 + 范围校验函数，与既有 `_validate_*` 同构。
   - `quests` 增加跨表引用：`objective.targetId` → `monsters`/`miscItems`（按 `objective.kind` 分支）、`reward.item` → `equipments`/`miscItems`、`giver` → 由 `maps.npcs` 汇总的 npc 集合。
   - `upgrade.json` 校验 `successRate` 长度与取值 (0,100]；避免 [upgrade.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/upgrade.gd#L16-L18) 的静默 0。
2. **收敛文案事实源（P3-2）**：`localization` 只保留一个加载入口，`data_loaded` 触发 `Localization` 重载。
3. **清理 EventBus 冗余接口（P2-1）**：删除或显式标注 4 个死信号；`buff_changed` 若保留则让 HUD 改订阅。
4. **统一瓦片常量（P2-3）**：`loot_burst` / `ground_item` / `npc` / `monster` 默认值 / `skill_range_fx` 默认值全部改引 `Iso.TILE_W/H`。
5. **去节点路径耦合（P2-2）**：`settings_runtime`、`travel_item`、`auto_battle`、`monster` 的世界/相机引用改为 `group` 或 `Game` 注入；`hud.gd` 的 `"../" + ...` 拼接改为注册表/显式引用。
6. **统一品质/部位来源（P3-6）**：以 `equipmentRules.json` 派生只读常量，删除其余字面量副本。
7. **修正售价品质回退（P3-3）**：`Shop.item_quality` 回退读 `defaultQuality`，并补一条针对「实例缺 quality」的断言测试。
8. **拆解双向引用（P3-7）**：优先 ItemSlot↔DragGhost、PlayerCharacter↔AutoBattle；表现层对实体改为信号/接口回调。
9. **分层收口（P3-4/P3-5）**：面板流程态迁往 `ui_layer`；`EquipmentMath` 增补分项纯函数供展示层复用。

> 建议 1–2 归为一个「数据驱动完整性」成果，3–4 归为「接口/常量收敛」，5–9 按域随对应功能改动顺带完成；每项完成后单独提交并补对应测试。

---

## 6. 与既有文档差异说明

| 既有文档 | 本报告差异 / 更新 |
|---|---|
| `产品文档/10` §10.2 / §10.4 | 产品声明「装备/NPC/任务/对话/怪物/掉落/地图/坐骑/如意/仓库/杂项全部数据驱动」与「启动校验 ID 唯一/权重/引用合法/等级范围」。本报告确认装备、掉落、地图、词缀、坐骑、如意、仓库**已校验**；但 `skills`、`quests`、`potions`、`miscItems`、`upgrade` 五表**无结构化校验**，任务引用**未在启动期校验**，属产品要求与实现的偏差（B-2 缺口）。 |
| `AGENT.md` §9「Autoload 只放确需跨场景服务/状态」 | 确认无越界挂节点；仅 `game_state` 兼收 UI 会话状态（P3-4），属边界偏宽而非违规。 |
| `AGENT.md` §9「避免靠散落节点路径/字符串串联系统」 | **明确存在违反项**（P2-2）：系统层硬编码 `Game/Ground/Camera2D` 与 `"../" + ...` 拼接。 |
| `AGENT.md` §9「共用规则有唯一入口」 | 伤害/售价/派生基本单一入口；但瓦片 64px 常量、品质/部位枚举多点复制（P2-3/P3-6），售价品质回退字段名不一致（P3-3）。 |
| `README.md` / `工程文档/01` 记录的「启动校验」 | README 与工程文档 01 描述 `DataLoader.validate_all()` 为「数据非法明确报错」。**属实但强度有限**：结果只在 [main.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd#L16-L21) 记警告并交 `FlowFeedback` 显示，不阻断启动；且覆盖表有限（见 B-2）。 |
| `工程文档/14` §1.1（刷新状态上提 Autoload） | 与本报告 B-1 结论一致：`spawn_respawn`/`unclaimed_loot`/`world_time` 上提属**有意设计**，非越界。 |
| 第一轮审阅报告 | 未在本域引入新回归；本报告独立于 A/C/E 域，未与其结论冲突。 |

---

> 本报告仅为审查产出，未改动任何源码、配置或数据，未提交 git。

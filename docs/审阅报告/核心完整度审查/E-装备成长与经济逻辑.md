# 问题域 E · 装备 / 成长 / 经济系统逻辑

> 配套：`00-总体方法论.md`、`01-审计计划.md` §2 问题域 E。
> 审查对象：装备三轴与穿脱、派生属性、经济与升级链路、容器/快捷栏一致性、消耗品语义。
> 基线快照：`773b7d1`（已确认 `78c20be` 为其祖先，P2 换装修复已在基线内）。
> 范围提醒：**只审系统逻辑**（机制正确性、缓存失效、公式一致性）；**不含具体数值调平**。报告内「数值」仅在涉及机制正确性（如公式结构、越界判定）时引用。

---

## 1. 覆盖范围与未覆盖项

**已覆盖（静态阅读 + 交叉核对）**

| 主题 | 主要证据文件 |
|---|---|
| 三轴 / 14 槽 / 双槽 / 门槛 / 换装 | [equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd)、[equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd) |
| 派生属性与缓存失效 | [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd)、[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd) |
| 经济（买卖 / 扩容 / 上限） | [shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd)、[warehouse.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/warehouse.gd)、[shops.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/shops.json)、[warehouse.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/warehouse.json) |
| 升级 / 升星 / 词条 | [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd)、[upgrade.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/upgrade.gd)、[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd)、[equipmentRules.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipmentRules.json)、[upgrade.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/upgrade.json) |
| 容器 / 坐骑 / 快捷栏一致性 | [inventory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/inventory.gd)、[hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd)、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd) |
| 消耗品语义 | [consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd) |
| 回归测试 | [equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd)、[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd) |

**未覆盖 / 排除**

- 具体装备数值、品质倍率、成功率表、扩容价格等**数值调平**问题不在本报告内（仅校验公式结构与越界判定）。
- 出售托盘 / 人物面板 UI 的布局与交互细节归 F（UI/输入健壮性）域；本报告只在涉及状态一致性时引用。
- 未执行真实窗口流程与压测：本报告以**静态分析（E2）+ 既有测试证据（E1）**为主；无法静态确认的运行结论标注「（推断）」。
- 既有失败基线（`ArtSampleTest`、`ChapterOneArtTest`、`QualityFrameTest`、`IconIntegrationTest`）不作为本域问题。
- 协作者未提交文件（`docs/测试反馈.md`、`scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`）只读不改。

---

## 2. 完整度评估（A–E 分级 + 依据）

| 子项 | 分级 | 依据 |
|---|---|---|
| 装备三轴 / 14 槽 / 双槽 / 穿戴门槛 | **A 已闭环** | 槽位定义与产品 5.1 一致（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L13-L28)）；门槛读实例 `requiredLevel`（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L145-L150)），提交前二次校验（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L604-L605)）；[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L71-L79) 覆盖门槛边界 |
| 满背包换装（第一轮 P2） | **A 已闭环** | 见 §3 与 §4，修复在基线内且有回归测试 |
| 派生属性与缓存失效 | **B 基本可用** | 无显式派生缓存（现算）→ AGENT.md §5 的失效要求天然满足；但若干**战斗属性**只在汇总/面板可见、结算未读取（P2-2） |
| 经济公式与交易原子性 | **B 基本可用** | 买卖主路径闭环、预检后提交（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L980-L995)）；扩容与金上限与产品 06 一致；存在上限截断与售价倍率口径差异（P3-2、§6） |
| 升级链路（HP/MP 结转、词条范围） | **A 已闭环** | 结转按百分比（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1075-L1088)），有 T05 测试（[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2860-L2880)）；词条取值由配置上下界约束（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L78-L90)） |
| 容器 / 坐骑 / 快捷栏一致性 | **A 已闭环** | 快捷栏只存模板引用（[hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd#L1-L36)）；跨容器转移一律复制、生成实例复制基底（无共享模板就地修改） |
| 消耗品 / 自动喝药语义 | **B 基本可用** | 冷却独立、满值不扣、按缺口选瓶均正确；**读档未清零药水冷却**（P2-1） |

**总体**：装备/成长/经济的**主链路完整**（三轴、穿脱、买卖、升级、升星、仓库扩容、容器一致性均为 A），扣分集中在两类**边界/一致性**问题——（a）药水冷却的读档语义，（b）装备战斗词条「显示与结算」口径不统一。均不阻断核心循环，判定为 **B 基本可用**。

---

## 3. 问题清单

### P2-1　读档未清零药水冷却，与产品 05 §5.11 / 本文件注释不符

- **位置**：[consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L50-L52)（注释声明「重启 / 读档后调用」）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L224)（唯一调用点，仅在 `reset_to_defaults()`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L585-L593)（读档应用入口）。
- **现象**：`apply_to_game_state()` 读档时清空了 `skill_cooldowns` 与 `clear_buffs()`，但**没有调用** `Consumable.reset()`；`Consumable._cd` 是静态运行态，只有 `reset_to_defaults()`（新游戏 / 初始化）会清。于是同一进程内「玩 → 回主菜单 → 读档」或「切换存档槽」时，上一局的药水剩余冷却被带进新读入的档。
- **复现条件（推断，路径明确）**：进程内先 `load_into_game` / `resume_last` 之外先使用药水（进入冷却）→ 再调用 `SaveManager.load_into_game(另一槽)`；观测 `Consumable.cd_of("potion_hp_small") > 0`。
- **影响**：与产品 05 §5.11「**冷却为运行态：不写入存档；重启 / 读档后清零**」不符；技能冷却已按此处理，药水冷却漏了一处，语义不一致。
- **建议**：在 [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L592-L593) 与 `skill_cooldowns = {}` / `clear_buffs()` 并列调用 `Consumable.reset()`；补一条「读档后 cd_of==0」回归断言。
- **证据等级**：E2（代码路径可复核；未跑运行复现）。

### P2-2　装备战斗类词条「汇总 / 面板可见」但战斗结算未读取（显示与结算口径不一致）

- **位置与现象**：`BONUS_KEYS` 声明了暴击率、暴击伤害、攻击间隔、闪避、格挡、CDR、移速等（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L31-L36)），人物面板把它们与装备加成**相加展示**（[character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L183-L189)）；但实际结算只读取玩家**基础值**：
  - 暴击率 / 暴击倍率：[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L496-L498)、[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L561-L563) 直接用 `GameState.player.get("criticalChance")`，未叠加 `equip_bonus()`。
  - 攻击间隔：[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L410-L412) 用 `player.attackInterval` 基础值。
  - 移动速度：[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L226) 在 `_ready` 一次性取基础 `movementSpeed`，[player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L308) 直接使用，且装备变化回调只换形象不重算速度。
  - 玩家闪避：[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L618) 用 `player.get("dodge")` 基础值。
  - CDR：技能冷却 [player.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L486) 直接取 `skill.cooldown`，未按 CDR 缩减。
- **当前是否触发**：**否**。产品 05 §5.2 明确「攻击 / 防御百分比及其他战斗属性须等执行链实现后再开放掉落」；`equipments.json` 的 `affixPool` 与 `equipmentRules.json` 的 `fixedAffixes/percentAffixes` 仅含 `atk/def/hp/mp/hpPercent/mpPercent`（[equipmentRules.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipmentRules.json#L36-L63)），无法产生上述键。故为**潜在（推断）**问题。
- **影响**：一旦未来按三轴开放这些词条，人物面板会显示已计入的合计值，而战斗 / 移动按基础值结算——形成「面板说增强、实际不生效」的静默偏差。属「内容缺口 / 执行链未完成」，非当前配置错误。
- **建议**：二选其一——（a）把结算处统一改为「基础 + `equip_bonus()`」（推荐，与面板口径一致，并为未来开放预留）；（b）暂缓面板展示这些键的装备加成，待执行链完成后再开放，并在文档标注。
- **证据等级**：E2（代码路径可复核）。

### P3-1　`shop_buy` 忽略 `add_item` 返回值

- **位置**：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L987-L992)：先 `has_space_for` 预检、再 `add_gold(-price)`、再 `add_item(item)`，但忽略 `add_item` 的结果。
- **现象**：预检与提交同处一段无 `await` 的同步逻辑，单线程下 `add_item` 不会失败，**当前无实际「扣钱不给货」**；一旦未来插入 `await`（如异步入包动画）即会成为真实缺陷。
- **建议**：保留预检，同时对 `add_item` 返回 `false` 走「退还金币 + 明确提示」或断言，避免静默。
- **证据等级**：E2。

### P3-2　单件 / 成批售金缺少金币上限校验，`add_gold` 静默截断

- **位置**：`sell_low_gear` 有上限校验（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L464-L465)）；但单件 `shop_sell`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1005-L1008)）与 `shop_sell_staged`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1016-L1027)）直接 `add_gold(price/total)`，而 `add_gold` 内部 `clampi(..., 0, GOLD_CAP)`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L332-L337)）会截断超额部分，且提示文案仍按全额 `price/total` 展示。
- **影响**：临近金币上限时出售，玩家实际到账少于提示金额（未提示截断）。属边界一致性缺口。
- **建议**：与 `sell_low_gear` 统一口径——超出上限时拒绝或按实际入账额提示（`add_gold` 已返回实际 `delta`）。
- **证据等级**：E2。

### P3-3　`upgrade.json` 注释与升星机制不一致（过时注释）

- **位置**：[upgrade.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/upgrade.json#L6) 注释称「starMult：每星加基础值×starMult（仅加固定属性，不增词条）」；实际 `EquipmentMath.effective_attrs` 对 `affixes/pctAttrs` **也乘** `star_factor`（[equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd#L18-L30)），与产品 05 §5.12（`S×（基底×品质+固定词条）`、`S×百分比词条`）一致。
- **影响**：注释误导维护者（AGENT.md §8：不得保留与行为相反的说明）。
- **建议**：更新该注释为「放大基底与全部词条贡献」。
- **证据等级**：E2 + E3。

### P3-4　出售托盘为面板内存态，交易会话中的自动存档可能漏掉已暂存装备（推断）

- **位置**：托盘由 `ShopPanel._tray` 持有，暂存即从背包 `remove_item_at`（[shop_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L485-L489)）；关闭会话时退回（[shop_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/shop_panel.gd#L100)）。托盘不入档。
- **现象**：`inventory_changed` 未接入自动存档（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L252-L268) 仅订阅 `trade_done` 等），正常路径下暂存期不会自动存；但若会话期间被其它事件触发自动存档（如 `player_leveled`），已暂存装备既不在背包也不在存档。
- **影响**：极端路径下可能「暂存物既不在背包、存档也未覆盖」，重开读到的是不含该件的档，但托盘已销毁 → 该件丢失（**推断**，需实际路径触发）。
- **建议**：交易会话期间挂起自动存档，或在存档前把托盘内容纳入写盘范围（或明确禁止会话内触发存档）。
- **证据等级**：E4（推断，未实机复现）。

### 无问题确认（结论性核对）

- **第一轮 P2「满背包换装被错误拒绝」已正确修复**：现实现把新装备所在格直接复用（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L170-L174)），`inv[inv_index] = old`、`slots[slot_id] = item`，保留双方实例与属性；回归测试 [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L39-L52) 覆盖「满包换装成功且 40 格不变」「满包单独卸装仍失败且原子」「错误槽位不改变状态」。**结论：已闭环。**
- **升级 HP/MP 结转**：按升级前上限计算比例、升级后按新上限回填（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1075-L1088)），符合产品 04 §4.3「保留当前 HP/MP 百分比」；T05 有隔离断言（[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2860-L2880)）。
- **词条不越界**：固定词条取 `randi_range(lo, hi)`，上下界由配置 `min/max × 档位倍率` 且强制 `lo≥1`（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L84-L90)）；百分比取 `randf_range(min, max)` 且每件至多一条（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L70-L78)）；同件不重复（从 `available` 移除）。[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L29-L37) 断言词条数=品质下标。
- **容器转移无共享模板污染**：`Inventory.add` / `warehouse_store/take` 入容器一律 `duplicate(true)`（[inventory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/inventory.gd#L69-L92)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L511-L512)）；生成实例复制 `rawBaseAttrs`（[item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L96)）；`Equipment.bonus` 写入自建字典，不回写模板（[equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L204-L213)）。
- **快捷栏模板引用**：条目仅 `{kind,id}` 两键（[hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd#L17-L28)），不存背包下标；整理、切图、读档后绑定不失效。
- **经济常量与产品 06 一致**：金上限 `999,999,999`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L12)）；扩容 `BASE=1000、R=1.6`（[warehouse.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/warehouse.json#L1-L7)）与产品 6.8 一致；品质售价倍率 普1/优1.5/稀3/史6/传12（[shop.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L10-L17)）与产品 6.2 一致。
- **消耗品其余语义正确**：每药水独立冷却、无全局公共冷却、满值不扣不冷却（[consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L76-L94)）；手动与自动共用唯一入口（[consumable.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L58-L94)）；冷却跨图保留（静态运行态）。

---

## 4. 证据与复核方法

**静态复核定位（文件:行号）**

| 结论 | 定位 |
|---|---|
| 14 槽定义 / 双槽 | [equipment.gd L13-L28](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L13-L28)、[L64-L78](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L64-L78) |
| P2 换装修复 | [equipment.gd L170-L174](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L170-L174) |
| 门槛校验 | [equipment.gd L145-L150](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L145-L150)、[game_state.gd L601-L614](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L601-L614) |
| 派生公式 | [game_state.gd L272-L294](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L272-L294) |
| 升级结转 | [game_state.gd L1064-L1088](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L1064-L1088) |
| 经济买卖 / 扩容 | [game_state.gd L453-L487](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L453-L487)、[L980-L1027](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L980-L1027) |
| 售价公式 | [shop.gd L113-L120](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L113-L120) |
| 药水冷却读档漏清 | [game_state.gd L224](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L224)、[save_manager.gd L585-L593](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L585-L593) |
| 装备战斗键未参与结算 | [equipment.gd L31-L36](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L31-L36)、[character_panel.gd L183-L189](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L183-L189)、[player.gd L226/L308/L410-L412/L496-L498/L561-L563](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/player.gd#L410-L412)、[monster.gd L614-L618](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L614-L618) |

**建议执行的隔离测试（E1 复核）**

```bash
python3 tools/run_isolated_tests.py EquipmentAxesTest ReviewRegressionTest SmokeTest
```

通过判据（方法论 §5）：退出码 0、输出含「全部通过 / PASS」、无 `SCRIPT ERROR`。上述三项为本域主回归；`SmokeTest` 内含 M2-5/T05 升级结转、M1-6 满包判定、出售托盘结算等专项断言。

> 本报告未新增运行证据；P2-2 / P3-4 的「未触发/潜在」判定为静态推断，未在实机路径复现。

---

## 5. 落地优化方案（可执行步骤）

1. **修 P2-1（读档清药水冷却）**：在 [save_manager.gd `apply_to_game_state`](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L585-L593) 与 `GameState.skill_cooldowns = {}`、`GameState.clear_buffs()` 并列，加入 `Consumable.reset()`。补「读档后 `Consumable.cd_of('potion_hp_small') == 0`」断言到 `SmokeTest` 或 `ReviewRegressionTest`。
2. **修 P2-2（结算口径统一）**：为战斗结算新增聚合入口（如 `GameState.stat_total(key)`），把暴击率 / 暴击倍率 / 攻击间隔 / 闪避 / CDR 的**基础值 + `equip_bonus()`** 一次取齐；`player.gd`、`monster.gd` 相应调用点改为该入口。改前先确认产品 05 §5.2「战斗属性延后开放」是否变更；若沿用延后开放，则退而把 [character_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/character_panel.gd#L183-L189) 的这些键改为「仅基础值 + 待开放标注」，避免显示与结算不一致。
3. **修 P3-2（售金上限口径）**：`shop_sell` / `shop_sell_staged` 采用 `add_gold` 返回值，超上限时按实际入账额提示或拒绝，与 [sell_low_gear](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L464-L465) 统一。
4. **修 P3-1（购买回滚）**：`shop_buy` 若 `add_item` 返回 `false`，退金币并提示；或加断言保护该不变量。
5. **修 P3-3**：更新 [upgrade.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/upgrade.json#L6) 注释与 [equipment_math.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment_math.gd#L18-L30) 行为一致（词条也乘星级）。
6. **P3-4 止损**：交易会话期间挂起自动存档（或在 `SaveManager` 落档前合并托盘内容），避免暂存装备落空。
7. **（可选）缓存化**：当前派生值每次现算（`equip_bonus()` 遍历 14 槽）；如未来出现高频调用，按 AGENT.md §5 引入「键 / 所有者 / 生命周期 / 失效事件」明确的缓存，并在装备 / 升星 / 词缀 / 等级 / 增益五类事件失效。

> 全部改动默认演练于独立提交；本报告只出结论与建议，不改源码/配置/数据。

---

## 6. 与既有文档的差异说明

| 项 | 文档口径 | 实现现状 | 判定 |
|---|---|---|---|
| 药水冷却读档清零（产品 05 §5.11；[consumable.gd L50-L52](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/consumable.gd#L50-L52) 注释） | 重启 / 读档后清零 | 仅新游戏（`reset_to_defaults`）清零；**读档未清零** | 实现偏差 → P2-1 |
| 装备战斗属性开放（产品 05 §5.2 / §5.10） | 「其他战斗属性须等执行链实现后再开放掉落」 | `BONUS_KEYS` 与人物面板已纳入这些键，结算未读取 | 与文档「延后开放」一致；但面板展示超前 → P2-2 |
| 升级 comment（[upgrade.json L6](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/upgrade.json#L6)） | 仅加固定属性、不增词条 | 理论（产品 §5.12）与实际代码均为「基底 + 词条整件放大」 | 注释过时 → P3-3 |
| 售价倍率层级（产品 06 §6.2） | `tierValueMult`：Lv1=1 / Lv10=2 / Lv20=3.5（按等级） | 按套阶跃 `equipmentRules.tierValueMultiplier = {1:1.0, 11:2.0}`，无 3.5 档（[equipmentRules.json L68-L71](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/equipmentRules.json#L68-L71)、[shop.gd L92-L101](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/shop.gd#L92-L101)） | **数值口径差异**（属数值调平，本报告不判缺陷，仅记录） |
| 第一轮 P2 满背包换装 | 应复用新装备所在格 | 已按此实现（[equipment.gd L170-L174](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L170-L174)） | **已闭环，无差异** |
| 防御向 % 词条（产品 05 §5.2） | 只开放生命 / 法力百分比 | `percentAffixes` 仅 `hpPercent/mpPercent` | 一致 |

---

*本报告仅作审查结论与改进建议输出，不修改任何源码 / 配置 / 数据，不提交。*

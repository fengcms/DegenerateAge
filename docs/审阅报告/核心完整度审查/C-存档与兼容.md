# C · 存档与兼容

> 配套：00-总体方法论.md（判定标准 §4 / 报告结构 §6）、01-审计计划.md（问题域 C §2）。
> 审查对象：《末法纪元：最后的守护者》（Godot 4.7.2 / GDScript）存档链路。
> 基线：`773b7d1`；第一轮审阅 P1 修复提交 `e3d9e0d`（已核对存在于 git 历史）。
> 证据口径：E2 = 代码静态阅读（文件:行号）；E3 = 文档明确记录；E4 = 推断（显式标注）。
> 排除项（不作为缺陷）：美术、后续章节内容、具体数值配置、第二章开发；既有失败基线 ArtSampleTest / ChapterOneArtTest / QualityFrameTest / IconIntegrationTest。

---

## 1. 覆盖范围与未覆盖项

### 1.1 覆盖范围

| 子系统 | 入口 |
|---|---|
| 存档 schema 与版本常量 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L23)、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L8) |
| 采集与写入 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L122)（`_collect`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L165)（`save_slot`） |
| 原子写入 / 备份复制 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L803)（`_write_json_atomic`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L1049)（`_copy_over`） |
| 读取 / 备份回退 / 自愈 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L274)（`read_slot`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L302)（`_restore_backup`） |
| 版本迁移 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L358)（`_migrate`）+ 各 `_migrate_*` |
| 应用 / 运行态边界 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L585)（`apply_to_game_state`） |
| 完整性校验 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L830)（`_is_valid_save`）及 `_valid_item` / `_valid_spawn_respawn` / `_valid_unclaimed_loot` |
| 跨图 / 跨档序列化 | [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L803)（spawn_respawn）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L880)（unclaimed_loot）、world_time |
| 测试隔离 | [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L67)；[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L236)（`_autosave_allowed`） |
| 自动化验证 | [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L55)、[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2239)、[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L78) |

### 1.2 未覆盖项

- 未运行任何测试场景（本轮为静态审查为主）；所有未实测结论标注 E4（推断）。
- 未做真机磁盘满 / 断电等物理写盘失败注入（仅静态推演 `_write_json_atomic` 错误分支）。
- 未逐条核对产品文档 03 §3.8 全部上限值与运行时使用点的对应（仅核对暴击/命中两处）。
- 不覆盖第二章及以后新增字段的迁移（明确排除项）。

---

## 2. 完整度评估

**结论：B（基本可用）。**

**依据**

- **主路径已达 A 级**：schema 校验、版本迁移、原子写入、主/备双保险、损坏自愈、读档失败不改运行态、运行态与落档边界、跨图序列化、测试隔离，均有实现 + 自动化验证（[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L55) 与 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2239) 覆盖损坏回退、主备双坏、主档缺失、旧档拒绝、备份字节不变、往返一致）。
- **第一轮 P1 已闭环**：`_is_valid_save` 已从「只要求 player 是字典」收紧为结构化 + 类型 + 范围校验，且「只有有效主档才覆盖备份」的前置判断到位（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L189)）。
- **未闭环的边界项（拉低到 B）**：校验对若干字段仅做类型/非负检查而无区间约束；新增 String 设置键与 `valid_choice` 之间存在「漏注册即全档判损坏」的脆弱耦合（历史上已发生一次事故）；测试隔离存在残余（显式存/删不受闸门保护）。这些不影响主路径可走通，但属「边界与错误路径尚未全部处理」，据此评为 B。

---

## 3. 问题清单

### P2-1 新增 String 设置键 ↔ `valid_choice` 的脆弱耦合（P1 修复引入的新漏洞面）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L920)（settings 逐键校验）、[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L108)
- **现象**：`_is_valid_save` 对 settings 的校验按 `default_settings()` 的**默认值类型**分派：默认值为 String 的键一律走 `SettingsRuntime.valid_choice(key, value)`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L929)）。只要新增一个默认值为 String 的设置键、而 `valid_choice` 未加对应分支，该键的**任何合法值**都会被判非法 → 整份存量存档判为损坏。代码注释已记录一次实测事故（[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L117)），`_migrate` 亦记录了 9c 加键导致的「槽 1 主档不可用」（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L377)）。
- **复现条件**：`default_settings()` 新增 String 键（如 `"fooMode": "auto"`）但 `SettingsRuntime.valid_choice` 无 `fooMode` 分支 → `_is_valid_save` 对所有既有存档返回 false → 启动续档失败、主档被判损坏。
- **影响**：一次「加设置键」的普通改动可能导致**全量玩家存档被误判损坏**，是 P1 收紧校验后新引入的脆弱点。`_migrate_settings` 只能补「缺键」，不能解决「新键未注册导致已有合法值被判非法」。
- **建议**：为所有 String 设置键建立「键名 → 合法枚举」的单一映射表，`default_settings` / `valid_choice` / 迁移共用该表；并在数据加载启动校验中对「默认值为 String 但未在映射表登记」的键直接报错，杜绝漏注册。
- **证据等级**：E2（代码）+ E1（注释记录的实测事故，非本轮实测）。

### P2-2 `unlocks` / `firstClear` 只校验值类型，不校验键合法性

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L910)
- **现象**：对 `firstClear` / `unlocks` 仅要求「每个 value 是 bool」，不校验键是否为已知 boss / 已知解锁标记。`unlocks` 被用于门禁（`spawner.gd` 的 `requires_unlock`，见 [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L151)）。
- **复现条件**：手工编辑或损坏的存档写入 `{"unlocks": {"任意未定义键": true}}` 仍通过校验并原样加载（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L626)）。
- **影响**：单机无安全外溢，但属完整性缺口——无法区分「合法解锁」与「部分损坏 / 被编辑的标记」。低概率触发。
- **建议**：对 `unlocks` 键做白名单（与 maps/quests 引用集对齐）校验，或至少限制键集合。
- **证据等级**：E2。

### P2-3 settings 数值键未按文档区间校验

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L932)（数值键仅要求 `_number ≥ 0`）
- **现象**：`mapScale`（文档区间 0.8–2.0，见 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L186)）、`uiScale` / `textScale` / `displayScale`（手动系数 0.75–1.5，见 [game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L188)）、`potionThreshold`（0–1）、`masterVolume` 等只校验「数值且非负」，无区间上界。仅 `lowGearLevelLimit` 有 1–100 的显式范围（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L934)）。
- **复现条件**：存档写入 `mapScale = 999`、`displayScale = 9` 仍通过校验。`displayScale` 在手动模式下会被运行时 `clampf`（[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L90)），而 `mapScale` 是直接使用的相机 zoom（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L186)），未见等价的读取钳制。
- **影响**：极值缩放导致画面不可用 / 体验断裂（P2 级观感风险）；或用户设置漂移。
- **建议**：把文档声明的区间集中为常量，校验与运行态读取共用；`mapScale` 在使用点补 clamp。
- **证据等级**：E2（`mapScale` 无钳制为 E4）。

### P2-4 测试隔离残余：`review_regression_test` 直接清空 3 号槽且不还原

- **位置**：[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L57)（开头 `delete_slot(3)`）、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L105)（结尾 `delete_slot(3)`）
- **现象**：`_autosave_allowed` 三重闸门 + `_is_test_scene()`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L236)、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L248)）确实挡住了**自动存**路径。但**显式** `save_slot` / `delete_slot` 不受闸门保护；`review_regression_test` 全程对 3 号槽读删且**未**做 `_snapshot_saves` / `_restore_saves`（对比 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2437) 与 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2403) 有快照还原）。
- **复现条件**：开发者**不经**隔离 runner、直接以 `godot --scene res://tests/ReviewRegressionTest.tscn` 在正式工程运行 → 若真实 3 号槽有玩家存档，会被删除/覆盖。同类风险见 [menu_flow_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/menu_flow_test.gd#L35)、[chapter_one_acceptance.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/chapter_one_acceptance.gd#L152)、[boss_review_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/boss_review_test.gd#L121)（均写 3 号槽）。
- **缓解现状**：标准入口 [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L67) 用随机项目名映射独立 `user://`（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L82)、[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L116)），经此运行不会触碰真实存档。
- **影响**：仅开发期、非隔离运行时有真实存档被覆盖的风险；与工程文档 06 §10 记录的「测试写坏玩家档」同类，但该次修复只封了自动存路径。
- **建议**：`review_regression_test` 补 `_snapshot_saves` / `_restore_saves`（对齐 SmokeTest）；或将显式 `save_slot` / `delete_slot` 也纳入测试闸门（非测试场景不允许写非活动槽）。
- **证据等级**：E2。

### P2-5 `unclaimed_loot` 无上限，「主动丢弃」路径未见注销记录

- **位置**：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L842)（`add_unclaimed_loot`）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L855)（`remove_unclaimed_loot`）、[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L186)
- **现象**：登记仅在精英/Boss 入包失败时发生（[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L168)）；注销只在**领取成功**路径调用（[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L193)，调用点 L292/L308/L318/L328）。全仓库对 `remove_unclaimed_loot` 的唯一外部调用来自 `_clear_unclaimed_record`。字段注释声明「直到领取**或玩家主动丢弃**」（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L76)），但代码中未见「玩家主动丢弃 persistent 地面物 → 注销记录」的路径。
- **复现条件**：背包/金币长期满、玩家反复刷新精英/Boss 且不领取 → `unclaimed_loot` 条目持续累积并随档落盘（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L153)）。无每图/全局条数上限，无过期清理。
- **影响**：极端玩法下存档体积与 `remove_unclaimed_loot` 的线性扫描成本增长；「丢弃后仍残留记录」与注释语义不一致（读档重建时会把它当作未领取物重新生成）。
- **建议**：为 persistent 地面物补「主动丢弃 → `remove_unclaimed_loot`」路径；或为每图未领取记录设上限并在超限时明确提示。
- **证据等级**：E2（丢弃路径缺失为 E4，因未穷举全部 UI 交互入口）。

### P3-1 玩家战斗属性无上界校验（依赖战斗侧钳制）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L884)（player 逐键：`_number ≥ 0`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L894)（仅 `attackInterval > 0`、`movementSpeed > 0`）
- **现象**：`criticalChance` / `criticalMultiplier` / `dodge` / `block` / `cdr` / `attack` / `defense` 仅要求非负（或 >0），无产品 03 §3.8 上限校验（暴击率 ≤ 75%、暴击倍率 ≤ 5.0×、闪避 ≤ 75%、攻击间隔 ≥ 0.2s、CDR ≤ 50%，见 [03-核心循环与战斗系统.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/03-核心循环与战斗系统.md#L107)）。
- **影响**：**被战斗侧钳制抵消**——暴击率与暴击倍率在结算时被 `clampf`（[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L43)、[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L46)），Miss 由公式封顶（[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd#L23)）。因此越界存档**不构成可利用漏洞**；风险仅在于攻击间隔/CDR 等未见读取点钳制（E4），以及派生显示值可能异常。属防御性校验缺失，非缺陷。
- **建议**：存档校验或应用阶段按 03 §3.8 收敛关键属性（尤其 `attackInterval` 下限、`cdr` 上限），与既有「HP/MP 应用阶段收敛」口径一致（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L652)）。
- **证据等级**：E2。

### P3-2 p0–v10 迁移分支在生产读档路径不可达（死代码）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L831)（`_whole(schemaVersion, 11, CURRENT_SCHEMA)`）与 [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L367)（v0 / v<3 / v<4 / v<6 / v<7 / v<8 / v<9 / v<10 分支）
- **现象**：`_is_valid_save` 在调用 `_migrate` 之前即以 `schemaVersion ∈ [11,13]` 拒绝低于 11 的存档；因此 `_migrate` 中所有 `v < 11` 的补默认值分支在 `read_slot` / `save_slot` / `apply_to_game_state` 路径**永远不会执行**。这些分支仅被单测「直接调用 `_migrate`」覆盖（[settings_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/settings_test.gd#L15)）。
- **影响**：与产品 10.3「schema 0—10 明确拒读」一致（[10-数据配置与存档技术.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/10-数据配置与存档技术.md#L62)），但死分支易误导读者以为 v0–v10 仍可导入。
- **建议**：删除不可达的 v<11 迁移分支，或加显式注释标注「仅历史保留 / 仅供 `_migrate` 单测」。
- **证据等级**：E2。

### P3-3 存档版本常量双来源：`SCHEMA_VERSION`(6) 为未引用死常量

- **位置**：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L8)（`const SCHEMA_VERSION := 6`）vs [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L23)（`const CURRENT_SCHEMA := 13`）
- **现象**：全仓库对 `SCHEMA_VERSION` 的引用仅有其定义行（grep 仅 1 处命中）；真实生效的是 `CURRENT_SCHEMA = 13`。任务前提所引「game_state.gd 的 SCHEMA_VERSION=6」与实际实现不符。
- **影响**：两处版本常量语义冲突，易在改编时引入偏差。
- **建议**：删除 `SCHEMA_VERSION`，或改为引用 `SaveManager.CURRENT_SCHEMA` 单一来源。
- **证据等级**：E2。

### P3-4 `menu_mode` 生命周期未复位

- **位置**：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L52)（字段）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L201)（`reset_to_defaults` 无 `menu_mode`）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L585)（`apply_to_game_state` 无 `menu_mode`）
- **现象**：`menu_mode` **不落档是正确的**（与注释一致）；但 `reset_to_defaults()` 与 `apply_to_game_state()` 都不复位它，实际由 UI 层设置（[menu_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/menu_panel.gd#L25)、[save_panel.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/save_panel.gd#L331)）。
- **影响**：新游戏 / 重置 / 读档后可能残留上一会话的 `"world"`（测试中常见直接赋值，见 [flow_feedback_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/flow_feedback_test.gd#L12)），属生命周期一致性小瑕疵。
- **建议**：在 `reset_to_defaults` / `apply_to_game_state` 中复位为 `"menu"`，与其它会话态（`skill_cooldowns`、`active_buffs`、`auto_battle_on`）一并处理。
- **证据等级**：E2。

### P3-5 `_write_last_slot` 写失败静默

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L1063)
- **现象**：`FileAccess.open(LAST_SLOT_FILE)` 失败时直接 `return`，无日志/提示。
- **影响**：`last_slot.json` 未更新时「继续」续档落空，玩家只见「无存档」而无原因说明（违反 AGENT.md §9「不静默」的低风险场景）。
- **建议**：失败时 `push_warning`，与 `_write_json_atomic` 的 `push_error` 口径一致。
- **证据等级**：E2。

### P3-6 `_write_json_atomic` 未校验写入错误 / 未读回

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L803)
- **现象**：`f.store_string(...)` 返回值未检查、未 `get_error()`、未读回校验，直接 `close()` 后 `rename`。若磁盘满导致内容截断，截断文件仍会被 rename 为主档。
- **影响**：兜底存在——下次读档 JSON 解析失败会回退 `.bak`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L285)），不会静默返回空档；但本次会话最新进度会在回退中丢失且当时无提示。
- **建议**：写后读回校验或检查 `get_error()`；失败则不 rename、保留 tmp 供排查。
- **证据等级**：E2（磁盘满场景为 E4）。

### P3-7 v11 存档中 `equipmentRuleVersion ≠ 2` 的实例会被整档拒绝（推断）

- **位置**：[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L468)（`_whole(value.get("equipmentRuleVersion"), 2, 2)` 才迁移）、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L951)（校验要求 `equipmentRuleVersion == 4`)
- **现象**：v11 迁移只处理版本恰为 2 的实例；版本缺失或更旧的实例**不改写**（注释明示「无法识别的 ID 留给严格存档校验拒绝」，[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L467)），随后被 `_valid_item` 以 `version == 4` 拒绝 → **整份 v11 存档判损坏**，而非仅丢一件装备。
- **复现条件**：真实 v11 构建写入的实例版本号若非 2（本仓库未见证据，标注 E4）→ 升级后读档失败，需靠 `.bak` 恢复。
- **影响**：单品异常导致整档拒读，与「地图数据变动不应导致读档失败」的宽容口径（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L987)）不一致。
- **建议**：对无法识别的旧装备给出逐件丢弃 + 明确提示，而非整档判损坏。
- **证据等级**：E4（推断）。

---

## 4. 逐项回答审计计划 §2-C 的五个问题

### 4.1 schema 必填字段与校验覆盖是否完整？P1 是否闭环？

**现状**：有效 schema 为 `CURRENT_SCHEMA = 13`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L23)），非任务前提所称的 6。

**校验函数清单**（均在 [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L830) `_is_valid_save` 主入口下）：

| 校验器 | 位置 | 覆盖 |
|---|---|---|
| `_is_valid_save` | L830–936 | 顶层结构 / 版本区间 / 全部容器与关键字段 |
| `_number` / `_whole` | L938–942 | 有限数 / 整数及区间 |
| `_valid_item` | L944–984 | 装备实例（基底/词条/品质/星级/快照）与非装备堆叠 |
| `_valid_spawn_respawn` | L990–1009 | 刷新状态结构 |
| `_valid_unclaimed_loot` | L1014–1036 | 未领取战利品结构 |
| `_valid_ground_coin` / `_valid_ground_mount` | L1039–1046 | 地面金币 / 坐骑 |
| `HotbarConfig.valid_layout` | [hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd#L30) | 12 格模板引用 |
| `SettingsRuntime.valid_bindings` / `valid_choice` | [settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd#L95) | 键位 / 枚举止 |
| `Equipment.slot_accepts` | [equipment.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/equipment.gd#L72) | 槽位与装备类型匹配 |
| `Quest._is_known_state` | [quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd#L378) | 任务状态枚举 |

**已完整校验**：版本区间、`player` 核心字段与正整数等级/经验/HP/MP、`gold` 上限（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L835)）、背包/仓库长度与扩容次数、坐骑收藏与骑乘一致性、当前地图/到访地图存在性、坐标形态、装备槽数量与内容、任务状态、设置类型与 `lowGearLevelLimit` 区间、刷新状态与未领取战利品结构。

**未校验 / 校验不足的关键项**：见 §3 P2-1 ~ P2-3、P3-1：`unlocks`/`firstClear` 键白名单、settings 数值区间、玩家战斗属性区间、`questItems` 内容（仅要求为字典，[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L384)）、`mapLayoutVersion`（完全未校验）。

**P1 闭环判定：闭环。**
- `{"player":{}}` 一类不完整档现被拒绝（[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L63)）；
- 无效主档不进入备份（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L189)），测试断言备份字节不变（[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L81)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L86)）；
- 校验先迁移、再对迁移结果校验（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L837)）；
- 读档/应用失败不改运行态（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L586)，测试 [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L89)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L92)）。

**新漏洞**：P2-1（String 设置键与 `valid_choice` 的脆弱耦合）是收紧校验后**新增的失效面**——严格按默认值类型分派，使「新增 String 键但漏注册」从无害变为「全档判损坏」。

### 4.2 迁移链是否可重复执行？有无重复发奖/扣费/坐标迁移？是否用副本？

- **可重复执行**：`_migrate` 首行 `source.duplicate(true)`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L359)），**不修改传入数据**（测试 [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L97) 断言迁移后输入仍无 `exploredMaps`）。各迁移步骤以幂等为判据并已有测试：
  - 布局迁移以 `mapLayoutVersion` 为闸门（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L365)、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L439)）——重复读取不二次迁移坐标（[chapter_two_routes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/chapter_two_routes_test.gd#L75)、[camp_live_integration_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/camp_live_integration_test.gd#L54)）。
  - 装备目录/需求迁移以 `equipmentRuleVersion` 为闸门（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L474)、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L513)）——重复执行不改变结果（[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L96)、[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L129)）。
- **重复发奖/扣费**：迁移链**不含**任何金币/经验/物品发放或扣费逻辑，无重复结算面。
- **重复迁移坐标**：白盒迁移把 camp 的 `playerPos`、`spawnRespawn` 的 camp 点、`unclaimedLoot.camp` 的落点统一重置到出生格（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L422)）。有 `mapLayoutVersion` 闸门保证只执行一次；同一输入的反复调用结果一致（幂等）。
- **重复卸装/返还未领取物**：`_migrate_equipment_*` 会把越级已穿装备移入背包/仓库/未领取（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L523)），并以版本号闸门保证不重复（[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L129)）。
- **残留风险**：P3-7（v11 实例版本异常时整档拒绝）。

### 4.3 写入原子性与备份：三条路径是否明确、不静默、不破坏旧备份？读档失败是否不改运行态？

- **写盘失败**：`_write_json_atomic` 打开 tmp 失败 `push_error` + 返回 false（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L805)）；rename 失败清 tmp + `push_error`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L812)）；`save_slot` 失败弹 `danger` toast（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L194)）。**明确、不静默**。
- **备份不破坏旧备份**：`_copy_over` 先复制到 `dst.tmp` 再 rename，失败先删 tmp（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L1049)）；且只有**有效主档**才触发备份覆盖（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L189)）。测试断言备份字节不变（[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L81)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L86)）。
- **主备均坏**：`read_slot` 返回 `ok=false` + 明确 message（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L296)）；旧版不兼容另有专用文案（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L292)）。`load_into_game` 仅弹 toast、**不 apply**（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L316)）。测试（[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2382)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L92)）。
- **主档缺失**：`read_slot` 同时检查主/备文件（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L276)）；主档缺失而备份有效时走备份恢复（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L302)，file_exists==false 时跳过改名直接写回）。测试（[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L101)）。
- **自愈**：坏主档改名 `.corrupt` 保留现场，备份写回主档（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L302)）；测试（[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2368)）。
- **读档失败不改运行态**：`apply_to_game_state` 首行校验失败即 toast 后 return（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L586)）；`load_into_game` 在 `read_slot` 失败时提前返回（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L316)）。**结论：满足。**
- **残余**：P3-6（写后未读回/未查写入错误）；恢复写盘失败时主档已被改名，仅剩备份，返回文案区分成功/失败（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L288)）——不静默。

### 4.4 运行态 vs 落档边界

**落档字段清单**（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L123)）：`schemaVersion / slotId / savedAt / player / gold / currentMap / mapLayoutVersion / visitedMaps / playerPos / inventory / inventoryExpansions / warehouse / warehouseExpansions / ownedMounts / activeMount / equipment / questStates / questItems / firstClear / unlocks / settings / hotbar / exploredMaps / worldTime / spawnRespawn / unclaimedLoot`。

**不落档字段**（运行态 / 会话态）：`auto_battle_on`、`auto_pickup_on`、`skill_cooldowns`、`active_buffs`、`menu_mode`、`skip_equipment_downgrade_prompt`、`preferred_mount`、`save_pos`/`has_save_pos`、`panel_open`/`_open_panels`、`pending_equipment_change`/`_equipment_request_sequence`、`Consumable` 冷却。

**逐项核对**：

| 字段 | 注释/文档声明 | 实现 | 结论 |
|---|---|---|---|
| `skill_cooldowns` | 不落档，读档/新游戏清零（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L48)） | `_collect` 未采集；`apply` 清空（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L592)）；`reset` 清空（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L225)） | ✅ 一致 |
| `active_buffs` | 跨图但不落档（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L50)） | `apply` 调 `clear_buffs()`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L593)） | ✅ 一致 |
| `auto_battle_on` / `auto_pickup_on` | 运行态开关，不落档（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L54)、[10-数据配置与存档技术.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/10-数据配置与存档技术.md#L52)） | `_collect` 注释显式排除（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L154)）；`apply` 置 false（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L647)） | ✅ 一致 |
| `menu_mode` | 「本次运行的菜单流程状态；不入档」（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L52)） | 不落档正确；但 reset/apply 均不复位 → 见 P3-4 | ⚠️ 见 P3-4 |
| `skip_equipment_downgrade_prompt` | 会话态，成功读档清零（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L35)） | `apply` 调 `reset_equipment_prompt_session()`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L591)） | ✅ 一致 |
| `world_time` | 随存档落档（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L64)） | `_collect` L150；`apply` 取 `maxf(0, …)`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L606)） | ✅ 一致 |
| `spawn_respawn` | 落档（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L74)） | `_collect` L151；`apply_spawn_respawn` | ✅ 一致 |
| 未领战利品 `unclaimed_loot` | 跨图/跨档保留（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L76)） | `_collect` L153；`apply_unclaimed_loot` | ✅ 一致（上限问题见 P2-5） |

### 4.5 跨图/跨档序列化与键增长

- **`world_time`**：`float`，逐帧累加、随档落档、读档 `maxf(0, ...)` 续算（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L606)）；离线真实时间不计入（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L64)）。校验要求有限且 ≥ 0（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L868)）。**正确**。
- **`spawn_respawn`**：`encode_spawn_respawn` 把 `Vector2 → [x,y]`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L803)）；`apply_spawn_respawn` 清空重建、逐项校验、非法项忽略（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L813)）；坐标解码 `_decode_pos` 长 2 数对（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L830)）。键用稳定标识 `map#monster#ordinal`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L764)），与数组下标解耦。
- **键是否无限增长**：`spawn_remaining` 在查询过期点时**顺带 erase**（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L782)），`clear_spawn_state` 在重生后清除（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L788)）。只要怪物点被持续巡检（[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L125) 每帧查询 `_remaining`），过期项即被回收 → **有界**（上限≈当前地图配置的怪物点数）。跨图往返往返一致、剩余按 `world_time` 递减，已有测试（[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L3303)）。
- **`unclaimed_loot`**：`encode` 逐项 `item.duplicate(true)` + `pos → [x,y]`（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L880)）；`apply` 清空重建、逐项校验、空 item 丢弃（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L900)）。uid 全局唯一以便跨图注销（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L855)）。**键增长风险**：见 P2-5（无上限、无丢弃注销路径）。

### 4.6 开发/测试是否会覆盖玩家真实存档？隔离机制在哪？

- **主隔离层（外部）**：标准测试入口 [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py) 生成随机项目名 `DegenerateAge-Test-<uuid>`（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L67)），把 `project.godot` 的 `config/name` 替换为该名（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L91)），从而映射到独立 `user://`（`app_userdata/<随机名>`），跑完 `rmtree`（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L116)）。**经此入口，真实存档不可达。**
- **次隔离层（引擎内）**：`_autosave_allowed()` 三重闸门（未开档 / 读档抑制期 / 测试场景）+ `autosave_in_tests` 默认 false（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L236)）；`_is_test_scene()` 按 `res://tests/` 前缀拦截（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L248)）。工程文档 06 §10 记录了「测试触发自动存写坏玩家档」的事故与本次收敛（[06-存档落地实施方案.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/06-存档落地实施方案.md#L192)）。
- **残余**：P2-4——显式 `save_slot` / `delete_slot` 不受闸门保护；`review_regression_test` 清空并重建 3 号槽却不快照还原。非隔离直跑测试仍有真实档被覆盖的风险。

---

## 5. 证据与复核方法

| 方式 | 命令 / 位置 |
|---|---|
| 静态阅读 | [save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd)（1076 行）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd)（1100 行） |
| 校验清单交叉核对 | [hotbar_config.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/hotbar_config.gd)、[settings_runtime.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/settings_runtime.gd)、[warehouse.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/warehouse.gd)、[fog.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/fog.gd)、[quest.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/quest.gd)、[combat.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/combat.gd) |
| 回归测试证据 | [review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd#L55)（损坏回退 / 备份不变 / 双坏 / 主档缺失 / 旧档拒绝）、[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2239)（往返一致 / 续档 / 自愈 / 坐标出生）、[smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L3303)（刷新状态跨图跨档）、[equipment_axes_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/equipment_axes_test.gd#L78)（v11/v12 迁移幂等） |
| 隔离运行 | `python3 tools/run_isolated_tests.py ReviewRegressionTest SmokeTest EquipmentAxesTest SettingsTest`（需非沙箱，Godot 写 `~/Library/Application Support/Godot`；通过判据：退出码 0 + 「全部通过/PASS」+ 无 `SCRIPT ERROR`） |
| 若需复现写坏路径 | 隔离运行 `ReviewRegressionTest`，观察是否对项目真实 3 号槽产生写入（本报告未执行，标注推断的 P2-4 由静态阅读 `delete_slot` 调用点得出） |
| 基线 commit 核对 | `git log --oneline -1 e3d9e0d` → `fix(save): 校验存档完整性并保护有效备份` |

> 说明：本轮未运行测试（静态为主）；未执行的项已标注 E4。上述测试文件的存在与断言为 E2 证据，其"通过"结论引用工程文档 06 §8 / 第一轮回复，未在本轮复跑。

---

## 6. 落地优化方案

按投入产出排序，均为「确认后另行提交」，本轮不改码：

1. **（对应 P2-1）建立设置键类型/枚举单一来源**：新增 `SETTINGS_SPEC`（键 → 类型 + 合法枚举 + 区间），`default_settings` / `_is_valid_save` / `SettingsRuntime.valid_choice` / 迁移共同引用；数据加载启动校验对「String 默认值但未登记」的键直接报错。目标：加键不再可能一次性判坏全部存档。
2. **（对应 P2-3 / P3-1）集中区间常量并在应用阶段收敛**：把 `mapScale`(0.8–2.0)、`uiScale/textScale`、`displayScale`(0.75–1.5)、`attackInterval`(≥0.2)、`cdr`(≤0.5) 收敛到一处；读档应用阶段按同一口径 clamp，与既有 HP/MP 收敛（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L652)）并列。
3. **（对应 P2-4）对齐测试隔离**：为 `review_regression_test` 补 `_snapshot_saves` / `_restore_saves`（复用 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L2437) 的辅助），或令非测试场景禁止写非活动槽；并把「测试必须经隔离 runner」写入提交前检查。
4. **（对应 P2-2）为 `unlocks` / `firstClear` 增加键白名单校验**，与 maps.json / quests.json 引用集对齐；未知键丢弃或整档拒绝二选一，明确口径。
5. **（对应 P2-5）补「主动丢弃 persistent 地面物 → `remove_unclaimed_loot`」路径**，并为每图未领取记录设上限 + 超限提示。
6. **（对应 P3-7）迁移宽容化**：对无法识别的旧装备逐件丢弃并提示，而非 `_valid_item` 整档拒绝。
7. **（对应 P3-2 / P3-3 / P3-4 / P3-5 / P3-6 清理）**：删除不可达的 v<11 迁移分支与死常量 `SCHEMA_VERSION`；`reset/apply` 复位 `menu_mode`；`_write_last_slot` 失败补 `push_warning`；`_write_json_atomic` 写后读回或查 `get_error()`。

---

## 7. 与既有文档的差异说明

| 项 | 文档/前提所述 | 代码实际 | 差异性质 |
|---|---|---|---|
| 当前 schema | 任务前提「game_state.gd `SCHEMA_VERSION=6`」 | `SCHEMA_VERSION := 6` 为**未引用死常量**；生效值为 `save_manager.gd` 的 `CURRENT_SCHEMA = 13`（[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L23)） | 前提过时 + 双来源（P3-3） |
| schema 早期版本可读性 | 工程文档 06（A6「旧档可导入」）描述 schema 1 迁移 | 现行 `_is_valid_save` 仅接受 11–13，schema 0–10 拒绝（与产品 10.3 现行口径一致）；06 的 v0/v1 迁移描述已成历史 | 文档滞后于现行产品口径（P3-2），非实现缺陷 |
| 「自动开关」入档 | 产品 10.3 记录清单含「…与自动开关」 | 落档的是 `settings.autoBattleDefault/autoPickupDefault`（默认值），**运行态开关不落档**——与 10.3 口径说明一致（[10-数据配置与存档技术.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/10-数据配置与存档技术.md#L52)） | 口径已澄清，非冲突 |
| 未领取战利品「主动丢弃」 | 字段注释称「直到领取或玩家主动丢弃」（[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L76)） | 代码仅见「领取成功后注销」，未见丢弃注销 | 注释与实现可能不一致（P2-5，推断） |
| 第一轮 P1 | 第一轮回复称 `e3d9e0d` 已修复 | 已核对：提交存在且校验/备份防护到位 | 已闭环 |

---

**小结**：存档与兼容域主链路（采集、校验、迁移、原子写入、双备份自愈、读档失败不动运行态、跨图序列化、测试隔离）实现完整且有自动化验证，第一轮 P1 已闭环；综合评为 **B（基本可用）**，主要未处理项集中在**新增设置键的脆弱耦合（P2-1）**、**区间校验缺失（P2-3/P3-1）** 与**测试隔离残余（P2-4）**，均为边界/维护性缺口，不阻断主流程交付。

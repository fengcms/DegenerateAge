# C · 战斗与首领动作

> 问题域：三章敌人档次与数量、共享线/扇/圈预警组件语义、二阶段（phaseB）/新增三阶段（phaseC）、脱战归位/复刷/首通去重、刷新预算。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.C。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 三章敌人模板数与档次（normal/elite/boss） | 生成正确、半径按档次 | — |
| 共享 `BossAction` 语义（shape/segments/预警/锁定几何/MIN_LOCK） | 逐条成立 | — |
| `phaseB`（50%）与新增 `phaseC`（25%） | 与创意文档一致，`phaseC` 只缩 A 间隔 | — |
| `phaseC` 接入最小化 / 对 phaseB 与 c1—c5 回归 | 无行为改变 | — |
| 脱战 5s 归位回满、18 格离场心、复刷 600s+墓碑+`bossCap=1`、首通去重 | 三章同口径 | — |
| 刷新预算「按 kind 配置」对非章节图副作用 | 未配置旧图保留旧行为，无副作用 | — |

**本域未发现 P0/P1/P2 问题。** 唯一登记项为下方 P3（测试恒真断言，归 F 域统一处理，此处仅登记）。

---

## 2. 档次、数量与半径

**结论：已核对，无异常。** 三章模板由测试逐实例覆盖档次与半径（`tests/chapter_six_combat_test.gd:56-70`；四/五章同构）。精英词缀池三章统一口径由 `data/monsters.json` 各章 elite 的 `affixPool/affixCount` 字段承载，逐章枚举一致。

---

## 3. 共享 `BossAction` 组件语义

**结论：逐条成立，已核对。**

| 语义 | 实现证据 |
|---|---|
| `shape` 三选一（line/circle/fan） | `scripts/entities/boss_action.gd:219-233` |
| 「同一段只结算一次」（不靠多碰撞格重复计伤） | `scripts/entities/boss_action.gd:177-189`（每段一次 `on_hit`，`_seg` 递进） |
| 预警期间不结算 | `scripts/entities/boss_action.gd:142-145`（仅 `_t<=0` 才 `_resolve_hit`） |
| 按**锁定几何**结算（命中前不追踪玩家） | `scripts/entities/boss_action.gd:50-51`（锁存 `_origin/_facing`）、`:236-254`（`hits()` 按几何判定）、`:124-140`（update 不使用实时玩家位置） |
| `MIN_LOCK` 公共动作锁 | `scripts/entities/boss_action.gd:22`、`:192-197` |
| A/B 互斥 | `scripts/entities/boss_action.gd:131-140`（IDLE 分支二选一） |

宿主接线：仅 `kind==boss` 且 `bossSkill` 含 `shape` 时装配（`scripts/entities/monster.gd`）；命中以 `attack × coeff` 结算且先过 `boss_action.hits(player.global_position)`（`scripts/entities/monster.gd:417-436`）。

---

## 4. `phaseB` 与新增 `phaseC`

### 4.1 与创意文档一致

- **证据**：`scripts/entities/boss_action.gd:43-46` 注释「C 招（phaseC）：仅空天之眼登记；血量降到 `hpBelow` 后只缩短 A 招重复间隔，预警时长与安全通路不变、不召唤新实体」；读入见 `:78-81`；生效见 `a_interval_at` `:85-88` 与 `:128-129`。
- 数据：`data/monsters.json:3152-3187`（`c6_boss03` `bossSkill`：`shape/fan`、`segments`、`phaseB`、新增 `phaseC` `hpBelow:0.25`、`interval:6.0`）。
- 文档对照：`docs/工程文档/34-第六章51-60级开发落地规划.md:54`「第三阶段只缩 A 间隔」；`docs/游戏创意/21-60级内容规划/第六章/03-怪物精英与Boss.md`（首领段）。
- 测试：`tests/chapter_six_combat_test.gd:115-141`——阈值以上仍 8s（`:121`）、到 25% 缩至 6s（`:122`）、更低血保持 6s（`:123`）、预警/后摇不变（`:124`）、跨阈值时把待发 A 倒计时压到 ≤6s（`:126-129`）；其余首领无 `phaseC` 且低血 A 间隔仍 8s（`:132-140`）。

### 4.2 最小改动与回归风险

**结论：已核对，无异常。**

- `phaseC` 仅作用于 `a_interval_at()` 与 `:129` 的 `minf` 压缩；**`_b_countdown` 未受影响**（`scripts/entities/boss_action.gd:130` 独立递减），`phaseB` 触发条件仍按 `triggerHp`（`:134`）判断。
- 对非 `phaseC` 首领：`a_interval_at()` 恒返回默认 `interval`（8.0），而 `_a_countdown` 本就在 `_start` 被置为 `interval` 后递减，**`:129` 的 `minf` 不产生新约束**，故既有 c1—c5 首领行为不变（静态推断；并以 `BossActionTest`、`BossReviewTest` 在默认回归集内佐证）。
- 全局搜索确认 `phaseC`/`phase_c` 仅出现在 `boss_action.gd` 与该数据/测试中，未在调用点硬编码章节判断。

---

## 5. 脱战 / 复刷 / 首通去重

**结论：三章同口径，机制位于共享引擎。**

- 脱战 5 秒归位回满、离场心 18 格判定：`tests/chapter_six_combat_test.gd:144-161`（离场心超 18 格进入脱战 `:154`；5 秒后归位回满 `:157`；回场心 `:158`；清零二阶段 `:159`）。
- 复刷 600 秒 + 墓碑 + `bossCap=1`：`tests/chapter_six_combat_test.gd:177-187`（`respawnTime==600` `:184`、`tombstone` `:186`、`bossCap==1` `:187`）；刷新实现 `scripts/world/spawner.gd:167-178`。
- 首通去重（同 id 只广播一次 `boss_first_clear`）：`tests/chapter_six_combat_test.gd:164-174`。
- **三章同口径的判据**：上述均为**共享组件/服务**（`scripts/entities/monster.gd`、`scripts/world/spawner.gd`、`EventBus`），三章复用同一实现；各章 combat 场景均含同类断言。

---

## 6. 刷新预算与副作用

**结论：已核对，无异常。**

- `normalCap/eliteCap/bossCap` 按地图 `kind`/配置读取：`scripts/world/spawner.gd:207-227`（`_cap_for`/`_load_caps`）。
- **对非章节图无副作用**：未配置该字段的旧图（营地/第一章/第二章）**保留旧行为**，新章图才读取显式预算。这修正了 `docs/工程文档/30-…:37` 记录的旧缺口（原 `CHAPTER_TWO_NORMAL_BUDGET` 仅对 `c2_` 前缀生效）。

---

## 7. 登记项

- **C-P3（与 F 域重复登记）**：`tests/chapter_six_combat_test.gd:57` 等三章 combat 测试首行断言的是测试文件内 `const` 数组长度（`NORMALS/ELITES/BOSSES.size()`），与游戏数据无关的恒真断言。见 [F-测试覆盖与交付可复现性.md](F-测试覆盖与交付可复现性.md) F-P3-1。

---

## 8. 复跑命令

```
python3 tools/run_isolated_tests.py BossActionTest BossReviewTest ChapterFourCombatTest ChapterFiveCombatTest ChapterSixCombatTest
# 判定：退出码 0 + 输出含「全部通过 ✅」/PASS + 无 SCRIPT ERROR
```

---

## 9. 残余未复核项

- 四/五章 combat 场景的断言已确认存在，但本域取证以**第六章用例**做详证；如需逐条比对四/五章断言细节，可在 F 域复跑时一并核。

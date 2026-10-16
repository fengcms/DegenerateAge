# D · 任务链、发奖与结局状态机

> 问题域：三章主线/支线前置链、`mapScope` 匹配、三态分离、持久发奖计划、放弃/重接、结局幂等与「不清成长」。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.D。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 三章主线/支线 `prev` 链 | 首尾相接、无环、无断点 | — |
| `giver/turnIn` 可定位真实 NPC 且在 `mapScope` 内 | 成立 | — |
| `mapScope` 与击杀/收集/交谈目标匹配 | 成立 | — |
| 三态分离（击杀不直接写结局标记） | 严格成立 | — |
| 持久发奖计划（满包不丢奖/重试复用同实例/成功清除/不重复发钱） | 成立 | — |
| 支线放弃/重接、主线不可放弃、门禁不被误回收 | 成立（见残余项） | — |
| 结局幂等、不清成长、旧内容仍可达 | 成立 | — |

**本域未发现 P0/P1/P2 问题。** 仅 1 项残余待核（见 §8）。

---

## 2. 前置链与目标匹配

**结论：已核对，无异常。**

- 前置链按 `prev` 且仅当前置 `rewarded` 才 `available`：`scripts/systems/quest.gd:55-68`。起始闭环：`C4Q01←C3Q12`（`data/quests.json:1117-1438` 段）、`C6Q01←C5Q14`（`data/quests.json:2189-2460` 段），三章主线 `prev` 依次衔接、无环。
- 接取校验 NPC 身份、所在地图、状态：`scripts/systems/quest.gd:115-154`（`talk` 类接取即达标）。
- 交付要求交付 NPC 匹配 `turnIn` 且同图：`scripts/systems/quest.gd:247-310`。
- 活动范围校验：`scripts/systems/quest.gd:208-241`（`_in_scope()` 校验当前图在 `mapScope` 内）；击杀目标所在图有对应 `spawnPoints`/`bossSpawn`，收集来源怪 `sourceMonster` 在该 scope 图刷新（`data/miscItems.json` 任务物品 ↔ `data/quests.json`），交谈目标 NPC 在该 scope 图。

---

## 3. 三态分离

**结论：已核对，无异常（严格成立）。**

- 核心击杀**不**直接写结局标记：`tests/chapter_six_quests_test.gd:108-171`（`C6Q10` 击杀不直接写 `campaign_complete`）。
- 终章任务把章门禁键写入 `reward.unlocks`：`C6Q03/Q05/Q06/Q09 → c6_access_02..05`、`C6Q12 → campaign_complete`（`data/quests.json:2190-2218`、`:2245-2269`、`:2355-2459`）。
- 三态顺序为 击杀/收集达标 → 回前哨交付 → 正式结局（`docs/工程文档/34-…:43`）。

---

## 4. 持久发奖计划

**结论：已核对，无异常。**

- 定义：`autoload/game_state.gd:50-55`（`quest_reward_plans`）。
- 实现：`scripts/systems/quest.gd:337-379`——首次有效交付尝试时抽定奖励实例并写入计划；**失败重试复用同一实例与词条**；无随机奖励时不建计划；领奖成功后清除计划（并写入 `GameState.unlocks`）。
- 存档兼容：`autoload/save_manager.gd:428-498`——旧档无该键补空字典；迁移时**逐条丢弃**任务 ID 不可解析或奖励实例非法的计划项，不使整档判坏。
- 测试：`tests/quest_reward_plan_test.gd:54-83`（满包失败不静默丢奖、失败重试复用同一实例与词条、清空间后正常领奖、领奖后置 `rewarded` 并清计划）。

---

## 5. 放弃 / 重接

**结论：成立（主线保护成立）。**

- 主线不可放弃由 `abandonable` 控制；放弃时仅对**收集类**任务清空 `quest_items`，并写 `abandoned`：`scripts/systems/quest.gd:187-200`。
- 章节门禁由 `reward.unlocks` 在领奖时写入（§3），**放弃支线不回收门禁**（门禁与支线奖励不耦合）。
- 残余细节见 §8。

---

## 6. 结局幂等与「不清成长」

**结论：已核对，无异常。**

- `tests/chapter_six_quests_test.gd:202-229`：重复读档后 `C6Q12` 不倒退、不能重复领奖；等级/金币/背包不回退；旧章枢纽仍可达。
- 设计口径（`docs/工程文档/34-…:45`）：结局后回信只在首次展示、NPC 常驻对话可重读、**不清成长**、旧图与支线仍可达、61 级以上保留现有无限成长。
- 与「结局后旧内容不可达」死锁的排除：门禁只锁正向（`docs/工程文档/30-…:23`「门禁只锁正向」），旧章枢纽与后续支线不受结局影响。

---

## 7. 复跑命令

```
python3 tools/run_isolated_tests.py QuestRewardPlanTest MapGateTest \
  ChapterFourQuestsTest ChapterFiveQuestsTest ChapterSixQuestsTest
# 判定：退出码 0 + 输出含「全部通过 ✅」/PASS + 无 SCRIPT ERROR
```

---

## 8. 残余未复核项

- **击杀类任务的放弃计数**：`scripts/systems/quest.gd:187-200` 的放弃逻辑明确只对**收集类**清 `quest_items`；**击杀计数**的存储位置与放弃后是否归零，本次未取证到对应断言（`abandonable` 为真时方可放弃）。建议在 F 域复跑或补一条「击杀类支线放弃→重接→计数从零」的断言确认。属静态待核，非已确认问题。

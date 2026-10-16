# E · 装备掉落与存档迁移

> 问题域：三章各 10 型号的三轴模型约束、`equipmentRules` 规则键覆盖、掉落表/掉落池、传说追加槽、旧存档迁移策略、`equipment_axes_test` 闸门是否被改松。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.E。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 三轴约束（`tierBases` 单键、`requiredLevel`=套起点+slotOrder、错档无基底） | 成立 | — |
| `equipmentRules` 覆盖 31/41/51，无「数据有、规则键无」悬空 | 成立 | — |
| 掉落表 `tierStart/levelRange/质量权重` 与文档一致、共用十型号 | 成立 | — |
| 传说追加槽可覆盖不同部位、Boss 池只产本章型号 | 成立（建议补断言） | P3 |
| 旧存档迁移「坏一件不坏全档」 | 成立 | — |
| `ruleVersion` 统一、`equipment_axes_test` 只扩展未放宽 | 成立 | — |

**本域未发现 P0/P1/P2 问题。**

---

## 2. 三轴模型约束

**结论：已核对，无异常。**

- 规则基线：`data/equipmentRules.json:2-10`（`ruleVersion` 与 `tiers`，含 **31/41/51**），`slotOrder` 十部位顺序。
- 执行校验：`scripts/systems/item_factory.gd:39-57`——生成实例时校验 `tierBases` 存在、`requiredLevel` 与套起点匹配、`affixTierScale` 存在。
- 测试：`tests/equipment_axes_test.gd:27-58`（每个型号只有一穿戴档、按部位逐级开放、错档无可借基底、生成实例可存档）。
- 逐章 10 型号：`tests/equipment_axes_test.gd` 的 `coverage` 字典以 `1/11/21/31/41/51` 六档各断 `size()==10`；型号总数断言由 `==30` 收紧为 `==60`（见 §6）。

---

## 3. 规则键覆盖（无悬空）

**结论：已核对，无异常。**

- `data/equipmentRules.json:73-88`：`affixTierScale` 与 `tierValueMultiplier` 对 31/41/51 均有键；与 `data/equipments.json` 已登记的套起点一一对应，无「数据已登记但规则键缺失」的悬空。

---

## 4. 掉落表与掉落池

**结论：已核对，无异常。**

- 掉落表：`data/dropTables.json:1000-1150` 段（`DT_C4_Normal/Elite/Boss` 的 `levelRange/templatePool/qualityWeight/tierStart`，四五章同构）；与 `docs/游戏创意/21-60级内容规划/第四|五|六章/05-装备奖励与成长.md` 规则逐项对应。
- 共用十型号：`data/lootPools.json:99-193` 的 `c4_normal/c4_legendary`、`c5_*`、`c6_*` 各 `includeIds` 均为 10（`tests/equipment_axes_test.gd` 逐池断言 `includeIds.size()==10`）。
- 掉落选择：`scripts/systems/loot.gd:104-165`——按 `tierStart` 从 `templatePool` 筛选**真正配置该套起点**的型号，**缺档不 fallback**，避免跨档/错档掉落；池过滤只按 `includeIds` 筛型号，与品质分离。

### E-P3-1 · 传说追加槽/ Boss 池「只产本章型号」缺乏定向断言

- **证据**：`scripts/systems/loot.gd:104-165` 的池过滤为「按 `includeIds` 型号」，理论上传说追加槽可产出池中任意部位；`tests/chapter_{four,five,six}_loot_test.gd:106` 现有断言为形态断言 `reward.has("item") and has("tierStart")`。
- **问题**：缺少「奖励实例确指向本章型号 / 传说槽覆盖到非武器部位」的定向断言。
- **严重度**：**P3**（与 F 域 F-P2-2 同源）。
- **改进建议**：将 `loot_test.gd:106` 的形态断言改为校验 `reward.item` 属于本章 `includeIds`，并补一条「多次 roll 命中不同部位」的断言。
- **落地方式**：改 `tests/chapter_{four,five,six}_loot_test.gd`；跑对应 Loot 场景。

---

## 5. 旧存档迁移

**结论：已核对，无异常（「坏一件不坏全档」成立）。**

- 按实例 `equipmentRuleVersion` 收敛：`autoload/save_manager.gd:432-438`；迁移链 `autoload/save_manager.gd:549-605`。
- 逐件丢弃不可识别装备：`autoload/save_manager.gd:629-665`（`_prune_unrecognized_equipment` 遍历 inventory/warehouse/equipment/unclaimedLoot，将迁移后仍不可识别的实例置空或移除，**不使整档拒绝读取**）。
- 迁移幂等与保真：`tests/equipment_axes_test.gd:104-153`（旧装备升级后保留实例 ID、星级、基础数值快照；**重复迁移不改变结果**）。
- 与 §4 的持久发奖计划迁移（D 域）叠加时同样按逐条丢弃（`autoload/save_manager.gd:428-498`），二者互不放大坏档风险。

---

## 6. `equipment_axes_test.gd` 闸门审查（是否被改松）

**结论：纯扩展，未放宽既有断言。** 证据：`git diff 76bb84e3..6b5ec7cd -- tests/equipment_axes_test.gd`（`numstat 15/6`，其中 6 行为被替换的旧行）：

| 变更 | 方向 |
|---|---|
| `check(templates.size() == 30)` → `== 60` | 收紧（仍精确等值） |
| `coverage` 由 `{1,11,21}` → 加 `{31,41,51}` | 扩展 |
| 掉落池清单 `+c4/c5/c6_normal/legendary`（各断 10） | 扩展 |
| `pool_of` 加 31/41/51 映射 | 扩展 |
| 随机 roll 掉落表清单 `+DT_C4/C5/C6_*` | 扩展 |
| `_tier_of()` 加 `DT_C6/C5/C4_` 前缀分支 | 扩展 |

无任何断言被删除或放宽；新增覆盖为「新档必须满足既有约束」。

**附带（非本域问题，登记）**：`git diff … -- tests/map_gate_test.gd`（`numstat 2/2`）将原断言 `not id.begins_with("c4_")` 放宽为 `id != "ash_land" and (id == "c4_map00" or not id.begins_with("c4_"))`——属**已发布章枢纽放行**的契约更新（第四章已发布，`c4_map00` 成为合法相邻枢纽目的地），与既有经验教训「仅跳过未发布章节的出口」一致，**非闸门改松**，判定为合理。

---

## 7. 复跑命令

```
git diff --numstat 76bb84e3..6b5ec7cd -- tests/equipment_axes_test.gd tests/map_gate_test.gd   # 期望 15/6 与 2/2
git diff 76bb84e3..6b5ec7cd -- tests/equipment_axes_test.gd
python3 tools/run_isolated_tests.py EquipmentAxesTest ReviewRegressionTest \
  ChapterFourLootTest ChapterFiveLootTest ChapterSixLootTest
```

---

## 8. 残余未复核项

- 传说追加槽「覆盖非武器部位」的**概率分布**未做统计取证（只在代码层面确认其筛选口径允许全池型号）；如需量化，可在 Loot 场景中加多次 roll 的分布断言。

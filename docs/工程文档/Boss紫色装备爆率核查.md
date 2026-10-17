# Boss「紫色装备」爆率核查

> 触发问题：用户反馈「打了很多 20—60 级的 Boss，一件紫色装备没爆，是不是爆率有问题？」
> 结论：**掉落配置本身没有缺陷**；「一件紫色都没爆」最可能的解释是本项目的品质色约定与常见认知相反 —— 本项目 **史诗=黄色、传说=紫色**，用户所找的「紫色」对应 **传说 legendary**，其 Boss 掉率本就只有 **5%/次**。
> 本文只做核查与归因，**未修改任何掉落表 / 品质色 / 代码**，等待用户裁决后再动。

---

## 1. 结论摘要

| 项目 | 实测 / 配置值 | 说明 |
| --- | --- | --- |
| 史诗 epic（本项目**黄色**） | 每只 Boss 期望 **0.5 件**，至少出 1 件的概率 **43.75%** | 「好装备槽」固定 2 件、25% 判为史诗 |
| 传说 legendary（本项目**紫色**） | 每只 Boss 固定 **5%** | 独立追加槽，`chance=0.05` |
| 精英 elite | **无传说槽** | 精英表里根本没有 legendary 条目，永远不掉紫色 |
| 基础槽（普通/优秀） | 每只 Boss **5—8 件** | 白 / 蓝，占掉落绝大多数 |

即：**Boss 每次掉落 7—10 件装备（5—8 白蓝 + 2 稀有/史诗 + 5% 传说）**，配置完全按产品文档执行，不存在「掉落表把高品质槽写没了」这类缺陷。

---

## 2. 排查方法

按「先复现、再改数据」的原则，走三层证据：

1. **数据层（可直接复核）**：直读 `data/dropTables.json` 的 8 张 BOSS 表逐条槽位，手算期望；直读 `data/lootPools.json` 确认传说池非空。
2. **运行层（Godot 实测）**：临时探针驱动 `Loot.roll()`（即 `monster.gd` 实际调用路径），对每张 BOSS 表跑 600 组随机种子，统计各品质出货期望。
3. **规范层**：查证品质色约定来源，确认「紫色」在产品语义中的确切档位。

> 探针为临时产物，核查完毕已删除、不入库（符合项目规则）。

---

## 3. 证据一：本项目的品质色约定（关键）

**本项目品质色不是常见顺序**，务必以此为准：

- [item_util.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_util.gd#L19-L26) 是品质色唯一来源：

```gdscript
const QUALITY_COLOR := {
	"common": Color("d8d8d8"),     # 白
	"uncommon": Color("4aa3e0"),   # 蓝
	"rare": Color("46c46a"),       # 绿
	"epic": Color("e0c04a"),       # 黄  ← 史诗
	"legendary": Color("b46ae0"),  # 紫  ← 传说
}
```

- [05-装备与背包系统.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/产品文档/05-装备与背包系统.md#L62-L69) §5.7 原文：「品质枚举：`common / uncommon / rare / epic / legendary`（普通 / 优秀 / 稀有 / 史诗 / 传说）。**颜色上是：白色，蓝色，绿色，黄色，紫色**。」
- [00-总纲与导航.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/素材设计/00-总纲与导航.md#L39) 明确要求「不能套用其他游戏的常见顺序」。

**结论：很多游戏里「紫」＝史诗，但本项目里「紫」＝传说（最高档）。** 用户口中的「紫色装备」在本项目对应 **legendary（传说）**，而**史诗在游戏内显示为黄色**。

---

## 4. 证据二：8 张 BOSS 表逐条数据与期望

以下 8 张 Boss 表的装备槽结构**完全一致**（数据直接摘自 `dropTables.json`，行号为该文件内位置）：

| 表 id | 基础槽 | 好装备槽 | 传说槽 | 行号 |
| --- | --- | --- | --- | --- |
| `DT_Boss_L1`（腐化源头） | 5—8 件 common70/uncommon30 | 2 件 rare75/**epic25** | chance 0.05 → legendary100 | L172 |
| `DT_C2_Boss` | 同上 | 同上 | 同上 | L365 |
| `DT_C2_Boss_Slag` | 同上 | 同上 | 同上 | L746 |
| `DT_C2_Boss_Final` | 同上 | 同上 | 同上 | L553 |
| `DT_C3_Boss` | 同上 | 同上 | 同上 | L~933 |
| `DT_C4_Boss` | 同上 | 同上 | 同上 | L~1120 |
| `DT_C5_Boss` | 同上 | 同上 | 同上 | L~1307 |
| `DT_C6_Boss` | 同上 | 同上 | 同上 | L~1494 |

逐条核对（`"epic": 25` 共出现 8 次、`"legendary": 100` 共出现 8 次，与 8 张 BOSS 表一一对应，无缺漏）。以 `DT_C2_Boss` 为例（[dropTables.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/dropTables.json#L394-L428)）：

```jsonc
{ "kind": "equip", "chance": 1.0, "countRange": [5, 8],
  "qualityWeight": { "common": 70, "uncommon": 30 } },        // 基础槽：白/蓝
{ "kind": "equip", "chance": 1.0, "countRange": [2, 2],
  "qualityWeight": { "rare": 75, "epic": 25 } },              // 好装备槽：绿/黄
{ "kind": "equip", "chance": 0.05, "countRange": [1, 1],
  "templatePool": "c2_legendary",
  "qualityWeight": { "legendary": 100 } }                     // 传说槽：紫，独立 5%
```

**期望计算**：

- 史诗（黄）：好装备槽固定 2 件 × 25% = **期望 0.5 件/Boss**；「至少出 1 件」的概率 = `1 − 0.75² = 43.75%`。
- 传说（紫）：`chance 0.05 × 1 件 × 100% = ` **0.05 件/Boss（5%）**。
- 即：**约 44% 的 Boss 会掉至少一件史诗（黄），但每 20 只 Boss 才有约 1 件传说（紫）**。

运行层探针实测与手算一致（600 seed × 8 表）：

```text
DT_Boss_L1       epicPerBoss≈0.490
DT_C2_Boss       epicPerBoss≈0.490
DT_C2_Boss_Slag  epicPerBoss≈0.490
DT_C2_Boss_Final epicPerBoss≈0.537
DT_C3_Boss       epicPerBoss≈0.490
DT_C4_Boss       epicPerBoss≈0.490
DT_C5_Boss       epicPerBoss≈0.490
DT_C6_Boss       epicPerBoss≈0.490
legendary 约 0.047 件/Boss（≈5%，与配置一致）
```

---

## 5. 证据三：传说池非空、装备生成链无静默丢件

- [lootPools.json](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/data/lootPools.json) 中 8 个传说池（`legendary`、`c2_legendary` … `c6_legendary`）**每个都含满 10 个型号**（全部位），不存在空池导致传说槽「抽不到型号而静默丢件」的问题。
- [item_factory.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/item_factory.gd#L39-L100) `make_equip_roll` 对品质做白名单校验、对词条池不足会 `push_error` 并返回空 —— 探针实测传说确实能生成实例（≈5%），说明词条池足够，未触发该分支。
- [loot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot.gd) / [loot_burst.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot_burst.gd) 均**无按品质过滤**的逻辑；[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd) 的认领序只影响入包顺序、LootBurst 只影响展示编排，都不会吞掉高品质件。
- 地图侧已核实：`bossSpawn` 均带 `"kind": "boss"`，Boss 模板/覆盖 `dropTableId` 全部指向上述 BOSS 表，不存在「用错表」。

---

## 6. 为什么「打了很多还没爆紫」是可能的

传说为独立 **5%** 槽，连续 N 只 Boss 全不爆的概率 = `0.95^N`：

| 击杀 Boss 数 | 至少爆 1 件传说（紫）的概率 | 完全不爆的概率 |
| --- | --- | --- |
| 10 | 40.1% | 59.9% |
| 20 | 64.2% | 35.8% |
| 30 | 78.5% | 21.5% |
| 40 | 87.1% | 12.9% |
| 60 | 95.4% | 4.6% |

只要你打的是**精英怪（elite）而非 Boss**，则**永远**不会掉紫 —— 因为精英表根本没有传说槽（见 §7）。

---

## 7. 需要用户确认的两个关键点

1. **你说的「紫色」指哪一档？**
   - 若指**最高档紫色（传说）**：配置正常，5%/Boss，无缺陷；「没爆」属正常概率区间。
   - 若你期待 boss 的「好装备槽」出**紫色**：那是**颜色认知差异** —— 本项目「好装备槽」= 稀有(绿)+史诗(黄)，史诗在游戏内是**黄色**，不是紫色。
2. **你打的是 Boss 还是精英？** 精英怪（金色血条/精英怪）**不掉传说**。若你刷的是精英，则「一件紫都没爆」完全符合设计。

---

## 8. 可选调整方案（**待确认后才动**，当前一律未改）

| 方案 | 做法 | 影响 | 建议 |
| --- | --- | --- | --- |
| A. 维持现状 | 不改 | 紫色（传说）5%/Boss 属合理顶级稀有度 | ⭐ 若用户本意只是「不知道颜色约定」，推荐此项，仅做说明 |
| B. 提高传说概率 | 8 张 BOSS 表传说槽 `chance` 由 0.05 上调（如 0.08~0.10） | 传说获取速度上升，需同步评估经济与评分体系 | 仅在用户明确「想要紫更多」时采用 |
| C. 调整品质色 | 交换 epic / legendary 颜色（史诗紫、传说黄） | **违反产品文档 §5.7 与素材总纲既定规范**，且影响全项目配色 | ❌ 不推荐；除非产品决策明确改规范 |

> 若用户确要调整（B），需按项目流程另起开发任务单，同步更新掉落表、相关测试与产品文档，再提交。

---

## 9. 交付物清单

| 文件 | 内容 |
| --- | --- |
| 本文档 | 复核结论、三层证据、概率表、待确认项与可选方案 |
| （临时探针，已删除）`tests/probe_epic_drop.gd` / `ProbeEpicDrop.tscn` | 运行层实测，用后即删、不入库 |

**核心发现**：Boss 掉落配置无缺陷；史诗（黄）约 44%/Boss、传说（紫）5%/Boss；用户「紫色」在本项目＝传说，且精英怪不掉传说 —— 问题根因是**品质色语义/预期差异**，非爆率 bug。

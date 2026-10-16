# A · 数据契约与引用完整性

> 问题域：第四/五/六章（31—60 级）新增数据登记的内部自洽、跨表引用、`tierRange` 与刷新等级口径、与创意权威文档的逐项一致性、JSON 格式约定。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.A。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`；证据均为 `文件:行号` 或可复跑命令。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 三章地图登记齐全 | 齐（**c4=6、c5=7、c6=6**） | — |
| 八表跨表引用可解析 | 复刻校验器交叉校验 `0` 问题 | — |
| `DataLoader.validate_all()` 口径 | 已逐条复刻，三章零问题 | — |
| 刷新等级 = `clamp(模板等级, tierRange)` | 枚举 `0` 不匹配，三章同口径 | — |
| 怪物 HP/攻/防/经验/等级/间隔与文档 | 逐项一致 | — |
| 职责 → `moveSpeed` 映射 | 文档无权威定义，跨章取值不一致 | **P2** |
| 精英表 `attackRange.kind` 跨章口径 | `c4_elite03` 与 `c5/c6` 同类招式取不同 kind | **P2** |
| `shops.json` 新增条目格式 | 纯追加、单行内联，无重排污染 | — |
| `miscItems` 任务袋物品 | 13 件全 `useType=quest`，与目标匹配 | — |

---

## 2. 地图数量与跨表引用完整性

**结论：已核对，无异常。**

- 三章地图条数：`c4` 六图、`c5` **七图**、`c6` 六图。证据：`data/maps.json` 各图块（如 `c3_map00` 块自 `data/maps.json:3379` 起，`c4/c5/c6` 各图同构）；与创意文档一致——`docs/游戏创意/21-60级内容规划/第四章/02-地图与布局.md:11-16`（6 行）、`第五章/02-地图与布局.md:11-17`（7 行）、`第六章/02-地图与布局.md:11-16`（6 行）。总览 25 张（6+6+7+6）见 `docs/工程文档/30-第三至六章开发落地总览与串联.md:23`。
- 跨表引用：以 `autoload/data_loader.gd:143-285` 的校验口径（ID 唯一、`monsters.dropTableId`、`maps` 的 `tierRange/刷新等级/monsterId/bossSpawn`、NPC role/shopId、车夫、出口、门禁、安全区、掉落表、装备池、runes/mounts、affixes、装备三轴、仓库、skills/quests/potions/miscItems/upgrade）复刻的静态交叉校验脚本输出 **`TOTAL ISSUES: 0`**；门禁键悬挂 `0`；出口配对 `0`。

**说明（P3）**：[01-审阅计划.md](01-审阅计划.md) §2.A.1 表述为「三章各 6 图」，与第五章实际 7 图不符。属**计划文档措辞**问题，非数据缺陷。改进：将 §2.A.1 改为「第四/六章各 6 图、第五章 7 图」。落地：直接编辑 [01-审阅计划.md](01-审阅计划.md)；无需验证数据。

---

## 3. 刷新等级与 `tierRange` 口径

**结论：已核对，无异常。**

- 枚举 c4/c5/c6 全部 `spawnPoints` + `bossSpawn` 的刷新等级 vs 模板 `monsters.level`：`mismatches: 0`，即刷新等级 = `clamp(模板等级, 该图 tierRange)`，三章同口径。
- 例：`c4_map01` `tierRange=[32,34]`，`c4_normal01` 模板 31 → 刷新 32，`c4_normal06` 模板 36 → 刷新 34（证据：`data/maps.json` 中 `c4_map01` 块与 `data/monsters.json` 对应模板 `level` 字段）。

---

## 4. 怪物数值与职责（文档对照）

**数值对照：已核对，无异常。** HP / 攻 / 防 / 经验 / 等级 / 攻击间隔按创意文档表格逐行比对全部一致。例：`第六章/03-怪物精英与Boss.md:10`（`c6_normal02` 1369／268／112，间隔 1.5／557）＝ `data/monsters.json:2659-2673`。

### A-P2-1 · `attackRange.kind` 与文档「职责」缺乏权威映射，跨章口径不一致

- **证据**：`data/monsters.json:2664-2667`（`c6_normal02` `kind=melee`）、`data/monsters.json:2676`（`monsterType=tank`）、`docs/游戏创意/21-60级内容规划/第六章/03-怪物精英与Boss.md:10`（该行职责标「**高防**」）。
- **问题**：创意文档 `03-怪物精英与Boss.md:5` 只给出 HP/攻/防公式，**未定义「职责 → 移速／攻击范围」映射**；同类「高防/盾卫」在第三章取 2.4（`第三章/03-怪物精英与Boss.md:9` 标注「近战高防」＝ `data/monsters.json:798` `moveSpeed=2.4`），在第六章取 1.8（`data/monsters.json:2668` `moveSpeed=1.8`）。两处职责措辞不同（「近战高防」vs「高防」），数值随之不同，但**没有任何权威规则句裁定该差异是否有意**，后接手工校准者易误判为数据回退。
- **严重度**：**P2**（可维护性／一致性，非玩家可见错误）。
- **改进建议**：在 `docs/游戏创意/21-60级内容规划/第{三,四,五,六}章/03-怪物精英与Boss.md` 的规则段补一张「职责 → 移速 / `attackRange.kind`」映射表（如 近战=2.4／快速=3.1／重型=1.8／盾卫·高防=1.8／定点=0）。
- **落地方式**：改创意文档规则段；验证用一次性只读脚本按职责枚举 `moveSpeed`/`kind`，确认全部落在映射表取值内。

### A-P2-2 · 精英表缺「职责」列，同类招式跨章取不同 `kind`

- **证据**：`第四章/03-怪物精英与Boss.md:18-25`（精英表列头为「外观与招式」，无职责列），对应 `data/monsters.json:1663`（`c4_elite03`「两条先后镜线」实现 `melee`）；同类的 `data/monsters.json:2261`（`c5_elite03`）、`data/monsters.json:2851`（`c6_elite01`）实现 `ranged`（`第五章/03:23`、`第六章/03:20`）。
- **问题**：精英远程判定口径无文档依据，同类「标线/弓」招式在不同章取不同 `attackRange.kind`。
- **严重度**：**P2**。
- **改进建议**：精英表补「职责/攻击类型」列，或统一明确「带标线/弓类招式一律 `ranged`」口径。
- **落地方式**：改创意文档；验证同 A-P2-1。

### A-P3-1 · `c4_normal03` 职责标注与移速不符

- **证据**：`第四章/03-怪物精英与Boss.md:11` 标「近战」，`data/monsters.json:1415` `moveSpeed=3.1`（按规则句属「快速」）。
- **严重度**：**P3**。
- **改进建议**：该行职责改标「快速近战」。
- **落地方式**：改创意文档单行；无需代码改动。

---

## 5. JSON 格式约定

**结论：已核对，无异常。**

- `data/shops.json`：`git diff --numstat 76bb84e3..HEAD -- data/shops.json` = `66 0`（**纯新增、零删除**），`git diff` 仅追加 c4/c5/c6 六个商店块，沿用「单元素单行内联」`{ "itemId": …, "price": …, "tier": … }` 约定，**无整表重排/缩进污染**。另核：12 个 `shopId` 均被地图 NPC 引用，`buyItems.itemId` 全部可解析、`tier` 与 `potions` 一致。
- `data/miscItems.json`：13 件 c4/c5/c6 任务物品 `useType` 全为 `quest`（自 `data/miscItems.json:94` 起），逐一对上 `data/quests.json` 的 collect `objective.targetId`；其 `sourceMonster` 均在该 quest 的 `mapScope` 图刷新。授予机制在 `scripts/systems/quest.gd:179`（按 `sourceMonster` 匹配死亡回调），**不经 `dropTables`**——「不在掉落表」属设计内。

---

## 6. 复跑命令

```
git diff --numstat 76bb84e3..HEAD -- data/shops.json      # 期望 66 0
git diff 76bb84e3..HEAD -- data/shops.json
python3 -c "import json;d=json.load(open('data/maps.json'));print([m['id'] for m in d if m['id'][:2] in ('c4','c5','c6')])"
# 静态交叉校验器（复刻 data_loader 口径，一次性使用，运行后删除）
```

---

## 7. 残余未复核项

- 制造源一致性：创意 `03/05` 文档由 `制作工具/内容定义.py` 生成；本次只校验「登记数据 ↔ 衍生文档」，**未**校验「制造源 ↔ 衍生文档」的重建一致性（超出本次范围）。

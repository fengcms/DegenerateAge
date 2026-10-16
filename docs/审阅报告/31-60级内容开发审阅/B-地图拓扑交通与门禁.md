# B · 地图拓扑、交通与门禁

> 问题域：第四/五/六章（31—60 级）六图/章拓扑、出口入口双向配对、车夫报价、门禁解锁链、布局掩码、构建脚本可复现性。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.B。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`；关键核对均以**逐边枚举**脚本完成（一次性只读脚本置于 `/tmp`，运行后删除，未在仓库留痕）。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 枢纽/野外分工、零刷新零首领、服务点入 `safeArea` | 与规划一致 | — |
| 跨章门户双向边配对（ch3—ch6，~50 条边） | 除 1 条外全部「目标园区 entrance cell == 反向 exit cell」 | — |
| `c2_well_town → c3_map00` 入口配对 | 目标入口 `[8,27]` ≠ 反向 exit `[4,27]`，**差 4 格** | **P2** |
| 「入口与返程出口间距」契约 | 文档要求 3 格，ch3—ch6 实为同格；校验器不校验 cell | **P2** |
| `hubLinks` 仅 hub↔hub、双向、不越级 | 成立 | — |
| 车夫报价（150／250／枢纽间） | 数据自洽；与 05 文档口径差一章 | **P2** |
| `requiresUnlock` 产出方—消费方双向匹配 | 无悬挂键，链首尾相接 | — |
| 布局掩码 / 出口可达 / 坐标一致 | 19 图全 OK | — |
| `build_chapter_*_layouts.py` 幂等可复跑 | `drift=0` | — |

---

## 2. 枢纽分工与野外刷位

**结论：已核对，无异常。**

- `c4_map00/c5_map00/c6_map00` 均为 `kind:"hub"`、`hubId` 指向自身、`safeZone:true`、`spawnPoints:[]`、`bossSpawn:null`（证据：`data/maps.json` 对应块；如 `c3_map00` 块 `data/maps.json:3388-3449` 同构，`spawnPoints:[]`/`bossSpawn:null` 见 `:3448-3449`）。
- 全部 NPC `cell` 落在 `safeArea`（`[0,0]-[95,53]`）内；野外图 普通/精英/Boss 位数与 `第四|五|六章/02-地图与布局.md` 表格逐一相符（64/2/0、72/2/1、96/2/0、64/2/1、72/2/1 …），无误位。

---

## 3. 跨章门户双向边配对

**约定（ch3—ch6 统一）**：上一章门户在西侧 `[4,27]`、本章野外门户在东侧 `[92,27]`、下一章门户在顶中 `[51~54,3]`（c6 只有西+东）。

### B-P2-1 · `c2_well_town → c3_map00` 入口与反向出口相差 4 格（唯一跨章不配对项）

- **证据**：
  - `data/maps.json:487-494`：`c2_well_town` 的 `exit to_c3`，`cell=[80,27]`，`toMap=c3_map00`，`toEntrance=from_c2_well_town`。
  - `data/maps.json:3430-3434`：`c3_map00.entrances.from_c2_well_town = [8,27]`。
  - `data/maps.json:3400-3406`：`c3_map00` 反向 `exit c3_map00_exit01`（回沉井镇）`cell = [4,27]`。
- **问题**：按本三章契约「**目标图 entrance 的 cell 等于该图反向 exit 的 cell**」，应满足 `[8,27] == [4,27]`，实际差 4 格。这是 ch3—ch6 全部跨章边中**唯一**的不配对项（其余 ~49 条均成立）。
- **严重度**：**P2**（拓扑契约被破坏；玩家从沉井镇进入 c3 后，第一次走回沉井镇的出口与入口不重合，往返体验与其它图不一致）。
- **改进建议**：将 `data/maps.json` 的 `c3_map00.entrances.from_c2_well_town` 由 `[8,27]` 改为 `[4,27]`；或在**明确采纳「入口与出口错位」口径**后（见 B-P2-2）同步把该图其余入口改为错位，二者取一，不可半套。
- **落地方式**：改 `data/maps.json` 单字段；复跑下方逐边枚举脚本确认输出全 `OK`；再跑 `ChapterThree` 与 `ChapterFourRoutesTest`。

### B-P2-2 · 「入口落点与返程出口间距」契约与实现口径冲突，且无自动保护

- **证据**：`docs/工程文档/19-*.md:194` 硬约束「入口落点与返程出口中心相距 **3 格**（防直接弹回）」；而 ch3—ch6 数据采用**同格（相距 0）**（如 `data/maps.json:3412-3416` 的 `c3_map00_exit02 cell=[92,27]` 与 `data/maps.json:3436-3438` 的 `from_c3_map01=[92,27]` 完全重合）；防抖兜底在 `autoload/map_service.gd:22` `WALK_ARRIVAL_LOCK_MSEC=1000`；而 `autoload/data_loader.gd:653` 的 `_validate_walk_exits` **只校验 id 配对，不校验 cell 相等或间距**。
- **问题**：同一横切契约有两种互相矛盾的表述（19 文档 3 格 vs 实际同格），且校验器不对任一表述做保护——契约处于「无人看管」状态，B-P2-1 的漂移因此不会被 CI 拦下。
- **严重度**：**P2**。
- **改进建议**：先裁定采纳「同格」还是「错位 3 格」，随后：(a) 更新 `docs/工程文档/19-*.md:194` 为最终口径；(b) 在 `data_loader.gd:_validate_walk_exits` 增加对应断言（同格则断言 `target.entrances[key] == reverse exit cell`；错位则断言间距）。
- **落地方式**：改 `autoload/data_loader.gd:653-707` 并跑 `tools/run_isolated_tests.py MapGateTest ChapterFourRoutesTest ChapterFiveRoutesTest ChapterSixRoutesTest`。

### B-P3-1 · ch1/ch2 历史图不满足同格约定（范围外遗留）

- **证据**：`camp → wild_trial`：`camp` exit `to_wild` cell `[79,31]`，而 `wild_trial.entrances.from_camp=[8,50]` ≠ `wild_trial` 反向 exit `[4,50]`；`ash_land`/`corruption_source`/`c2_*` 同类（枚举脚本输出全 `!!`，内缩 4 格）。
- **严重度**：**P3**（明确范围外的历史遗留；本三章未引入）。
- **改进建议**：若统一口径为「同格」，随下次沉井镇—c3 交通改动一并归正；或在新契约断言中把这些图加入白名单。
- **落地方式**：与 B-P2-2 合并处理。

---

## 4. hubLinks 与车夫报价

**hubLinks：已核对，无异常。** 仅 hub↔hub、双向、只连相邻章（`camp↔c2↔c3↔c4↔c5↔c6`），无越级；`c6_map00.hubLinks=[c5_map00]`（终章）合法。

**报价数据自洽：已核对。** 16 张野外图 `carterFares→枢纽` 与 `bossSpawn` 有无完全对应（无 boss→150、有 boss→250）；枢纽间 `c4↔c5=400`、`c5↔c6=500` 双向对称。

### B-P2-3 · 车费口径与文档差一章

- **证据**：`docs/游戏创意/21-60级内容规划/第五章/02-地图与布局.md:282` 写「枢纽间 300/400/500/600（第三至六章进入价）」；数据 hub 实际值为 **300/300/400/500**，其中 `c3↔c4` 实为 **300**（按文档进入第四章应为 400）。
- **严重度**：**P2**（文档与数据不一致；影响经济预期）。
- **改进建议**：核准预期后同步二者之一——改 `data/maps.json` 的 hub `carterFares`，或改 05 文档。
- **落地方式**：改数据后跑 `ChapterFourRoutesTest`（其断言扣费等于 `fee_to()` 自身，需补方向一致性断言，见下）。

### B-P3-2 · `fee_to` 出发地优先导致枢纽→首领图报价不对称

- **证据**：`autoload/map_service.gd:252-261` `fee_to` 为**出发地优先**：枢纽→首领野外图走类型兜底 `carterFare.spoke=150`，而首领图→枢纽为显式 250，形成 150/250 不对称。
- **严重度**：**P3**（若确按「目的地类型统一报价」，枢纽→首领图应为 250）。
- **改进建议**：明确「按目的地类型报价」，或为方向不对称补文档说明。
- **落地方式**：`tests/chapter_{four,five,six}_routes_test.gd` 目前只断言扣费等于 `fee_to()` 自身，未覆盖方向一致性；建议补一条「枢纽→首领图 == 首领图→枢纽」断言。

---

## 5. 门禁解锁链

**结论：已核对，无异常。** 全部被消费键（地图 `requiresUnlock` 与 `exits[].requiresUnlock`）均有**唯一产出方**，无悬挂键。

- **关键事实核实通过**：`c6_access_02/03/04/05 ← C6Q03/Q05/Q06/Q09`、`campaign_complete ← C6Q12`（`data/quests.json` 各任务 `reward.unlocks`；`C6Q03` 见 `data/quests.json:2190-2218`，`C6Q12` 见 `data/quests.json:2355-2459` 段）。
- 链首尾相接：`chapter2←Q005`、`chapter3←C2Q12`、`chapter4←C3Q12`、`chapter5←C4Q12`、`chapter6←C5Q14`、`campaign_complete←C6Q12`。
- `campaign_complete` 产出后无地图消费（结局标记），被 `tests/chapter_six_loot_test.gd:136`、`tests/chapter_six_quests_test.gd` 消费，非悬挂，符合设计。

### B-P3-3 · `requiresUnlock` 空值风格不一致

- **证据**：`c3_map01`/`c4_map01` 的 `requiresUnlock=""`，而 `c5_map01`/`c6_map01` 为 JSON `null`（`autoload/data_loader.gd:757` 将 `null` 视为不锁，合法）。
- **严重度**：**P3**。
- **改进建议**：统一为 `""` 或 `null` 之一。
- **落地方式**：批量编辑 `data/maps.json`；跑 `validate_all`。

---

## 6. 布局掩码与构建脚本

**结论：已核对，无异常。**

- 19 个 `data/layouts/c4|c5|c6_map*.json`：`grid_size` 等于 maps `size`、行数=高度、每行长度=宽度且仅含 `0/1`；所有 exit/entrance/bossSpawn/spawn 格均落在可走格且与主区四邻接连通；`points` 中出口格与 maps `exits[].cell` 一致。
- 构建脚本幂等：`compile_one`（`tools/build_chapter_four_layouts.py:102`、`five:103`、`six:104`）从源重建，与已提交 `data/layouts` **19/19 字节一致（`drift=0`）**；输入为仓库内设计参考 `docs/游戏创意/21-60级内容规划/第X章/地图参考/*.json`（非 `assets/`）；产物写 `data/layouts`（`four:17`、`five:17`、`six:17`），**不写 `assets/`**。

---

## 7. 复跑 / 枚举命令

```
# 逐边配对枚举（/tmp 一次性只读脚本）
#   对每条 exit：源 cell 在界内 → toEntrance 命中目标 entrances → 目标存在反向 exit → 目标 entrance cell == 反向 exit cell
#   输出：c3/c4/c5/c6_map* 全 OK；camp/wild_trial/ash_land/corruption_source/c2_* 全 !!；
#         c2_well_town exit to_c3：目标 c3 入口 [8,27] ≠ [4,27]
# 布局可达 + 幂等校验（/tmp 一次性只读脚本）
#   输出：19 图掩码全 OK；chapter four: sources=6 drift=0; five: sources=7 drift=0; six: sources=6 drift=0
python3 tools/run_isolated_tests.py MapGateTest ChapterFourRoutesTest ChapterFiveRoutesTest ChapterSixRoutesTest
```

---

## 8. 残余未复核项

- 「入口错位 3 格」是否曾对 ch1/ch2 生效过、何时被改为同格，需查更早历史（超出本次基线范围）。

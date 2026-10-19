# 55 · 无尽回廊（c7_arena）扩席与场地改造记录

> 日期：2026-10-19　｜　性质：**已完成改造（已落地）**　｜　上级文档：工程 43 · M10-3 循环 Boss 图实施方案 / 产品 13 §4.1

本文记录 `c7_arena`（无尽回廊）在 2026-10-19 的一次场地改造：把 Boss 席位由 10 席扩到 20 席，并把场地几何由「细环 + 五个区厅圆盘」改为「外椭圆 − 内椭圆」的大环结构。适用于需要了解该图当前几何口径、20 席冻结坐标、改造影响面与性能变化的场景 —— 后续对该图的任何几何或席位数调整，都以本文的几何常量与席位表为基准；配置与掩码的最终口径以 `data/maps/ch07/c7_arena/map.json`、`data/layouts/c7_arena.json` 与本文为准。

---

## 1. 改造动因

- **可走面积过低**：改造前可走仅 **2,197 / 14,400 格（15.3%）**，约 85% 是墙。外椭圆 `a=48,b=24` 减内椭圆 `a=40,b=16` 只剩一圈细环，再被 5 个半径 8 的区厅圆盘切割，主通道被挤到更窄。
- **席位密度过高**：10 席分 5 组，同组两只仅隔 8 格。
- **格数不是间距的正确度量**：等距投影 2:1 压缩会显著改变世界距离 —— `Iso` 中 `Δcol = 8` 只对应世界 **286px**；同一「8 格」差，因朝向不同（正交 vs 斜向）换算出的世界距离最多相差约 **25%**。因此扩席必须按**世界像素间距**设计，而不能只看格距。

---

## 2. 方案对比

| 方案 | 外椭圆 (a,b) | 内椭圆 (a,b) | 可走格 / 总数 | 可走占比 | 席位两两最小世界间距 | 结论 |
|---|---|---|---|---|---|---|
| 现状 | 48, 24 | 40, 16 | 2,197 / 14,400 | 15.3% | 286px | 基准（85% 为墙） |
| A | 56, 28 | 16, 9 | 4,608 / 14,400 | 32.0% | 501px | 面积提升有限 |
| **B（采用）** | **72, 38** | **20, 11** | **7,936 / 14,400** | **55.1%** | **544px** | **唯一同时满足「可走面积大幅提升」与「席位显著分散」** |
| B2 | 68, 36 | 18, 10 | 7,174 / 14,400 | 49.8% | 630px | 间距更大但可走面积偏低 |
| C | 48, 24（保留区厅形态，10 个区厅 × 每厅 2 席） | 40, 16 | 4,052 / 14,400 | 28.0% | 319px | 面积与间距均不足 |

**选 B 的理由**：只有 B 同时把「可走面积」抬到 55%（远超 A / C / B2）并把「席位间距」提到 544px（较现状的 286px 近翻倍）。B2 的间距更大，但可走面积掉到 49.8%；A 与 C 则两项都不达标。

---

## 3. 最终几何口径

- **外椭圆**：`a = 72`，`b = 38`。
- **内椭圆**：`a = 20`，`b = 11`。
- **中心**：`(80, 45)`。
- **西门走廊**：`4 ≤ x ≤ 40 ∧ 42 ≤ y ≤ 48`，连接入口 `(8,45)` 与环。
- **可走定义**：`环 ∨ 走廊`（原「五个区厅圆盘」部件已整体移除）。
- **生成入口**：`tools/build_c7_arena_layout.py` —— 按几何公式栅格化，**禁止手绘**；幂等（输入不变则产物字节一致）。
- **产物**：`data/layouts/c7_arena.json`，`layoutVersion = 2026-10-19-arena-20seats-v1`；`points` 共 **22 项**（`c7_arena_exit01`、`carterArrival`、`spawn000`–`spawn019`）。

---

## 4. 20 席冻结坐标表

| # | `monsterId` | `cell` | `group` |
|---|---|---:|---|
| 0 | `c6_boss03` | [19, 57] | A |
| 1 | `c6_boss02` | [23, 39] | A |
| 2 | `c5_boss04` | [39, 70] | A |
| 3 | `c4_boss02` | [44, 57] | A |
| 4 | `c3_boss02` | [29, 26] | B |
| 5 | `boss_corrupted_beast` | [59, 55] | B |
| 6 | `c2_boss_iron_foreman` | [57, 37] | B |
| 7 | `c2_boss_slag_devourer` | [75, 75] | B |
| 8 | `c2_boss_hundred_arm_extractor` | [45, 18] | C |
| 9 | `c5_boss02` | [89, 61] | C |
| 10 | `c6_boss03` | [59, 15] | C |
| 11 | `c6_boss02` | [86, 28] | C |
| 12 | `c5_boss04` | [106, 48] | D |
| 13 | `c4_boss02` | [119, 70] | D |
| 14 | `c3_boss02` | [96, 14] | D |
| 15 | `boss_corrupted_beast` | [131, 65] | D |
| 16 | `c2_boss_iron_foreman` | [123, 46] | E |
| 17 | `c2_boss_slag_devourer` | [118, 19] | E |
| 18 | `c2_boss_hundred_arm_extractor` | [143, 53] | E |
| 19 | `c5_boss02` | [143, 36] | E |

**筛选口径**：以「掩码腐蚀 6 格」后的可行域做全局最远点采样（farthest-point），取 20 个样本点。

**形象来源**：沿用 `data/endgame.json` 现有 10 条 `arenaBosses`，每只出现 2 次；同名两只以 `ordinal 0/1` 各占一条血条（`endgame.json` 未改动）。

**分组与尺度**：`group` 分 A–E 五组、每组 4 只，属纯数据标注（运行时无消费者）。20 席两两最小世界间距 **544px**（改造前仅 286px）；同名两只分处场地两端，同名最近一对约 **2,183px**。

**门禁契约（不变）**：出口格 `[8,45]`、`carterArrival [10,45]`、`carterFares.c6_map00 = 1200`、`unclaimedLootCap = 200`（本次不改）、`levelFromPlayer.minLevel = 60`、`normalCap / eliteCap` 仍为 0。

---

## 5. 影响面

**本次改动的文件**：

| 文件 | 改动 |
|---|---|
| `tools/build_c7_arena_layout.py` | 几何常量（方案 B）+ 20 席冻结坐标 + 内置断言 |
| `data/maps/ch07/c7_arena/map.json` | `bossCap: 20`、20 条 `bossSpawns`、`layoutVersion` 更新 |
| `data/layouts/c7_arena.json` | 重建通行掩码（可走 2,197 → 7,936） |
| `tests/arena_map_test.gd` | 席位/连通/规格断言同步至 20 席 |
| `tests/boss_multi_target_test.gd` | 多目标血条断言同步 |
| `tests/boss_token_test.gd` | 令牌面板行数断言同步 |
| `tests/map_render_benchmark.gd` | 补入 c7_arena 渲染基准覆盖 |
| `data/maps/ch07/README.md` | 章节 README 同步 |
| `data/maps/ch07/c7_arena/README.md` | 地图 README 同步（几何 / 20 席 / 改造记录） |

**明确未改动**：

- `autoload/data_loader.gd`（校验逻辑复用既有 `bossSpawns` / `levelFromPlayer` 分支）
- `scripts/world/spawner.gd`（`ACTIVE_DISTANCE` 等生成预算不变）
- `scripts/world/cave_layout.gd`（掩码消费方式不变）
- `data/endgame.json`（仍 10 条 `arenaBosses`）
- `data/dropTables.json`（`DT_C7_Arena_Boss` 未动）
- 存档结构与既有存档（本次不改；既有存档不受影响）

---

## 6. 验证记录

- **测试**：`ArenaMapTest` / `BossMultiTargetTest` / `BossTokenTest` 全部通过。
- **总数断言**：`TOTAL_BOSS_ROWS` 由 **27 → 37**。
- **目录校验**：`python3 tools/check_map_catalog.py` 报「36 张地图、配置与 README 一致」。
- **生成器幂等**：`python3 tools/build_c7_arena_layout.py` 重跑产物字节一致。
- **连通性**：可走 **7,936 格**与 **22 个固定格**全连通（西门 BFS 覆盖全部可走格）。

---

## 7. 性能对照

采样工具 `MapRenderBenchmark`（`--rendered`，本机采集，140 帧/样本，前 20 帧预热）：

| 采样 | 改造前（2,197 可走格） | 改造后（7,936 可走格） |
|---|---|---|
| c7_arena normal | median 7.007 ms, P95 10.780, P99 13.407, peak 15.936, draws 156.0 | median 1.308 ms, P95 2.235, P99 2.518, peak 8.597, draws 163.3 |
| c7_arena ground hidden | median 6.943 ms, P95 10.143, P99 13.583, peak 13.801, draws 151.9 | median 1.072 ms, P95 1.676, P99 3.134, peak 3.435, draws 159.3 |
| c7_arena maps hidden | median 6.932 ms, P95 10.740, P99 11.582, peak 15.550, draws 145.0 | median 1.190 ms, P95 1.959, P99 2.199, peak 2.294, draws 154.3 |

**结论**：

- 改造后帧时间大幅下降（约 **−81%**），而绘制调用仅 **+4.7%**。
- **原因判定**：`ground hidden`（只隐藏地面视觉，物理碰撞仍在）与 `maps hidden`（隐藏小地图 / 大地图）两种采样下，改造前的帧时间几乎不下降（6.943 / 6.932 ≈ 7.007），说明改造前的每帧开销主要来自**静态碰撞轮廓**（细环 + 5 个区厅圆盘产生的多段边界），而非渲染；改造后障碍边界变为「外椭圆 / 内椭圆」两条平滑闭合曲线，物理开销随之显著下降。
- **口径说明**：以上为单机单次采样，`draws` 为每帧平均总绘制调用。

---

## 8. 遗留观察项

- `unclaimedLootCap: 200` 本次未调整。20 只 Boss 满场未领取量约 **180–240 件**（`DT_C7_Arena_Boss` 每只约掉 9–12 件），已接近上限；若实际挂机确认触顶，需另开变更评估。

---

## 9. 回滚方式

- **改回生成器**：把 `OUTER=(48.0,24.0)` / `INNER=(40.0,16.0)` 复原，并恢复五区厅三常量与 `hall_centers()`，重跑 `python3 tools/build_c7_arena_layout.py` 重建掩码。
- **或 git revert**：`ba3267ed` / `03431826` / `572feb13` / `d2ebdd38`。
- **注意**：两种回滚都会同时把席位退回 **10 席**（席位数据与掩码一并回退）。

---

相关 commit：`ba3267ed`（几何 + 20 席数据）、`03431826`（重建掩码）、`572feb13`（测试断言同步）、`d2ebdd38`（README 补齐）。

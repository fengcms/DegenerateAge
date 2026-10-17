# 42 地砖族扩充 cave 9 变体接入验收

日期：2026-10-17
前置：[41 号 §6 决策点① ②](41-地砖族扩充cave脚本派生小样与验收.md)（你已批准：「同意你的建议，继续」）
性质：**已接入 `assets/`**；本文记录接入内容、实现要点、自检数据与回归结果。

## 1. 结论速览

| 项 | 结果 |
|---|---|
| cave 砖 | 由 4 变体扩到 **9 变体**，全部写入 `assets/tiles/cave/tile_0..8.png` |
| 派生与拉平 | 由确定性脚本 [build_cave_tiles.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_cave_tiles.gd) 产出，**零生图** |
| 与已验收小样 | 9 块与 41 号评审件 `_packed/cave_derived_flat/tile_0..8.png` **逐块字节一致**（`cmp` 全通过） |
| 隐藏冲突（本轮必须解决） | 族砖从 4 扩到 9 会**挤占道路边缘槽位**，导致八张道路边缘被地砖顶掉；已通过 [ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd) 的 `_road_atlas_index` 把道路索引与族变体数解耦 |
| 回归门槛 | 复跑 [build_environment_art.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_environment_art.gd) 后 `assets/tiles/` 除 cave 外**零改动**（wild/ash/camp 逐字节不变） |
| 测试 | 新增 [GroundTileThemeTest](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/ground_tile_theme_test.gd)；全量 97 项 **87 PASS**，10 项失败经基线快照（`--committed-tree`）复跑确认**全部为既有问题**（§5.4） |

## 2. 接入内容

### 2.1 素材（`assets/tiles/cave/`）

- `tile_0..3.png`：基础 4 块，**被重写为横向明暗拉平版**（决策点②）。
- `tile_4..8.png`：新增 5 块派生变体（已拉平）。
- 9 块均为 64×32、菱形掩码包围盒恒为 `62x32+1+0`。

### 2.2 构建脚本

| 文件 | 角色 |
|---|---|
| [tools/build_cave_tiles.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_cave_tiles.gd)（新增） | cave 砖唯一产出方：读冻结基线 → 派生 4..8 → 9 块拉平 → 写 `assets/tiles/cave/tile_0..8.png` |
| [tools/build_environment_art.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_environment_art.gd)（调整） | 地砖打包循环不再含 cave（避免覆盖已投产的拉平产物）；cave 仍走 `_pack_props`。`_pack_tiles` 内部逻辑未改 |

**为什么需要冻结基线**：派生要求「同一轴值 + 同一 seed → 逐位可复现」。若直接以 `assets/tiles/cave/tile_0..3.png` 为输入，则一旦被拉平写回，重复执行会以拉平版为输入派生，结果漂移。故把接入前的 4 块基础砖冻结为
`art_source/environment/ground_tiles_v1/cave_base/tile_0..3.png`（字节等于接入前的 `assets/tiles/cave/tile_0..3.png`，也等于 `_pack_tiles(cave_tiles_v2.png)` 的产物），派生输入自此稳定，且两条构建路径互不影响。

### 2.3 代码（[scripts/world/ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd)）

- `CAVE_TILES` 由 4 块扩到 9 块（L27–37）。
- `_pick_theme_tile(cell, theme_size)`（新增）：4 变体沿用历史公式，9 变体按 [35 号 §8](35-地砖族扩充第一批复核.md) 加权表散列。
- `_road_atlas_index(road_index, theme_size)`（新增）：把道路索引（3 为中心、4..11 为八张边缘）映射为「本族砖 + 道路边缘」图集内的绝对下标。

## 3. 本轮必须解决的隐藏冲突：道路索引 vs 族变体数

`_draw_tile_floor` 的图集是 `active_tiles = 族砖 + 道路边缘`，而 `_chapter_one_road_tile_index` 返回的是**绝对下标**（3 为中心、4..11 为八张边缘）。它之所以成立，是因为族砖恰好 4 块、道路边缘恰好从第 4 位起。

族砖一扩到 9 块：

| | 族砖 4（旧） | 族砖 9（若不处理） |
|---|---|---|
| 图集长度 | 4 + 8 = 12 | 9 + 8 = 17 |
| 下标 3 | 族砖 3（道路中心） | 族砖 3（仍为道路中心） |
| 下标 4..11 | 道路边缘 0..7 | **族砖 4..8 + 道路边缘 0..2** ← 八张边缘被地砖顶掉三张 |

因此 cave 地图的道路边缘会静默错位。修法：道路边缘固定落在族砖**之后**的槽位。

```gdscript
func _road_atlas_index(road_index: int, theme_size: int) -> int:
	return 3 if road_index == 3 else theme_size + road_index - 4
```

- 族砖 4：`(3)=3`、`(4)=4` … `(11)=11` —— **与改动前逐位一致**，wild/ash/camp 画面不变。
- 族砖 9：`(3)=3`（中心仍沿用第 3 号砖，cave 道路中心观感不变）、`(4)=9` … `(11)=16`。

## 4. 构建期自检数据（`build_cave_tiles.gd` 实测打印）

内部 = `24x12+20+10`（288px 安全区）；外圈 = `2x6+31+1`；左−右 = 左内半 R − 右内半 R。

| 块 | 内部 std | 内部均值 RGB | 外圈 std | 外圈均值 RGB | 左−右落差 | 掩码 bbox |
|---|---|---|---|---|---|---|
| 0 | 22.73 | (204,173,127) | 17.41 | (204,173,122) | +6.7 | 62x32+1+0 |
| 1 | 23.71 | (198,167,122) | 15.10 | (201,172,126) | +6.8 | 62x32+1+0 |
| 2 | 28.29 | (190,159,116) | 11.65 | (197,165,118) | +10.2 | 62x32+1+0 |
| 3 | 17.01 | (200,169,124) | 11.75 | (205,176,130) | +9.3 | 62x32+1+0 |
| 4 | 20.76 | (199,168,122) | 13.79 | (206,176,127) | +8.8 | 62x32+1+0 |
| 5 | 23.65 | (198,167,122) | 16.07 | (204,174,126) | +7.4 | 62x32+1+0 |
| 6 | 20.95 | (192,162,119) | 10.42 | (196,165,120) | +7.3 | 62x32+1+0 |
| 7 | 25.71 | (196,166,123) | 11.10 | (203,174,129) | +4.7 | 62x32+1+0 |
| 8 | 21.35 | (203,172,126) | 16.17 | (203,173,124) | +10.7 | 62x32+1+0 |

- 掩码：基础 4 块 alpha 与几何掩码**不一致像素数 = 0**；族基色 = (197.9, 167.0, 122.5)。
- 自检：内部 R 区间 190.6–204.2（极差 13.5）；**内部 std 下限 17.01 ≥ 15（37 号 §8.3 判据）**。
- 左−右落差由未拉平的 +25…+31 降到 +4.7…+10.7（条带衰减 70–80%，颗粒未受损）。

## 5. 回归与测试

### 5.1 素材回归门槛

复跑**未改动的现行管线** `build_environment_art.gd` 后：

```
assets/tiles/ 的 git 改动只出现在 cave/tile_0..8.png
```

wild、ash、camp 的砖与道具**逐字节不变**（`git status --short assets/tiles/` 中非 cave 条目为空）→ 零回归。

### 5.2 隔离回归

新增 [tests/ground_tile_theme_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/ground_tile_theme_test.gd)，逐项锁定：

- cave 9 变体、wild/ash/camp 仍 4 变体；9 块均为 64×32；
- 4 变体选择与历史公式**逐格一致**（64×64 采样，不一致格数 = 0）；
- 9 变体九档全部出现且占比落在 35 号 §8 加权表 ±5 个百分点内；
- 道路索引映射：4 变体保持 3/4..11，9 变体中心 3、边缘顺延到 9..16，且不越过图集末位。

`GroundTileThemeTest` 已纳入 `DEFAULT_TESTS`（默认集 30 → 31 项，同步更新 [AGENT.md §7](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/AGENT.md) 的计数口径）。

### 5.3 受影响的既有测试同步

图集长度与选砖公式都变了，原有写死断言必然失效，已同步：

| 文件 | 改动 | 原因 |
|---|---|---|
| [tests/map_texture_batch_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_texture_batch_test.gd) | 图集长度断言由 `== 12` 改为「按本族变体数推导」并断言 cave 为 9、wild/ash 为 4；选砖改为调用 `_pick_theme_tile` / `_road_atlas_index`，UV 分母改用图集实际长度 | 该测试原本写死「四张基础砖 + 八张道路过渡砖」与旧散列公式（`variation<4 → 1` 等），族砖扩到 9 后必然对不上 |

### 5.4 全量隔离回归（97 项场景）

```
python3 tools/run_isolated_tests.py --all
```

- 结果：**87 项 PASS / 10 项 FAIL**。
- 把 10 项失败逐个放到**不含本轮改动的已提交快照**（`--committed-tree`，即 `HEAD`）上复跑，**结果逐项完全相同** → 全部为既有问题，非本轮引入：

| 失败项 | 基线同样失败 | 原因 |
|---|---|---|
| `ArtSampleTest` | ✓ | 未输出标准成功标记（抽样/留档场景） |
| `ChapterOneMapArtCapture` | ✓ | 未输出标准成功标记（截图留档场景） |
| `CampLiveIntegrationTest`、`CampMapEditorTest`、`CampStyleSampleTest`、`CampStyleTraversalTest` | ✓ | 未输出标准成功标记（营地工具/编辑器场景） |
| `CampFullArtAcceptanceTest`、`CampWhiteboxAcceptance` | ✓ | 已打印 `PASS · …`，但成功标记不在**行尾**，被 [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py) 的严格行尾规则判为未完成 |
| `MapRenderBenchmark` | ✓ | 需 `--rendered` 实机渲染，headless 必然失败（本就不在默认集） |
| `QualityFrameTest` | ✓ | 槽位图填充 / 图标裁边断言失败，既有问题 |

- 受本轮改动影响过的 `MapTextureBatchTest`：基线 PASS、改动后一度 FAIL，**已同步断言**（§5.3）后 PASS。
- 地面与第一章相关定向复跑全绿：`MapTextureBatchTest`、`ChapterOneAcceptance`、`ChapterOneMapArtTest`、`GroundTileThemeTest`。

## 6. 目视证据

接入后的游戏内观感 = [41 号](41-地砖族扩充cave脚本派生小样与验收.md) 第三幅（9 变体 + 拉平）且资产**逐字节一致**，故不再另出对照图：

- [cave_derived_iso_paving_3panels_2x.png](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/art_source/environment/ground_tiles_v1/_verify/cave_derived_iso_paving_3panels_2x.png)
- [cave_derived_8x.png](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/art_source/environment/ground_tiles_v1/_verify/cave_derived_8x.png)

## 7. 处置清单

| # | 事项 | 状态 |
|---|---|---|
| 1 | 本文件 42 号 | 已产出 |
| 2 | `assets/tiles/cave/tile_0..8.png` + 5 个 `.import` | 已接入 |
| 3 | `tools/build_cave_tiles.gd`、`cave_base/` 冻结基线、`build_environment_art.gd` 调整 | 已落地 |
| 4 | `ground.gd`（9 变体选择 + 道路索引解耦）、`ground_tile_theme_test.gd` | 已完成 |
| 4b | `map_texture_batch_test.gd` 的图集长度与选砖断言同步新契约 | 已完成 |
| 5 | 临时脚本 `tools/_derive_cave_tiles.gd` 及其 `.uid` | 已删除（未入库） |
| 6 | `_packed/cave_derived*` 与 `_verify/*` 对照图 | 保留（评审留档，与 `_verify/` 证据图同性质） |
| 7 | 下一批：B 层新增材质族 + L1 过渡边缘 | 另起制作单 |

## 8. 待人工确认

1. **游戏内目视**：进腐化源头洞穴（`corruption_source`）确认 9 变体铺装与拉平后的观感；道路格仍沿用第 3 号砖，观感与改动前一致。
2. **编辑器资源**：新增的 5 个 `.import` 需要在编辑器内完成导入（已在本机触发过一次 `--headless --import`，`.godot/imported` 缓存已就绪）。

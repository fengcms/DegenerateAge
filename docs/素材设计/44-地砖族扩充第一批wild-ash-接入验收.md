# 44 地砖族扩充第一批：wild 9 变体 / ash 8 变体接入验收

日期：2026-10-17
执行方：我方
上游依据：[33 号制作单 §7](33-地砖族扩充第一批制作单-A层变体扩充.md)、[35 号复核 §8/§9](35-地砖族扩充第一批复核.md)、[41 号 §7](41-地砖族扩充cave脚本派生小样与验收.md)、[43 号道路索引冲突裁决](43-地砖族扩充第一批接入前道路中心索引冲突.md)
本轮范围：**A 层变体扩充收尾**——wild 由 4 变体扩到 9、ash 由 4 变体扩到 8，并修掉接入前发现的「道路中心被族变体数顶掉」隐患。不含 B 层新材质族与 L1 过渡边缘。

## 1. 交付物清单

| 文件 | 内容 |
|---|---|
| [tools/build_environment_art.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/build_environment_art.gd#L8-L59) | `TILE_PLAN` 查表化：wild 单张 3×3、ash 两张 2×2；`_pack_tiles` 四步逻辑不变 |
| [scripts/world/ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L47-L54) | 新增 `CAMP_ROAD/WILD_ROAD/ASH_ROAD/CAVE_ROAD` 与九档累计阈值常量 |
| [scripts/world/ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L480-L547) | 图集改「族砖 + 道路中心 + 八张边缘」；`_road_tile()` 新增；`_road_atlas_index()` 与族变体数彻底解耦；`_pick_theme_tile()` 支持 8/9 两套加权 |
| `assets/tiles/wild/tile_0..8.png` | 9 块新族砖（3×3 源稿打包） |
| `assets/tiles/ash/tile_0..7.png` | 8 块新族砖（两张 2×2 源稿打包） |
| `assets/tiles/wild/road.png` | 现役浅褐土路砖另存（道路中心独立资源） |
| [tests/ground_tile_theme_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/ground_tile_theme_test.gd) | 契约更新：wild 9 / ash 8 / camp 4；两套加权；三套道路索引；道路砖独立性 |
| [tests/map_texture_batch_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_texture_batch_test.gd#L33-L38) | 图集长度改按「族砖 + 1 道路中心 + 8 边缘」推导 |

## 2. 变更内容

### 2.1 打包脚本泛化（行列数查表）

`_pack_tiles` 不再写死 2×2 与 `theme + "_tiles.png"`，改为查 `TILE_PLAN`：

| 族 | 源稿 | 格数 | 产物 |
|---|---|---|---|
| wild | `ground_tiles_v1/wild_tiles_3x3.png` | 3×3 | `tile_0..8.png` |
| ash | `ground_tiles_v1/ash_tiles_a.png` + `ash_tiles_b.png` | 2×2 + 2×2 | `tile_0..7.png` |

每格仍走 **alpha 硬阈 → trim → 点采样 64×32 → 菱形掩码 + 填隙** 四步（含 cave 的边色 lerp 分支），仅文件名与行列数改为查表，处理逻辑逐行未动。

### 2.2 道路中心独立成槽（方案 A，见 43 号 §4）

**这是本轮最关键的一处改动。** 接入前发现下标 3 一直是**道路中心砖**（wild_trial 857 格、ash_land 874 格、corruption_source 538 格道路格通过 `_road_atlas_index(3, n)` 落到该位），若按 [35 号 §6.2](35-地砖族扩充第一批复核.md) 的「死位」判断直接扩块，两张图的道路会被绿草/灰土地面顶掉。

改法：图集由「族砖 + 八张边缘」变为 **「族砖(N) + 道路中心(1) + 八张边缘(8)」**，长度 N+9：

| 图 | 族砖 N | 图集布局 | 道路中心取自 |
|---|---|---|---|
| camp | 4 | 0–3 族砖 ｜ 4 道路 ｜ 5–12 边缘 | `camp/tile_3.png` |
| wild_trial | 9 | 0–8 族砖 ｜ 9 道路 ｜ 10–17 边缘 | `wild/road.png`（现役土路砖） |
| ash_land | 8 | 0–7 族砖 ｜ 8 道路 ｜ 9–16 边缘 | `chapter1_v2/ash_land/road_soft.png` |
| corruption_source | 9 | 0–8 族砖 ｜ 9 道路 ｜ 10–17 边缘 | `cave/tile_3.png` |

`_road_atlas_index(road_index, theme_size)` 相应改为 `theme_size`（中心）/ `theme_size + 1 + road_index - 4`（边缘）。camp 走白盒全图不经此路径；camp 样例（`sample_camp_theme`，无 `road_rows`）仍走原 `tile = 3` 兜底分支，落点仍是 `CAMP_TILES[3]`，**画面不变**。

### 2.3 选砖加权（8/9 两套）

`_pick_theme_tile` 改为按 `WEIGHTED_CUMULATIVE` 累计阈值取档，变体数不足九档时**末档并入前一档**：

| 变体数 | 各档占比 | 来源 |
|---|---|---|
| 4 | 沿用历史公式 `posmod(…,19)` 的 `1 if <4 / 2 if ==5 / 0` | 未动，camp 画面不变 |
| 9 | 38 / 24 / 10 / 7 / 6 / 5 / 4 / 3 / 3 | 35 号 §8 九档表 |
| 8 | 38 / 24 / 10 / 7 / 6 / 5 / 4 / **6** | 九档表末档 3% 并入第 7 档 |

### 2.4 资源

- wild 族砖整体换代（旧 2×2 → 新 3×3），ash 族砖由 4 块扩到 8 块。
- `assets/tiles/wild/road.png` = **HEAD 版 `wild/tile_3.png` 原字节另存**（已用 `cmp` 验证字节一致），保证 wild 道路观感零变化。
- camp / cave / chapter1_v2 全部资源**未改动**。

## 3. 回归门槛（逐项实测）

| 门槛 | 方法 | 结果 |
|---|---|---|
| 新产物 = 已评审小样 | `cmp` 逐块比对 `_packed/<fam>/tile_N.png` | **wild 0–8、ash 0–7 全部字节一致** |
| camp/cave 资源零改动 | `git status --porcelain assets/tiles/{camp,cave,chapter1_v2}` | 输出为空 |
| prop 资源零改动 | 同上（wild/ash/cave props 未被 git 标为 modified） | 未改动 |
| 道路砖仍为原土路 | `cmp <HEAD:wild/tile_3.png> assets/tiles/wild/road.png` | 字节一致 |
| 4 变体画面零漂移 | `GroundTileThemeTest` 逐格比对历史公式（64×64 格） | 差异 0 格 |
| 图集像素保真 | `MapTextureBatchTest` 逐槽比对图集与源图 `get_data()` | 通过 |
| UV 与道路槽位一致 | 同上，逐格核对 `u = tile / atlas_size` | 通过 |

## 4. 测试结果

### 4.1 定向

```
python3 tools/run_isolated_tests.py GroundTileThemeTest MapTextureBatchTest
→ GroundTileThemeTest: PASS · 全部通过
→ MapTextureBatchTest:  PASS
```

### 4.2 默认集（32 项）

```
python3 tools/run_isolated_tests.py
→ 32 / 32 PASS
```

### 4.3 全量（`--all`，98 项）

```
python3 tools/run_isolated_tests.py --all
→ 88 PASS / 10 FAIL
```

失败 10 项及其核对：

| 失败测试 | 是否本轮引入 | 核对方式 |
|---|---|---|
| ArtSampleTest | 既有 | 与本轮无关（槽位原画/图标裁边） |
| QualityFrameTest | 既有 | 同上（复用 ArtSample 断言） |
| ChapterOneMapArtCapture | 既有 | `--committed-tree` 复跑同样失败 |
| CampFullArtAcceptanceTest | 既有 | `--committed-tree` 复跑同样失败 |
| CampWhiteboxAcceptance | 既有 | `--committed-tree` 复跑同样失败 |
| CampLiveIntegrationTest / CampMapEditorTest / CampStyleSampleTest / CampStyleTraversalTest | 既有 | 已知基线（营地图层/编辑器口径） |
| MapRenderBenchmark | 既有 | 需 `--rendered` 窗口模式，headless 下天然失败 |

即**失败集合与本轮改动前的固定基线逐项一致，无新增失败**。

## 5. 实机确认用一览图

6× 点采样，每行末位为该图道路中心砖：

- 上行：`wild/tile_0..8` + `wild/road.png`（末位，浅褐土路）
- 下行：`ash/tile_0..7` + `chapter1_v2/ash_land/road_soft.png`（末位，压暗灰烬）

![wild/ash 族砖与道路砖一览](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/art_source/environment/ground_tiles_v1/_verify/44_wild_ash_tiles_6x.png)

## 6. 遗留与待实机确认

1. **待实机目视**：wild_trial 的道路是否仍读作一条完整的浅褐土路；ash_land 的道路（`road_soft` 压暗灰烬）是否清晰。
2. **待实机目视**：wild 新 9 变体的铺装观感（35 号 §4 提示新砖整体偏绿偏冷，是否需要在 `_pack` 后统一 +2 暖色）。
3. **延后项（B 批）**：`chapter1_v2/<map>/road_edge_*.png` 仍由旧 `tile_0`/`tile_3` 烘成，换族砖后道路边缘格底色与新地面存在轻微色差；按 35 号 §7 与 43 号 §5.2，本批不动，B 批随 L1 过渡边缘统一重烘。
4. **同源耦合提醒**：`build_chapter_one_v2_art.py` 仍以 `assets/tiles/{theme}/tile_3.png` 作为「道路」输入，wild 的 `tile_3` 已是绿草族砖——B 批重烘时必须改指向 `wild/road.png`，否则会烘出错误边色。

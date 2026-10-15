# D · 性能与长时稳定

> 审查对象：《末法纪元：最后的守护者》（Godot 4.7.2 / GDScript）核心系统的**运行成本与长时间稳定性**。
> 依据：[00-总体方法论.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/核心完整度审查/00-总体方法论.md)（判定标准与报告结构 §6）、[01-审计计划.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/核心完整度审查/01-审计计划.md)（§2 问题域 D）、[AGENT.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/AGENT.md) §2 / §7。
> 代码快照：`773b7d1`（工作区另有协作者未提交改动：`docs/测试反馈.md`、`scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`；本报告只读不改，未触碰上述文件）。
> 方法：静态逐入口核对（E2）+ 隔离测试实测（E1）+ 既有基准对照（E3）。未实测的帧率 / 内存结论一律标注「（推断）」。

---

## 1. 覆盖范围与实测命令

### 1.1 覆盖范围

| 项 | 内容 |
|---|---|
| §2 架构约束 | [AGENT.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/AGENT.md#L18) §2 表中 7 项逐入口核对：map_canvas / flat_tile_mesh / ground / spawner / cave_layout + cave_navigator / map_service |
| 热路径 | `_process()` / `_physics_process()` 内的资源加载、文件 I/O、JSON 解析、全表查询、深拷贝、节点树重建、高频日志 |
| 缓存 | map_canvas / cave_layout / map_service 的缓存键、所有者、生命周期、失效事件；读档 / 切图 / 缩放 / 门禁 / 布局变化的覆盖 |
| 节点与内存 | ground_item / loot_burst / fx(伤害飘字) / damage_number / monster_projectile / boss_tombstone 的创建→认领→回收入口 |
| 对象池 | 是否只在测量证明必要时引入；池化复用语义（本项目现状） |
| 实测 | §7 推荐入口的 7 项定向回归 + 附加渲染诊断 MapRenderBenchmark |

### 1.2 未覆盖项（明确声明）

- **SoakTest 正式 600s 压测本轮未复测**：需连续 600s 且其流程会快照 / 还原真实 `saves/`（见 [09-长时稳定性压测（SoakTest）.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/09-长时稳定性压测（SoakTest）.md#L50)），成本高且触碰真实玩家存档；按任务许可跳过，相关结论以历史基准（E3）引用并显式标注。
- 真实设备稳定帧率 / 帧时间 P99、GPU 耗时、过绘制、显存与纹理内存未采样；仅采到渲染诊断组（`MapRenderBenchmark`，冻结主要玩法逻辑）。
- 4K / 高缩放下的长时游玩、切图与读档瞬间的尖峰曲线未采样。
- 排除范围（不作为缺陷）：美术素材、后续章节内容、具体数值配置、第二章功能开发。

### 1.3 实测命令与运行环境

```bash
# 主命令（AGENT.md §7 定向回归）
python3 tools/run_isolated_tests.py MapCanvasCacheTest SpawnerBudgetTest CaveConnectivityTest \
  MapLoadingCacheTest FlatTerrainMeshTest MapTextureBatchTest MapPerformanceTest

# 附加：实际窗口绘制诊断（本报告补充执行）
python3 tools/run_isolated_tests.py --rendered MapRenderBenchmark
```

- 运行方式：macOS，Godot `/Applications/Godot.app/Contents/MacOS/Godot`，**非沙箱**执行（Godot 需写 `~/Library/Application Support/Godot`）。
- 隔离：`tools/run_isolated_tests.py` 使用随机项目名 + 独立 `user://`，不触碰真实存档（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L1)）。
- 通过判据（依 [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L54)）：进程退出码 0 且输出含 `SCRIPT ERROR:` / `FAIL` 即判失败，另外要求输出含成功完成标记（`PASS` / `全部通过`）。

**实测结论：主命令 7 项全部 PASS，无任何 FAIL 诊断行、无 `SCRIPT ERROR:`，运行器总退出码 0。附加 MapRenderBenchmark（渲染）1 项 PASS。**

---

## 2. 完整度评估

### 2.1 §2「必须保留的性能架构」逐项核对

| # | 约束 | 入口 | 现状 | 判定 |
|---|---|---|---|---|
| 1 | 小地图 / 大地图：静态底图与动态标记分层；玩家移动不重建底图；投影参数缓存 | [map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L39) | 标记层为独立 `Node2D`（`_overlay`，L39-42）；玩家位置 / 标记变化只 `_overlay.queue_redraw()`（L91-95）；`_ensure_projection()` 缓存 `_dims/_world_rect/_scale`（L98-116），`_polygon()` 直取缓存投影（L181-182） | **保持** |
| 2 | 静态同色地形：批量几何，避免每格独立绘制调用 | [flat_tile_mesh.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/flat_tile_mesh.gd#L41) | 凸四边形批量进单个 `ArrayMesh`，`build()` 一次提交（L41-55）；map_canvas 已探索地形与 ground 阻挡顶面各用单表面（[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L220)、[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L350)） | **保持** |
| 3 | 纹理地面：复用图集与网格，保留瓦片选择 / 透明度 / 铺设顺序 | [ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L394) | 运行时拼一张 `ImageTexture` 图集（仅在图集块变化时重建，L398-406），全图一组 `FlatTileMesh` + 单 `draw_mesh`（L407-433）；瓦片变体 / 道路过渡 / 列行插入顺序未改（L413-430） | **保持** |
| 4 | 怪物刷新：每轮统计一次普通怪预算，同轮生成 / 退场同步更新；禁止逐候选全量计数 | [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L112) | `_process` 开头取一次快照 `_active_normal_count()`（L114），生成成功 +1、退场 -1（L120-131）；批量装配同样一次快照并复用（L61、L97-98）；仅独立 `_spawn()` 调用保留自算快照兜底（L158-159） | **保持** |
| 5 | 可达性筛选：连通区域判断；选中移动目标后才构建完整路线 | [cave_layout.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/cave_layout.gd#L114)、[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L492) | `_ensure_components()` 懒构建连通编号（L114-144）；`_route_reachable()` 只查连通分量（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L492)）；完整 `route()` 仅在目标跨格 / 偏航时构建（[cave_navigator.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/cave_navigator.gd#L27)） | **保持** |
| 6 | 动态门禁：通行变化更新导航版本，路线 / 巡游 / 地图显示缓存随之失效 | [cave_layout.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/cave_layout.gd#L73)、[cave_navigator.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/cave_navigator.gd#L19) | 开关门递增 `navigation_revision` 并改 AStar 实心格（L73-87）；CaveNavigator 比对 revision 后清缓存重算（L19-22）；巡游按 revision 重建（[auto_battle.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/auto_battle.gd#L444)）；地图底图把 revision 纳入失效键（[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L81)） | **保持** |
| 7 | 默认落点：查询布局掩码并缓存，不为一个坐标重复建立完整 A* | [map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L435) | `entry_point()` 走静态掩码 `nearest_cell_in_layout`（不建 AStar、不建 blocked 字典），结果按 `(size, layoutPath)` 缓存（L445-453），`data_loaded` 清缓存（L35） | **保持** |
| 8 | 静态碰撞：相同且不再修改的几何复用 Shape 资源 | [ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L281) | 一个 `ConvexPolygonShape2D` 复用到所有洞壁格（L281-287） | **保持** |

**退回检查（AGENT.md §2 末段禁止项）：未发现退回。**

- 未见逐格 `draw_colored_polygon()`：map_canvas 的探索地形走批量网格（[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L207)）；ground 的阻挡顶面同样合批（[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L347)）。余下 `draw_colored_polygon` 均为**整块填充**（地图外框、营地白盒实体、腐化源洞壁立面），不属于「静态同色地形逐格」。
- 未见逐瓦片切换纹理：图集一次拼成，纹理绑定只在 `draw_mesh` 一次（[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L433)）。
- 未见逐候选全量计数：刷新预算为每轮一次快照（[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L114)）；巡游候选零完整寻路（实测断言，见 §4.1）。

### 2.2 分项完整度分级

| 维度 | 分级 | 依据 |
|---|---|---|
| §2 性能架构约束保持 | **A 已闭环** | 7 项全部成立（E2，逐入口行号见 2.1）；5 项有专项测试断言（E1） |
| 热路径洁净度 | **B 基本可用** | 未发现资源加载 / 文件 I/O / JSON 解析 / 深拷贝进入逐帧路径（E2）；但**全表线性查询仍混入热路径**（P2-2 / P2-3 / P3-1 / P3-2） |
| 缓存键 / 所有者 / 生命周期 / 失效 | **A 已闭环** | 三处缓存均有明确键与失效事件，且读档 / 切图 / 缩放 / 门禁 / 探索替换均有测试覆盖（[map_canvas_cache_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_canvas_cache_test.gd#L26)） |
| 节点 / 内存长期稳定 | **B 基本可用** | 掉落 / 飘字 / 投射物 / 墓碑均有明确回收入口（E2）；但**未领取战利品（persistent）无上限**（P2-1），且**本轮未复测长跑**，长时结论只能引用历史基准（E3） |
| 对象池 | **A 已闭环** | 全项目未引入节点对象池，全部为「即时实例化 → 自动回收」；符合 AGENT.md §5「只有测量显示尖峰时才引入」（E2 + 历史 E3） |

**本域完整度：B（基本可用）** —— 架构约束与缓存机制达 A，主路径可走通；扣分点是长时稳定的**上限缺失**与**热路径残留的全表查询**，且缺少本轮的长跑实测。

---

## 3. 问题清单

> 未发现 P0 / P1：本轮 7 项定向回归与 1 项渲染诊断全部通过，未测到崩溃、卡死、预算突破、逐候选全量计数或架构回退；长时稳定的问题均为「上限 / 常数级成本」类，按方法论 §4.2 归入 P2–P3。

### P2-1 「未领取战利品」无件数上限，长挂机下节点与存档条目单调增长

- **位置**：[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L186)（登记）、[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L146)（persistent 跳过 60s 淡出）、[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L842)（仅 append，无上限）、[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L244)（场景重载时按记录逐件重建地面物）。
- **现象**：精英 / Boss 掉落入包失败（背包满、金币满）时，`_register_unclaimed()` 写入 `GameState.unclaimed_loot`；该条记录只在「领取成功」或玩家主动丢弃时注销。同时该地面物 `persistent=true`，**不参与 60s 淡出**（L146 只在 `not persistent` 时递减寿命），`_physics_process` 每帧照常重绘与跑动画。切图 / 读档回来时 `_rebuild_unclaimed_loot()` 会把**该图全部记录逐件实例化**（[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L251)）。
- **影响**：在背包长期满、反复击杀精英/Boss 的挂机场景下，节点数、每帧重绘成本、存档体积都会随掉落次数**单调增长**（推断：本轮未做满背包长跑，属 E4 推断；机制为 E2 代码证据）。这不是「设计上的留地物」，而是设计意图（§11 持久化）**缺少累积上限**。
- **建议**：为每图未领取记录设上限（例如 30 件）与超限策略（按品质保留、其余转为批量摘要提示或自动折算）；`_rebuild_unclaimed_loot()` 同样按上限分批实例化；把上限与策略写入产品 / 工程文档并与批次摘要文案一致。
- **证据等级**：E2（代码路径）+ E4（增长结论，未实测）。

### P2-2 迷雾揭示在每次换格时对内层 17×17 格重复解析地图尺寸（净增全表线性查询）

- **位置**：[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L61)（玩家换格即 `Fog.reveal`）→ [fog.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/fog.gd#L22)（`reveal` 内层循环）→ [fog.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/fog.gd#L16)（`block_id` → `block_grid`）→ [fog.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/fog.gd#L8)（`block_grid` → `MapService.grid_size`）→ [map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L123) → [data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L75)（按 id 线性查找 `maps` 数组）。
- **现象**：`reveal()` 每次调用先做一次 `contains()`（又解析一次尺寸），随后对半径 8 的圆内 17×17=289 格逐格调用 `block_id()`，而 `block_id()` 内部再次调 `block_grid()` → `MapService.grid_size()`。也就是**每次换格约 290 次「数据结构 + 全表线性查找」**，仅用于取同一个 `dims`。
- **影响**：移动本身就会持续产生该成本（换格频率 ∝ 移动速度）；这是 [大地图运行卡顿性能改进报告.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/大地图运行卡顿性能改进报告.md#L44) 已点名「每格重复获取地图尺寸 / 线性查找」这一类问题的**未清理残留**（该报告只修了小地图侧）。单次成本不高，量级为 CPU 常数开销（推断，未分别计时）。
- **建议**：`reveal()` 内把 `dims` 与 `block_width` 提到循环外；`block_id()` 允许传入已解析的 `block_grid`；或让 `DataLoader.get_entry` 变为索引查表（见 §5 第 1 项），从根上消除该类重复。
- **证据等级**：E2（调用链）+ E4（耗时量级）。

### P2-3 快捷栏冷却显示在 `_process` 中逐帧遍历背包并线性查表

- **位置**：[hotbar_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hotbar_slot.gd#L54)（每帧）→ [hotbar_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hotbar_slot.gd#L65)（`_remaining_cooldown`：遍历 `GameState.inventory`，对每件药水调 [DataLoader.get_entry("potions")](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L75)）。
- **现象**：`auto_potion` 类型的快捷栏格，每帧遍历整包（上限 40 格）并对每件药水做一次全表线性查找，只为算出一个「最小剩余冷却」；若有 N 个自动喝药格，成本再乘 N。
- **影响**：属 AGENT.md §6 明确禁止的「`_process` 热路径全表查询」；与挂机时长无关，是**固定每帧开销**，背包越满越贵。实测未单独计时（推断量级：数十次线性查找/帧）。
- **建议**：冷却显示改为事件驱动或降频（0.25s 级），并由 `Consumable` 暴露聚合冷却查询入口（唯一入口），避免 UI 自己扫背包；或在 `HotbarVisual` 层统一算一次供全部格共享。
- **证据等级**：E2 + E4（量级）。

### P3-1 `MapService.is_in_rest_zone()` 每次调用重新解析安全区，且未缓存

- **位置**：[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L224)（`safe_area_cells` 每次 `data_for` → 线性查找 + 重建 `Rect2`）→ 被 [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L548)、[monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L559)（每只怪物每物理帧 1–2 次）与 [monster_projectile.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster_projectile.gd#L23)（每个投射物每物理帧 1 次）调用。
- **现象**：安全区判定每次都要「解析 maps 表 → 取 safeArea → 建 Rect2」，且 `map_service` 侧只缓存了默认落点（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L32)）。
- **影响**：物理热路径上的固定全表查询；同时是 [spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L262) 兜底扫描（最多 40×40 格）里最贵的单步。量级为常数开销（推断）。
- **建议**：按 `map_id` 缓存 `safeArea`（与 `_entry_cache` 同机制，`data_loaded` 清空）；或随 §5 第 1 项的索引一并解决。
- **证据等级**：E2。

### P3-2 地图标记每次刷新对全部刷新点做全表查询

- **位置**：[map_markers.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_markers.gd#L21)（对每个刷新点查 `monsters` 表判 Boss / 匹配任务目标），被 [map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L73) 每 0.2s 调用一次（小地图常驻可见即常驻执行）。
- **现象**：一次刷新 = 刷新点条数（`c2_lower_works` 实测 131 点）× 线性查 `monsters`；若进行中的收集任务匹配，还会对每个点再遍历一次掉落表（[map_markers.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_markers.gd#L44)）。
- **影响**：非逐帧但高频（5 次/s），且随「刷新点条数 × 任务数」线性放大；属可事件化的开销（推断）。
- **建议**：标记列表按「刷新点集合 / 任务状态 / 解锁状态」失效缓存，而非定时全量重算；`monsters` / `dropTables` 查表改为索引。
- **证据等级**：E2。

### P3-3 腐化源仍残留约 1,988 次绘制调用（实测，属既有已知残余）

- **位置**：[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L320)（洞壁段收集）→ [ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L517)（逐段 `draw_colored_polygon` + 2 条折线 + 4 条刻痕线）。
- **实测**：`corruption_source` 正常显示 **1,988 次绘制调用**，诊断帧间隔中位数 **8.306 ms**、P95 **9.811 ms**；隐藏地面后降到 **135 次 / 0.981 ms**（见 §4.1 表）。
- **判定**：这是**洞窟壁面装饰分支**的逐段绘制，不是「静态同色地形逐格绘制」的退回；[大地图性能优化实施记录.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/大地图性能优化实施记录.md#L89) 阶段 6 已记录该残余并明确「当前诊断未显示需要立即重构」。本轮复测数值与记录一致（1,987 → 1,988），**不构成新回退**。
- **建议**：仅在后续新增腐化源探索内容或加大该图规模时，评估洞壁合批（同类边批量成网格）；不建议本轮动。
- **证据等级**：E1（实测）+ E3（历史记录）。

### P3-4 / P3-5 两处运行时 `load()`（非逐帧，均有引擎缓存）

- [chapter_two_art.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/chapter_two_art.gd#L31)：正式美术包附加时每次刷怪 `load()` 5 张动画图集（`_manifest` 已静态缓存，纹理经 `ResourceLoader` 复用）。
- [monster.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster.gd#L220)：Boss 召唤/死亡召唤时 `load("res://scenes/entities/Monster.tscn")`。
- **判定**：两者都不在逐帧路径（分别在刷怪与召唤事件），且受引擎资源缓存保护，**不违反 §6 热路径约束**；记录为可读性 / 一致性建议（可改为与 `MONSTER_SCENE` 同款的预加载常量）。
- **证据等级**：E2。

### P3-6 地面物每物理帧重绘与组查询（表现必需，仅提示边界）

- [ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L137)：每物理帧 `queue_redraw()`（浮动 / 落地 / 高亮 / 飞行需要持续重绘），并在未认领 / 飞行阶段每帧 `get_first_node_in_group("player")`（[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L344)）。
- **判定**：属 AGENT.md §5「限制的是可替代的表现开销」范围内的**不可替代表现**；不判缺陷。建议与 P2-1 的上限一并考虑：若同时存在的掉落物被限制在个位数，则该项成本可忽略。
- **证据等级**：E2。

### 3.x 已核对为「正确」的关键点（不计问题）

- **缓存键 / 失效**（任务项 3）：map_canvas 键 = `当前地图 + 装饰框 + 控件尺寸 + 小地图标志 + CaveLayout 实例 + navigation_revision + 探索字典标识与大小`（[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L79)），缩放 / 尺寸变化由 `resized` 触发失效（[map_canvas.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/map_canvas.gd#L43)）；cave_layout 分量缓存键 = `navigation_revision`（[cave_layout.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/cave_layout.gd#L115)）；map_service 默认落点缓存键 = `(size, layoutPath)`，`data_loaded` 清空（[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L447)）。读档（探索字典被替换→`is_same` 判否）、切图（`current_map` 变化 / CaveLayout 实例变化）、门禁（revision）、布局变化（新实例）**全部覆盖**，且由 MapCanvasCacheTest / CaveConnectivityTest / MapLoadingCacheTest 断言。
- **节点回收**：GroundItem 三条回收路径（认领即入包免飞行 [ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L178)、飞行抵达 [ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L253)、未认领 60s 淡出 [ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L338)）均先 `set_physics_process(false)` 再 `queue_free()`；DamageNumber 用节点自持 Tween + `tween_callback(queue_free)`（[damage_number.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/damage_number.gd#L37)），节点释放即 Tween 一并销毁；MonsterProjectile 在超距 / 命中 / 来源失效 / 进安全区四条路径回收（[monster_projectile.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/monster_projectile.gd#L10)）；墓碑在被重生时 `queue_free()` 并置空引用（[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L177)）。**未发现脱组后残留的活动节点、未回收计时器或跨代信号引用**（怪物 `died` 用一次性 lambda 连接，随怪物释放消失，[spawner.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/spawner.gd#L183)）。
- **LootBurst**：纯 `static` 计算、无节点、无副作用（[loot_burst.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/loot_burst.gd#L100)），不构成节点增长源。
- **热路径无 I/O**：全部 `FileAccess.open` / `JSON.parse_string` 出现在装配期或显式重载入口（[ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd#L107)、[chapter_two_art.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/chapter_two_art.gd#L55)、[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L54)、[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L24)、[save_manager.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/save_manager.gd#L822)），均不在 `_process` / `_physics_process` 内。深拷贝（`duplicate(true)`）集中在存档编码 / 物品流转，亦不在逐帧路径。

---

## 4. 证据与复核方法

### 4.1 实测结果表

命令：`python3 tools/run_isolated_tests.py MapCanvasCacheTest SpawnerBudgetTest CaveConnectivityTest MapLoadingCacheTest FlatTerrainMeshTest MapTextureBatchTest MapPerformanceTest`（非沙箱，隔离 `user://`）

| 测试 | 结论 | 关键数值（本轮实测） | 历史基准 | 对照说明 |
|---|---|---|---|---|
| MapCanvasCacheTest | **PASS** | 底图绘制计数：移动不动底图、探索 / 缩放 / 探索字典替换 / 隐藏后重开均重建、静止保持缓存（6 条断言，[map_canvas_cache_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_canvas_cache_test.gd#L26)） | 阶段 1（2026-10-14） | 一致 |
| SpawnerBudgetTest | **PASS** | `count_calls == 1`（初始化 / 满额刷新各只统计一次）、同轮普通怪 ≤ 10、死亡补位不破预算、外部释放不泄漏、远距退场再返回恢复预算、精英不占普通预算（[spawner_budget_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/spawner_budget_test.gd#L24)） | 阶段 2 | 一致 |
| CaveConnectivityTest | **PASS** | 624 个巡游候选点 **完整寻路 0 次**（`path_calls == 0`）、门禁开关使缓存路线失效并重试、连通判定与 AStar 逐点一致、合法空巡游只构建 1 次（[cave_connectivity_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/cave_connectivity_test.gd#L71)） | 阶段 3 | 一致 |
| MapLoadingCacheTest | **PASS** | 默认落点缓存 **1000 次查询 3.506 ms**；洞壁 **522 个** CollisionShape 共享同一 Shape 资源；连通数据在装配期就绪（[map_loading_cache_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_loading_cache_test.gd#L36)） | 阶段 4：**3.712 ms** | 同口径略快（−5.6%） |
| FlatTerrainMeshTest | **PASS** | `c2_lower_works` **28,740 个可行走格 → 单个绘制表面**（28,740×4 顶点 / ×6 索引）、不泄露洞壁、每格恰好一次、清空探索后旧网格被移除（[flat_terrain_mesh_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/flat_terrain_mesh_test.gd#L29)） | 阶段 5（合批前约 2.9 万次调用） | 一致 |
| MapTextureBatchTest | **PASS** | 纹理地面单表面、每可走格 4 顶点、图集每块与原始瓦片像素逐点相同、12 块图集、UV 与道路过渡选择正确（[map_texture_batch_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_texture_batch_test.gd#L20)） | 阶段 6 | 一致 |
| MapPerformanceTest | **PASS** | 装配 **135.734 ms**；巡游构建 **1.634 ms / 624 点**；投影 10,000 次 **5.368 ms**；刷新器 200 次 **53.068 ms / 131 点** | 阶段 6：126.001 / 1.693 / 4.999 / 51.446 ms | 装配 +9.7 ms，其余同量级（见 §6） |
| MapRenderBenchmark（附加，`--rendered`） | **PASS** | 见 4.2 | 阶段 6 | 一致 |
| SoakTest（600s 正式压测） | **未执行（跳过）** | — | 2026-10-12：击杀 108、孤儿节点恒 0、节点 276→279、对象 2642→2647、静态内存 109→110MB、最大采样间隔 5.02s、引擎错误 0 | 见 §6 差异说明 |

判定通过性：主命令运行器总退出码 0；7 项均输出成功完成标记；运行器仅在测试失败时才回显 `SCRIPT ERROR:` / `ERROR:` / `失败：` 诊断行，**本次无任何诊断行输出**，且 `run()` 把输出含 `SCRIPT ERROR:` 视为失败（[run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L54)），故可判定本轮无脚本错误。

### 4.2 渲染诊断（附加，1280×800 窗口，冻结主要玩法逻辑，每组确认绘制 140 帧）

| 地图 | 场景 | 绘制调用 | 诊断帧间隔中位数 | P95 |
|---|---|---:|---:|---:|
| c2_lower_works | 正常显示 | **198** | 1.794 ms | 6.489 ms |
| c2_lower_works | 隐藏地面 | 194 | 1.340 ms | 4.390 ms |
| c2_lower_works | 隐藏地图 UI | 191 | 1.466 ms | 4.619 ms |
| wild_trial | 正常显示 | **148.1** | 1.273 ms | 16.164 ms |
| wild_trial | 隐藏地面 | 139.1 | 1.210 ms | 2.586 ms |
| corruption_source | 正常显示 | **1,988** | 8.306 ms | 9.811 ms |
| corruption_source | 隐藏地面 | 135 | 0.981 ms | 2.270 ms |

历史对照（阶段 6）：`c2_lower_works` 198 次 / 2.365 ms（P95 11.254）；`wild_trial` 137 次 / 1.225 ms（P95 3.338）；`corruption_source` 1,987 次 / 8.228 ms（P95 10.620）。三者绘制调用与中位数均在历史同区间，**无回退**；`wild_trial` 的 P95 16.164 ms 与记录「窗口调度会造成波动」一致（该组隐藏地面时 P95 仅 2.586 ms）。

> ⚠ 该诊断冻结主要游戏逻辑并显式强制绘制，**不代表完整战斗帧率**（AGENT.md §7 明确）。本报告不据此给 FPS 结论。

### 4.3 复核方法

```bash
# 复现本报告全部实测
python3 tools/run_isolated_tests.py MapCanvasCacheTest SpawnerBudgetTest CaveConnectivityTest \
  MapLoadingCacheTest FlatTerrainMeshTest MapTextureBatchTest MapPerformanceTest
python3 tools/run_isolated_tests.py --rendered MapRenderBenchmark

# 单点复核（本报告行号为静态证据）
#   架构约束 → scripts/ui/map_canvas.gd、scripts/systems/flat_tile_mesh.gd、scripts/world/ground.gd、
#              scripts/world/spawner.gd、scripts/world/cave_layout.gd、scripts/world/cave_navigator.gd、
#              autoload/map_service.gd
#   热路径   → scripts/systems/fog.gd、scripts/ui/hotbar_slot.gd、scripts/entities/monster.gd、
#              scripts/entities/monster_projectile.gd
#   节点回收 → scripts/entities/ground_item.gd、scripts/systems/loot_burst.gd、
#              scripts/ui/damage_number.gd、scripts/entities/monster_projectile.gd
```

- 静态证据为**文件 + 行号**，可被他人逐条复核（E2）。
- 实测证据为隔离工程输出，独立 `user://`，不污染真实存档（E1）。
- 历史基准引用自 [大地图性能优化实施记录.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/大地图性能优化实施记录.md) 与 [09-长时稳定性压测（SoakTest）.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/09-长时稳定性压测（SoakTest）.md)，仅作对照（E3），不作为本轮实测结论。

---

## 5. 落地优化方案

按「先消同类根因、再加保险上限、最后按新证据决定大改」排序；每项独立提交、独立对照。

### 第 1 步（根因，一次解决 P2-2 / P3-1 / P3-2 的同类成本）

给 `DataLoader` 增加「表名 → id → entry」索引，`get_entry()` 由线性查找改为查表；并在 `load_all()` / `_load_json()` 写入时重建索引（失效点唯一）。

- 触及：[data_loader.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/data_loader.gd#L75)、[map_service.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/map_service.gd#L123)。
- 验证：`MapPerformanceTest` 同入口对照 + `MapLoadingCacheTest`（默认落点缓存仍有效）+ `SmokeTest`（数据校验与跨表引用不回归）。新增断言宜放在「同轮查询次数」而非耗时。

### 第 2 步（保险上限，解决 P2-1）

为「未领取战利品」设每图件数上限与超限策略：按品质保留，其余合并为批次摘要（不丢真实掉落，符合 AGENT.md §5）；`_rebuild_unclaimed_loot()` 按上限分批实例化。

- 触及：[game_state.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/game_state.gd#L842)、[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L244)、[ground_item.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/entities/ground_item.gd#L186)。
- 验证：`BossReviewTest`（未领取记录可存档的既有断言）+ `SmokeTest::_test_unclaimed_loot` + 满背包场景的定向长跑（建议配合第 4 步）。

### 第 3 步（热路径降频，解决 P2-2 / P2-3）

`Fog.reveal()` 把 `dims` 与区块宽度提到循环外；`block_id()` 接受已解析的区块网格；快捷栏冷却显示改为事件 / 降频，并让 `Consumable` 提供聚合冷却唯一入口。

- 触及：[fog.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/systems/fog.gd#L22)、[game.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/game.gd#L61)、[hotbar_slot.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/ui/hotbar_slot.gd#L54)。
- 验证：`MapCanvasCacheTest`（迷雾失效路径）、`SmokeTest` 迷雾 / 安全区 / 快捷栏断言、`HotbarUiTest`、`InputFeedbackTest`；改前后同入口测量。

### 第 4 步（补证据，缩放阈值判定）

在 M7 / 大版本交付前重跑一次 `SoakTest`（无头 600s，先 `--check-only` 确认脚本可解析，再短跑 3–5s 验证流程），并在其负载里**加入「背包满 → 精英/Boss 掉落留地」场景**，验证第 2 步上限生效且节点 / 内存不漂移。

- 依据：AGENT.md §7「新增高负载内容或交付大版本时实际持续游玩并检查节点/内存」；工程文档 09 §6 已知边界。
- 产出：更新 [09-长时稳定性压测（SoakTest）.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/09-长时稳定性压测（SoakTest）.md) 的实测章节与新基准。

### 暂不做（缺测量支撑）

- **对象池**：当前无实测尖峰证据（历史 600s 压测节点 / 对象无漂移），引入即违反「只有测量证明必要时」；
- **地形视口分块 / 碰撞轮廓合并 / 洞壁合批**：绘制调用主问题已由合批解决，腐化源残余 1,988 次有场景隔离证据（隐藏地面降 135 次）但未显示需要立即重构；
- **刷新空间索引**：131 点规模不构成需求。

---

## 6. 与既有文档差异说明

| 既有文档 | 差异 / 本轮结论 |
|---|---|
| [大地图性能优化实施记录.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/大地图性能优化实施记录.md)（阶段 0–6） | 阶段 0–6 的核心数值本轮**复测保持**（巡游 1.634 vs 1.693 ms、投影 5.368 vs 4.999 ms、刷新器 53.068 vs 51.446 ms、绘制调用 198/148/1988 vs 198/137/1987）。差异项为**装配耗时 135.734 ms vs 126.001 ms（+9.7 ms）**：该记录已声明同期美术改动不宜归因，本轮工作区此后又并入 `look_02` 骑士形象与营地白盒正式接入等提交，装配内容增加，属**装配量增长而非性能回退**（E2+E3，未逐段归因）。 |
| [大地图运行卡顿性能改进报告.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/审阅报告/大地图运行卡顿性能改进报告.md) | 其 P1「小地图投影缓存 + 分层」「刷新器预算复用」「巡游可达性」均已落地并通过本轮断言（属**已闭环**）；其 P2「地形分块」的「不应未经采样就作为第一项大改」结论仍成立。**差异**：该报告 §三 点名的「每格重复地图尺寸查询 / `get_entry` 线性查找」只在小地图侧被消解，`Fog` 与 `MapService` 侧仍是残留 → 本轮记为 P2-2 / P3-1。 |
| [09-长时稳定性压测（SoakTest）.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/09-长时稳定性压测（SoakTest）.md)（2026-10-12，M1） | 该基准的负载不含此后新增的 **未领取战利品持久化（M6-0c）、装备雨编排（M6-0d）、切图 / 多图（M3）、坐骑与技能（M7/M8）**，故其「无泄漏」结论**不再覆盖当前链路**；且本轮未复测。本报告因此把长时稳定结论标为 B 级并给出第 4 步复测方案。文档 §5 的「留地掉落物 0 → 0」也需按 M6-0c 的 persistent 分支重新解读。 |
| 审计计划 §2 问题域 D（5 问） | ①架构约束 7 项仍在、无退回 → 已核；②热路径无 I/O 与深拷贝，但存在全表查询残留 → P2-2/P2-3/P3-1/P3-2；③缓存键 / 所有者 / 失效明确且测试覆盖 → A；④节点回收入口完整，但未领取战利品缺上限、长跑未复测 → P2-1；⑤对象池按「测量必要时才引入」保持未引入 → A。 |
| 既有失败基线 | `ArtSampleTest`、`ChapterOneArtTest`、`QualityFrameTest`、`IconIntegrationTest` 为本轮**未执行**项；其历史失败（如 `ChapterOneArtTest` 木桩血条差异）与本域无关，**未作为新问题上报，也未降低任何断言**。 |

---

## 7. 结论摘要

- **架构层面无退化**：AGENT.md §2 七项性能架构在本轮逐入口核对全部成立，7 项定向回归 + 1 项渲染诊断实测通过（退出码 0、无 `SCRIPT ERROR:`）。
- **实测基准与历史一致**：合批、缓存、预算复用三类优化的数值均落在历史同区间（详见 §4.1 / §4.2）。
- **待办集中在两处**：一是「未领取战利品无上限」的长时增长保险（P2-1），二是「全表线性查询混入热路径」的残留（P2-2 / P2-3 / P3-1 / P3-2）；两者都不阻断当前交付，但建议在 M7 前按 §5 第 1–4 步处理并重跑 SoakTest 建立新基准。

# H · 测试覆盖与发布就绪度

> 问题域：**H｜测试覆盖与发布就绪度**（审计计划 §2-H）。
> 审查对象：《末法纪元：最后的守护者》（Godot 4.7.2 / GDScript）。
> 产出定位：回答「验证是否可信、能否真正交付」。
> 快照：HEAD = `a5c3ad7`（详见 §1.2 工作区状态）。

---

## 1. 覆盖范围与实测命令

### 1.1 覆盖范围

本报告覆盖以下对象（不含美术素材、后续章节内容、具体数值配置——见方法论 §2 排除项）：

| 类别 | 对象 | 证据来源 |
|---|---|---|
| 测试基础设施 | [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py) | E2 静态 + E1 实测 |
| 测试场景全集 | `tests/*.tscn`（61 个）、`tests/*.gd`（61 个） | E2 清单 |
| 核心路径覆盖 | 战斗/掉落/背包/经济/任务/地图/死亡/技能/存档/出行/设置/性能 | E2/E1 对照矩阵（§4.2） |
| 发布就绪 | [project.godot](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/project.godot)、[export_presets.cfg](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/export_presets.cfg)、[main.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/main.gd)、[localization.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd) | E2/E3 + E1 实测 |
| 文档声明 | [15-M5收口与MVP实施方案.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/15-M5收口与MVP实施方案.md)、[25-第一章功能收口与准出计划.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/25-第一章功能收口与准出计划.md) | E3 文档对照 |

**明确不做**（方法论 §2）：美术素材的合格性、第二章及以后内容、具体数值调平。美术类测试的失败仅在 §2/§4 中作为**已知基线事实**记录，不作为缺陷上报。

### 1.2 实测命令

```
python3 tools/run_isolated_tests.py
python3 tools/run_isolated_tests.py ArtSampleTest ChapterOneArtTest QualityFrameTest IconIntegrationTest
```

运行器用法（读 [run_isolated_tests.py](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py) 确认）：

- **测试选择**：无参时运行内置 `DEFAULT_TESTS` 列表（22 项，见 [run_isolated_tests.py#L17](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L17)）；带参则运行指定 `res://tests/{Name}.tscn`。
- **隔离方式**：随机项目名 `DegenerateAge-Test-<uuid>`（[#L67](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L67)），`user://` 指向该随机名目录并在结束时只清理该目录（[#L69](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L69)、[#L117](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L117)），**永不触碰正式游戏名存档**。`project.godot` 的 `config/name` 被替换为随机名（[#L90](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L90)）。
- **判定通过**：`failed = returncode != 0 or "SCRIPT ERROR:" in output or "FAIL" in output`（[#L54](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L54)）；再叠加**成功完成标记**校验 `completed = any(marker in output for marker in ("PASS","全部通过","全部断言通过"))`（[#L103](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L103)）。无完成标记一律判 FAIL（[#L106](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L106)），即**异步测试必须显式完成，不允许「提前退出也算通过」**。
- **`--committed-tree`**：支持（[#L61](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L61)、[#L73](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L73)），用 `git archive HEAD` 解包到临时目录，取**已提交快照**跑回归，隔离并行美术试作。
- **工作区复制策略**（无 `--committed-tree` 时）：`scripts/autoload/data/scenes/tests/addons` **整目录拷贝冻结**，其余（assets 等素材）用软链接复用（[#L82](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L82)）——即**代码/数据/测试冻结，素材复用工作区**（见 §6 与 AGENT.md §7「并行工作时固定代码快照」）。
- 单测试超时 240s（[#L102](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L102)）、`--quit-after 14400` 帧上限。

### 1.3 工作区快照状态（重要）

实测 `git status`：

- HEAD = `a5c3ad7 feat(assets): 制作幸存者营地正式环境分层素材`
- **未提交改动**（本次实测快照包含，属营地正式分层美术整合工作）：
  - [docs/测试反馈.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/测试反馈.md)（试玩反馈追加）
  - [ground.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/ground.gd)（新增 `_load_camp_final_art()`：读 `assets/maps/camp_final_v1/manifest.json`，绘制正式底图 + 六个整体前景精灵）
  - [rest_zone_overlay.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/scripts/world/rest_zone_overlay.gd)（营地不再叠加安全区调试线）
  - [camp_live_integration_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/camp_live_integration_test.gd)、[map_render_benchmark.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/map_render_benchmark.gd)
- **任务/方法论描述与实测不符**：任务与方法论 §8 称工作区含「`scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`」未提交改动，但实测这两个文件已随 `b84d726 fix(ui): 修复货郎购买页横向滚动` **提交**，当前工作区对它们为 clean。**本报告快照以上述真实 `git status` 为准。**

> 结论：本次全量回归快照 = 已提交树 `a5c3ad7` + 上列 5 个未提交文件（营地美术整合）。回归运行时 `tests/` 被整目录拷贝（含未提交的 `camp_live_integration_test.gd`），但该文件**不在默认回归集**中，故未影响默认 22 项结论。

---

## 2. 完整度评估

| 子项 | 分级 | 依据 |
|---|---|---|
| **测试覆盖广度** | **B 基本可用** | 主路径（战斗/掉落/背包/经济/任务/地图/死亡/技能/存档/出行/设置）均有测试且断言可信；但默认回归只跑 **22/61** 场景，本地化缺 key 与通用长时稳定**无自动化**。 |
| **验证可信度** | **A 已闭环** | 退出码 + 成功完成标记 + `SCRIPT ERROR`/`FAIL` 三重判据（[run_isolated_tests.py#L54](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L54)、[#L103](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L103)）；抽样测试均为真实行为断言（含物理帧/视口输入），无空断言、「提前退出也算通过」被显式拦截。 |
| **发布就绪度** | **B 基本可用** | 导出预设存在、启动日志有数据校验、官方预览包可运行（[25-第一章功能收口与准出计划.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/25-第一章功能收口与准出计划.md)）；但导出把 **61 个测试场景与开发期样例脚本**打进正式包（§3-P2-2），且版本号仍为 `0.1.0-scaffold`（§3-P3-1）。 |

**问题域 H 总评：B（基本可用）**——验证结论可信、核心路径覆盖充分、默认回归可一次跑通且可复现；扣分集中在**覆盖广度**（默认集不含全部场景）与**发布包内容治理**两处。

**实测结果表（E1）**

| 指标 | 值 |
|---|---|
| 命令 | `python3 tools/run_isolated_tests.py` |
| 默认回归场景总数 | 22 |
| 通过 | 22 |
| 失败 | 0 |
| 退出码 | `0`（两次独立运行一致） |
| `SCRIPT ERROR` | 0 |
| 与「21/21 通过」声明 | 口径一致、数量差 1（现默认集 22 项，较文档 25 所述 21 项多 1 项） |
| 与「已知 4 项失败」声明 | 一致（见 §4.1，4 项仍 FAIL，但**不在默认集内**） |

---

## 3. 问题清单

> 严重度依方法论 §4.2；证据等级依 §4.3。**未实测项已标「推断」。**

### P2-1｜默认「全量回归」只覆盖 61 个场景中的 22 个
- **位置**：[run_isolated_tests.py#L17](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L17)（`DEFAULT_TESTS`）
- **现象**：`tests/` 下共 **61** 个测试场景；无参运行的默认集仅 **22** 项。未被默认集覆盖的 **39** 项包括：`ActorCollisionTest`、`BattleFocusTest`、`CaveAutoBattleTest`、`CaveConnectivityTest`、`CaveLayoutTest`、`CharacterLookTest`、`FlatTerrainMeshTest`、`FloatingWindowInputTest`、`InventoryUpgradeBadgeTest`、`MapCanvasCacheTest`、`MapLoadingCacheTest`、`MapPerformanceTest`、`MapRenderBenchmark`、`MapTextureBatchTest`、`MonsterAnimationTest`、`MountShortcutTest`、`NpcAutoBattleTest`、`PanelChromeCoverageTest`、`PanelChromeLayoutTest`、`QuestInlineNavigationTest`、`QuestMainLeadTest`、`ShopBuyLayoutTest`、`SpawnerBudgetTest`、`WarehouseSlotVisualTest`、`CampLiveIntegrationTest`、`CampWhitebox`、`CampWhiteboxAcceptance`、`ChapterOneMapArt*`（3 个）、`ChapterTwo*`（5 个）及 4 个美术测试等。
- **影响**：性能/缓存/连通性/章节二/徽标/蒙皮等回归**不会**在标准命令中执行；`--committed-tree` 亦只覆盖默认 22 项。文档 25 的「21/21 项隔离自动化回归」因此**只代表默认子集**，读者易误读为「全部测试全绿」。
- **建议**：把「按改动范围补跑对应测试」显式写成发布前清单（AGENT.md §7 已有此要求），或在 CI 中增加「全场景回归」入口与结果留证。
- **证据等级**：E1（脚本清单实测）+ E2。

### P2-2｜导出包把测试场景与开发期样例脚本打入正式包
- **位置**：[export_presets.cfg#L9](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/export_presets.cfg#L9)（`export_filter="all_resources"`，`exclude_filter=""`）
- **现象**：实测对 `build/DegenerateAge-Chapter1-FunctionPreview.app/Contents/Resources/末法纪元：最后的守护者.pck` 做字符串扫描，含 **78** 条 `res://tests/...` 路径（如 `art_sample_test.gd`、`boss_review_test.gd`），以及开发期样例脚本 `res://scripts/art_sample.gd`、`chapter_one_art_sample.gd`、`cave_art_sample.gd`。
- **影响**：违反 AGENT.md §9「调试入口、测试存档、作弊开关与临时素材不能误入正式玩家流程」的**边界**。这些场景不在 `run/main_scene` 可达路径内（**推断**：玩家正常流程无法到达），因此**不是可触发的作弊入口**，但属于交付包内容治理缺陷，且增大包体。
- **建议**：导出预设加 `exclude_filter="tests/*,scripts/*_sample.gd,scripts/**/sample_*"`（或把 `tests/`、开发期样例移入带 `.gdignore` 的目录/构建期剔除），并在导出后复验 PCK 内不再含 `res://tests/` 与 `*sample*` 路径。
- **证据等级**：E1（PCK 实测扫描）+ E2。

### P2-3｜本地化缺 key 无自动化闸门，且注释与实测不符
- **位置**：[localization.gd#L6](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L6)（注释称「冒烟有专项断言」）、[localization.gd#L57](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L57)（`missing_keys()`）
- **现象**：`Localization` 已实现缺 key 回退 + `push_warning` + `missing_keys()` 去重记录；但全仓测试中**仅有** [npc_auto_battle_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/npc_auto_battle_test.gd) 引用了 `tr_key`（且用途是校验 NPC 对话暂停行为，非 key 覆盖率），**没有任何测试断言 `missing_keys()` 为空**。冒烟测试 [smoke_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd) 亦无该断言，与 `localization.gd` 注释所述「冒烟有专项断言」不符。
- **影响**：缺 key 只在运行期产生 `push_warning`；而运行器判据只认 `FAIL`/`SCRIPT ERROR`/非 0 退出码，**`push_warning` 不阻断**（[run_isolated_tests.py#L54](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L54)）。故 P0/P1 界面文案遗漏**无法在回归中被发现**，与「缺 key 可检测」的交付承诺存在缺口。
- **建议**：在冒烟测试补一条 `_expect(Localization.missing_keys().is_empty(), ...)`（需先跑一遍 UI 触达路径），或新增独立 `LocalizationCoverageTest` 扫描 `tr_key` 调用与 `localization.json` 覆盖差集。
- **证据等级**：E2（静态：注释与断言缺失）+ E1（运行器判据实测）。

### P3-1｜发布版本号仍为脚手架值
- **位置**：[project.godot#L19](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/project.godot#L19)（`config/version="0.1.0-scaffold"`）、[export_presets.cfg#L28](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/export_presets.cfg#L28)
- **现象**：应用 `config/version`、导出 `application/short_version`、`application/version` 三者均为 `0.1.0-scaffold`。
- **影响**：正式包无有效版本标识；影响可追溯性与玩家侧问题定位。发布流程尚未「固化版本」。
- **建议**：发布前提升为正式版本号（如 `0.1.0`），并检查 `application/icon`（当前为 `res://icon.svg` 占位，属美术范围）。
- **证据等级**：E2。

### 已知基线（非本次新问题，据方法论 §8 记录）
- **美术类 4 项持续失败**：`ArtSampleTest`、`ChapterOneArtTest`、`QualityFrameTest`、`IconIntegrationTest` 实测均 FAIL、整体退出码 `1`（详见 §4.1）。与「已知 4 项失败」声明一致，属美术素材范围，**不作为缺陷上报**。仅提示其**不在默认回归集内**，与「22/22 全绿」并存并不矛盾。

### 未发现（抽样确认，作正面结论）
- **无空断言/复述实现**：抽样 [boss_review_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/boss_review_test.gd)、[chapter_one_acceptance.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/chapter_one_acceptance.gd)、[skill_combat_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/skill_combat_test.gd)、[review_regression_test.gd](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/review_regression_test.gd) 等，断言均针对具体数值/状态/信号计数（如「首杀恰好一次」「耗蓝与冷却只结算一次」「非法主档应恢复有效备份」），非复述实现。
- **无「提前退出也算通过」**：运行器强制成功完成标记；且如 [smoke_test.gd#L4002](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/smoke_test.gd#L4002) 的早退前先 `_expect(bar != null, ...)` 记录失败，`ArtSampleTest` 用 `expect(false, "Sample wolves must exist")` 兜底（[art_sample_test.gd#L85](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/art_sample_test.gd#L85)）。
- **异步测试有完成标记**：如 [AutoExplorationSurvival](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/auto_exploration_survival.gd) 输出「[M4-9] 全部断言通过 ✅」、[SkillCombatTest](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tests/skill_combat_test.gd#L138) 输出「全部通过 ✅」后 `quit(0)`。

---

## 4. 证据与复核方法

### 4.1 实测结果（E1）

**① 默认全量回归**

```
python3 tools/run_isolated_tests.py
```

| 项 | 结果 |
|---|---|
| 总计 | 22 |
| 通过 | 22 |
| 失败 | 0 |
| 失败名单 | （无） |
| 退出码 | 0 |
| SCRIPT ERROR | 0 |

通过清单（按运行顺序）：`EquipmentAxesTest`、`SettingsTest`、`PotionAccessibilityTest`、`AudioCuesTest`、`FlowFeedbackTest`、`DeathChoiceTest`、`DeathDropTest`、`RandomTicketTest`、`TownScrollTest`、`HotbarConfigTest`、`HotbarUiTest`、`InputFeedbackTest`、`MenuFlowTest`、`SkillCombatTest`、`AutoControlAcceptance`、`AutoExplorationSurvival`、`BluePotionDropTest`、`CaveNavigationTest`、`ReviewRegressionTest`、`BossReviewTest`、`ChapterOneAcceptance`、`SmokeTest`（每项均带显式完成标记）。两次独立运行结果一致，可复现。

**② 已知 4 项美术失败复核**

```
python3 tools/run_isolated_tests.py ArtSampleTest ChapterOneArtTest QualityFrameTest IconIntegrationTest
```

| 测试 | 结果 | 关键失败项 |
|---|---|---|
| `ArtSampleTest` | FAIL | 无完成标记；`Guardian display scale keeps foot pivot`、`Unmade icons must preserve fallback`、`Dummy HP bar clears sprite head` |
| `ChapterOneArtTest` | FAIL | 无完成标记 |
| `QualityFrameTest` | FAIL | `slot artwork fills canvas`、`equipment icon trims transparent padding` |
| `IconIntegrationTest` | FAIL | `c2_road_* / c2_copper_* / c2_warm_*` 图标缺失或尺寸不符（章节二内容） |
| 合计退出码 | **1** | 与「已知 4 项失败」基线一致 |

> 说明：`ArtSampleTest`/`ChapterOneArtTest` 因断言失败会走 `push_error` 分支而不打印完成标记，运行器据此正确判 FAIL（**印证完成标记机制有效**，非静默通过）。

### 4.2 核心路径 × 测试覆盖矩阵（E2 对照）

| 核心路径 | 覆盖测试（示例入口） | 覆盖度 |
|---|---|---|
| 战斗伤害/暴击/闪避/受击保护 | SmokeTest（`_test_combat`/`_test_single_resolution`）、SkillCombatTest、ActorCollisionTest | A |
| 等级差/精英词缀 | SmokeTest（`_test_level_gap`/`_test_elite_affixes`） | A |
| 掉落/拾取/认领/未领战利品 | SmokeTest（`_test_loot`/`_test_pickup`/`_test_claim_fly`/`_test_unclaimed_loot`）、BluePotionDropTest、DeathDropTest | A |
| 背包/装备/仓库/快捷栏/坐骑 | SmokeTest（`_test_inventory*`/`_test_equipment`/`_test_warehouse*`/`_test_mount_core`）、ReviewRegressionTest、EquipmentAxesTest、InventoryUpgradeBadgeTest、HotbarUiTest、HotbarConfigTest、WarehouseSlotVisualTest | A |
| 商店/铁匠/升星/符文 | SmokeTest（`_test_shop`/`_test_blacksmith`/`_test_upgrade`/`_test_rune_upgrade`/`_test_trade_panel`）、ShopBuyLayoutTest | A |
| 任务机制 | SmokeTest（`_test_quest_chain`/`_test_quest_save`/`_test_quest_side`）、QuestMainLeadTest、QuestInlineNavigationTest、ChapterTwoQuestsTest | A |
| 地图切换/迷雾/刷新/Boss/门禁/寻路 | SmokeTest（`_test_map_travel`/`_test_map_reload`/`_test_walk_exit`/`_test_spawn_respawn_cross_map`/`_test_fog*`）、ChapterOneAcceptance、BossReviewTest、CaveLayoutTest、CaveNavigationTest、CaveConnectivityTest、ChapterTwoRoutesTest | A |
| 死亡与复活 | DeathChoiceTest、DeathDropTest、SmokeTest（`_test_death_settles_once`） | A |
| 技能与增益 | SkillCombatTest、BattleFocusTest | A |
| 存档存取/迁移/备份/原子性 | SmokeTest（`_test_save`）、SettingsTest（旧档迁移）、ReviewRegressionTest（`_test_save`） | A |
| 出行随机券/车票 | RandomTicketTest、TownScrollTest、ChapterOneAcceptance | A |
| 设置/缩放/显示适配 | SettingsTest、PotionAccessibilityTest、AudioCuesTest | A |
| **本地化（缺 key 检测）** | 仅 npc_auto_battle_test（行为用途） | **C（无 key 覆盖断言）** |
| **性能/长时稳定** | MapPerformanceTest、SpawnerBudgetTest、MapCanvasCacheTest、MapLoadingCacheTest、FlatTerrainMeshTest、MapTextureBatchTest、MapRenderBenchmark、ChapterOneMapArtSoakTest（600 物理帧）、AutoExplorationSurvival | **B（无通用 SoakTest/PerfProbe）** |

**无测试覆盖的关键路径**：① 本地化缺 key 的自动化断言（0 条）；② 通用长时间挂机/内存/信号连接稳定性——M5-1/M5-2 的 `SoakTest`/`PerfProbe` 在「批次③ 开发期工具清理」中被删除，现仅存第一章地图美术 soak（600 帧）与 `AutoExplorationSurvival`，无通用长时基准（E3 文档 + E2 实测目录均无）；③ 导出包内容治理无校验。

### 4.3 复核方法

1. 复跑默认回归：`python3 tools/run_isolated_tests.py`（须**非沙箱**，Godot 需写 `~/Library/Application Support/Godot`）；以退出码 + 完成标记 + 无 `SCRIPT ERROR` 判定。
2. 复跑已知失败：`python3 tools/run_isolated_tests.py ArtSampleTest ChapterOneArtTest QualityFrameTest IconIntegrationTest`。
3. 验证导出包内容：`strings build/<包名>.app/Contents/Resources/*.pck | grep -c "res://tests/"`。
4. 覆盖清单核对：`ls tests/*.tscn | wc -l`（应为 61）；对照 [run_isolated_tests.py#L17](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/tools/run_isolated_tests.py#L17) 的 `DEFAULT_TESTS`。
5. 同态/基准对照（若需）：历史基线见 [15-M5收口与MVP实施方案.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/15-M5收口与MVP实施方案.md) §9（M5-1/M5-2/M5-7 数据）。

> 分析使用的探针/日志（`/tmp/da_h_*.log`）未入库，审查仅新增本报告。

---

## 5. 落地优化方案

| # | 步骤 | 产出 | 验收 |
|---|---|---|---|
| L1 | **导出内容治理**：`export_presets.cfg` 增加 `exclude_filter`，剔除 `tests/`、`scripts/*_sample.gd`、`sample_*`；或将开发期样例移入带 `.gdignore` 的构建剔除目录 | 导出预设 | 导出后 PCK 内 `res://tests/` 计数为 0、无 `*sample*` 脚本 |
| L2 | **本地化闸门**：新增 `LocalizationCoverageTest`（或冒烟补断言）——遍历 `tr_key` 调用与 `localization.json` 做差集，断言 `missing_keys()` 为空 | 新测试或冒烟补断言 | 缺 key 时测试 FAIL 且列出 key |
| L3 | **回归入口分级**：明确「默认冒烟 22 项」与「全场景 61 项」两档，在 AGENT.md §7 / 工程文档 04 中列出全场景命令与预期结果；CI 增加全场景入口 | 文档 + CI | 全场景一次跑通并留证 |
| L4 | **长时稳定恢复**：重建通用 `SoakTest`（帧间隔/内存/节点数/信号连接，同态收敛判据），或在 `PerfProbe` 基础上留一份最小可复现基准 | 测试件 | 长时无单调增长 |
| L5 | **版本固化**：发布前提升 `config/version` 与导出 `version`，纳入发布清单 | `project.godot` / `export_presets.cfg` | 包内版本正确 |

> 以上均为建议，按方法论 §7「本审查默认不改动代码」执行；如需落地，另行确认后单独提交。

---

## 6. 与既有文档差异说明

1. **工作区快照与文档描述不一致**：任务与方法论 §8 称未提交改动含 `scripts/ui/shop_panel.gd`、`tests/ShopBuyLayoutTest.*`；实测这些已随 `b84d726` 提交，当前未提交改动的实为 `ground.gd`/`rest_zone_overlay.gd`/`camp_live_integration_test.gd`/`map_render_benchmark.gd`/`docs/测试反馈.md`（营地正式分层美术整合）。本报告以实测为准。
2. **「21/21 通过」口径**：文档 25 记为 21 项；实测默认集为 **22** 项并全通过（多 1 项）。两者**均指默认子集**，非全场景；文档未点明「全量」≠「全部 61 场景」，易造成「所有测试全绿」的误读。
3. **「浮 key 可检测」承诺**：[25-第一章功能收口与准出计划.md](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/docs/工程文档/25-第一章功能收口与准出计划.md) 节点 5 验收含「缺 key 可检测」，且 [localization.gd#L6](file:///Users/fungleo/Sites/GameProjects/DegenerateAge/autoload/localization.gd#L6) 注释称「冒烟有专项断言」；实测**无该断言**，为机制存在但**门禁缺失**（见 P2-3）。
4. **发布包内容**：文档 15「批次③ 开发期工具清理」声明清理测试件；实测**默认回归仍只跑 22 项**，且**导出包内含 61 个测试场景路径与样例脚本**——「清理」未覆盖导出内容治理（见 P2-2）。
5. **性能/稳定性回归**：文档 15 §9 依据 `SoakTest`/`PerfProbe` 给出 M5-1/M5-2 结论，这两个工具**已不在当前 `tests/`**；当前长时稳定的自动化承载弱化，历史基准需按 AGENT.md §7「引擎/地图/玩法显著变化后重新建立基准」重新评估。
6. **已知 4 项失败**：与基线声明一致（仍 FAIL），且**不在默认回归集内**；「22/22 全绿」与「4 项失败」并行成立，二者不矛盾但需明确口径。

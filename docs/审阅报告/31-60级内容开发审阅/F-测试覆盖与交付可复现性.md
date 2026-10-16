# F · 测试覆盖与交付可复现性

> 问题域：三章 15 场景与 `.tscn`、断言质量（形态/恒真）、默认回归集覆盖、假绿机制、提交纪律、构建脚本可复现、文档同步、复跑口径。
> 方法依据：[00-总体方法论.md](00-总体方法论.md) §4；判定标准见 [01-审阅计划.md](01-审阅计划.md) §2.F。
> 基线 `76bb84e3` → HEAD `6b5ec7cd`（`origin/master` 同步）。

---

## 1. 结论概览

| 检查项 | 结论 | 级别 |
|---|---|---|
| 15 场景 + `.tscn` 齐全、可独立跑通 | 齐全（已由子代理复跑） | — |
| 断言真实性 | 主体为真实业务断言；3 处恒真 + 若干形态断言 | **P3** |
| 15 场景是否在默认隔离回归集 | **全部不在** `DEFAULT_TESTS` | **P1** |
| 假绿机制（吞断言 / 无完成标记判通过） | 无漏洞 | — |
| 提交纪律（每批独立/无探针/.uid/夹带） | 大体达标；`.uid`/`__pycache__` 卫生遗留 | **P2** |
| 构建脚本可复现、临时脚本清除 | 达标 | — |
| 文档同步（30/32/33/34） | 看板正确；顶栏与基线残留过期 | **P1** |
| 复跑命令与通过判定写入章节文档 | **未写** | **P1** |

---

## 2. 场景清单与断言质量

**结论：场景齐全，断言质量良好，存在少量恒真/形态断言（P3）。**

- 15 场景与 `.tscn` 齐全：`tests/chapter_{four,five,six}_{routes,combat,quests,loot,map}_test.gd` 及对应 15 个 `.tscn`。
- **F-P3-1 · 恒真断言 3 处**：`tests/chapter_four_combat_test.gd:55`、`chapter_five_combat_test.gd:55`、`chapter_six_combat_test.gd:57` 断言的是测试文件内 `const` 数组长度（`NORMALS/ELITES/BOSSES.size()`，定义在同文件 P12-16），与游戏数据无关，**永不失败**。
  - 改进：改为从 `DataLoader` 读本章模板总数断言，或删除该行。落地：改三个 combat 场景；跑对应 Combat 场景。
- **F-P3-2 · 形态断言**（仅字段存在/数组非空，均作为真实断言的伴随守卫）：`chapter_*_combat_test.gd:60/62`、`chapter_*_loot_test.gd:39/106/115`（其中 `:106` 见 E-P3-1）、`chapter_*_map_test.gd:45/83/100`、`chapter_*_routes_test.gd:95`。
  - 改进：把 `loot_test.gd:106` 改为校验 `reward.item` 实指向本章型号（与 E-P3-1 合并）。
- 其余断言（档次、半径、预警几何结算、门禁、任务链、掉落等级、存档往返、结局幂等）均为真实业务断言，读的是真实数据/引擎，**未发现大面积形态化**。

---

## 3. 默认回归集覆盖（P1）

- **F-P1-1 · 15 场景全部不在默认隔离回归集**：`tools/run_isolated_tests.py:21-30` 的 `DEFAULT_TESTS`（实测 25 项）中唯一 Chapter 项为 `ChapterOneAcceptance`；裸跑 `run_isolated_tests.py` **不会触达**三章 15 场景。全量需 `--all`（`tools/run_isolated_tests.py:36-38`，扫 `tests/*.tscn` 排除夹具）。
- 佐证：全仓无 CI workflow（`.github/workflows` 不存在），无其它清单引用三章场景。
- **影响**：`docs/工程文档/30-…:88-90` 所称「5 场景全绿 + 默认回归 25 项全绿」**字面为真但易误读**——默认回归并不包含三章场景，读者会误以为回归集已覆盖本次交付。
- 改进建议：把每章**至少 1 个契约场景**（建议 Map 或 Routes）纳入 `DEFAULT_TESTS`；或将文档表述改为「三章 15 场景 + `--all` 全量」。
- 落地方式：改 `tools/run_isolated_tests.py:21-30`（须先确认总时长可接受）；随后裸跑确认含三章。

---

## 4. 假绿机制

**结论：无漏洞，已核对。**

- `tools/run_isolated_tests.py:119-122`：`completed = any(marker in output …)`，`ok = ok and completed`；未输出标记即追加 `FAIL: 测试未输出成功完成标记，不能视为通过`。
- `tools/run_isolated_tests.py:67`：`failed = returncode != 0 or "SCRIPT ERROR:" in output or "FAIL" in output`。
- 三章测试失败时 `get_tree().quit(1)`（如 `tests/chapter_four_map_test.gd:35`），`check()` 直接追加 failures，无包装吞并。
- **F-P3-3（轻微）**：判通过为「输出任意位置含子串 `PASS`」，理论上易被无关输出误命中；建议限定为行首或去误伤。

---

## 5. 提交纪律与产物卫生

- **每批独立提交 ✓**：`git log 76bb84e3..6b5ec7cd` 共 **24 提交**，每章 1 个 `feat`（数据）+ 5 个 `test`，命名规范。
- **临时探针未入库 ✓**：`find . -name '_tmp_*'` 空；`git log --all -- 'tools/_tmp*'` 空；`tools/_tmp_register_c*.py` 工作区与历史均无。
- **F-P2-1 · 卫生遗留**：`.gd.uid` 全仓跟踪 179 个（既定惯例；三章 test 的 `.uid` 目前未跟踪）；`tools/__pycache__/run_isolated_tests….pyc` 系更早提交 `b62f6036` 引入且**当前仍被跟踪**。本三章区段未新增 `__pycache__`。
  - 改进：统一 `.uid`/`__pycache__` 策略并写进 `.gitignore` 与文档；`git rm --cached` 既有 `.pyc`。
- **F-P3-4 · 共享测试文件**：`ea7aa985` 改 `tests/equipment_axes_test.gd`/`map_gate_test.gd`，`cbc79b91`/`6b5ec7cd` 各改 `equipment_axes_test.gd`——属配套扩断言（见 E 域 §6），非越界；建议在提交说明标注影响面。
- **未触碰协作者文件 ✓**：三章 test 提交不含 `docs/测试反馈.md`、`project.godot`、`addons/camp_map_editor/`。

---

## 6. 构建脚本与文档同步

- **构建脚本可复现 ✓**：`tools/build_chapter_{four,five,six}_layouts.py` 随 `c5c67057`/`a3ef9ef3`/`50e37975` 入库，源与产物齐备，幂等 `drift=0`（见 B 域 §6）。
- **F-P3-5**：三脚本 docstring 为英文（`tools/build_chapter_six_layouts.py:1`），与 `AGENT.md` §8「中文文件说明」不符。改进：补中文头注。
- **看板正确 ✓**：`docs/工程文档/30-…:85-91` 的 E0—E5 均标「已完成（2026-10-16）」；`docs/工程文档/32/33/34` 头部状态「已交付」；与代码（数据表 + 15 场景）一致。
- **F-P1-2 · 30 号文档顶栏与基线残留过期**：`docs/工程文档/30-…:3` 仍写「状态：待用户确认」；§3 基线（`:31-33`）仍称 `origin/master = 13085c1` 且「**尚无** c3—c6 任何地图」，而实际 `data/maps.json` 已含 25 张 c3—c6 图、HEAD 已是 `6b5ec7cd` —— 前后自相矛盾。
  - 改进：更新 `:3` 状态与 §3 基线为交付后快照。
- **F-P2-2 · 34 号文档场景名不符**：`docs/工程文档/34-…:57` 建议列含 `ChapterSixEndingTest`，但仓库无该场景；且未列实际存在的 `ChapterSixRoutesTest`。
  - 改进：将 `ChapterSixEndingTest` 改为 `ChapterSixRoutesTest`。
- **F-P3-6 · AGENT.md 计数过期**：`AGENT.md` §10 称默认集「当前 22 项」、全量「60 项」，实测 `DEFAULT_TESTS` 25 项、`tests/*.tscn` 90 个。改进：同步为 25 项 / 当前 tscn 数。

---

## 7. 可复现性（P1）

- **F-P1-3 · 复跑命令与通过判定未写入三章文档**：`grep -E 'run_isolated_tests|退出码|SCRIPT ERROR|全部通过|PASS|复跑|复现' docs/工程文档/32-33-34` **零命中**；命令仅见 `docs/工程文档/31-…:85`（默认 25 项 / `--all` / `--rendered`），32/33/34 以「同 [31 §5/§6]」转引；判定三条件（退出码 0 + 出现「全部通过/PASS」+ 无 `SCRIPT ERROR`）只在 `AGENT.md` §10。
  - 改进：在 `docs/工程文档/32|33|34` 的验收段明写命令与判定三条件，使他人可独立复跑。
- **旁证核实**：一次沙箱内测试运行中 `ArtSampleTest`/`ChapterOneArtTest`/`QualityFrameTest`/`IconIntegrationTest` 报 FAIL 且伴随 `TRAE Sandbox Error: hit restricted`，属**沙箱限制导致的假失败**；该四项均**不在** `DEFAULT_TESTS`，与三章交付无关。**须在非沙箱环境复跑**（Godot 需写 `~/Library/Application Support/Godot`）。

---

## 8. 复跑命令

```
python3 tools/run_isolated_tests.py                 # 默认 25 项（注意：不含三章场景）
python3 tools/run_isolated_tests.py --all           # 全量（含三章 15 场景）
python3 tools/run_isolated_tests.py ChapterFourRoutesTest ChapterFourCombatTest ChapterFourQuestsTest \
  ChapterFourLootTest ChapterFourMapTest ChapterFiveRoutesTest ChapterFiveCombatTest ChapterFiveQuestsTest \
  ChapterFiveLootTest ChapterFiveMapTest ChapterSixRoutesTest ChapterSixCombatTest ChapterSixQuestsTest \
  ChapterSixLootTest ChapterSixMapTest
# 判定：退出码 0 + 输出含「全部通过 ✅」/PASS + 无 SCRIPT ERROR（须非沙箱环境）
```

---

## 9. 残余未复核项

- 15 场景「可独立跑通」依子代理复跑结论，本域未在本机重跑（沙箱限制）；建议在非沙箱环境执行 §8 的定向复跑做最终确认。

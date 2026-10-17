# Boss 墓碑跨地图消失 —— 排查与修复方案

> 日期：2026-10-17　｜　触发：实测 Lv60 地图 `c6_map05` 击杀 Boss 后跨图返回，墓碑不见。
> 结论：**bug 真实存在**。全库 17 个墓碑点中 **11 个进图即不可见**（16 个 fixed 点的 69%），第二～六章除个别首图外几乎全线命中。
> 状态：**仅出方案，未改代码**，等确认后实施（无 schema 变更）。

---

## 1. 结论摘要

| 项 | 结论 |
|---|---|
| 是否真实存在 | ✅ 是，探针 100% 复现（失败 2 项，见 §3） |
| 触发条件 | 墓碑点配了 `cell`/`cells`（`fixed = true`）**且**装配时玩家与该点距离 > `ACTIVE_DISTANCE`（760px） |
| 用户感知 | 当场击杀有墓碑 → 跨图回来没有 → 走到 Boss 面前**依然没有** → 时间到 Boss 凭空出现 |
| 根因 | 两处叠加：① `_spawn()` 在「等待期落墓碑」之前就被 `fixed` 距离检查 `return` 掉；② `_process()` 的等待分支只更新**已存在**的墓碑，从不补建 |
| 影响面 | 17 个墓碑点中 16 个是 fixed；其中 **11 个** 从任一入口 / 车夫落点进来都 > 760px（占比 **69%**，章节覆盖 ch02–ch06） |
| 修复量 | `spawner.gd` 两处，约 12 行（顺序调整 + 一处补建），**不动数据、不动存档、不动 UI** |

---

## 2. 复现路径

### 2.1 手工复现（用户现象，最短路径）

1. 车夫直达 `c6_map05`（屏障心台，Lv60），走到 `(193,63)` 击杀 `c6_boss03`（60 级 Boss）。
2. 此时墓碑正常显示倒计时（600s）—— 因为它由 `_on_monster_died()` 直接放置。
3. 从 `c6_map05_exit01 → c6_map03` 离开，再返回 `c6_map05`（入口 `(9,63)`）。
4. **墓碑消失**；走到 Boss 点位站定也没有；等到倒计时结束，Boss 直接凭空出现。

### 2.2 探针复现（无头，可脚本化）

临时探针 `tests/_probe_tombstone.gd`（**未入库，用完即删**）用真实数据 `c6_map05` 跑四段：

| 段 | 场景 | 期望 | 实测 |
|---|---|---|---|
| ① | 玩家站 Boss 旁装配 → 击杀 | 当场有墓碑 + 登记刷新状态 | ✅ PASS |
| ② | 切图销毁 → 时间 +30s → 玩家在入口 `(9,63)` 重新装配 | 墓碑重建（剩 570s） | 🔴 **FAIL：墓碑 = false** |
| ③ | 玩家瞬移到 Boss 旁，跑 30 帧 `_process` | 墓碑补建 | 🔴 **FAIL：墓碑 = false** |
| ④ | 对照：玩家站 Boss 旁直接装配 | 墓碑重建 | ✅ PASS |

---

## 3. 实测证据（探针原始输出）

```text
[probe] boss_pos=(4160.0, -4096.0) entry_pos=(-1728.0, -1152.0) 距离=6583.0 ACTIVE_DISTANCE=760.0
[probe] PASS ① 装配后应生成 Boss
[probe] PASS ① 击杀瞬间应出现墓碑
[probe] PASS ① 应登记刷新状态
[probe] PASS ② 未到点不应重生
[probe] ② 跨图回来：墓碑=false  fixed=true  remaining=570.0
[probe] FAIL ② 跨图回来墓碑应重建 ★失败即复现 bug
[probe] ③ 走近 30 帧后：墓碑=false
[probe] FAIL ③ 走近后墓碑应补建 ★失败即 _process 不补建
[probe] ④ 近处装配：墓碑=true
[probe] PASS ④ 近处装配应重建墓碑
[probe] 结论：失败 2 项
```

三条硬事实：

1. 刷新状态**没有丢**（`remaining = 570.0`，`fixed = true`）—— 数据层是好的，纯表现层漏建。
2. ② 与 ④ 的唯一差别是**装配时玩家离 Boss 多远**，直接锁定距离检查为触发条件。
3. ③ 证明**走近也救不回来**：`_process` 在等待期不做补建，所以整段 300–600s 的等待里墓碑等于不存在。

---

## 4. 根因

### 4.1 代码现状

`scripts/world/spawner.gd:158`（`_spawn`，生成单点）：

```gdscript
func _spawn(point: Dictionary, active: Variant = null) -> bool:
	var unlock := String(point.get("requires_unlock", ""))
	if not unlock.is_empty() and not bool(GameState.unlocks.get(unlock, false)):
		return false
	if bool(point.get("fixed", false)) and _player != null \
			and (point.position as Vector2).distance_to(_player.global_position) > ACTIVE_DISTANCE:
		return false                                    # ← ① 在这里就走了，墓碑没机会放
	var counts: Dictionary = active if active is Dictionary else _active_counts()
	...
	if cap != UNLIMITED_CAP and int(counts.get(kind, 0)) >= cap:
		return false                                    # ← ② 预算满同样提前走
	var remaining := _remaining(point)
	if remaining > 0.0:
		if bool(point.get("tombstone", false)):
			_place_tombstone(point, remaining)          # ← ③ 只有走到这里才会放墓碑
		point.entry = null
		return false
	... 生成怪物 ...
```

`scripts/world/spawner.gd:133`（`_process`，每帧）：

```gdscript
	var remaining := _remaining(p)
	if remaining > 0.0:
		if is_instance_valid(p.marker):
			p.marker.set_remaining(remaining)           # ← 只更新，不创建
		continue
```

### 4.2 时序（跨图返回）

```text
切图返回 c6_map05
  → 新 MonsterSpawner 装配（player 在入口 9,63）
  → spawn_from_specs → _spawn(boss点)
       fixed=true 且 距离 6583 > 760  ⇒ return false   （墓碑未放，marker = null）
  → 之后每帧 _process：entry 为 null → remaining=570 > 0
       is_instance_valid(marker) 为 false ⇒ 直接 continue（永不补建）
  → 玩家一路走到 Boss 面前：_process 仍走同一分支，依旧 continue
  ⇒ 整段等待期无墓碑，倒计时到了 Boss 直接生成
```

### 4.3 为什么这是「设计意图被实现顺序打翻」

- 距离检查的本意是**推迟生成怪物**（省性能、避免玩家一进图就被远程怪围），不是「推迟墓碑」。
- 墓碑是**刷新状态的可视化**：状态存在 `GameState.spawn_respawn` 里跨图跨档保留（工程 14 §3.1），本来就该与「要不要现在生成怪」解耦。
- 现有代码把两者写在同一个函数里且顺序是「距离 → 预算 → 墓碑」，于是**生成前置条件顺带成了墓碑展示的前置条件**。

### 4.4 为什么既有 101 个测试没抓到

唯一覆盖跨图墓碑的用例是 `tests/smoke_test.gd:3499 _test_spawn_respawn_cross_map()`，它用的是 `corruption_source` 的 `boss_corrupted_beast` —— **该点是全库唯一没有 `cell`/`cells` 的墓碑点**（无 `fixed`），距离检查整个跳过，所以「墓碑应存在」一路绿灯。

> 换句话说：测试选中的恰好是**唯一免疫**的那个点。

---

## 5. 影响面（普遍度）

统计口径：遍历 `data/maps/ch*/*/map.json`，取所有 `tombstone: true` 的点；`fixed` 判定 = 配了 `cell` 或 `cells`；「最近落点」= 该图所有 `entrances` + `carterArrival` 中距该点最近者（**乐观口径**，实际进图入口可能更远，故受影响只会更多不会更少）。

- 墓碑点总数 **17**
- 非 fixed（免疫）**1** 个：`corruption_source / boss_corrupted_beast`（第一章）
- fixed **16** 个，其中距最近落点 > 760px 者 **11** 个 ⇒ **69% 的墓碑点进图即不可见**

| 地图 | Boss | cell | 最近落点距 | 落点 | 刷新 | 判定 |
|---|---|---|---|---|---|---|
| corruption_source | boss_corrupted_beast | 随机 | — | — | 300s | 免疫（非 fixed） |
| c2_ember_furnace | c2_boss_slag_devourer | (137,46) | 1368 | entry | 300s | 🔴 受影响 |
| c2_old_well | c2_boss_iron_foreman | (192,64) | 809 | entry | 300s | 🔴 受影响 |
| c2_well_core | c2_boss_hundred_arm_extractor | (177,58) | 5910 | carter | 600s | 🔴 受影响 |
| c3_map02 | c3_boss01 | (179,59) | **751** | entry | 600s | ⚠️ 临界通过 |
| c3_map04 | c3_boss02 | (151,50) | 4937 | carter | 600s | 🔴 受影响 |
| c3_map05 | c3_boss03 | (179,59) | 5903 | carter | 600s | 🔴 受影响 |
| c4_map02 | c4_boss01 | (165,54) | 680 | entry | 600s | ✅ 可见 |
| c4_map04 | c4_boss02 | (151,50) | 4937 | carter | 600s | 🔴 受影响 |
| c4_map05 | c4_boss03 | (193,63) | 6368 | carter | 600s | 🔴 受影响 |
| c5_map02 | c5_boss01 | (165,54) | 680 | entry | 600s | ✅ 可见 |
| c5_map04 | c5_boss02 | (151,50) | 4937 | carter | 600s | 🔴 受影响 |
| c5_map05 | c5_boss03 | (179,59) | **751** | entry | 600s | ⚠️ 临界通过 |
| c5_map06 | c5_boss04 | (193,63) | 6368 | carter | 600s | 🔴 受影响 |
| c6_map02 | c6_boss01 | (165,54) | 680 | entry | 600s | ✅ 可见 |
| c6_map04 | c6_boss02 | (151,50) | 4937 | carter | 600s | 🔴 受影响 |
| c6_map05 | c6_boss03 | (193,63) | 6368 | carter | 600s | 🔴 受影响（用户命中） |

章节分布：**ch02 3/3、ch03 2/3、ch04 2/3、ch05 2/4、ch06 2/3**，仅 ch01 免疫。

两点补充：

- **`c3_map02` 与 `c5_map05` 是 751px，距阈值只差 9px。** 这类「刚好通过」不是好事 —— 只要入口格微调或改 `ACTIVE_DISTANCE`，它们立刻翻转成 bug；也就是说这个判定本质上是**隐性配置耦合**，靠数值侥幸不是靠逻辑正确。
- 目前 `spawnPoints`（普通 / 精英点）没有配 `tombstone`，所以暂时只有 Boss 受影响。但一旦将来给某只精英点开墓碑，同一缺陷会立刻复制过去。

---

## 6. 修复方案

### 6.1 原则

> **墓碑的可见性 = 「该点有未到点的刷新状态」**，与「现在要不要生成怪」（距离 / 预算）**完全解耦**。

### 6.2 S1（主修）`_spawn()`：把等待期判断提到距离与预算之前

```gdscript
func _spawn(point: Dictionary, active: Variant = null) -> bool:
	var unlock := String(point.get("requires_unlock", ""))
	if not unlock.is_empty() and not bool(GameState.unlocks.get(unlock, false)):
		return false
	# M4-10 修复：等待期先落墓碑 —— 墓碑是刷新状态的可视化，
	# 不能被「玩家当前距离 / 本图生成预算」这类生成前置条件挡住
	# （否则 fixed 点在远程装配时永不显示墓碑：跨图回来、远程进图都看不见）。
	var remaining := _remaining(point)
	if remaining > 0.0:
		if bool(point.get("tombstone", false)):
			_place_tombstone(point, remaining)
		point.entry = null
		return false
	if bool(point.get("fixed", false)) and _player != null \
			and (point.position as Vector2).distance_to(_player.global_position) > ACTIVE_DISTANCE:
		return false
	var counts: Dictionary = active if active is Dictionary else _active_counts()
	var kind := String(point.get("kind", "normal"))
	var cap := _cap_for(kind)
	if cap != UNLIMITED_CAP and int(counts.get(kind, 0)) >= cap:
		return false
	var m: Monster = MONSTER_SCENE.instantiate()
	...
```

改动量：**仅位置移动**（原 172–178 行的 `remaining` 段落整体上移到 164 行之前），生成段逻辑零改动。

保留 `requires_unlock` 在最前 —— 未解锁的点不该显示墓碑（该点根本不该存在死亡记录；保持原语义）。

### 6.3 S2（补强）`_process()`：等待期缺墓碑时补建

```gdscript
		var remaining := _remaining(p)
		if remaining > 0.0:
			# 修复：等待期墓碑可能因装配时序（未解锁 → 解锁、预算、旧档）缺失，
			# 这里补建；已存在时 _place_tombstone 内部只刷新倒计时，无额外开销。
			if bool(p.get("tombstone", false)):
				_place_tombstone(p, remaining)
			elif is_instance_valid(p.marker):
				p.marker.set_remaining(remaining)
			continue
```

为什么 S1 之外还要 S2：

- **同会话内解锁**：装配时 `requires_unlock` 未满足 → 不建墓碑；玩家在本图开机关解锁后，`_process` 走不到 `_spawn`（remaining 仍 > 0），S1 救不到，只有 S2 能补。
- **旧档 / 异常**：读入的 `readyAt` 合法但 `pos` 非法时状态仍在，墓碑应照常显示。
- S1 保证「进图第一帧就对」，S2 保证「任何时刻发现缺失都能自愈」。

### 6.4 不采用的方案

| 方案 | 为何不选 |
|---|---|
| 把 `ACTIVE_DISTANCE` 调大 / 去掉距离检查 | 会让远处 Boss 一进图就实体存在（AI 跑动、性能、玩家被远程怪围），直接违背 E1 生成预算的初衷 |
| 墓碑改为常驻场景节点，进图统一重建 | 等于自己再实现一遍 `_place_tombstone`，重复状态源，且要处理地图切换清理；收益为零 |
| 给所有受影响 Boss 加「入口即生成」 | 治标：只对当前 11 个点生效，改地图/改阈值立刻复发，且换来性能代价 |

---

## 7. 验证计划

### 7.1 新增回归用例（`tests/smoke_test.gd`）

`_test_tombstone_fixed_cross_map()`，用真实数据 `c6_map05`：

1. 构造 `player` 的 `position = Iso.grid_to_world(Vector2i(9,63))`（入口）。
2. 先 `mark_spawn_dead("c6_map05", "c6_boss03", 0, 600.0, boss_pos)` 造出「刚被杀」状态。
3. 装配 `spawner.spawn_from_specs([boss_spec], "c6_map05")`。
4. 断言：墓碑存在（**修复前此处必失败**）。
5. 断言：墓碑 `position ≈ boss_pos`（死亡位置，不是入口附近）。
6. 玩家瞬移到 `boss_pos`，跑 10 帧 → 断言墓碑仍在、`remaining` 递减。
7. `world_time += 601` 后跑一帧 → 断言墓碑消失、Boss 已生成、`spawn_respawn` 已清。

另补一条 `_test_tombstone_missing_marker_heals()` 直接覆盖 S2：手动删掉 marker 后跑一帧 → 断言重建。

### 7.2 负向验证（证明断言有牙）

| 回退 | 期望的精确失败 |
|---|---|
| 注释 S2 的 `_place_tombstone` 补建 → 还原 `_spawn` 顺序 | 「装配后墓碑应存在」失败，复现探针 ② |
| 只回退 S1、保留 S2 | 首帧断言可能通过（S2 兜住），故**必须**同时用「跑 0 帧即断言」的用例锁定 S1，避免 S2 掩盖 S1 回归 |
| `ACTIVE_DISTANCE` 改 99999 | 用例仍应通过（墓碑与距离无关）——反向证明解耦 |

### 7.3 四层回归

```
--headless --path . --import
res://tests/SmokeTest.tscn        （「全部通过 ✅」）
res://tests/SettingsTest.tscn
--quit                            （「配置校验通过 ✅」+ 0 SCRIPT ERROR）
python3 tools/run_isolated_tests.py   （默认 32 项）
```

另需比 `md5(slot_1.json)` 前后一致（测试只写槽 3）。

---

## 8. 风险与待办

| 编号 | 风险 | 处置 |
|---|---|---|
| **R1** | `_process` 每帧对等待期点调 `_place_tombstone`，是否变慢？ | 否。marker 有效时该函数**首行就 return**，只做 `set_remaining`，与现状等价；位置计算仅在首次执行 |
| **R2** | 顺序调整会不会让「到点重生」失效？ | 不会。`remaining <= 0` 时跳过新分支，后续生成路径逐行不变 |
| **R3** | 未解锁点会不会误显墓碑？ | 不会。`requires_unlock` 仍是第一道闸 |
| **R4** | 预算已满时现在会显示墓碑，是否算行为变更？ | 是，且是**修正**：该点的死亡事实与其它点是否占满预算无关。不增加任何怪物数量 |
| **R5** | `_place_tombstone` 依赖 `_ground.clamp_to_map`，`_ground` 为空会崩？ | 已有 null 分支（`if _ground != null else recorded`），且装配时 `setup()` 已注入 ground |
| **R6** | `apply_spawn_respawn` 把非法 `pos` 解成 `Vector2.ZERO`，墓碑会落在原点 | 既有问题，**不在本次范围**；如要修，改为 `null` 语义并让 `_tombstone_position` 回退到配置 cell |
| **R7** | `c3_map02` / `c5_map05` 的 751px 临界值 | 修复后不再依赖距离阈值，临界问题自然消失；无需改数据 |

### 待办

- [ ] R-a 实施 S1 + S2（`scripts/world/spawner.gd`，约 12 行）
- [ ] R-b 新增 §7.1 两条用例，并跑 §7.2 三组负向
- [ ] R-c 四层回归 + `slot_1.json` md5 比对
- [ ] R-d 回填工程 14（§3.1 ④ 刷新状态）与 08 交接文档 §5.25
- [ ] R-e（可选，单独排期）R6：非法 `pos` 的墓碑定位健壮性

---

## 9. 复核方法

```bash
# 复现（修复前应看到"跨图回来墓碑应重建"FAIL）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  res://tests/_ProbeTombstone.tscn --quit-after 400

# 普遍度重算（改地图数据后重新评估）
python3 - <<'PY'
import json,glob,math
# 见 §5 口径：tombstone 点 + fixed + 距最近入口/车夫落点 > 760
PY
```

> 探针仅用于本次排查，**不随代码入库**（`AGENT.md` §10：临时探针用完即删）。

---

## 10. 一句话总结

墓碑功能在**当前 11 张 Boss 图上等于不存在**（进图即无、走近也无），只因唯一那条跨图测试恰好选到了全库唯一免疫的 Boss 点。修法不是调距离，而是把「墓碑展示」从「怪物生成」的前置条件里拆出来：`_spawn` 把等待期判断上移，`_process` 补一个幂等补建。

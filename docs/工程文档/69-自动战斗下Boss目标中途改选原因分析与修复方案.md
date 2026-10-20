# 69 · 自动战斗下「打一个 Boss 没打死又改打别的 Boss」原因分析与修复方案

> 现象提出：自动战斗开启、自动打 Boss 时，角色打到一半丢下当前 Boss，绕出去打另一只 Boss。
> 结论一句话：**这不是随机行为，也不是数值改动引起的——是「卡住判定用了直线距离」+「重选目标缺少粘性」两条逻辑共同造成的目标中途改选，另有三个放大器让观感更明显。**
> 本文只做分析与方案，未改动任何代码。

---

## 1. 现象的可观测判据

先给出「如何确认是哪一条链路」的现场判据，后面的根因排序都以它为准：

| 判据 | 指向 |
| --- | --- |
| 改选瞬间屏幕弹出提示「**目标不可达，已改选**」 | 主因 A/B（黑名单链路，见 §3.1、§3.2） |
| 改选前后**没有任何提示**，角色只是走去打隔壁那只 | 主因 B（重选策略）或放大器 C（怪被静默回收） |
| 目标血条**从残血跳回满血**、且它走回原来的席位 | 放大器 D（脱战归位回满） |
| 角色中途**先去捡地上的东西**再走 | 放大器 E（拾取抢占） |

提示文案定义在 `data/localization.json:504`（`ui.auto.unreachable` = 「目标不可达，已改选」），由 `scripts/systems/auto_battle.gd` 的 `_blacklist_target()` 发出——只要走了黑名单链路，**必定**有这条提示。

---

## 2. 目标是怎么被「换掉」的：代码事实

自动战斗只在一种情况下重新选目标，即 `_target == null`：

- `scripts/systems/auto_battle.gd:269-286`：仅当 `_target == null` 时按 `SEARCH_INTERVAL(0.35s)` 节流调用 `_find_target()`。
- `scripts/systems/auto_battle.gd:403-433`（`_find_target`）：在**当前屏幕内**（`game.gd:325-337` 的 `visible_enemies()` 要求目标在视口矩形内）的敌人中取**距离最近**者，同距离取血量更低者；排除黑名单目标、排除不可达目标。
- 因此：**不存在「更近的怪把目标抢走」的机制**，也不存在周期性重评；只有目标被丢弃后才会重选一次。

目标被丢弃的全部出口在 `auto_battle.gd:257-262`：

```
not is_instance_valid(_target)  → 实例被释放（见 §3.3 放大器 C）
_target.get("is_dead") == true  → 死了（= 正常击杀，非本次现象）
_is_blacklisted(_target)        → 被拉黑（见 §3.1 主因 A）
```

另有 `auto_battle.gd:181-186`：`_player.is_sitting` 时也会清空目标 + 清空 loot——但打坐只有手动按键（`game.gd:387`）能触发，不是本次现象的来源。

**关键推论**：既然「最近的那只会抢走目标」这条路不存在，那么用户看到的「绕出去打另一只」必然是 **A 或 C** 造成的——先丢掉当前目标，再就近选到隔壁那只。

---

## 3. 根因排序（主因两条 + 放大器三条）

### 3.1 主因 A：卡住判定用「直线距离」而不是「沿路径的推进量」

`scripts/systems/auto_battle.gd:580-604`（`_tick_stuck`）：

```
const STUCK_INTERVAL := 0.3      # 每 0.3 秒检查一次
const STUCK_PROGRESS_EPS := 6.0  # 单次检查要求直线距离至少下降 6px
const STUCK_LIMIT := 3           # 连续 3 次不足 → 拉黑
const BLACKLIST_TIME := 8.0      # 拉黑 8 秒
```

即：**只要 0.9 秒内「与目标的直线距离」没有累计下降 6px，当前目标就被拉黑 8 秒**（`_blacklist_target`，`:607-618`），随后 1 秒 BLOCKED 再重选。

而 `_tick_stuck` 只在 `PATH_TO_TARGET` 状态调用（`auto_battle.gd:293-304`），传入的是 `_player.global_position.distance_to(target.global_position)`（`:289`）——**是两点直线距离，不是路径推进量**。这带来两类系统性误判：

1. **绕行时直线距离不下降**。移动方向来自 `cave_nav.direction()`，返回的是**路径第一段航点的方向**（`scripts/world/cave_navigator.gd:16-41`，由 `ground.route()` 生成航点）。当路径需要绕过一段悬崖/障碍时，角色在头 0.9 秒里可能是在**侧向或反向**走（先绕到障碍的另一侧），与目标的直线距离几乎不变 → 三连击 → 拉黑。
   量化：`c7_arena`（无尽回廊）的可行走率只有 **55.1%**（160×90 中 6464 格是墙，布局 `data/layouts/c7_arena.json`），是明显的迷宫地形；`c7_boss_field` 为 92.2%（开阔）。所以这条在**无尽回廊**会高频出现。
2. **被击退 / 倒地期间距离不降反增**。Boss 技能命中会触发击退与倒地（`monster.gd:496` 的 `_apply_skill_knockback`，常量 `SKILL_KNOCKBACK_DISTANCE 48px` / `SKILL_KNOCKDOWN_DURATION 0.5s`，`monster.gd:35-37`）。被推开的 0.3 秒窗口内距离是**变大**的，判定为「不推进」，连续两三次（多段招式）即可凑满 3 次。

速度对比可排除「单纯追不上」这一解释：玩家 `movementSpeed 4.0` 格 = **256px/s**（`player.gd:45`、`:258`），Boss `moveSpeed 1.6–1.8` 格 = **102–115px/s**——正对正追时距离一定快速下降，不会触发判定。**触发必然是路径非直线，或角色处于被推开/硬直状态。**

### 3.2 主因 B：重选策略没有「目标粘性」，且改选成本极低

拉黑/丢弃后 `_find_target()` 只看「谁最近」，完全不知道「上一只打到什么程度」。而三张图的席位密度让「就近改选」几乎必然落到**隔壁的 Boss**：

| 地图 | 席位数 | 最近两席世界距离 | 玩家 760px 内同时在世的席位数（中位） |
| --- | --- | --- | --- |
| `c7_boss_field` 百首禁域 | 100 | **393.5px** | **7** |
| `c7_arena` 无尽回廊 | 20 | 544.2px | 2 |

（数据由 `data/maps/ch07/*/map.json` 的 `bossSpawns[].cell` 经 `Iso` 的 2:1 投影换算得到；生成闸门是 `spawner.gd:16` 的 `ACTIVE_DISTANCE 760px`，所有 Boss 席位都是 `fixed` 格。）

也就是说：**百首禁域里角色周围常年有约 7 只 Boss 在世**，最近的另一只离 393px（约 1.4 个 2:1 菱形格宽），并且就在视口内（视口半径约 600+px）。任何一次「丢目标」都会立刻变成「走去打隔壁那只」，而且 8 秒黑名单期内角色至少能在别处打半场——回到原目标时，原目标可能已经被 §3.3 静默回收/§3.4 回满血。

### 3.3 放大器 C：`fixed` 席位在玩家走远后被静默回收，回来是满血

`scripts/world/spawner.gd:150-155`：

```
if bool(p.get("fixed", false)) and _player != null \
        and (p.entry as Node2D).global_position.distance_to(_player.global_position) > RETIRE_DISTANCE:
    p.entry.queue_free()
    p.entry = null
```

- `RETIRE_DISTANCE = 1100px`（`spawner.gd:17`）；三张循环图的席位**全部是 fixed 格**。
- 回收时**不写刷新状态**（没有调 `mark_spawn_dead`）→ 该点没有倒计时，玩家再次进入 760px 时立刻在**固定格**重新生成，且 HP 是满的（HP 不落档）。
- 触发条件虽然是「玩家离怪 > 1100px」，但它是被 A/B 造成的位移「顺带」触发的：角色被拉黑/被拾取带走几百 px 后，跨过 1100px 线，正在打的那只就被回收了 → 目标实例被释放 → `auto_battle.gd:258` 判定 `not is_instance_valid` → 再次重选。**这是「没打死却满血」的第二来源**。

### 3.4 放大器 D：Boss 脱战归位会把血回满

- 默认脱战半径 `LEASH_RANGE = 420px`（`monster.gd:13`、`:113`）；只有配置了 `bossSkill.shape` 的 Boss 才在 `_setup_boss_action()`（`monster.gd:228-236`）里放宽到 `BOSS_ARENA_TILES 18` 格 = **1152px**。
- 经 `data/monsters/ch0*/monsters.json` 核对，百首禁域圣用的 10 个型号里有 **4 只没有 `bossSkill.shape`**：`c2_boss_iron_foreman`、`c2_boss_slag_devourer`、`c2_boss_hundred_arm_extractor`、`boss_corrupted_beast` → 它们的脱战半径只有 **420px**，比同排席距 644px 还小、仅略大于邻排席距 393px。这类 Boss 稍微被带偏一点就会往回走，而 4 只中有 3 只是 `c2_boss_*`（走 `_update_chapter_boss`）。
- 更关键的是 `_update_boss_action()`（`monster.gd:455-469`）的脱战判据 `away = player == null or 离席距离 > leash_range`，其中 `_get_player()`（`monster.gd:724-732`）在**玩家死亡或进入休息区**时返回 `null` → 立即进入 RETURN；5 秒后 `_reset_boss_to_arena()`（`:499-510`）执行 **位置回席位 + `hp = max_hp`**。
- 观感即「打了一半，血跳回满，它走回原地」。

### 3.5 放大器 E：自动拾取在战斗中抢占优先级

`scripts/systems/auto_battle.gd:264-267`：

```
if GameState.auto_pickup_on and _tick_loot():
    return
```

拾取分支排在目标逻辑**之前**，且只看「6 格内有没有可拾取的地面物」（`_find_loot`，`:436-454`）。战斗中一旦附近有掉落，角色立刻放手走过去捡（`_target` 不清空，但角色不再攻击，且会离开原目标数百 px）——正好把 A/B/C 的触发概率放大。百首禁域的掉落容量上限是 `unclaimedLootCap 2400`，地面物长期堆积，这条极易命中。

---

## 4. 明确排除的项（避免误改）

- **不是数值改动引起的**：本次 Boss 血量 ×2、经验下调、不破防下限改动都不参与目标选择与移动决策；只影响「一场要打多久」，即**拉长了每场战斗，从而让上面的误判有更多机会发生**（这解释了「也是最近才明显」）。
- **不是「攻击距离不够」**：`melee_range_px()` = `basic_slash.range 1.0` 格 = 64px（`player.gd:494-495`，`data/skills.json`），自动战斗的停步阈值是 64−8 = 56px（`STOP_GAP`），而怪物碰撞半径固定 13px、玩家 12px（`scenes/entities/Monster.tscn:6`、`Player.tscn:7`，且玩家 `collision_mask=1` 与怪不同层，**不会互相卡住**）——不存在「走不进攻击距离」的问题。
- **不是「怪被别的怪挡住」**：怪物 `collision_layer=4`、`collision_mask=1`，彼此不碰撞。
- **不是「打坐中断」**：打坐只有手动按键触发。
- **不是「面板打开」**：普通面板不中断自动战斗（与既有规则一致）；只有 `get_tree().paused` 的模态面板会让自动战斗进入 RECOVER。

---

## 5. 修复方案（待拍板，未实施）

按「最小改动、先治主因」排序。P1/P2 是治本项，P3–P6 是收敛项。

| 编号 | 改动点 | 具体做法 | 影响面 |
| --- | --- | --- | --- |
| **P1** | `auto_battle.gd::_tick_stuck` 判定口径 | 把「直线距离」改为**路径推进量 + 角色真实位移**：只有「角色本 0.3 秒**实际位移** < 4px」或「`cave_nav.direction()` 连续返回 `Vector2.ZERO`」才计一次；并把 `STUCK_LIMIT` 由 3 提到 5（约 1.5–1.8 秒） | 只影响「不可达判定」的灵敏度，不碰战斗结算 |
| **P2** | `auto_battle.gd::_find_target` 目标粘性 | ① 原目标仍有效、仍 `_route_reachable`、未被拉黑时**优先返回原目标**；② `BLACKLIST_TIME` 8s → **3s**，且黑名单只对「路径为空」这类**硬不可达**生效；③ 只有「原目标确实不可达/已死」才改选，避免被「更近的隔壁」抢走 | 直接影响改选频率；需回归 `AutoBattle` 相关用例 |
| **P3** | `_direction_to(...) == ZERO` 单帧拉黑（`auto_battle.gd:295-297`） | 改为**连续 0.5 秒为 0** 才判定不可达，避免一次寻路抖动就丢目标 | 低风险，纯放宽 |
| **P4** | `spawner.gd:150-155` 的 fixed 点退役 | 退役判据排除「**当前正被玩家锁定 / 处于 CHASE·ATTACK**」的怪；或退役时给该点写一个短刷新计时，避免「走远→回来满血」的错觉 | 影响刷新与跨图一致性，需跑 `EndgameCycleMapTest` / 刷新相关用例 |
| **P5** | `auto_battle.gd:264-267` 拾取优先级 | 只在「无目标 / 目标已死 / 目标被拉黑」时才走拾取分支；战斗中不因掉落停手 | 影响挂机拾取手感，需实机确认 |
| **P6** | 百首禁域 4 只短脱战半径型号 | 给 4 只 `c2_boss_*` / `boss_corrupted_beast` 在**循环图席位**上补统一的脱战半径（席位级字段 `leashTiles`，缺省沿用现状），使 Boss 图 100 席行为一致 | 涉及 `monster.gd` + 席位规格 + 数据落盘 |

不建议的做法（会引入新问题）：① 直接把 `BLACKLIST_TIME` 调到 1 秒以下——会让真正卡在悬崖对面的目标被反复选中、反复卡住；② 去掉黑名单机制——3.14 明确要求「连续 3 次不推进 → 目标短期黑名单重搜」，只能改口径不能删。

---

## 6. 验证计划

1. **临时探针确认链路（不入库，验证后删除）**：在 `auto_battle.gd` 的四个丢目标分支（实例失效 / 死亡 / 拉黑 / 拾取抢占）各加一条带原因的 `push_warning`，实机打 3 分钟百首禁域 + 无尽回廊，统计各原因的命中次数。
2. **实机验收口径**（每张图刷 5 分钟）：
   - 改选次数 / 分钟（目标：改选只发生在**当前 Boss 被击杀**之后）；
   - 是否仍出现「目标不可达，已改选」提示；
   - 一次 Boss 战的**血量单调下降**（不允许出现回满）。
3. **回归**：`python3 tools/run_isolated_tests.py`（默认集）全绿；涉及 `_find_target`/`_tick_stuck` 的改动需补有牙用例（构造「直线距离不变但角色在推进」的场景，断言**不**拉黑）。

---

## 7. 待确认项

- 现象出现在哪张图为主？（`c7_arena` 无尽回廊 vs `c7_boss_field` 百首禁域）——决定 P1（绕墙）与 P6（脱战半径）的优先级。
- 是否见过「目标不可达，已改选」提示？——一句话即可确认主因 A/B。
- 是否观察到 Boss **血条回满**？——确认放大器 D。
- 是否开着自动拾取（G）？——确认放大器 E 的权重。

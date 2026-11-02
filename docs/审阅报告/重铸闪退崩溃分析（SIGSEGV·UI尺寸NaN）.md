# 重铸闪退崩溃分析（SIGSEGV · UI 尺寸 NaN 传播）

> 历史取证记录：本轮根因假设已被后续证据替代，不应作为当前修复依据。请以[第三轮结论](重铸闪退第三轮：根因确证与修复.md)及[独立复核](重铸闪退修复独立复核与历史负债清理建议.md)为准；正文保留以追溯调查过程。

> 分析时间：2026-11-02 15:15 ｜ 分析对象：玩家实机运行（Godot 4.7.2 / gl_compatibility / Apple M4）
> 结论性质：**部分证实**。崩溃类型、崩溃时机、传播链已用硬证据闭合；「重铸操作 → 崩溃」的最后一环尚未直接复现，见 §7。

---

## 1. 结论摘要

| 项 | 结论 | 置信度 |
|---|---|---|
| 有无崩溃记录 | 有。macOS 系统级 `.ips` 两份 + Godot 自身 `handle_crash` 栈两份 | 已证实 |
| 崩溃类型 | `SIGSEGV`（空指针 + 小偏移），发生在 Godot C++ 层 | 已证实 |
| 是否偶发 | **否**。今日两次 + 10-30 一次，崩溃栈帧偏移完全一致 | 已证实 |
| 崩溃时机 | **主场景（重）加载流程中**，非掷骰瞬间 | 已证实 |
| 存档是否损坏 | **否**。slot_1 完整、无数值异常、689 级 | 已证实 |
| 直接诱因 | `viewport` 尺寸或 `uiScale` 变为 `inf/nan`，经 UI 缩放函数**无守卫**放大到全 UI | 代码+实验证实，触发源待定 |
| 与「重铸」的因果 | 未证实。日志无重铸埋点，仅能从存档频率反推高频操作 | **推断** |

**一句话**：这不是数据算错、也不是存档写坏，而是 **UI 尺寸被写成了 `inf/nan`，一路传到渲染层导致引擎底层空指针**。守卫代码写的是 `if size <= 0.0`，而 `nan <= 0.0` 在浮点语义下永远是 `false`，所以它拦不住这一类值。

---

## 2. 崩溃记录在哪（可复核）

| 位置 | 内容 |
|---|---|
| `~/Library/Logs/DiagnosticReports/Godot-2026-11-02-150443.ips` | 进程 15:04:20 启动、15:04:41 崩溃（存活 21 秒） |
| `~/Library/Logs/DiagnosticReports/Godot-2026-11-02-150424.ips` | 进程 11:53:20 启动、15:04:17 崩溃（存活 3h10m） |
| `.../app_userdata/末法纪元：最后的守护者/logs/godot2026-11-02T15.04.20.log` | 崩溃前日志，675 KB |
| `.../logs/godot2026-11-02T11.53.20.log` | 崩溃前日志，971 KB |
| `.../logs/godot.log` | 最近一次运行日志（2 次「启动」+ 崩溃栈） |

复核命令：

```bash
# 崩溃类型与存活时长
python3 -c "
import json
raw=open('$HOME/Library/Logs/DiagnosticReports/Godot-2026-11-02-150443.ips').read()
b=json.loads(raw[raw.index(chr(10)):])
print(b['exception'], b.get('procLaunch'), b.get('captureTime'))"

# Godot 自己的崩溃栈（日志尾）
tail -25 "$HOME/Library/Application Support/Godot/app_userdata/末法纪元：最后的守护者/logs/godot.log"
```

---

## 3. 崩溃是什么

```
handle_crash: Program crashed with signal 11        ← SIGSEGV
exception: EXC_BAD_ACCESS SIGABRT
subtype:   KERN_INVALID_ADDRESS at 0x0000008c       ← 空指针 + 偏移
```

- **不是** GDScript 报错（否则日志里会有 `SCRIPT ERROR` + 脚本栈，实际一条都没有）。
- 崩溃线程是主线程（`com.apple.main-thread`）。
- 三层格式完全一致的栈（`abort` ← `_sigtramp` ← Godot 内部帧），且 **13 帧偏移逐个相等**：`81312400, 81312400, 81309444, 48251836, 48266316, 50360928, ...`。
- 三次非法地址分别是 `0x00019309` / `0x00000eaf` / `0x0000008c` —— **都在 NULL 附近**，是典型的「指针为 0（或接近 0），访问其成员」。
- Godot 官方 macOS 二进制符号被 strip，`atos` 只能给出 `(in Godot) + N`，无法还原函数名。**因此崩溃的具体 C++ 函数无法从栈直接读出**，只能由时机与现象反推。

> 附带发现：`DiagnosticReports` 里另有 13 份 10-29～10-30 的崩溃，**栈指纹完全不同**、存活恰好 8～11 秒、地址 `0x0`。那一批是开发期跑测试/探针的进程，**与玩家侧崩溃无关**，已排除。

---

## 4. 崩溃时机：主场景重载

两份日志的最后两条打印完全一样：

```
========================================
[Main] 《末法纪元：最后的守护者》启动
[Main] 配置校验通过 ✅
========================================
                                        ← 紧接着就是 handle_crash
```

`[Main] 配置校验通过 ✅` 是 `scripts/main.gd:18`，说明 **`main.gd._ready()` 已经跑完**，崩溃发生在它之后。

而 `main.gd._ready()` 里排了三个延迟动作：

```gdscript
SettingsRuntime.apply_display_strategy()
SettingsRuntime.apply_all.call_deferred()      # ← 下一帧执行
get_viewport().size_changed.connect(_on_viewport_size_changed)
$UI/MenuPanel.initialize_if_current.call_deferred()
```

`apply_all()` → `_apply_ui_scale()` → `apply_ui_scale_to()`，正是日志里报错的那条路径。

**为什么主场景会重载？** 切图走的是整场景重载，不是替换子节点：

```gdscript
# autoload/map_service.gd:665
func reload_world() -> void:
    call_deferred("_reload_world_now")

# autoload/map_service.gd:677
var err := get_tree().reload_current_scene()
```

每次重载都会重新执行 `main.gd._ready()`，也就会重新走一遍 `apply_all` → UI 全量重排。日志中「启动」打印次数（各文件 2～6 次）正好对应这个过程。

---

## 5. 已定位的确定缺陷

### 5.1 守卫对 `NaN` / `inf` 完全失效

`scripts/systems/settings_runtime.gd:261-274`：

```gdscript
static func apply_ui_scale_to(ui: CanvasLayer) -> void:
    var scale_value := ui_scale_value()
    var viewport_size := ui.get_viewport().get_visible_rect().size
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:   # ← 拦不住 nan / inf
        return
    var logical_size := viewport_size / scale_value
    for child in ui.get_children():
        if child is Control:
            control.size = logical_size                     # ← 非法值直接落地
```

实测（`tools/nan_guard_probe.gd`，Godot 4.7.2 本机）：

| 表达式 | 结果 | 含义 |
|---|---|---|
| `NAN <= 0.0` | **false** | 守卫放行 |
| `INF <= 0.0` | **false** | 守卫放行 |
| `is_finite(NAN)` | false | 唯一可靠判据 |
| `clampf(NAN, 0.8, 2.0)` | **nan** | `ui_scale_value()` 也不兜底 |
| `INF - INF` | **nan** | 边框 `draw_rect` 算出 NaN 的原因 |

### 5.2 日志与缺陷一一对应

| 日志现象 | 次数 | 对应代码 |
|---|---|---|
| `Condition "!isfinite(p_size.x)"` at `set_size` | 75 | `control.size = logical_size`（第 273 行） |
| `Vector2 cannot be normalized, elements must be finite` | 1401 | `hud_status_icon.gd:29` / `map_canvas.gd:399` |

两处 `_draw` 的共性：**都是对「尺寸/坐标含 inf 的图形」做运算**——
`hud_status_icon.gd:29` 是 `draw_rect(..., filled=false, width=1.0)`，即**画边框**，内部要 4 条线段各算法线 ⇒ `INF - INF = NaN`；
`map_canvas.gd:399` 画的是**玩家位置圆环**，`_project(_player_position)` 为 NaN。

1401 次 ≈ 21 秒 × 67 fps，说明**每帧都在画 NaN**，不是偶发一帧。

### 5.3 完整传播链

```
某次场景重载瞬间 viewport / current_scene 状态不稳
        ↓
get_visible_rect().size  → inf 或 nan
        ↓  守卫 `<= 0.0` 判 false（实测），放行
logical_size = size / scale  → inf / nan
        ↓  重复赋值给 UI 下每个 Control
引擎报 !isfinite(p_size) × 75
        ↓  子控件继承非法尺寸
HudStatusIcon.size = inf → draw_rect 边框 → INF-INF = NaN
        ↓
Vector2 normalize 告警 × 1401（每帧）
        ↓
渲染层拿到 NaN 顶点/变换矩阵
        ↓
Godot C++ 层空指针 → SIGSEGV(0x8c) → abort → 闪退
```

**这一整条链，除最后一跳「NaN 顶点→C++ 崩溃」需要在实机上复现确认外，其余每一环都有实测或代码证据。**

---

## 6. 存档安全状态（已核查）

| 项 | 结果 |
|---|---|
| `slot_1.json` | 318,894 字节，JSON 可解析，**无 nan / inf / Infinity 文本** |
| 递归扫描数值 | 无 NaN、无 inf、无 >1e15 的异常值 |
| `player` | 689 级法师，`hp` 12,289,264，`attack` 118,819，正常 |
| `playerPos` | `[1913.70751953125, -1789.62353515625]`，正常浮点 |
| 磁盘可用 | 28 GB（86% 已用），不构成写盘失败 |
| 备份 | 已另存 `/tmp/deg_saves_backup_20261102-151021`，md5 `3ebe8b16…` |

**结论：存档没有坏，玩家进度不会因这次崩溃丢失。** 这一点与 114 打包冒烟那次（写入真实档）性质完全不同。

---

## 7. 尚未证实的一环（重要）

**日志里没有任何重铸相关打印**，`reforge_equipment` 全链路无埋点。因此「重铸操作 → 崩溃」目前只有间接线索：

1. `slot_1` 的 `已保存到槽 1` 打印共 **16,435 次**，活跃时长 3h10m ⇒ 平均 **0.66 秒一次**。
2. 这个节奏正好等于 `AUTOSAVE_DEBOUNCE = 0.6`，说明 `request_autosave()` 被**持续**触发——重铸成功会发 `equipment_changed`，与「连续点重铸按钮刷词条」的行为吻合。
3. 按 0.6 s 一次的稳态反推，那 3 小时里约发生 **1.6 万次重铸**，累计写盘 ≈ 16 GB（每次 312 KB 正文 + 312 KB 读回校验 + 312 KB 备份复制）。

**但没有一条日志能证明「崩溃发生在掷骰那一刻」。** 现有证据反而显示崩溃发生在**主场景重载之后**。两种可能的统一解释：

- **解释 A**：重铸 → 面板关闭/切图 → 场景重载 → 重载瞬间 UI 尺寸非法 → 崩。玩家体感是「重铸完就闪退了」。
- **解释 B**：崩溃独立于重铸，只是玩家几乎全程待在重铸面板里刷词条，崩的时候刚好在重铸。

**两者都会表现为「重铸时闪退」，必须靠复现区分。**

---

## 8. 建议方案（择一，需确认后再动手）

### 方案 A：修守卫 + 兜底（推荐先做，成本最低）

改动三处，均属「防非法值」而非改玩法数值：

1. `apply_ui_scale_to`：守卫改为 `if not is_finite(viewport_size.x) or viewport_size.x <= 0.0 ...`，并对 `logical_size` 再判一次 finite，非有限直接 return。
2. `ui_scale_value()`：`clampf` 前先 `is_finite` 检查，非有限回落 1.0（实测 `clampf(NAN)` 会原样透传）。
3. `main.gd._ready` 的 `apply_all.call_deferred()`：在重载场景下改为「等一帧、确认 `current_scene` 已是新场景且视口尺寸 finite」再执行。

**收益**：把 NaN 挡在渲染层之外，即使触发源还在，也不再升级成崩溃。
**风险**：低。改的都是防御分支，不动任何平衡数值。
**验证**：新增负向探针（注入 inf 尺寸，断言不落 `control.size`）；跑默认集 97 + `--all` 166。

### 方案 B：加崩溃取证埋点（成本最低，但要多崩一次）

在 `reforge_equipment`、`_on_reforge`、`reload_world`、`apply_ui_scale_to` 四处打点，带日志落盘 flush。下次闪退时日志能精确指到「崩在哪个动作之后」。

**收益**：一次就能拿到确定的因果，不用猜。
**风险**：要请你再操作一次，大概率再崩一次（存档已确认安全，有备份）。

### 方案 C：沙盒复现（最彻底，耗时长）

把存档复制到隔离目录，用脚本驱动「进世界 → 开重铸面板 → 连续重铸 N 次 → 切图重载」全流程，窗口模式跑到崩为止，抓崩溃前最后动作。

**收益**：可重复、可回归。
**风险**：需临时移走真实存档目录（有完整备份 + md5 可核），期间不要开游戏。

**推荐顺序：A → B**。A 成本低且能立刻止血；B 用来确认根因，一次操作即可。

---

## 9. 顺带发现的工程问题（不阻塞，但建议排期）

1. **存档风暴**：每次重铸触发一次全量存档（312 KB × 3 次 IO），3 小时 1.6 万次 ≈ 16 GB 写入。建议重铸路径改用 `request_autosave` 的更长去抖（如 3 s）或「面板关闭时才存」。
2. **重铸链路无日志**：`reforge_equipment` 全链路零打印，导致这次只能靠 .ips 反推。建议至少在成功/失败分支各打一行。
3. **`_draw` 缺少 finite 前置判断**：`hud_status_icon`、`map_canvas` 等绘制代码在尺寸非法时仍会算 NaN。可在 `_draw` 入口加 `if not size.is_finite(): return`（与「`draw_*` 前置 return」同族的加固）。

---

## 10. 本轮产出 / 未完成 / 建议下一步

**产出**
- 崩溃记录定位与解析（4 份文件、3 次同栈比对、排除 13 份开发期无关崩溃）
- 确定缺陷：UI 缩放守卫对 nan/inf 失效（附实测表）
- 崩溃时机锁定：主场景重载之后
- 存档安全性核查（无损失）
- 证据探针 `tools/nan_guard_probe.gd`

**未完成**
- 「重铸 → 崩溃」最后一环未复现
- 崩溃的具体 C++ 函数无法还原（二进制无符号表）

**建议下一步**
- 已选定 **方案 A**，实施与验证记录见 §11。

---

## 11. 方案 A 实施记录（2026-11-02 15:35）

### 11.1 改动清单

| 文件 | 改动 | 目的 |
|---|---|---|
| `scripts/systems/settings_runtime.gd` | 新增 `is_usable_layout_size(size)` 作**唯一判据** | 把「尺寸是否可用」收敛成一个可独立测试的纯函数，杜绝各处重写 `size <= 0` |
| 同上 | `apply_ui_scale_to()`：视口尺寸与逻辑尺寸都改用该判据；补 `scale_value` 有限性检查、`viewport == null` 检查 | 非法值一律不落进控件尺寸 |
| 同上 | `ui_scale_value()`：`uiScale` 与 `display_scale_factor()` **分别**做 finite 兜底 | 实测 `clampf(NAN)` 原样透传，clamp 不能当兜底 |
| `scripts/main.gd` | `apply_all.call_deferred()` → `_apply_settings_after_scene_ready()`（延后一帧 + `is_inside_tree()` 检查） | 等 `reload_current_scene()` 完成再重排 |

**一行没动平衡数值、没动存档结构、没动任何玩法逻辑。**

### 11.2 新增测试 `tests/NanGuardTest.tscn`（已纳入默认集）

四组断言：① NaN/INF 的浮点语义前提；② 判据本身（字面量入参，不复用生产常量）；③ 倍率入口兜底；④ 端到端 + 正常倍率回归。

### 11.3 负向验证 `tools/verify_115_negative.py` → **3/3 有牙**

| 注入 | 如期变红的断言 |
|---|---|
| N-1 判据退回 `not (x <= 0 or y <= 0)`（原始 bug 形态） | 「NaN 尺寸必须判为不可用」 |
| N-2 去掉 `uiScale` 的有限性兜底 | 「uiScale 为 NaN 时倍率必须是有限值」 |
| N-3 去掉显示倍率的有限性兜底 | 「手动显示倍率为 NaN 时必须回落 1.0」 |

> **第一版 N-1 被判「红错断言」**：注入写成 `size.x > 0 and size.y > 0` 反而把 NaN 拦住了（`NAN > 0` 为 false），只会红在 INF 那条上。必须还原 `not (x <= 0 or y <= 0)` 才是等价注入。**这个不等式本身就是本 bug 的全部要害。**

### 11.4 四层验证结果

| 层 | 命令 | 结果 |
|---|---|---|
| 资源导入 | `--import` | **0 ERROR / 0 SCRIPT ERROR** |
| 默认隔离集（含 NanGuardTest） | `run_isolated_tests.py` | **111 PASS / 1 FAIL**（FAIL 为既有欠债，见 §11.5） |
| 全量 | `run_isolated_tests.py --all` | **185 PASS / 2 FAIL / 3 SKIP**（2 条均为既有欠债） |
| 启动校验 | `--quit` | 配置校验通过 ✅，0 SCRIPT ERROR，无 ObjectDB/RID leak |
| 主场景实跑 | `res://scenes/Main.tscn` | 0 报错，启动正常 |

### 11.5 期间发现的两条既有欠债（**均与本次改动无关，已定位到具体提交**）

| 测试 | 症状 | 根因 | 引入提交 |
|---|---|---|---|
| `ToolReclaimTest` | `panel 类道具应为 4 件，实际 5` | 数据表新增第 5 件 `tool_super_portable_token`（超级随身令牌），测试的 `EXPECTED_TOOLS` 未同步 | `2310948c feat(随身三件套): 新增超级随身令牌集成服务` |
| `SuperPortablePanelTest` | `测试未输出成功完成标记` | 测试只打印 `[SuperPortablePanelTest] 五项数字键及隐藏状态隔离通过`，而运行器只认行尾 `全部通过` / `PASS`。**直跑该测试本体是通过的** | `88118e6a feat(ui): 为超级随身菜单增加数字快捷键` |

**两条都需要产品决策或文案修正，本次未擅自改动**——尤其 `EXPECTED_TOOLS` 是否加第 5 项，取决于「超级随身令牌是否纳入永久工具补领范围」，属业务判断；直接加数字属于「改测试求绿」，是坑 46 明令禁止的做法。

### 11.6 尚未验证

**「重铸 → 崩溃」的直接因果仍然没有复现**（§7 已说明）。本次修的是**崩溃的放大机制**：即使触发源仍在，NaN 也进不了控件尺寸与渲染层。若修复后仍闪退，说明触发源不在这条链上，需要走方案 B 埋点重新定位。


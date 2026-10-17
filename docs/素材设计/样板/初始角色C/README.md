# `look_01` 腐化之翼八向骑乘形态样板 C

本目录对应 [初始角色形象补全规划](../../17-初始角色形象补全规划.md) 的 C 节点第一种坐骑样板。日期：2026-10-17。八向待机与移动图现已复制到 `assets/sprites/player/guardian/mounts/` 并接入正式游戏。第二种坐骑 `mount_furnace_beast` 与骑乘攻击/受击/死亡/打坐尚未制作；这些情形保持现有角色动画回退。

## 造型判断

`data/mounts.json` 将 `mount_corrupted_wing` 描述为“腐化巨兽残留的羽翼”；已有 48×48 图标也是一对翼。基于这个事实，本样板把“骑乘”表现为 **`look_01` 人物背负/佩戴暗紫双翼**，不另创一只兽，也不表现离地飞行。脚底依旧接地，移动路径、障碍与移速规则不受美术样板影响。人物的黑发、旧布披肩、灰银护甲、炭灰衣物与短刃青色点缀沿用已审定的初始形象。

## 交付物与重建

| 文件 | 规格 | 用途 |
|---|---|---|
| `corrupted_wing_idle_candidate_atlas.png` | 1024×512，8 列×4 行，每格 128×128 | 八向佩戴双翼待机，双翼轻微展开/收拢 |
| `corrupted_wing_walk_candidate_atlas.png` | 1024×512，8 列×4 行，每格 128×128 | 八向地面移动，脚步与双翼跟随 |
| `GuardianWingPreview.tscn` / `.gd` | Godot 可运行场景 | 上排双翼人物、下排未佩戴人物同缩放比较；按 1/2 切换待机/行走 |
| `corrupted_wing_runtime_preview.png` | 1280×800 | Godot GL Compatibility 实际窗口录帧，用于静态审稿 |

源稿保留在 `art_source/player/look_01/mount_sources/`，以项目已有 `guardian_source_atlas.png`、`guardian_walk_source.png` 和 `mount_corrupted_wing.png` 为参考，经内置 imagegen 生成；没有新增第三方素材。`tools/build_guardian_wing_sample.gd` 负责透明阈值、四行八列裁切、缩小后的孤立羽片清理和脚底锚点统一，可复建候选图集：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/build_guardian_wing_sample.gd
```

两张图方向列均为 `s, sw, w, nw, n, ne, e, se`。128×128 是带翼组合的画布，不代表角色变成 128 像素高；有效主体高度约 56 像素，脚底锚点 (64,104)。正式接入时需依据游戏内世界缩放和场景遮挡再次验收。

## 本轮自检与后续审稿点

- 两张候选图共 64 个动作格，全部有内容；每个方向四帧均不完全相同；透明主体的下沿逐格为 y=104，格内没有越界。
- 初次缩小发现源稿有离开人物的羽片；构建工具已按每格最大连通主体清理，重新检查图集与浅色背景后未见明显悬浮片。
- Godot 4.7.2 GL Compatibility 已导入候选图；预览场景 headless 加载无资源/脚本错误，实际窗口录帧表明角色体量与未佩戴版本接近、羽翼可辨且地面线对齐。
- 目前只验证静态截图与可运行样板，完整逐帧转向、场景内前后遮挡、攻击/受击/死亡/打坐状态仍需后续审查。尤其需要确认“羽翼附着式骑乘”的形态符合用户对 `腐化之翼` 的预期，审定后再推广至第二种坐骑与正式游戏。

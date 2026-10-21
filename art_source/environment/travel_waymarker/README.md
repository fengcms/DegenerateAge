# 步行出口“行旅界碑”样图

本目录只保存美术源稿；`docs/素材设计/样板/步行出口路标/` 保存预览。对应设计依据是 `docs/素材设计/步行出口路标美术设计方案.md`。当前**未接入游戏**，没有修改 `TravelExit`、地图配置或交互逻辑。

## 文件与规格

| 文件 | 用途 |
|---|---|
| `concept_reference.png` | 内置 imagegen 生成的透明造型参考，高分辨率源参考，不供游戏加载 |
| `waymarker_idle_64.png` | 常态，旧木双向箭牌、铁箍、灰石座 |
| `waymarker_near_64.png` | 靠近状态，只将牌心箭形镶片改为浅青绿 |
| `waymarker_locked_64.png` | 封锁状态，主体降亮度并在牌心加像素锁片 |

三张候选运行图均为 **64×64 RGBA**，实像素约 `x=10…52, y=6…61`，建议脚底锚点 `(32,61)`；Alpha 严格只有 0/255。源图不含目的地文字、等级、按键、金币或地面背景。牌面有可见上沿与侧边厚度，石座对应 64×32 等距地砖的斜向地面。它是一件整体实体，不拆成逐格瓦片；样图不定义新的碰撞。

制作方式：选取 imagegen 的第二张透明候选图，硬阈值裁切透明边，等比缩为 43×58，关闭抖动量化到 24 个主体颜色，保留硬边 Alpha 后放入 64×64 画布；状态变化在这个像素稿上做局部换色与锁片覆盖，未重新生成导致三张轮廓漂移。`concept_reference.png` 仅用于追溯造型；进入游戏时只应使用经核对的 64×64 文件。六倍图使用最近邻放大，没有新增像素细节。

采用的 imagegen 提示词：

> Use case: stylized-concept. Asset type: single transparent pixel-art sprite concept for a 2D isometric dark-fantasy ARPG. One low roadside waymarker only: short old wood post, short thick double-ended arrow plank pointing both left and right, muted iron straps, a small pale inlaid double-arrow emblem, compact angular stone footing and tight contact shadow. 45-degree elevated isometric camera with visible top and right side of board, vertical post. Genuine transparent background, no terrain, no characters, no words. Clear bold silhouette at 64x64, hard pixel clusters, no anti-aliasing, no vector outlines, no gradients, no glow, no extra objects.

## 预览的口径

- `camp_scale_1x.png`：取现有营地 B 全图预览的道路画面作为背景，叠入靠近状态路标、守护者 1 级待机图集首帧（64×80，按代码 `ART_SCALE=1.5` 显示）和模拟交互文字。
- `cave_scale_1x.png`：取现有《腐化源头》BossReviewTest 渲染截图中的洞壁/地面区域作为背景，叠入常态路标、同一守护者帧和模拟目的地文字。
- `*_scale_2x.png` 只是对应 1:1 合成图的最近邻两倍放大；`states_scale_1x.png` 在中性底上比较三种状态，`states_x6.png` 与 `waymarker_idle_x6.png` 专供检查像素轮廓。

两张场景图是**使用真实项目背景与人物资源制作的同屏比例合成预览**，不是当前游戏实时出口截图；画面中的标签是预览模拟，不代表已改 Godot 世界文字。它们证明造型在浅路面、洞穴地面和玩家旁边的初步可读性；实际 UI 倍率、遮挡、点击热区、锁定条件、地图倍率及帧时间必须等接入时在窗口中验证。定稿前重点请确认主体大小、木石材质和封锁状态的小锁片是否清楚。

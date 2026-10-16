# 11—60 级美术制作记录

本目录跟踪第二至六章 150 个稳定数据 ID 的美术生产状态。`asset_manifest.json` 由 `tools/build_chapter_art_manifest.py` 从运行数据与 [93 号资源梳理文档](../../../游戏创意/21-60级内容规划/93-21-60级新增装备物品怪物梳理与美术提示词.md)生成；该来源文档目前是工作区提供的输入，清单已保存其逐件造型主体与任务锚点。

执行 `python3 tools/build_chapter_art_manifest.py --check` 可核对 ID、顺序和数量。生成器不会覆盖已有清单，以免覆盖后续人工记录。新数据增加时应先核对差异，再更新清单。

`status` 依次为 `planned`、`designed`、`exported`、`reviewed`、`integrated`；`integration` 单独标记游戏接入，`resource_registered` 表示图标已经预载、但尚无任务袋图标界面。初始值为 `planned/pending`，仅表示制作队列已冻结。`existing_partial` 只标记第二章汲灵幼虫已有未接入的局部方向帧；该怪仍需要八向、必要状态、图集元数据和游戏验收。

装备与任务物的预期运行图是 48×48 透明 PNG。怪物的 `runtime_art` 是目录，完成后须包含符合现有 `animation_pack` 契约的图集与元数据。实际源稿、提示词、审查图和导出文件在后续各批提交中逐项补齐，不能仅凭目标路径认定文件存在。

## 第二章首批图标

第二章 10 件装备和 4 件任务物使用内置 `image_gen` 逐件生成透明源稿，生成方式及授权依据为本次用户授权的游戏美术制作任务。源稿保存在 `art_source/chapters/ch02/{equip,quest_items}/<id>/source.png`，运行图保存在清单的 `runtime_art`；统一以 ImageMagick 执行 `-trim +repage -filter Lanczos -resize 44x44 -background none -gravity center -extent 48x48` 导出，未对图标烘焙品质框、文字或数量。逐件造型主体见清单的 `visual_brief`，共同生成约束为：复古末法幻想像素图标、旧铜/铆钉铁/布革/炉灰材质、左上光、透明背景、独立主体、34px 仍可辨、不带 UI/文字/投影。原始生图提示是在此约束上强化各件轮廓；源稿保留以供重绘，不能把这些 1254px 源稿直接加载进游戏。

[深色底拼版](ch02_icons_dark.png)和[浅色底拼版](ch02_icons_light.png)按清单顺序排列，供 48px 轮廓复核。14 张图标均通过尺寸、RGBA、非空主体和至少 2px 透明边检查。10 件装备路径和预载表已接入，4 件任务物图标仅注册资源读取入口；当前没有显示任务袋图标的正式界面，因此不能标为界面已接入。

## 第三章图标

第三章的 10 件装备与 4 件任务物沿用逐件透明源稿与 48×48 导出流程，以渠铜、赭石、白布、水位刻度和盐痕区分第二章的旧铜工业器物。逐件主体取自清单 `visual_brief`；任务物以配水封片、警报索引、原字拓片、净水布封的实物形状生成。运行图通过尺寸、RGBA、非空主体和透明安全边检查，供复核的[深色底拼版](ch03_icons_dark.png)与[浅色底拼版](ch03_icons_light.png)按清单顺序排列。装备图标已更改数据路径与预载；任务物目前只完成资源注册。

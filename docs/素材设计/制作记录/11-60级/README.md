# 11—60 级美术制作记录

本目录跟踪第二至六章 150 个稳定数据 ID 的美术生产状态。`asset_manifest.json` 由 `tools/build_chapter_art_manifest.py` 从运行数据与 [93 号资源梳理文档](../../../游戏创意/21-60级内容规划/93-21-60级新增装备物品怪物梳理与美术提示词.md)生成；该来源文档目前是工作区提供的输入，清单已保存其逐件造型主体与任务锚点。

执行 `python3 tools/build_chapter_art_manifest.py --check` 可核对 ID、顺序和数量。生成器不会覆盖已有清单，以免覆盖后续人工记录。新数据增加时应先核对差异，再更新清单。

`status` 依次为 `planned`、`designed`、`exported`、`reviewed`、`integrated`；`integration` 单独标记游戏接入。清单初始值全部为 `planned/pending`，仅表示制作队列已冻结，不表示图片已生成。`existing_partial` 只标记第二章汲灵幼虫已有未接入的局部方向帧；该怪仍需要八向、必要状态、图集元数据和游戏验收。

装备与任务物的预期运行图是 48×48 透明 PNG。怪物的 `runtime_art` 是目录，完成后须包含符合现有 `animation_pack` 契约的图集与元数据。实际源稿、提示词、审查图和导出文件在后续各批提交中逐项补齐，不能仅凭目标路径认定文件存在。

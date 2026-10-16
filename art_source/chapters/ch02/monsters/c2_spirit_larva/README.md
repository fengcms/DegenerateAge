# 汲灵幼虫多方向试作（未接入）

`direction_trial.png` 由内置 `image_gen` 以项目已有的 `art_source/chapter2/concepts/spirit_larva_keypose_source.png` 为参考生成，尝试一次得到 8 个方向。逐格查看发现下排所谓背向仍出现眼睛和正面口器，右侧视角与左侧也高度相似，因此不是合格的八向图集。`rear_trial.png` 是单独要求背面后生成的进一步试作，背面结构有所改善，但仍需统一等距视角、像素尺寸、脚底锚点和同一套动作。

这两张图只供方向设计比较，不是正式运行资源，不含 idle/walk/attack/hit/death 各状态帧。已有 `assets/sprites/monsters/c2_spirit_larva/*_se_atlas.png` 是未接入的东南向局部帧，也不因此补齐。当前运行数据继续使用 `placeholder`。

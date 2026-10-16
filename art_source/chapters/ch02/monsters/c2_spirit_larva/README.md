# 汲灵幼虫多方向试作（未接入）

`direction_trial.png` 由内置 `image_gen` 以项目已有的 `art_source/chapter2/concepts/spirit_larva_keypose_source.png` 为参考生成，尝试一次得到 8 个方向。逐格查看发现下排所谓背向仍出现眼睛和正面口器，右侧视角与左侧也高度相似，因此不是合格的八向图集。`rear_trial.png` 是单独要求背面后生成的进一步试作，背面结构有所改善，但仍需统一等距视角、像素尺寸、脚底锚点和同一套动作。

这两张图只供方向设计比较，不是正式运行资源，不含 idle/walk/attack/hit/death 各状态帧。已有 `assets/sprites/monsters/c2_spirit_larva/*_se_atlas.png` 是未接入的东南向局部帧，也不因此补齐。当前运行数据继续使用 `placeholder`。

`idle_grid_trial.png` 进一步要求内置 `image_gen` 输出严格的 8 行方向 × 4 列待机帧。画面虽按网格排布，但第 5 行“北/背面”仍画成有眼睛和口器的正面，第 4/6 行也不是稳定的背侧；同一行的四帧几乎只有细小像素抖动，没有可靠的腹囊呼吸或阀门动作。因此本样本未通过方向和动作验收，禁止切图后命名为 `idle_atlas.png`。

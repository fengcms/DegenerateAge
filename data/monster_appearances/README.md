# 怪物表现档案

`index.json` 登记可复用的外观 ID。具体怪物在 `data/monsters/chNN/monsters.json` 通过 `appearanceId` 引用本目录档案；多个怪物可引用同一个档案。外观 ID 不进入任务、掉落或存档身份。

`renderer`：`procedural` 沿用怪物分档绘制；`sample_atlas` 为旧 8×8 动作图集，可提供 `walk`；`static_atlas` 为木桩等静态图集；`animation_pack` 引用 `MonsterAnimationLibrary.PACKS` 内已生成的八方向状态包；`chapter2_manifest` 可适配仍在使用的第二章正式资源清单（当前清单为空）。数值、伤害、冷却、经验和掉落不得写在表现档案中。

素材文件保持原路径；这里仅登记元数据，不复制贴图。修改图集、帧尺寸、脚底锚点、头顶位置或生成包后，检查本档案与实际素材、八方向状态、点击范围及正式导出。没有正式素材的怪物引用 `placeholder`，不要为每只占位怪复制空档案。新增档案必须登记索引并在实际怪物上验证复用。

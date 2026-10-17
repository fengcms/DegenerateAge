# 怪物表现档案

`index.json` 登记可复用的外观 ID。具体怪物在 `data/monsters/chNN/monsters.json` 通过 `appearanceId` 引用本目录档案；多个怪物可引用同一个档案。外观 ID 不进入任务、掉落或存档身份。

`renderer`：`procedural` 沿用怪物分档绘制；`sample_atlas` 为旧 8×8 动作图集，可提供 `walk`；`static_atlas` 为木桩等静态图集；`directional_preview` 为八方向单帧试玩稿，保留受击和死亡变色，并非正式动画；`animation_pack` 引用 `MonsterAnimationLibrary.PACKS` 内已生成的八方向状态包；`chapter2_manifest` 可适配仍在使用的第二章正式资源清单（当前清单为空）。数值、伤害、冷却、经验和掉落不得写在表现档案中。

正式动画包由 `data/monster_animation_packs.json` 登记审核源稿，运行图集与路径索引由 `node tools/build_monster_animation_assets.mjs` 生成，`--check` 只读校验。`MonsterAnimationCache` 在地图怪物生成前预取本图正式包，按外观 ID 共享纹理，并在世界退出时释放地图缓存；直接创建怪物的隔离场景在装配点补加载。定点怪可省略 `walk`，其余实际使用的状态仍须完整。动画索引只保存路径，不全局预载全部图集。

素材文件保持原路径；这里仅登记元数据，不复制贴图。修改图集、帧尺寸、脚底锚点、头顶位置或生成包后，检查本档案与实际素材、八方向状态、点击范围及正式导出。没有正式素材的怪物引用 `placeholder`，不要为每只占位怪复制空档案。新增档案必须登记索引并在实际怪物上验证复用。

第二至六章目前按[42 号规范](../../docs/素材设计/42-11至60级怪物八方向试玩稿批量制作规范.md)逐只升级：未升级怪物仍用 `static_atlas` 三格，依次为单一东南向原姿、受击闪白、死亡褪色；已升级者用 `directional_preview` 三列八行图集。普通、精英、首领分别使用 80、112、192 像素方帧，脚底锚点为 64、88、152 像素。`SimplifiedMonsterLibrary` 只预载仍使用静态图的怪物；方向试玩图由 `MonsterAnimationCache` 按地图预取和释放，并在导出全部资源模式中按外观档案路径加载。用 `godot --headless --path . --script tools/build_monster_directional_preview.gd -- --id=怪物ID` 从各 ID 的七张方向图和原东南向图构建。本批不表示步行和专属技能逐帧动画已完成，怪物数据 ID 不变。

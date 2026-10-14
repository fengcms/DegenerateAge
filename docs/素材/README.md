# 堕落纪元游戏美术素材交付说明

制作日期：2026 年 10 月 13 日至 14 日。沿用项目的复古像素等距末法幻想风格：铁灰、旧布、骨白和磨损器物，玩家灵能为青白，腐化裂隙为紫色。所有成果保存在本目录，未修改游戏数据、资源路径或场景，未接入游戏。

交付 **35 个方形图标、4 只缺失怪物的设计、6 组技能特效、4 档动态品质边框**，共 49 项资源。图标覆盖当前全部 6 个技能及 28 个物品模板，另外补充金币图标。尚未实现的技能和未投放的物品同样制作了美术储备。

## 查看素材

- [本地浏览预览页](index.html)：打开后可以查看图标、怪物和动画，点击下载原图或导出图。
- [图标总览](previews/icons_overview.png)：带中文名称的全部 35 个图标。
- [怪物总览](previews/monsters_overview.png)：裂爪狼王、灰烬怨灵、裂壳虫卫、腐化巨兽。
- [品质边框动画演示](previews/quality_demo.gif)：同一把短刃分别叠加四种品质框。
- [技能特效动画演示](previews/skills_fx_demo.gif)：六种特效并排演示。
- [资源元数据](asset_manifest.json)、[验证报告](validation_report.json)、[提示词和原图记录](sources/generation_manifest.json)。

## 文件组织

| 目录 | 内容 |
| --- | --- |
| icons/skills | 6 个技能的方形图标 |
| icons/equipment | 12 个装备模板的方形图标 |
| icons/items | 6 药水、4 如意、5 杂项和金币，共 16 个图标 |
| icons/mounts | 腐化之翼图标 |
| monsters | 四只缺失怪物的透明设计图与世界尺寸静态姿态 |
| fx | 六种技能的逐帧 PNG、图集、独立 GIF 预览和播放参数 |
| quality_frames | 蓝、绿、金黄、紫四档边框的逐帧 PNG、图集、SVG 源文件和播放参数 |
| sources | 未修改的 image_gen 原图、参考图备份、完整提示词及导出脚本 |
| previews | 中文标注总览及合成动画预览 |

## 图标尺寸与使用

每个图标交付透明 RGBA PNG，主体居中，周围留约 12.5% 以上的安全区。文件 ID 与游戏数据一致。

- <id>.png：48×48，适配现有 UI 图标建议尺寸。
- <id>_96.png：96×96，适合放大 UI 和审阅。
- <id>_256.png：256×256，适合更大展示和二次加工。
- sources/icon/...：未修改的高分辨率生成原图；不是分层 PSD 或 Aseprite 文件。

主体采用最近邻缩放，不把品质色、等级、数量或文字烘焙进图标。后续叠加品质框时，建议图标和框使用同一画布尺寸、中心锚点；48 像素 UI 对应使用 atlas_48.png，64 像素 UI 将图标放到 64 像素透明画布中央后叠加 atlas_64.png。品质来自装备实例，同一模板可以复用不同颜色的边框。

### 方形图标完整索引

| 名称 | 数据 ID | 48 像素 PNG |
| --- | --- | --- |
| 基础斩击 | `basic_slash` | [图片](icons/skills/basic_slash.png) |
| 裂地斩 | `earth_cleave` | [图片](icons/skills/earth_cleave.png) |
| 旋风斩 | `whirlwind` | [图片](icons/skills/whirlwind.png) |
| 战意觉醒 | `battle_focus` | [图片](icons/skills/battle_focus.png) |
| 破甲重击 | `armor_break` | [图片](icons/skills/armor_break.png) |
| 灵刃风暴 | `spirit_storm` | [图片](icons/skills/spirit_storm.png) |
| 守护者短刃 | `weapon_starter` | [图片](icons/equipment/weapon_starter.png) |
| 初级护甲 | `armor_starter` | [图片](icons/equipment/armor_starter.png) |
| 狼王之刃 | `weapon_wolfking` | [图片](icons/equipment/weapon_wolfking.png) |
| 布质头盔 | `helmet_cloth` | [图片](icons/equipment/helmet_cloth.png) |
| 布鞋 | `shoes_cloth` | [图片](icons/equipment/shoes_cloth.png) |
| 木盾 | `shield_basic` | [图片](icons/equipment/shield_basic.png) |
| 皮质护腕 | `bracer_basic` | [图片](icons/equipment/bracer_basic.png) |
| 皮质护膝 | `knee_basic` | [图片](icons/equipment/knee_basic.png) |
| 铜手镯 | `bracelet_basic` | [图片](icons/equipment/bracelet_basic.png) |
| 铜戒指 | `ring_basic` | [图片](icons/equipment/ring_basic.png) |
| 兽骨项链 | `necklace_basic` | [图片](icons/equipment/necklace_basic.png) |
| 镇脉之刃 | `weapon_legendary_vein_guard` | [图片](icons/equipment/weapon_legendary_vein_guard.png) |
| 小红药 | `potion_hp_small` | [图片](icons/items/potion_hp_small.png) |
| 小蓝药 | `potion_mp_small` | [图片](icons/items/potion_mp_small.png) |
| 中红药 | `potion_hp_mid` | [图片](icons/items/potion_hp_mid.png) |
| 中蓝药 | `potion_mp_mid` | [图片](icons/items/potion_mp_mid.png) |
| 大红药 | `potion_hp_large` | [图片](icons/items/potion_hp_large.png) |
| 大蓝药 | `potion_mp_large` | [图片](icons/items/potion_mp_large.png) |
| 铁如意 | `rune_iron` | [图片](icons/items/rune_iron.png) |
| 玉如意 | `rune_jade` | [图片](icons/items/rune_jade.png) |
| 金如意 | `rune_gold` | [图片](icons/items/rune_gold.png) |
| 钻石如意 | `rune_diamond` | [图片](icons/items/rune_diamond.png) |
| 烟花 | `misc_firework` | [图片](icons/items/misc_firework.png) |
| 随机券 | `misc_random_ticket` | [图片](icons/items/misc_random_ticket.png) |
| 回城卷 | `misc_town_scroll` | [图片](icons/items/misc_town_scroll.png) |
| 复活卷 | `misc_revive_scroll` | [图片](icons/items/misc_revive_scroll.png) |
| 灵能碎片 | `spirit_shard` | [图片](icons/items/spirit_shard.png) |
| 腐化之翼 | `mount_corrupted_wing` | [图片](icons/mounts/mount_corrupted_wing.png) |
| 金币 | `coin` | [图片](icons/items/coin.png) |

## 四只怪物设计

现有木桩、腐化野狼、裂壳虫、灰烬游魂已有美术，本批补齐其他四个怪物模板。每只保留普通同族的材质、轮廓语言和紫色裂隙，但增加独立结构，而不是只放大或换色。

| 怪物 | 设计识别点 | 世界姿态画布 | 脚底或虚拟脚底锚点 |
| --- | --- | --- | --- |
| 裂爪狼王 | 更高肩背、断裂骨冠、长爪与少量古铜束件 | 112×112 | (56,88) |
| 灰烬怨灵 | 分裂骨面具、悬浮残袍、碎铜冠、明亮胸前余烬 | 112×112 | (56,88) |
| 裂壳虫卫 | 更厚叠层甲、隆起背脊、骨色护刺与稀疏金属边缘 | 112×112 | (56,88) |
| 腐化巨兽 | 厚重四肢、巨型前爪、层叠骨甲、胸口紫裂核心 | 192×192 | (96,152) |

每只位于 monsters/<monster_id>/，包含 concept_512.png 和 keypose_112.png（Boss 为 keypose_192.png）。生成原图位于 sources/monster/monsters/。世界姿态均为面向屏幕左下的单方向静态关键姿态，脚底锚点按统一画布登记。

本批交付的是设计与静态姿态，**不包含完整八向待机、行走、攻击、受击、死亡动画**。后续制作角色动作时应参考本批造型，不直接用旋转贴图模拟不同方向。

## 技能特效

每组交付 8 帧 128×128 透明 PNG，图集 atlas.png 为 512×256，4 列×2 行。帧顺序从左到右、从上到下，锚点 (64,64)。最后一帧为空白，便于结束时消隐。

| 技能 | 视觉设计 | FPS | 建议播放 |
| --- | --- | --- | --- |
| 基础斩击 | 短青白弧光与少量星火 | 12 | 单次约 0.67 秒，接入时按攻击间隔调整 |
| 裂地斩 | 向前分叉的灵能裂隙与土金碎片 | 12 | 单次约 0.67 秒 |
| 旋风斩 | 逐步扩展的圆形刀光旋涡 | 12 | 单次约 0.67 秒 |
| 战意觉醒 | 规则刻纹、底部灵能环与上升短焰 | 12 | 激活瞬间单次约 0.67 秒 |
| 破甲重击 | 穿透闪线、裂开的盾形与金属碎片 | 12 | 单次约 0.67 秒，储备素材 |
| 灵刃风暴 | 三次交错灵刃与弧形风流 | 10 | 单次约 0.8 秒，储备素材 |

每组 animation.json 标明帧尺寸、列行数、FPS、锚点及建议表现峰值帧。每组 preview.gif 和合览 GIF 为审阅而循环，实际短技能特效建议单次播放；战意特效是施放瞬间表现，不是已覆盖 8 秒增益全过程的持续动画。

特效以 alpha 混合交付，可根据场景选择加法混合。旋风斩按世界圆形设计；裂地斩的裂隙是艺术表现，其最终放置、方向和缩放应由真实技能射程确定。表现峰值帧不能触发额外伤害，不能代替游戏自身战斗结算。破甲重击、灵刃风暴目前仍未接入玩法，制作特效不会改变其状态。

## 四档正方形动态品质边框

| 品质 ID | 颜色 | 动画造型 |
| --- | --- | --- |
| uncommon | 优秀蓝 #4AA3E0 | 单角刻纹与沿边流动亮点 |
| rare | 稀有绿 #46C46A | 双角刻纹与沿边流动亮点 |
| epic | 史诗金黄 #E0C04A | 四角刻纹与缓慢呼吸光 |
| legendary | 传说紫 #B46AE0 | 四角刻纹、上下菱形徽记与四路流光 |

各档交付 24 个不同动画帧，12 FPS，2 秒循环。主体为严格正方形，中央透明，不附带装备图片。普通白装未要求彩色动效，本批不制作普通品质动画。

- atlas_64.png：384×256，6 列×4 行，每帧 64×64。
- atlas_48.png：288×192，6 列×4 行，每帧 48×48。
- frames/00.png ... 23.png：64 像素逐帧 PNG；00_48.png ... 23_48.png 为 48 像素版本。
- static.png：64 像素静态首帧，适合减少动效或静态展示。
- svg/：24 帧可编辑矢量源文件。
- animation.json：颜色、帧尺寸、帧顺序、FPS、循环时长与中心透明区域。
- preview.gif：透明动效审阅，不作为正式游戏纹理格式。

中心 40×40 区域（64 像素画布内，从 x=12,y=12 起）保持完全透明。边框采用规则刻纹区分紫色传说和不规则腐化裂痕；光效只在边缘运动，不遮住物品中心。

## 制作与验证

图标、怪物、技能特效由 **内置 image_gen** 逐资产生成，使用现有短刃、普通狼、裂壳虫、灰烬游魂作为风格参考。原图原样保留，ImageMagick 只用于透明边距规范化、最近邻导出、切分图集和预览打包。品质框属于精确 UI 几何图形，由 SVG 绘制并导出 PNG 动画，SVG 可继续编辑。

已逐项核对当前数据 ID，检查 PNG 尺寸、透明角点、怪物导出画布、六组特效图集及透明结束帧。四档品质框均检查 24 帧内容不同，且中心透明。已查看图标总览、怪物总览、特效逐帧序列和边框叠加预览。没有启动游戏进行效果接入验收，本批没有改动玩法。

构建脚本以 Node.js 和 ImageMagick 为依赖，当前机器 ImageMagick 路径为 /opt/homebrew/bin/magick，预览标注使用系统黑体字体。复现时可以按环境调整工具及字体路径。

~~~sh
node docs/素材/sources/build_assets.mjs
node docs/素材/sources/build_previews.mjs
node docs/素材/sources/verify_assets.mjs
~~~


生成提示词与原图关联保存在 sources/generation_manifest.json；本地原图已复制到 sources/，重新导出无需联网调用生成工具。参考图备份在 sources/references/。所有资源的 integrated 均为 false，未来接入需单独绑定游戏事件、状态、方向和数据路径。

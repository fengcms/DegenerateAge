# 同风格营地NPC八向源稿

内置imagegen原创制作，使用本项目已确认素材作风格参考，无外部游戏图片。每角色独立提示保存在同目录。正式采用quest_v2、blacksmith_v2、shop_source、warehouse_source、carter_alpha；初稿有渐变色底，已弃用并不入库。车夫由carter_source经内置工具去底，完整编辑提示另存。

四列两行顺序为s/sw/w/nw/n/ne/e/se，每向单帧静态转面。tools/art_pipeline/turntables.json定义确定性构建：112×128、脚锚(56,112)、主体高96，输出assets/sprites/npcs/modular_v1，线性过滤、1倍显示。不是行走或呼吸动画。

五种角色在所有章节共用Npc实体，替换同职业外观；名称、身份、任务、仓库、交易及马车逻辑不变。五图理论RGBA8总量2.19MiB，共享ResourceLoader纹理，NPC不复制图片。点击框与新帧规格一致，姓名和任务标记继续使用原世界文字设置。

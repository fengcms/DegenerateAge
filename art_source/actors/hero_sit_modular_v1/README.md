# 主角八向打坐源稿

使用内置imagegen生成，参考本项目hero_walk_pilot_v3/idle_source.png保持人物身份。源稿四列两行，方向依次s/sw/w/nw/n/ne/e/se，真实透明背景；不引用商业游戏角色。

运行规格：112×128，脚锚(56,112)，主体高70像素，单帧静坐；不以重复帧冒充动画。通过tools/art_pipeline/build_turntables.gd读取turntables.json确定性编译，--check核对像素。以alpha>0.1确定主体边界，裁切内部保留原alpha；源稿未覆盖。恢复数值、站起及打断继续由正式玩家逻辑处理。完整提示见同目录prompt.txt。

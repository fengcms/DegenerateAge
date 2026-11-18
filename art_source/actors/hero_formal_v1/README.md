# 主角正式八向基础形象

来源为已验收 assets/art_pilot/hero 各方向动作，原始生成记录见 art_source/actors。由 tools/camp_combat/build_formal_hero.gd 无损重排，--check 逐像素验证。方向横排 s/sw/w/nw/n/ne/e/se，帧纵排；单帧112×128，脚锚(56,112)，待机1帧，其余4帧。运行显示比例为1，保留玩家碰撞半径12。

CharacterLook.look_01 使用新五状态；原打坐与骑乘图按各自脚锚和比例保留，后续装备档位不变。攻击从接触帧2开始，死亡0.9秒，不改变结算。源包与运行包各约7.44MiB RGBA8。

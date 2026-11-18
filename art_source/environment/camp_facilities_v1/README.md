# 营地专用设施源稿

warehouse.png由内置imagegen原创生成，参考本项目棚屋的材质与视角；完整提示见warehouse_prompt.txt。不使用外部游戏贴图。

由tools/art_pipeline/build_facilities.gd确定性裁切、缩放至384×281，生成运行PNG与上部75%实体轮廓遮挡蒙版；脚锚(192,277)。运行图和蒙版位于assets/environment/camp_facilities_v1，合计理论RGBA8约843KiB。局部淡出沿用CampModuleOccluder，无动态灯光、额外粒子或碰撞修改。

本批马车候选存在残留背景色晕，未采用；正式游戏继续使用原马车素材。营地仓库沿用白盒实体整体位置、宽度和原碰撞，不改变仓管服务坐标。

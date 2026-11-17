# 姿态约束行走候选 V2：仍未通过正式接入

pose_guide.png是Blender程序化双色人偶姿态参照，pose_checks.json记录骨段长度、膝盖坐标和足底高度。左肢蓝、右肢红，只用于约束姿势，不是主角美术。重建：

```sh
blender -b -t 4 --python-exit-code 1 --python tools/motion_review/build_pose_guide.py -- /tmp/hero-pose-guide
```

candidate.png由内置image_gen根据姿态图生成。完整提示词与各次选择见prompts.json；只有代表候选入库，未采用稿不进入项目。源图2048×768、四列，每格512×768。review.json统一使用(288,680)审片锚点、96/550倍率，未逐帧修图或对齐。此锚点未作为正式脚底锚点验收。

相比V1，前后半周期的落脚姿势已有区别，但胸甲、披布与原主角不同，帧间位置仍有漂移。没有通过身份、完整循环和脚滑验收；不导出到assets，不替换营地。

生成预览里可见的棕色雾状区域不能直接等同运行光晕。Godot浅色底合成未见大面积光晕，三个外部探针alpha为0；但非零alpha包围盒触及部分帧边缘，说明仍有弱透明像素，需要进一步检查。只测几个透明点不能证明全图边缘干净，不做阈值抠图。

审片：

```sh
python3 tools/motion_review/launch.py --source art_source/actors/hero_walk_pose_v2
```

G切换下方姿态条带，B切换底色；左右键单帧检查。姿态图和候选图的同格中心没有像素级对齐，不应据此声称关节坐标被生成模型严格保持。

# 单方向动作审片工具

用于在接入游戏前发现循环步态、服装一致性、帧间比例和脚底漂移问题。不运行游戏单例，不读取存档，不注册正式动画。

```sh
python3 tools/motion_review/launch.py
python3 tools/motion_review/launch.py --verify --capture /tmp/hero-motion-review
```

依赖Python3、Godot4；macOS默认查找/Applications/Godot.app。临时项目退出即清理；窗口为1280×800 Compatibility。

- 空格：播放/暂停。
- 左右方向键：暂停并前后切一帧。
- 1：6帧/秒；2：3帧/秒慢放（基于当前配置）。
- R：回首帧，保留播放/暂停状态。

左侧为已认可静态主角和原尺寸候选，右侧三倍放大同步预览，下方为全部帧。所有候选使用同一倍率和锚点，不逐帧紧裁、伸缩或自动吸附脚底，因此原稿漂移不会被工具掩盖。横线是屏幕坐标标尺，不是角色碰撞或游戏地面。

当前输入固定为art_source/actors/hero_walk_trial_v1/candidate.png和review.json。frameSize为源稿格尺寸，columns为列数，frames为帧数，fps为播放速度，pivot为每格统一锚点（像素），scale为原尺寸显示倍率，direction为候选方向，issues/status记录人工质量结论。status不是自动审批字段。本批明确为rejected_for_runtime。

自动验证只证明工具可用：透明帧角、共享图集、双预览同步、暂停、切帧、慢放、循环以及位置/倍率保持。成功标记MOTION_REVIEW_VERIFY_OK同时注明ART_NOT_APPROVED，不能用于证明步态或美术质量通过。

图集仅加载一次，四个AtlasTexture共享源纹理；两个动态预览、四个静态帧、一个原图对照。热路径无文件读取、图片加工或纹理分配；窗口关闭释放临时项目与资源。此工具可加载大源稿用于审片，不属于正式运行素材打包入口。

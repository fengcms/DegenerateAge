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

## 姿态约束与透明检查

新增`--source <目录>`选择含candidate.png、review.json的候选；默认仍为V1。配置可用guide字段指定同目录、同尺寸的姿态图，background_probes指定要输出alpha的源图像素坐标。G只切换下方条带，不替换上方候选。B循环深色、浅色、棋盘底，用于避免只凭生成预览判断透明边缘；外部采样点为0也不能证明整个背景已干净。

`build_pose_guide.py`在Blender中使用等长双骨腿解析膝盖位置，显式交换接触脚与支撑脚，生成姿态参照和数值校验记录。它不重建主角模型、不生成最终人物，也不宣称实现了连续脚锁定；目前是四个关键姿态。

```sh
blender -b -t 4 --python-exit-code 1 --python tools/motion_review/build_pose_guide.py -- /tmp/hero-pose-guide
python3 tools/motion_review/launch.py --source art_source/actors/hero_walk_pose_v2 --verify --capture /tmp/hero-motion-pose-v2
```

新版验证增加底色循环、姿态条带切换而候选不变，以及窗口截图中棋盘颜色差异；打印各帧非零alpha包围盒。失败或超时保留子进程日志，不把断言中断误报为成功。加载一张姿态图额外约6MiB理论RGBA8纹理，只在审片器使用。

## 怪物候选与独立对照图

--reference <图片>可选择静态怪物对照，默认仍为原主角；review.json可设actorName。支持四帧的四列或2×2源格。自动验证检查数据和播放，不要求候选先被拒绝，也不会把under_review或isolated_idle_trial升级为正式通过；始终输出ART_NOT_APPROVED。原V1拒绝候选已复测通过工具检查，透明角和同步断言保留。

## 背面姿态约束

build_pose_guide.py新增--direction ne；默认se保持原骨架坐标。相机和四人偶排列随视角一起改变，身体前方、左蓝/右红肢体及骨长不变，不使用镜像。渲染前额外验证身体前方投影确实指向屏幕右上/右下。Blender分别输出两方向POSE_GUIDE_OK，前后四帧骨架数值与原se版一致；数值通过仍不能批准AI输出的步态。

review.json还可指定referencePivot（静态对照图像素坐标）；默认仍是底边中心。使用带透明帧格的站姿时必须提供其实际接触区锚点，例如(56,112)，避免把帧底当脚底造成虚假的高低差。此字段只调整对照图，不修正候选各帧的漂移。

## 四斜向姿态参照

--direction现支持se/ne/sw/nw。四方向使用同一腿骨和接触姿态，只改变相机以及沿画面水平排列的方向；输出projected_forward_delta，验证身体前方在画面中的左右/上下符号。左向不镜像左右手，不自动批准生成美术。原se/ne数值骨架回归保持一致。

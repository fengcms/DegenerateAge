# 独立美术尺寸查看器

使用 Godot 打开本目录 project.godot 后运行，或执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path tools/art_pilot
```

拖动三种静态对象可查看相互遮挡，空格切换1×/2×。拖动不是行走动画；建筑是背景，不参与遮挡和碰撞。该独立工程无正式游戏单例，不读取或写入玩家存档。

从仓库根目录重建素材：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/art_pilot/build.gd
```

只裁剪透明留白、缩放PNG，不执行自动抠图。四张纹理只在进入查看器时读取，节点退出释放，无每帧加载、无全图扫描。视图只含一个背景和三个对象，不能代表正式游戏性能。

# 模块化营地结构实验场

这是51号方案第一步的可运行实现。**使用现有旧素材验证地图结构，不是已完成的写实美术包。** 不加载整图背景，不修改正式地图或存档。

从仓库根目录运行：

```sh
python3 tools/modular_camp/launch.py
```

依赖Python3与Godot4。启动器优先使用PATH中的godot，macOS回退到/Applications/Godot.app。启动时创建临时项目，复制现有Iso、FlatTileMesh、CaveLayout源码与所需7张PNG，导入后运行，关闭后删除临时项目。无需安装Python第三方库。

- Tab：切换同一资产包拼出的两种16×16格布局。
- 左键：使用既有CaveLayout路径和平滑算法移动至可达目标。
- WASD：直接移动，真实CharacterBody2D半径12碰撞。
- B：显示布局同源碰撞区域。
- M：移动一段墙，同时重建该小样板布局、碰撞、物件位置和导航，清空旧路线。

角色只是静态表现，不代表行走动画。墙/树/棚屋的旧美术轮廓与结构占地仍需下一阶段匹配；门洞是墙段之间的通行间隙，不是棚屋室内。

## 数据与实现

`layouts.json`为两份样板的道路行和物件位置事实源。物件种类、占地、视觉尺寸在main.gd的DEFINITIONS中集中维护。道路按八邻接规范化成47种形状，基础和道路各一个合批网格。物件按世界Y排序；占地生成物理菱形和CaveLayout输入。未另写寻路或战斗系统。

每次加载/布局切换重建256格场景，属于开发样板，尚非正式地图局部编辑系统。运行中无地面逐格重绘或纹理重复加载。临时项目的compiled_layout.json只在切换布局时写入，与玩家存档无关。

## 验证

```sh
python3 tools/modular_camp/launch.py --verify
python3 tools/modular_camp/launch.py --verify --capture /tmp/modular-camp-review
```

检查256邻域规范化与47种形状、固定随机排列相邻道路边的alpha连续性、两布局256格通行与碰撞一致性、真实物理长路径、门洞通行、墙体正面阻挡、绕墙到达以及移动墙后旧格释放/新格阻挡/旧路线清空。

成功必须出现 `MODULAR_CAMP_VERIFY_OK`；断言失败或超时不算通过。截图为真实Godot窗口输出。headless结果不用于证明画面或GPU性能。

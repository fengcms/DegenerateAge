# 地图配置目录

每张地图独立放在 `chNN/<地图 ID>/`，目录内的 `map.json` 是该地图的运行配置，`README.md` 说明地图名称、用途和当前关键参数。各章节目录也有 README 作为导航，新增地图时同步登记。`index.json` 是有序路径清单，只登记地图配置路径，不重复保存地图属性。`DataLoader` 启动时按清单聚合为 `maps` 表，游戏仍通过 `get_table("maps")` / `get_entry("maps", id)` 查询。

地图的可通行掩码在 `data/layouts/<地图 ID>.json`，美术输入和运行素材位于各自原目录；这些文件的用途不同，不要复制进 `map.json`。清单、目录名和配置内的稳定 `id` 必须一致。

编辑已有地图时，修改该图 `map.json` 后同步更新同目录 `README.md` 的用途、路线、NPC、怪物、出入口或其他受影响的说明。README 中两个 `MAP PARAMETERS` 标记之间是参数区，可运行 `python3 tools/check_map_catalog.py --update` 根据配置刷新；标记外的设计意图由编辑者维护。生成脚本应通过 `tools/map_catalog.py` 的 `load_maps` / `save_maps` 读写，以便自动同步参数区。新增地图需创建目录、配置、README，并在 `index.json` 登记，再检查跨图引用和可通行性。

提交前运行 `python3 tools/check_map_catalog.py` 检查目录、ID、README 和参数一致性，并运行相关地图测试。JSON 必须保持标准语法，不写注释；解释写在同目录 README。
